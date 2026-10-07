# WebP engine

C++ 래퍼와 libwebp 1.6.0 소스를 포함한 Dart FFI 패키지입니다.

- `src/encoder.cpp`: C ABI, libwebp 옵션, native 메모리 소유권 관리.
- `lib/webp_engine.dart`: 직접 선언한 FFI 바인딩. 별도의 코드 생성은 없습니다.
- `hook/build.dart`: C 코덱을 정적 빌드하고 C++ 공유 라이브러리에 연결합니다.
- `vendor/libwebp`: 공식 1.6.0 소스, COPYING/PATENTS/AUTHORS 포함.

루트 프로젝트의 `flutter test`에서 실제 native 인코더까지 검사합니다.
호출은 UI를 막지 않도록 작업용 isolate에서 수행해야 합니다.
PNG 디코딩·리사이즈·저장은 앱의 `lib/src/converter.dart`가 담당합니다.
