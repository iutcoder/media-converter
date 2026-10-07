import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:webp_engine/webp_engine.dart';
import 'package:webp_studio/src/stealth_metadata.dart';

// 사용자 파일은 프로젝트/ZIP에 포함하지 않고 명시된 경우에만 읽는다.
void main() {
  const source = String.fromEnvironment('SAMPLE_WEBP');
  const destination = String.fromEnvironment('CLEAN_WEBP');
  test('사용자 샘플의 숨김 데이터 제거 및 RGB 보존', () {
    final original = File(source).readAsBytesSync();
    final image = img
        .decodeWebP(original)!
        .convert(format: img.Format.uint8, numChannels: 4);
    final rgb = image.getBytes(order: img.ChannelOrder.rgb);
    final detected = hasStealthMetadata(image);
    var minimum = 255;
    for (final pixel in image) {
      if (pixel.a < minimum) minimum = pixel.a.toInt();
    }
    // 프롬프트 본문은 출력하지 않는다.
    // ignore: avoid_print -- 샘플 검사 결과만 출력하며 프롬프트는 출력하지 않는다.
    print(
      'sample: ${image.width}x${image.height}, alphaMin=$minimum, stealth=$detected',
    );
    expect(detected, true);
    expect(removeStealthMetadata(image), true);
    final encoded = encodeWebp(
      image.getBytes(order: img.ChannelOrder.rgba),
      image.width,
      image.height,
      lossless: true,
    );
    final decoded = img.decodeWebP(encoded)!;
    expect(hasStealthMetadata(decoded), false);
    expect(decoded.getBytes(order: img.ChannelOrder.rgb), rgb);
    for (final pixel in decoded) {
      expect(pixel.a, 255);
    }
    expect(File(source).readAsBytesSync(), original);
    if (destination.isNotEmpty) File(destination).writeAsBytesSync(encoded);
  }, skip: source.isEmpty ? '샘플 파일이 지정된 경우에만 실행' : false);
}
