#include <cstddef>
#include <cstdint>
#include "src/webp/encode.h"
#ifdef _WIN32
#define API extern "C" __declspec(dllexport)
#else
#define API extern "C" __attribute__((visibility("default"))) __attribute__((used))
#endif
// C ABI 경계: 연속된 RGBA 8비트 픽셀을 받아 WebP 메모리를 반환한다.
// 반환값 0은 성공, 음수는 입력 오류, 양수는 WebPEncodingError다.
API int studio_encode(const uint8_t* rgba, int width, int height,
                      float quality, int lossless, int method,
                      uint8_t** result, size_t* length) {
  if (!result || !length) return -1;
  *result = nullptr;
  *length = 0;
  if (!rgba || width < 1 || height < 1 || width > 16383 || height > 16383) return -1;
  WebPConfig config;
  if (!WebPConfigInit(&config)) return -2;
  config.quality = quality;
  config.lossless = lossless;
  config.method = method;
  config.exact = 1; // 무손실 모드에서 완전히 투명한 픽셀의 RGB도 보존한다.
  config.thread_level = 1;
  if (!WebPValidateConfig(&config)) return -3;
  WebPPicture picture;
  if (!WebPPictureInit(&picture)) return -2;
  picture.width = width;
  picture.height = height;
  picture.use_argb = 1;
  WebPMemoryWriter writer;
  WebPMemoryWriterInit(&writer);
  picture.writer = WebPMemoryWrite;
  picture.custom_ptr = &writer;
  if (!WebPPictureImportRGBA(&picture, rgba, width * 4)) {
    WebPPictureFree(&picture);
    WebPMemoryWriterClear(&writer);
    return -4;
  }
  const int ok = WebPEncode(&config, &picture);
  const int error = picture.error_code;
  WebPPictureFree(&picture);
  if (!ok) {
    WebPMemoryWriterClear(&writer);
    return error == 0 ? -5 : error;
  }
  // 소유권을 Dart 호출자에게 이전한다. studio_free로 반드시 반환한다.
  *result = writer.mem;
  *length = writer.size;
  return 0;
}
API void studio_free(uint8_t* data) { WebPFree(data); }
