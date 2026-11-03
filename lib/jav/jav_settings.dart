import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Player tweaks behind the subtitle ball (字幕悬浮球), with the defaults of
/// the MissAV "字幕悬浮球助手" userscript they come from.
class JavPlayerSettings {
  JavPlayerSettings({
    this.accelerateKey = 'z',
    this.forwardKey = 'x',
    this.backwardKey = 'c',
    this.accelerationRate = 3,
    this.skipSeconds = 5,
    this.subtitleOffset = 0,
    this.subtitlePosition = 15,
    this.subtitleSize = 55,
    this.subtitleColor = '#ffffff',
    this.ballX,
    this.ballY,
  });

  static const prefsKey = 'jav.player_settings.v1';

  /// Held down: play at [accelerationRate]; released: back to normal speed.
  String accelerateKey;
  String forwardKey;
  String backwardKey;
  double accelerationRate;
  double skipSeconds;

  /// Seconds; positive shows the subtitles later (mpv `sub-delay`).
  double subtitleOffset;

  /// Percent of the picture height above the bottom edge, 0-90.
  double subtitlePosition;

  /// mpv `sub-font-size` (scaled to a 720 px high window; mpv default 55).
  double subtitleSize;
  String subtitleColor;

  /// Ball position as fractions of the player size, so it survives resizes.
  double? ballX;
  double? ballY;

  /// mpv `sub-pos`: 100 is the bottom edge, 0 the top.
  int get mpvSubPos => (100 - subtitlePosition.clamp(0, 90)).round();

  Map<String, Object?> toJson() => {
    'accelerateKey': accelerateKey,
    'forwardKey': forwardKey,
    'backwardKey': backwardKey,
    'accelerationRate': accelerationRate,
    'skipSeconds': skipSeconds,
    'subtitleOffset': subtitleOffset,
    'subtitlePosition': subtitlePosition,
    'subtitleSize': subtitleSize,
    'subtitleColor': subtitleColor,
    'ballX': ballX,
    'ballY': ballY,
  };

  factory JavPlayerSettings.fromJson(Map<String, Object?> j) {
    final d = JavPlayerSettings();
    String key(Object? v, String fallback) {
      final s = (v is String ? v.trim().toLowerCase() : '');
      return s.length == 1 ? s : fallback;
    }

    double num_(Object? v, double fallback, double min, double max) {
      final n = v is num ? v.toDouble() : double.tryParse('$v');
      return n == null || n.isNaN ? fallback : n.clamp(min, max).toDouble();
    }

    double? frac(Object? v) =>
        v is num ? v.toDouble().clamp(0.0, 1.0).toDouble() : null;

    return JavPlayerSettings(
      accelerateKey: key(j['accelerateKey'], d.accelerateKey),
      forwardKey: key(j['forwardKey'], d.forwardKey),
      backwardKey: key(j['backwardKey'], d.backwardKey),
      accelerationRate: num_(j['accelerationRate'], d.accelerationRate, 0.1, 16),
      skipSeconds: num_(j['skipSeconds'], d.skipSeconds, 0.1, 600),
      subtitleOffset: num_(j['subtitleOffset'], d.subtitleOffset, -600, 600),
      subtitlePosition: num_(j['subtitlePosition'], d.subtitlePosition, 0, 90),
      subtitleSize: num_(j['subtitleSize'], d.subtitleSize, 10, 150),
      subtitleColor: normalizeHexColor(j['subtitleColor']) ?? d.subtitleColor,
      ballX: frac(j['ballX']),
      ballY: frac(j['ballY']),
    );
  }

  JavPlayerSettings copy() => JavPlayerSettings.fromJson(toJson());

  static Future<JavPlayerSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw == null) return JavPlayerSettings();
      return JavPlayerSettings.fromJson(
        (jsonDecode(raw) as Map).cast<String, Object?>(),
      );
    } catch (_) {
      return JavPlayerSettings();
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, jsonEncode(toJson()));
  }
}

/// `'#FFF'` -> `'#ffffff'`; null for anything that is not a hex color.
String? normalizeHexColor(Object? value) {
  if (value is! String) return null;
  final v = value.trim().toLowerCase();
  if (RegExp(r'^#[0-9a-f]{6}$').hasMatch(v)) return v;
  if (RegExp(r'^#[0-9a-f]{3}$').hasMatch(v)) {
    return '#${v.substring(1).split('').map((c) => '$c$c').join()}';
  }
  return null;
}
