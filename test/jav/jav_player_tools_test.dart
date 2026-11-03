import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/jav/jav_player_tools.dart';
import 'package:moonfin/jav/jav_settings.dart';

void main() {
  test('Xunlei results: format from the ext field, links have none', () {
    final subs = parseXunleiSubtitles({
      'code': 0,
      'data': [
        {'url': 'https://subtitle.v.geilijiasu.com/1E/7B/1E7B34C2', 'ext': 'ass', 'name': 'ipx177.ass', 'extra_name': '（网友上传）'},
        {'url': 'https://subtitle.v.geilijiasu.com/62/B1/62B1097C', 'ext': 'ASS', 'name': 'IPX177'},
        {'url': 'https://example.com/a.srt', 'name': 'a'},
        {'url': 'https://example.com/b', 'ext': 'sup', 'name': 'bitmap.sup'},
        {'name': 'no url', 'ext': 'srt'},
        'garbage',
      ],
    });
    expect(subs.map((s) => s.ext), ['ass', 'ass', 'srt']);
    expect(subs.first.label, 'ipx177.ass (（网友上传）)');
    expect(subs[1].label, 'IPX177');
    expect(parseXunleiSubtitles({'code': 1, 'data': []}), isEmpty);
    expect(parseXunleiSubtitles(null), isEmpty);
  });

  test('settings: userscript defaults, clamping and round trip', () {
    final d = JavPlayerSettings();
    expect([d.accelerateKey, d.forwardKey, d.backwardKey], ['z', 'x', 'c']);
    expect(d.accelerationRate, 3);
    expect(d.skipSeconds, 5);
    expect(d.mpvSubPos, 85); // 15 % above the bottom

    final s = JavPlayerSettings.fromJson({
      'accelerateKey': 'Q',
      'forwardKey': 'too long',
      'subtitlePosition': 200,
      'subtitleColor': '#F0A',
      'skipSeconds': 'abc',
      'ballX': 1.7,
    });
    expect(s.accelerateKey, 'q');
    expect(s.forwardKey, 'x');
    expect(s.subtitlePosition, 90);
    expect(s.mpvSubPos, 10);
    expect(s.subtitleColor, '#ff00aa');
    expect(s.skipSeconds, 5);
    expect(s.ballX, 1.0);

    final copy = s.copy();
    expect(copy.toJson(), s.toJson());
  });

  test('normalizeHexColor', () {
    expect(normalizeHexColor('#FFF'), '#ffffff');
    expect(normalizeHexColor(' #12ab9C '), '#12ab9c');
    expect(normalizeHexColor('red'), isNull);
    expect(normalizeHexColor(null), isNull);
  });
}
