import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:webp_studio/src/converter.dart';
import 'package:webp_studio/src/stealth_metadata.dart';

// NAI와 같은 순서로 무해한 테스트 프롬프트를 alpha 최하위 비트에 넣는다.
img.Image fixture(String marker) {
  final image = img.Image(width: 64, height: 64, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(64, 128, 192, 255));
  final text = utf8.encode('{"Comment":"test prompt","seed":123}');
  final payload = marker.endsWith('comp') ? gzip.encode(text) : text;
  final length = payload.length * 8;
  final bytes = [
    ...ascii.encode(marker),
    for (var shift = 24; shift >= 0; shift -= 8) (length >> shift) & 255,
    ...payload,
  ];
  for (var i = 0; i < bytes.length * 8; i++) {
    image.getPixel(i ~/ image.height, i % image.height).a =
        254 | ((bytes[i ~/ 8] >> (7 - i % 8)) & 1);
  }
  return image;
}

void main() {
  for (final marker in ['stealth_pngcomp', 'stealth_pnginfo']) {
    test('$marker 본문까지 제거하며 RGB와 원본은 유지한다', () {
      final image = fixture(marker);
      expect(hasStealthMetadata(image), true);
      final dir = Directory.systemTemp.createTempSync('nai-strip-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final source = File('${dir.path}/source.png')
        ..writeAsBytesSync(img.encodePng(image));
      for (final lossless in [true, false]) {
        final result = convertPng(
          source.path,
          dir.path,
          '$lossless.webp',
          EncodeOptions(lossless: lossless),
        );
        expect(result.stealthRemoved, true);
        final output = img.decodeWebP(File(result.path).readAsBytesSync())!;
        expect(hasStealthMetadata(output), false);
        // 헤더만 망가뜨린 것이 아니라 전체 alpha에 남은 비트도 제거됐는지 확인한다.
        for (final pixel in output) {
          expect(pixel.a, 255);
        }
        if (lossless) {
          expect(output.getPixel(0, 0).r, 64);
          expect(output.getPixel(0, 0).g, 128);
          expect(output.getPixel(0, 0).b, 192);
        }
      }
      final preserved = convertPng(
        source.path,
        dir.path,
        'preserved.webp',
        const EncodeOptions(lossless: true, keepColorProfile: true),
      );
      expect(preserved.stealthRemoved, true);
      expect(
        hasStealthMetadata(
          img.decodeWebP(File(preserved.path).readAsBytesSync())!,
        ),
        false,
      );
      expect(
        hasStealthMetadata(img.decodePng(source.readAsBytesSync())!),
        true,
      );
      final resized = convertPng(
        source.path,
        dir.path,
        'resized.webp',
        const EncodeOptions(maxEdge: 32),
      );
      expect(resized.stealthRemoved, true);
      expect(
        hasStealthMetadata(
          img.decodeWebP(File(resized.path).readAsBytesSync())!,
        ),
        false,
      );
    });
  }
  test('일반 반투명 이미지와 작은 이미지의 픽셀은 변경하지 않는다', () {
    for (final size in [2, 64]) {
      final image = img.Image(width: size, height: size, numChannels: 4);
      img.fill(image, color: img.ColorRgba8(10, 20, 30, 128));
      final original = image.getBytes();
      expect(removeStealthMetadata(image), false);
      expect(image.getBytes(), original);
    }
  });
}
