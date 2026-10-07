#!/usr/bin/env bash
# Apple Silicon Mac에서 실행. 코덱은 Flutter 빌드 훅이 자동으로 포함한다.
set -euo pipefail
cd "$(dirname "$0")/.."
flutter pub get
flutter analyze
flutter test
flutter build macos --release
mkdir -p dist
# 앱 번들 전체를 압축해야 프레임워크와 native 코덱이 함께 배포된다.
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "build/macos/Build/Products/Release/WebP Studio.app" "dist/WebP-Studio-macOS.zip"
