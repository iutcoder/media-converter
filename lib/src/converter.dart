import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:webp_engine/webp_engine.dart';

import 'metadata.dart';
import 'stealth_metadata.dart';

/// 값 객체로 전달하므로 UI 설정 변경과 진행 중인 작업이 서로 간섭하지 않는다.
class EncodeOptions {
  final bool lossless;
  final bool keepColorProfile;
  final double quality;
  final int method;
  final int maxEdge;
  const EncodeOptions({
    this.lossless = false,
    this.keepColorProfile = false,
    this.quality = 80,
    this.method = 4,
    this.maxEdge = 0,
  });
}

/// Windows에서도 유효한 파일명으로 정규화한다. 경로 이동 문자를 허용하지 않는다.
String safeStem(String value) {
  var s = value
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  if (s.isEmpty) s = 'image';
  if (RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
    caseSensitive: false,
  ).hasMatch(s)) {
    s = '_$s';
  }
  // 너무 긴 파일명은 운영체제별 경로 제한에 걸릴 수 있다.
  return String.fromCharCodes(s.runes.take(80));
}

String outputName(
  String path,
  int index, {
  String prefix = '',
  int start = 1,
  int digits = 3,
}) {
  final number = (start + index).toString().padLeft(digits, '0');
  final stem = prefix.trim().isEmpty ? number : '${prefix.trim()}_$number';
  return '${safeStem(stem)}.webp';
}

class ConversionResult {
  final String path;
  final int bytes;
  final bool stealthRemoved;
  const ConversionResult(this.path, this.bytes, {this.stealthRemoved = false});
}

/// CPU 작업은 UI가 아닌 isolate에서 실행한다. 모든 파일 처리는 한 장씩 수행한다.
ConversionResult convertPng(
  String source,
  String directory,
  String name,
  EncodeOptions options,
) {
  final file = File(source);
  if (file.lengthSync() > 256 * 1024 * 1024) {
    throw StateError('PNG 파일은 256MB 이하만 지원합니다.');
  }
  final bytes = file.readAsBytesSync();
  final decoder = img.PngDecoder();
  final info = decoder.startDecode(bytes);
  if (info == null) throw StateError('올바른 PNG 파일이 아닙니다.');
  if (info.numFrames > 1) throw StateError('애니메이션 PNG는 아직 지원하지 않습니다.');
  // 디코딩 전에 크기를 검사해 손상된 파일이나 과도한 메모리 사용을 막는다.
  if (info.width * info.height > 40000000) {
    throw StateError('이미지는 4천만 픽셀 이하만 지원합니다.');
  }
  var image = decoder.decodeFrame(0);
  if (image == null) throw StateError('PNG 데이터를 읽을 수 없습니다.');
  // 리사이즈 전에 숨김 정보를 찾아 제거해야 위치가 바뀌어 놓치는 일이 없다.
  image = image.convert(format: img.Format.uint8, numChannels: 4);
  final stealthRemoved = removeStealthMetadata(image);
  if (options.maxEdge > 0 &&
      math.max(image.width, image.height) > options.maxEdge) {
    final ratio = options.maxEdge / math.max(image.width, image.height);
    image = img.copyResize(
      image,
      width: math.max(1, (image.width * ratio).round()),
      height: math.max(1, (image.height * ratio).round()),
      interpolation: img.Interpolation.average,
    );
  }
  // WebP는 채널당 8비트다. 16비트 PNG도 명시적으로 8비트 RGBA로 변환한다.
  image = image.convert(format: img.Format.uint8, numChannels: 4);
  var encoded = encodeWebp(
    image.getBytes(order: img.ChannelOrder.rgba),
    image.width,
    image.height,
    quality: options.quality,
    lossless: options.lossless,
    method: options.method,
  );
  if (options.keepColorProfile) {
    encoded = attachMetadata(
      encoded,
      pngMetadata(bytes, colorProfileOnly: true),
      image.width,
      image.height,
    );
  }
  final folder = Directory(directory);
  if (!folder.existsSync()) throw StateError('저장 폴더가 존재하지 않습니다.');
  final stem = safeStem(p.basenameWithoutExtension(name));
  File? destination;
  // exclusive 생성으로 다른 프로세스가 같은 파일을 만들어도 덮어쓰지 않는다.
  for (var suffix = 0; suffix < 10000; suffix++) {
    final candidate = File(
      p.join(directory, '$stem${suffix == 0 ? '' : ' ($suffix)'}.webp'),
    );
    try {
      candidate.createSync(exclusive: true);
      destination = candidate;
      break;
    } on FileSystemException {
      if (FileSystemEntity.typeSync(candidate.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        continue;
      }
      rethrow;
    }
  }
  if (destination == null) throw StateError('사용 가능한 파일명을 찾지 못했습니다.');
  try {
    destination.writeAsBytesSync(encoded, flush: true);
  } catch (_) {
    // 쓰기 실패 시 이번 작업이 생성한 빈 파일만 정리한다.
    try {
      destination.deleteSync();
    } catch (_) {}
    rethrow;
  }
  return ConversionResult(
    destination.path,
    encoded.length,
    stealthRemoved: stealthRemoved,
  );
}

/// UI 객체가 isolate 클로저에 포함되지 않도록 최상위 함수에서 실행한다.
Future<ConversionResult> convertPngAsync(
  String source,
  String directory,
  String name,
  EncodeOptions options,
) => Isolate.run(() => convertPng(source, directory, name, options));
