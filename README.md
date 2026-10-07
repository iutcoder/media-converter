# WebP Studio

Flutter 화면 + Dart 작업 관리 + C++/libwebp 변환 엔진으로 만든 macOS·Windows용 PNG 일괄 변환 앱입니다. Python 실행 환경이나 외부 코덱 설치는 필요하지 않습니다.

## 구현된 기능

- PNG 여러 장 불러오기: Finder/탐색기 파일 선택 또는 드래그 & 드롭.
- 썸네일 목록과 드래그 정렬. 손잡이를 잡아 순서를 변경합니다.
- 일괄 이름 변경: 선택적 접두어, 시작 번호, 최소 자릿수. 접두어 없이도 `001.webp`, `002.webp`처럼 번호를 사용합니다. 번호가 자릿수보다 크면 잘라내지 않습니다.
- 목록에서 저장될 이름 미리 보기. 원본 PNG의 이름·내용은 변경하지 않습니다.
- 공통 옵션과 파일별 옵션: 손실/무손실, 품질(무손실에서는 압축 노력), 인코딩 속도, 긴 변 크기 제한.
- 비율 유지 축소, 투명도 보존, 저장 폴더 선택. macOS 선택창의 새 폴더 생성을 활성화했습니다.
- 기존 결과와 이름이 겹치면 `(1)`, `(2)`를 자동으로 붙입니다. 파일 생성 시 독점 생성으로 덮어쓰기를 방지합니다.
- 이미지별 진행·오류 표시, 현재 이미지 완료 후 중단, 실패 이후 다음 파일 계속 처리.

## 실행 및 패키징

개발 기준: Flutter **3.47.4 / Dart 3.13.3**. `pubspec.lock`으로 패키지 버전을 고정했습니다.
빌드 훅이 포함된 libwebp 소스를 자동으로 컴파일합니다. 별도로 Homebrew libwebp나 CMake를 설치할 필요는 없습니다. Windows의 Flutter 빌드 도구에는 Visual Studio CMake 구성 요소가 필요합니다.

### macOS (Apple Silicon)

Flutter와 Xcode를 설치하고 Xcode 초기 설정 및 라이선스 동의를 완료한 Mac에서 실행합니다.

```sh
flutter pub get
flutter run -d macos
```

테스트·릴리스 빌드·ZIP 생성을 한 번에 실행합니다.

```sh
bash scripts/build-macos.sh
```

결과: `dist/WebP-Studio-macOS.zip`. 앱 번들 전체가 포함됩니다.
앱 샌드박스를 유지하며, 사용자가 선택한 파일과 폴더에 대한 읽기·쓰기 권한을 사용합니다. Finder 드롭의 보안 범위 접근도 처리합니다.
다른 사람에게 정식 배포할 때는 Developer ID 서명·공증을 별도로 구성해야 합니다. 현재 스크립트는 업로드나 공증을 수행하지 않습니다.

### Windows (x64)

Flutter와 Visual Studio 2022의 **C++를 사용한 데스크톱 개발** 워크로드 및 Windows SDK를 설치합니다. Visual Studio Code만 설치한 환경과는 다릅니다.

```powershell
flutter pub get
flutter run -d windows
powershell -File scripts/build-windows.ps1
```

결과: `dist/WebP-Studio-Windows.zip`. 압축을 풀고 `webp_studio.exe`를 실행합니다. DLL과 data 폴더도 함께 보관해야 합니다. 대상 PC에는 Visual C++ 런타임이 필요할 수 있습니다. 설치 프로그램/MSIX와 코드 서명은 이번 버전에 포함하지 않았습니다.
Windows 패키지는 Windows에서, macOS 패키지는 Mac에서 빌드합니다.

### 자동 빌드

`.github/workflows/build.yml`에 두 운영체제용 테스트·빌드·ZIP 아티팩트 구성을 준비했습니다. GitHub Actions에서 수동 실행하거나 `v*` 태그를 푸시하면 실행됩니다. GitHub Actions의 실제 빌드 실행은 아직 검증하지 않았습니다.

## 구조와 수정 위치

| 파일 | 역할 |
| --- | --- |
| `lib/main.dart` | 화면, 파일 목록, 순서, 공통/개별 설정, 작업 상태 |
| `lib/src/metadata.dart` | PNG 메타데이터 추출 및 WebP 표준 RIFF 청크 구성 |
| `lib/src/converter.dart` | 안전한 이름 생성, PNG 디코딩, 축소, 충돌 없는 저장 |
| `packages/webp_engine/lib/webp_engine.dart` | Dart ↔ native FFI 및 메모리 반환 |
| `packages/webp_engine/src/encoder.cpp` | C++ 변환 엔진, libwebp 설정 및 오류 처리 |
| `packages/webp_engine/hook/build.dart` | 플랫폼에 맞는 native 라이브러리 빌드 및 번들링 |
| `test/` | 실제 코덱 왕복, 파일 보호, 오류 처리 및 화면 크기 테스트 |
| `scripts/` | 운영체제별 패키지 생성 |

