import 'package:image/image.dart' as img;

/// NovelAI 공식 alpha-LSB 형식: 열 우선(x → y), 바이트 안에서는 MSB 우선.
/// JSON을 복원하거나 기록하지 않고 식별자만 읽어 개인 프롬프트를 노출하지 않는다.
bool hasStealthMetadata(img.Image image) {
  const markers = ['stealth_pngcomp', 'stealth_pnginfo'];
  final bitCount = markers.first.length * 8;
  if (image.numChannels < 4 || image.width * image.height < bitCount) {
    return false;
  }
  final signature = <int>[];
  for (var byte = 0; byte < markers.first.length; byte++) {
    var value = 0;
    for (var bit = 0; bit < 8; bit++) {
      final position = byte * 8 + bit;
      final alpha = image
          .getPixel(position ~/ image.height, position % image.height)
          .a
          .toInt();
      value = (value << 1) | (alpha & 1);
    }
    signature.add(value);
  }
  return markers.contains(String.fromCharCodes(signature));
}

/// PeroPix와 같이 alpha가 전부 254/255이면 255로 복원한다.
/// 실제 반투명 이미지에서는 알려진 NAI 식별자가 있을 때만 LSB를 정리한다.
/// RGB는 바꾸지 않으며 alpha 변화는 최대 1/255이다.
bool removeStealthMetadata(img.Image image) {
  final detected = hasStealthMetadata(image);
  var nearlyOpaque = true;
  var needsNormalization = false;
  for (final pixel in image) {
    if (pixel.a < 254) {
      nearlyOpaque = false;
      break;
    }
    if (pixel.a == 254) needsNormalization = true;
  }
  if (nearlyOpaque) {
    if (needsNormalization) {
      for (final pixel in image) {
        pixel.a = 255;
      }
    }
    return detected || needsNormalization;
  }
  if (!detected) return false;
  for (final pixel in image) {
    final alpha = pixel.a.toInt();
    if (alpha != 0) pixel.a = alpha | 1;
  }
  return true;
}
