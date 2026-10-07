import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// PNG와 WebP 양쪽에서 표현할 수 있는 ICC, EXIF, XMP만 복사한다.
/// PNG 전용 텍스트/감마 청크는 다른 형식의 청크로 임의 변환하지 않는다.
Map<String, Uint8List> pngMetadata(
  Uint8List png, {
  bool colorProfileOnly = false,
}) {
  final result = <String, Uint8List>{};
  final data = ByteData.sublistView(png);
  for (var offset = 8; offset + 12 <= png.length;) {
    final size = data.getUint32(offset);
    if (size > png.length - offset - 12) {
      throw const FormatException('잘못된 PNG 청크');
    }
    final type = ascii.decode(png.sublist(offset + 4, offset + 8));
    final payload = Uint8List.sublistView(png, offset + 8, offset + 8 + size);
    if ((colorProfileOnly ? ['iCCP'] : ['iCCP', 'eXIf', 'iTXt']).contains(
      type,
    )) {
      if (size > 16 * 1024 * 1024) {
        throw const FormatException('메타데이터가 16MB를 초과합니다.');
      }
      if (type == 'eXIf') result['EXIF'] = payload;
      if (type == 'iCCP') {
        final end = payload.indexOf(0);
        if (end < 1 || end + 2 > size || payload[end + 1] != 0) {
          throw const FormatException('잘못된 ICC 프로필');
        }
        result['ICCP'] = _inflate(payload.sublist(end + 2));
      }
      if (type == 'iTXt') {
        final end = payload.indexOf(0);
        if (end > 0 &&
            ascii.decode(payload.sublist(0, end), allowInvalid: true) ==
                'XML:com.adobe.xmp') {
          if (end + 3 > size) throw const FormatException('잘못된 XMP');
          final flag = payload[end + 1], method = payload[end + 2];
          final languageEnd = payload.indexOf(0, end + 3);
          final translatedEnd = languageEnd < 0
              ? -1
              : payload.indexOf(0, languageEnd + 1);
          if (translatedEnd < 0 || flag > 1 || method != 0) {
            throw const FormatException('잘못된 XMP');
          }
          final text = payload.sublist(translatedEnd + 1);
          result['XMP '] = flag == 1 ? _inflate(text) : text;
        }
      }
    }
    offset += size + 12;
    if (type == 'IEND') break;
  }
  return result;
}

// 압축 메타데이터가 과도하게 부풀어 메모리를 소진하지 않도록 제한한다.
class _LimitedSink implements Sink<List<int>> {
  final bytes = BytesBuilder(copy: false);
  @override
  void add(List<int> value) {
    if (bytes.length + value.length > 16 * 1024 * 1024) {
      throw const FormatException('압축 해제한 메타데이터가 16MB를 초과합니다.');
    }
    bytes.add(value);
  }

  @override
  void close() {}
}

Uint8List _inflate(List<int> bytes) {
  final sink = _LimitedSink();
  final decoder = ZLibDecoder().startChunkedConversion(sink);
  decoder.add(bytes);
  decoder.close();
  return sink.bytes.takeBytes();
}

/// libwebp의 픽셀 압축 결과에 표준 RIFF 청크를 붙인다.
/// VP8X를 먼저, ICC를 픽셀 앞에, EXIF/XMP를 뒤에 두고 홀수 크기는 패딩한다.
Uint8List attachMetadata(
  Uint8List webp,
  Map<String, Uint8List> metadata,
  int width,
  int height,
) {
  if (metadata.isEmpty) return webp;
  final chunks = <(String, Uint8List)>[];
  final data = ByteData.sublistView(webp);
  var flags = 0;
  for (var offset = 12; offset + 8 <= webp.length;) {
    final size = data.getUint32(offset + 4, Endian.little);
    if (offset + 8 + size > webp.length) {
      throw const FormatException('잘못된 WebP 청크');
    }
    final type = ascii.decode(webp.sublist(offset, offset + 4));
    final payload = Uint8List.sublistView(webp, offset + 8, offset + 8 + size);
    if (type == 'VP8X') {
      flags = payload[0];
    } else {
      chunks.add((type, payload));
      // 무손실 비트스트림의 alpha_is_used 비트를 확장 헤더에 반영한다.
      if (type == 'VP8L' && payload.length >= 5 && (payload[4] & 0x10) != 0) {
        flags |= 0x10;
      }
    }
    offset += 8 + size + (size & 1);
  }
  if (metadata.containsKey('ICCP')) flags |= 0x20;
  if (metadata.containsKey('EXIF')) flags |= 0x08;
  if (metadata.containsKey('XMP ')) flags |= 0x04;
  final header = Uint8List(10)..[0] = flags;
  for (var i = 0; i < 3; i++) {
    header[4 + i] = ((width - 1) >> (i * 8)) & 255;
    header[7 + i] = ((height - 1) >> (i * 8)) & 255;
  }
  final body = BytesBuilder()..add(ascii.encode('WEBP'));
  void chunk(String type, Uint8List payload) {
    body.add(ascii.encode(type));
    body.add(
      (ByteData(
        4,
      )..setUint32(0, payload.length, Endian.little)).buffer.asUint8List(),
    );
    body.add(payload);
    if (payload.length.isOdd) body.addByte(0);
  }

  chunk('VP8X', header);
  if (metadata['ICCP'] case final profile?) chunk('ICCP', profile);
  for (final entry in chunks) {
    chunk(entry.$1, entry.$2);
  }
  for (final type in ['EXIF', 'XMP ']) {
    if (metadata[type] case final payload?) chunk(type, payload);
  }
  return (BytesBuilder()
        ..add(ascii.encode('RIFF'))
        ..add(
          (ByteData(
            4,
          )..setUint32(0, body.length, Endian.little)).buffer.asUint8List(),
        )
        ..add(body.takeBytes()))
      .takeBytes();
}
