import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:webp_studio/src/converter.dart';

void main() {
  late Directory directory;
  late String source;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('webp-studio-test-');
    source = p.join(directory.path, '원본.png');
    final image = img.Image(width: 32, height: 16, numChannels: 4);
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 32; x++) {
        image.setPixelRgba(x, y, x * 7, y * 13, 127, x * 8);
      }
    }
    File(source).writeAsBytesSync(img.encodePng(image));
  });
  tearDown(() => directory.deleteSync(recursive: true));
  test('백그라운드 isolate에서 native 변환 결과를 반환한다', () async {
    final result = await convertPngAsync(
      source,
      directory.path,
      'async.webp',
      const EncodeOptions(),
    );
    expect(img.decodeWebP(File(result.path).readAsBytesSync())!.width, 32);
  });
  test('무손실 RGBA 왕복과 원본 보호', () {
    final original = File(source).readAsBytesSync();
    final result = convertPng(
      source,
      directory.path,
      '결과.webp',
      const EncodeOptions(lossless: true),
    );
    final png = img.decodePng(original)!;
    final webp = img.decodeWebP(File(result.path).readAsBytesSync())!;
    expect(
      webp.getBytes(order: img.ChannelOrder.rgba),
      png.getBytes(order: img.ChannelOrder.rgba),
    );
    expect(File(source).readAsBytesSync(), original);
  });
  test('비율 유지 축소와 손실 압축', () {
    final result = convertPng(
      source,
      directory.path,
      'small.webp',
      const EncodeOptions(maxEdge: 16),
    );
    final image = img.decodeWebP(File(result.path).readAsBytesSync())!;
    expect(image.width, 16);
    expect(image.height, 8);
  });
  test('기존 결과는 덮어쓰지 않는다', () {
    final first = convertPng(
      source,
      directory.path,
      'image.webp',
      const EncodeOptions(),
    );
    final bytes = File(first.path).readAsBytesSync();
    final second = convertPng(
      source,
      directory.path,
      'image.webp',
      const EncodeOptions(),
    );
    expect(p.basename(second.path), 'image (1).webp');
    expect(File(first.path).readAsBytesSync(), bytes);
  });
  test('손상된 PNG는 결과 파일을 남기지 않는다', () {
    File(source).writeAsStringSync('invalid');
    expect(
      () =>
          convertPng(source, directory.path, 'bad.webp', const EncodeOptions()),
      throwsA(anything),
    );
    expect(File(p.join(directory.path, 'bad.webp')).existsSync(), false);
  });
  test('파일명은 안전하고 순서에 따라 번호가 매겨진다', () {
    expect(safeStem('../bad:name'), '.._bad_name');
    expect(safeStem('CON'), '_CON');
    expect(
      outputName(source, 2, prefix: '사진', start: 10, digits: 4),
      '사진_0012.webp',
    );
  });
}
