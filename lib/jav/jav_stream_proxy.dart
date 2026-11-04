import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Hosts of the 115 CDN, the only upstream this proxy takes over.
final _cdn115 = RegExp(r'115cdn\.(net|com)|115\.com|anxia\.com|115vod\.com', caseSensitive: false);

/// Asks the JavHub Emby gateway for the CDN redirect only: no connection
/// accounting, no relaying through the NAS, just the 302.
const javResolveHeader = 'X-Jav-Resolve';

/// A loopback range proxy in front of the 115 CDN, so mpv never talks to it
/// directly.
///
/// 115 allows 2 connections per client IP per file and keeps counting a closed
/// one for 30-60 s, while mpv opens a new connection for every seek and reads
/// the file's index at the end before playing. Through this proxy mpv's
/// connections end on 127.0.0.1; upstream there are at most [maxUpstream]
/// keep-alive connections fetching fixed-size chunks in turn, so a seek only
/// changes which chunk is fetched next. A "pmt" refusal is waited out instead
/// of reaching mpv, which would take it for the end of the file. The video
/// still goes CDN -> this computer; nothing passes through the NAS.
class JavStreamProxy {
  JavStreamProxy({
    this.chunkSize = 2 << 20, // ~0.85 s each from here: a seek waits for one
    this.cacheBytes = 96 << 20,
    this.maxUpstream = 2,
    this.userAgent = 'Moonfin-jav/1.0 (libmpv)',
    this.pmtWait = const Duration(seconds: 90),
    bool Function(Uri location)? isCloud,
  }) : _isCloud = isCloud ?? ((u) => _cdn115.hasMatch(u.host));

  static final instance = JavStreamProxy();

  final int chunkSize;
  final int cacheBytes;
  final int maxUpstream;

  /// The CDN link is signed for the User-Agent it was resolved with, so the
  /// resolve and every chunk request use this one.
  final String userAgent;

  /// How long a chunk keeps retrying while 115 answers "pmt" (too many
  /// connections) before giving up.
  final Duration pmtWait;
  final bool Function(Uri) _isCloud;

  HttpServer? _server;
  Future<HttpServer>? _starting;
  final HttpClient _client = HttpClient()
    // Idle keep-alive connections are kept, so pausing and seeking don't
    // close (and so re-open) upstream connections.
    ..idleTimeout = const Duration(seconds: 120)
    ..autoUncompress = false;
  final _sessions = LinkedHashMap<String, _Session>();
  int _nextId = 0;

  // Upstream slots: chunk requests a player waits for go first, read-ahead
  // only takes a slot that is free right now.
  int _busy = 0;
  final _waiters = Queue<Completer<void>>();

  /// Upstream requests currently running (for tests and diagnostics).
  int get activeUpstream => _busy;

  /// The URL to give mpv for [url]: a loopback URL when [url] redirects to
  /// the 115 CDN, else [url] itself. Never throws.
  Future<String> wrap(String url, {Map<String, String> headers = const {}}) async {
    try {
      final origin = Uri.parse(url);
      if (!origin.isScheme('http') && !origin.isScheme('https')) return url;
      final path = origin.path.toLowerCase();
      if (!path.contains('/videos/') || path.endsWith('.m3u8')) return url;
      final cdn = await _resolve(origin, headers).timeout(const Duration(seconds: 8));
      if (cdn == null) return url;
      final session = _Session(origin: origin, headers: headers, cdn: cdn);
      // The first chunk tells the size and type, and is what mpv reads first.
      await _chunk(session, 0, demand: true).timeout(const Duration(seconds: 30));
      final server = await _ensureServer();
      final id = '${++_nextId}';
      _sessions[id] = session;
      while (_sessions.length > 3) {
        _sessions.remove(_sessions.keys.first);
      }
      return 'http://127.0.0.1:${server.port}/s/$id/${origin.pathSegments.isEmpty ? 'video' : origin.pathSegments.last}';
    } catch (_) {
      return url;
    }
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
    _starting = null;
    _client.close(force: true);
  }

  // ---------------- upstream ----------------

  Future<Uri?> _resolve(Uri origin, Map<String, String> headers) async {
    final req = await _client.getUrl(origin);
    req.followRedirects = false;
    headers.forEach(req.headers.set);
    req.headers
      ..set(HttpHeaders.userAgentHeader, userAgent)
      ..set(HttpHeaders.rangeHeader, 'bytes=0-0')
      ..set(javResolveHeader, '1');
    final resp = await req.close();
    final location = resp.headers.value(HttpHeaders.locationHeader);
    await resp.drain<void>().catchError((_) {});
    if (!resp.isRedirect || location == null) return null;
    final target = origin.resolve(location);
    return _isCloud(target) ? target : null;
  }

