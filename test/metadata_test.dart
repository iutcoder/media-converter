import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:webp_studio/src/converter.dart';

// 실제 PNG 파일에 유효한 CRC를 가진 부가 청크를 추가한다.
Uint8List pngChunk(String type, List<int> payload) {
  final bytes = [...ascii.encode(type), ...payload];
  var crc = 0xffffffff;
  for (final b in bytes) {
    crc ^= b;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc >> 1) ^ ((crc & 1) != 0 ? 0xedb88320 : 0);
    }
  }
  return (BytesBuilder()
        ..add((ByteData(4)..setUint32(0, payload.length)).buffer.asUint8List())
        ..add(bytes)
        ..add(
          (ByteData(4)..setUint32(0, crc ^ 0xffffffff)).buffer.asUint8List(),
        ))
      .takeBytes();
}

Map<String, Uint8List> riffChunks(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  expect(data.getUint32(4, Endian.little), bytes.length - 8);
  final chunks = <String, Uint8List>{};
  for (var pos = 12; pos < bytes.length;) {
    final size = data.getUint32(pos + 4, Endian.little);
    chunks[ascii.decode(bytes.sublist(pos, pos + 4))] = bytes.sublist(
      pos + 8,
      pos + 8 + size,
    );
    if (size.isOdd) expect(bytes[pos + 8 + size], 0);
    pos += 8 + size + (size & 1);
  }
  return chunks;
}

void main() {
  for (final lossless in [false, true]) {
    for (final compressedXmp in [false, true]) {
      test('메타데이터 보존/제거: lossless=$lossless, compressedXmp=$compressedXmp', () {
        final dir = Directory.systemTemp.createTempSync('webp-metadata-');
        addTearDown(() => dir.deleteSync(recursive: true));
        final pixels = img.Image(width: 8, height: 4, numChannels: 4);
        img.fill(pixels, color: img.ColorRgba8(120, 60, 30, 128));
        final png = img.encodePng(pixels);
        final exif = Uint8List.fromList([
          0x49,
          0x49,
          42,
          0,
          8,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
        ]);
        final xmp = utf8.encode(
          '<x:xmpmeta xmlns:x="adobe:ns:meta/">테스트</x:xmpmeta>',
        );
        // ICC 컨테이너의 바이트 보존을 검사한다. 색 변환 테스트가 아니다.
        final icc = Uint8List(128);
        ByteData.sublistView(icc).setUint32(0, 128);
        icc.setRange(36, 40, ascii.encode('acsp'));
        final source = File('${dir.path}/metadata.png');
        source.writeAsBytesSync([
          ...png.sublist(0, 33),
          ...pngChunk('iCCP', [
            ...ascii.encode('ICC'),
            0,
            0,
            ...zlib.encode(icc),
          ]),
          ...pngChunk('eXIf', exif),
          ...pngChunk('iTXt', [
            ...ascii.encode('XML:com.adobe.xmp'),
            0,
            compressedXmp ? 1 : 0,
            0,
            0,
            0,
            ...compressedXmp ? zlib.encode(xmp) : xmp,
          ]),
          ...png.sublist(33),
        ]);
        for (final strip in [false, true]) {
          final result = convertPng(
            source.path,
            dir.path,
            '$strip.webp',
            EncodeOptions(lossless: lossless, keepColorProfile: !strip),
          );
          final bytes = File(result.path).readAsBytesSync();
          final chunks = riffChunks(bytes);
          if (strip) {
            expect(chunks.keys, isNot(contains('ICCP')));
            expect(chunks.keys, isNot(contains('EXIF')));
            expect(chunks.keys, isNot(contains('XMP ')));
          } else {
            expect(chunks['ICCP'], icc);
            expect(chunks.keys, isNot(contains('EXIF')));
            expect(chunks.keys, isNot(contains('XMP ')));
            expect(chunks['VP8X']![0] & 0x3c, 0x30);
          }
          final decoded = img.decodeWebP(bytes)!;
          expect(decoded.width, 8);
          expect(decoded.height, 4);
          expect(decoded.getPixel(0, 0).a, 128);
        }
      });
    }
  }
  test('접두어 없이 시작 번호와 최소 자릿수를 적용한다', () {
    expect(outputName('original.png', 0, digits: 1), '1.webp');
    expect(outputName('original.png', 0, digits: 3), '001.webp');
    expect(
      outputName('original.png', 2, prefix: '  ', start: 10, digits: 4),
      '0012.webp',
    );
    expect(outputName('original.png', 0, start: 100, digits: 2), '100.webp');
  });
}