새로 작성한 핵심 로직에는 한국어 주석을 넣었습니다. Flutter 생성 파일과 외부 코덱 소스는 원래 주석을 유지합니다.
PNG 디코딩과 리사이즈는 Dart, WebP 압축은 C++ 래퍼와 C 라이브러리인 libwebp가 담당합니다. 압축 작업은 별도 isolate에서 처리해 화면이 멈추지 않게 했습니다.

## 현재 제한과 검증 상태

- 현재는 정지 PNG만 지원합니다. GIF·MP4·APNG의 애니메이션 변환은 후속 단계입니다.
- 입력은 파일당 256MB·4천만 픽셀 이하. WebP 출력은 한 변 16,383픽셀 이하입니다.
- WebP는 채널당 8비트이므로 16비트 PNG는 8비트로 줄어듭니다. “무손실”은 이 변환 및 선택한 리사이즈 이후 픽셀 기준입니다.
- EXIF·XMP와 알려진 NAI 숨김 정보는 항상 제거합니다. 공통/개별 설정에는 ICC 색상 프로필만 선택적으로 보존할 수 있으며 기본은 ICC도 제거입니다. PNG 일반 텍스트·감마 청크도 복사하지 않습니다. ICC 제거 시 색상 표시가 달라질 수 있습니다. 메타데이터 청크당 16MB 제한이 있습니다.
- 폴더 재귀 가져오기, 설정 영구 저장, 임의의 크기 직접 입력은 아직 없습니다. 제공된 선택값을 사용합니다.
- 중단은 현재 이미지 인코딩이 끝난 다음 적용됩니다. 저장 도중 앱을 강제 종료하면 마지막 파일이 불완전할 수 있습니다.
- macOS에서 실제 C++ 코덱/isolate 테스트와 Flutter 화면 실제 사용자 샘플 테스트를 포함한 18개를 통과했고, 정적 검사도 통과했습니다. 전체 앱의 Finder 드롭/파일 선택과 Windows 네이티브 실행은 아직 실기 검증하지 못했습니다.
- macOS 릴리스 빌드는 이 작업 환경의 Xcode/Swift 캐시 폴더 쓰기 권한 제한으로 중단되었습니다. **실행 앱이 빌드 완료된 배포본은 아닙니다.** 허용된 일반 개발 환경에서 위 스크립트를 실행해야 합니다.

## 외부 코드

libwebp 1.6.0은 공식 릴리스 소스를 포함하며 BSD 라이선스와 PATENTS 파일을 보관합니다. 앱 정보의 라이선스 화면에서도 고지합니다. Flutter/Dart 패키지 고지는 Flutter 라이선스 화면에 포함됩니다.

참고: [Flutter native FFI](https://docs.flutter.dev/platform-integration/bind-native-code), [macOS 빌드](https://docs.flutter.dev/deployment/macos), [Windows 빌드](https://docs.flutter.dev/deployment/windows), [libwebp](https://developers.google.com/speed/webp/docs/api).

## macOS CodeSign 오류 수정

`resource fork, Finder information, or similar detritus not allowed`는 앱 번들에 붙은 FinderInfo/ResourceFork 속성 때문에 발생할 수 있습니다. Xcode의 마지막 프레임워크 복사 단계에서 `scripts/prepare-macos-signing.sh`를 실행하도록 구성했습니다. 생성된 앱의 두 속성만 정리하며, quarantine이나 샌드박스 설정은 변경하지 않습니다.

2026-10-06: 실제 실패한 Debug 앱에 적용한 뒤 코드 서명 및 `codesign --verify --deep --strict` 검증이 통과했습니다. 수정 후 Flutter 전체 빌드/GUI 실행은 별도로 다시 확인해야 합니다. 반복되는 `-Wl,-encryptable` 경고는 이 CodeSign 오류와 별개입니다.

## NAI 숨김 정보 제거 (0.1.3)

EXIF/XMP는 설정과 무관하게 항상 제거하며, 색상용 ICC만 선택적으로 보존합니다. 외부 Python 실행 환경 없이 Dart/C++로 처리합니다.

참고한 PeroPix backend.py의 처리처럼 alpha가 모두 254/255인 이미지는 255로 복원합니다. 실제 반투명 이미지에서는 alpha-LSB의 stealth_pngcomp/stealth_pnginfo 식별자가 감지될 때만 LSB를 정리합니다. RGB와 완전히 투명한 픽셀은 유지하고 alpha 변화는 최대 1/255입니다. 무손실 압축은 정리 이후 픽셀에 적용됩니다. 임의의 모든 스테가노그래피 형식 제거를 보장하지는 않습니다.

사용자 샘플 31.webp는 EXIF/XMP/ICC 청크 없이 NAI alpha-LSB 정보가 있는 파일이었습니다. 이를 제거한 출력에서 RGB가 바뀌지 않고 NAI 식별자와 EXIF/XMP/ICC가 없는 것을 확인했습니다. 참고용 Python 소스와 사용자 원본은 수정하지 않았습니다.

기존 출력은 자동 수정되지 않습니다. 다시 변환하면 중복 이름에 (1), (2)가 붙으므로 완료 목록에 표시된 실제 저장 파일을 확인하세요. 실행 중인 앱은 종료한 뒤 다시 실행해야 새 설정이 반영됩니다.