  Future<bool> _acquire({required bool demand}) async {
    if (_busy < maxUpstream) {
      _busy++;
      return true;
    }
    if (!demand) return false;
    final waiter = Completer<void>();
    _waiters.add(waiter);
    await waiter.future; // the slot is handed over by _release
    return true;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    } else {
      _busy--;
    }
  }

  /// Chunk [index] of [s], from the cache, an identical request already
  /// running, or the CDN. Null only for a read-ahead that found no free slot.
  Future<Uint8List?> _chunk(_Session s, int index, {required bool demand}) async {
    final cached = s.cache.remove(index);
    if (cached != null) {
      s.cache[index] = cached; // most recently used
      return cached;
    }
    final running = s.inflight[index];
    if (running != null) return running;
    if (s.size != null && index * chunkSize >= s.size!) return Uint8List(0);
    if (!await _acquire(demand: demand)) return null;
    final future = _download(s, index).whenComplete(_release);
    s.inflight[index] = future;
    try {
      final data = await future;
      s.cache[index] = data;
      s.cachedBytes += data.length;
      while (s.cachedBytes > cacheBytes && s.cache.length > 1) {
        final oldest = s.cache.keys.first;
        s.cachedBytes -= s.cache.remove(oldest)!.length;
      }
      return data;
    } finally {
      s.inflight.remove(index);
    }
  }

  Future<Uint8List> _download(_Session s, int index) async {
    final start = index * chunkSize;
    final deadline = DateTime.now().add(pmtWait);
    var failures = 0;
    var resolves = 0;
    while (true) {
      final end = s.size == null ? start + chunkSize - 1 : math.min(start + chunkSize, s.size!) - 1;
      try {
        final req = await _client.getUrl(s.cdn);
        req.followRedirects = true;
        req.headers
          ..set(HttpHeaders.userAgentHeader, userAgent)
          ..set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
        final resp = await req.close().timeout(const Duration(seconds: 20));
        if (resp.statusCode == HttpStatus.partialContent || resp.statusCode == HttpStatus.ok) {
          // Read to the end, so the keep-alive connection can be reused.
          final builder = BytesBuilder(copy: false);
          await resp.timeout(const Duration(seconds: 30)).forEach(builder.add);
          var data = builder.takeBytes();
          final total = RegExp(r'/(\d+)$').firstMatch(resp.headers.value(HttpHeaders.contentRangeHeader) ?? '');
          if (total != null) s.size = int.parse(total[1]!);
          if (resp.statusCode == HttpStatus.ok) {
            s.size ??= data.length;
            data = Uint8List.sublistView(data, math.min(start, data.length), math.min(end + 1, data.length));
          }
          s.contentType ??= resp.headers.contentType?.toString();
          return data;
        }
        final body = await utf8.decodeStream(resp).catchError((_) => '');
        if (resp.statusCode == HttpStatus.forbidden && body.contains('pmt')) {
          // Too many connections for this file right now: wait it out.
          if (DateTime.now().isAfter(deadline)) throw _CdnRefused('115 pmt: $body');
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }
        if ((resp.statusCode == HttpStatus.forbidden || resp.statusCode == HttpStatus.notFound ||
                resp.statusCode == HttpStatus.gone) &&
            resolves < 2) {
          // The signed link expired: ask the gateway for a fresh one.
          resolves++;
          s.cdn = await _resolve(s.origin, s.headers) ?? s.cdn;
          continue;
        }
        throw _CdnRefused('CDN HTTP ${resp.statusCode}');
      } on _CdnRefused {
        rethrow;
      } catch (_) {
        // Network trouble (reset, timeout ...): retry a few times.
        if (++failures > 3) rethrow;
        await Future<void>.delayed(Duration(seconds: failures));
      }
    }
  }

  // ---------------- loopback server ----------------

  Future<HttpServer> _ensureServer() {
    final server = _server;
    if (server != null) return Future.value(server);
    return _starting ??= HttpServer.bind(InternetAddress.loopbackIPv4, 0).then((s) {
      _server = s;
      s.listen((req) => unawaited(_serve(req)), onError: (_) {});
      return s;
    });
  }

  Future<void> _serve(HttpRequest req) async {
    final res = req.response;
    try {
      final seg = req.uri.pathSegments;
      final s = seg.length >= 2 && seg[0] == 's' ? _sessions[seg[1]] : null;
      final size = s?.size;
      if (s == null || size == null) {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      var start = 0;
      var end = size - 1;
      final range = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(req.headers.value(HttpHeaders.rangeHeader) ?? '');
      if (range != null) {
        if (range[1]!.isEmpty && range[2]!.isNotEmpty) {
          start = math.max(0, size - int.parse(range[2]!)); // suffix range
        } else {
          start = int.tryParse(range[1]!) ?? 0;
          if (range[2]!.isNotEmpty) end = math.min(end, int.parse(range[2]!));
        }
        if (start >= size) {
          res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size');
          return;
        }
        res.statusCode = HttpStatus.partialContent;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$size');
      }
      res.headers
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..set(HttpHeaders.contentTypeHeader, s.contentType ?? 'video/mp4');
      res.contentLength = end - start + 1;
      if (req.method == 'HEAD') return;

      var pos = start;
      while (pos <= end) {
        final index = pos ~/ chunkSize;
        final data = await _chunk(s, index, demand: true);
        if (data == null || data.isEmpty) break;
        // Keep the next chunks coming while mpv chews on this one.
        for (var ahead = 1; ahead <= 3; ahead++) {
          unawaited(_chunk(s, index + ahead, demand: false).catchError((_) => null));
        }
        final offset = pos - index * chunkSize;
        if (offset >= data.length) break;
        final take = math.min(data.length - offset, end - pos + 1);
        res.add(Uint8List.sublistView(data, offset, offset + take));
        await res.flush(); // throws once mpv has hung up (a seek): stop here
        pos += take;
      }
    } catch (_) {
      // mpv closed the connection, or the CDN failed for good.
    } finally {
      try {
        await res.close();
      } catch (_) {}
    }
  }
}

/// The CDN said no for good (as opposed to a network error worth retrying).
class _CdnRefused implements Exception {
  _CdnRefused(this.message);

  final String message;

  @override
  String toString() => message;
}

class _Session {
  _Session({required this.origin, required this.headers, required this.cdn});

  final Uri origin;
  final Map<String, String> headers;
  Uri cdn;
  int? size;
  String? contentType;
  final cache = LinkedHashMap<int, Uint8List>();
  int cachedBytes = 0;
  final inflight = <int, Future<Uint8List>>{};
}
