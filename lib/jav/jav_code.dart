/// JAV product codes (番号) from messy file, folder and title names.
///
/// A port of JavHub's `normalize_code`, so the player finds the same code
/// JavHub filed the movie under: `hhd800.com@ABP-123.mp4` -> `ABP-123`,
/// `fc2ppv 1942212` -> `FC2-PPV-1942212`, `13gvh00239` -> `GVH-239`.
library;

final _fc2 = RegExp(r'FC2[\s_-]*(?:PPV)?[\s_-]*(\d{5,8})', caseSensitive: false);
final _heyzo = RegExp(r'HEYZO[\s_-]*(\d{3,5})', caseSensitive: false);
// 010914-518 / 120415_201
final _dateNum = RegExp(r'(?<!\d)(\d{6})[-_](\d{2,3})(?!\d)');
final _tokyoHot = RegExp(r'^(n|k)(\d{4})$', caseSensitive: false);
// 300MIUM-123 style digit prefixes must not be glued on from a preceding
// date ("2022-04-01MIDV-075").
final _stdDigit = RegExp(
  r'(?<![a-z0-9-])(\d{2,3}[a-z]{2,8})[\s_-]*0*(\d{2,6})(?!\d)',
  caseSensitive: false,
);
final _std = RegExp(
  r'(?<![a-z])([a-z]{2,8})[\s_-]*0*(\d{2,6})(?!\d)',
  caseSensitive: false,
);
// hhd800.com@ / www.98T.la@ / 489155.com@ (not "[4K]@R90s")
final _sitePrefix = RegExp(r'^[^@\s]*\.[a-z]{2,6}@', caseSensitive: false);
// "www.98T.laSSIS-541": a spam prefix glued on without "@".
final _wwwGlued = RegExp(
  r'^www\.[\w-]+\.(?:la|cc|me|tv|co|io|in|com|net|org)(?=[a-z\d\[(_-])',
  caseSensitive: false,
);
// DMM content ids: "13gvh00239" = maker id 13 + GVH-00239 -> GVH-239.
final _dmmCid = RegExp(
  r'(?<![a-z\d])\d{1,2}([a-z]{2,6})(00\d{3})(?!\d)',
  caseSensitive: false,
);
final _domain = RegExp(
  r'(?:www\.)?[\w-]+\.(?:com|net|org|cc|la|me|tv|xyz|top|vip|io|co|info|club|site|fun|in)\b',
  caseSensitive: false,
);

/// `'ssis001'` -> `'SSIS-001'`. Empty when nothing code-like is found.
String normalizeJavCode(String? raw) {
  var s = (raw ?? '').trim();
  if (s.isEmpty) return '';
  final cleaned = s
      .replaceFirst(_sitePrefix, '')
      .replaceFirst(_wwwGlued, '')
      .replaceAll(_domain, ' ')
      .trim();
  if (cleaned.isNotEmpty) s = cleaned;

  var m = _dmmCid.firstMatch(s);
  if (m != null) return '${m[1]!.toUpperCase()}-${m[2]!.substring(2)}';
  m = _fc2.firstMatch(s);
  if (m != null) return 'FC2-PPV-${m[1]}';
  m = _heyzo.firstMatch(s);
  if (m != null) return 'HEYZO-${m[1]}';
  m = _dateNum.firstMatch(s);
  if (m != null) {
    final sep = s.substring(m.start, m.end).contains('-') ? '-' : '_';
    return '${m[1]}$sep${m[2]}';
  }
  m = _tokyoHot.firstMatch(s.trim());
  if (m != null) return '${m[1]!.toLowerCase()}${m[2]}';
  m = _stdDigit.firstMatch(s) ?? _std.firstMatch(s);
  if (m != null) {
    final number = m[2]!.length < 3 ? m[2]!.padLeft(3, '0') : m[2]!;
    return '${m[1]!.toUpperCase()}-$number';
  }
  return '';
}

/// The code of an Emby item: JavHub files every movie in a folder named after
/// it (`/media/jav-115/WAAA-615/WAAA-615.strm`), so the path is the most
/// reliable source, then the file name, then the titles.
String javCodeForItem(Map<String, dynamic>? item) {
  if (item == null) return '';
  final candidates = <String?>[];
  final path = item['Path'] as String?;
  if (path != null && path.isNotEmpty) {
    final parts = path.split(RegExp(r'[\\/]'))..removeWhere((p) => p.isEmpty);
    if (parts.length >= 2) candidates.add(parts[parts.length - 2]);
    if (parts.isNotEmpty) candidates.add(parts.last);
  }
  final sources = item['MediaSources'];
  if (sources is List && sources.isNotEmpty && sources.first is Map) {
    candidates.add((sources.first as Map)['Name'] as String?);
  }
  candidates
    ..add(item['Name'] as String?)
    ..add(item['OriginalTitle'] as String?)
    ..add(item['SortName'] as String?);
  for (final c in candidates) {
    final code = normalizeJavCode(c);
    if (code.isNotEmpty) return code;
  }
  return '';
}
