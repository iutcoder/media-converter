// ignore_for_file: non_constant_identifier_names
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

@Native<
  Int32 Function(
    Pointer<Uint8>,
    Int32,
    Int32,
    Float,
    Int32,
    Int32,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
>()
external int studio_encode(
  Pointer<Uint8> pixels,
  int width,
  int height,
  double quality,
  int lossless,
  int method,
  Pointer<Pointer<Uint8>> out,
  Pointer<Size> size,
);
@Native<Void Function(Pointer<Uint8>)>()
external void studio_free(Pointer<Uint8> data);

/// 작업용 isolate에서 호출한다. native 메모리는 finally에서 항상 반환한다.
Uint8List encodeWebp(
  Uint8List rgba,
  int width,
  int height, {
  double quality = 80,
  bool lossless = false,
  int method = 4,
}) {
  if (width < 1 ||
      height < 1 ||
      width > 16383 ||
      height > 16383 ||
      rgba.length != width * height * 4) {
    throw ArgumentError('잘못된 이미지 크기 또는 RGBA 데이터');
  }
  final pixels = calloc<Uint8>(rgba.length);
  final out = calloc<Pointer<Uint8>>();
  final size = calloc<Size>();
  try {
    pixels.asTypedList(rgba.length).setAll(0, rgba);
    final error = studio_encode(
      pixels,
      width,
      height,
      quality,
      lossless ? 1 : 0,
      method,
      out,
      size,
    );
    if (error != 0) throw StateError('WebP 인코딩 실패 (코드 $error)');
    return Uint8List.fromList(out.value.asTypedList(size.value));
  } finally {
    if (out.value != nullptr) studio_free(out.value);
    calloc.free(pixels);
    calloc.free(out);
    calloc.free(size);
  }
}
