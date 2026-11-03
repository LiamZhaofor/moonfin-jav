import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/jav/jav_code.dart';

void main() {
  // Same table as JavHub's tests/test_core.py::test_normalize.
  const cases = {
    'ssis001': 'SSIS-001',
    'SSIS-001': 'SSIS-001',
    'ssis-00001': 'SSIS-001',
    'abp123': 'ABP-123',
    'fc2ppv 1942212': 'FC2-PPV-1942212',
    'FC2-PPV-1942212': 'FC2-PPV-1942212',
    'heyzo_0841': 'HEYZO-0841',
    '010914-518': '010914-518',
    '[HD] MIAA-715-C.mp4': 'MIAA-715',
    '300MIUM-123': '300MIUM-123',
    'n1234': 'n1234',
    '': '',
    'hello': '',
    'hhd800.com@ABP-123.mp4': 'ABP-123',
    'www.98T.la@FC2PPV-4781367_chf3_iris2.mp4': 'FC2-PPV-4781367',
    '489155.com@START-539-UC.(mp4)': 'START-539',
    '[456k.me]MIDV-372.mp4': 'MIDV-372',
    'www.98T.la@2022-04-01MIDV-075新人(破解字幕).mp4': 'MIDV-075',
    'SNOS-334.[4K]@R90s': 'SNOS-334',
    '126353_3xplanet_Caribbeancom_112318-798.mp4': '112318-798',
    'www.98T.la@13gvh00239.restored0.10.mp4': 'GVH-239',
    'www.98T.laSSIS-541-U.mp4': 'SSIS-541',
    'www.98T.laghmt40_hd_02_6000k_000^WM.mp4': 'GHMT-040',
    'GHKR-67聖心～01.mp4': 'GHKR-067',
  };

  test('normalizeJavCode matches JavHub', () {
    cases.forEach((raw, code) {
      expect(normalizeJavCode(raw), code, reason: raw);
    });
  });

  test('javCodeForItem prefers the JavHub folder name', () {
    expect(
      javCodeForItem({
        'Name': '让狂妄的妹妹穿上及膝袜',
        'Path': '/media/jav-115/IPX-177-C/IPX-177-C.strm',
      }),
      'IPX-177',
    );
    expect(
      javCodeForItem({'Name': 'WAAA-615 中文标题', 'Path': r'D:\Video\未整理\x.mp4'}),
      'WAAA-615',
    );
    expect(javCodeForItem({'Name': '没有番号'}), '');
    expect(javCodeForItem(null), '');
  });
}
