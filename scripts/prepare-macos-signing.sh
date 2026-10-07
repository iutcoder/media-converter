#!/bin/bash
# Apple QA1940: Finder/동기화 도구가 붙인 두 속성은 코드 서명을 막는다.
# 생성된 앱만 대상으로 하며 quarantine, 서명, 샌드박스 설정은 변경하지 않는다.
set -euo pipefail
bundle="${1:?앱 번들 경로가 필요합니다}"
if [[ ! -d "$bundle" || "$bundle" != *.app ]]; then
  echo "올바른 앱 번들이 아닙니다: $bundle" >&2
  exit 1
fi
# 재귀 처리를 한 번에 수행해 서명 직전에 번들 전체를 정리한다.
/usr/bin/xattr -dr com.apple.ResourceFork "$bundle"
/usr/bin/xattr -dr com.apple.FinderInfo "$bundle"
