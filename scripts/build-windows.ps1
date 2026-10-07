# Windows + Visual Studio의 'C++를 사용한 데스크톱 개발' 워크로드가 필요하다.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
function Run-Flutter {
  & flutter @args
  if ($LASTEXITCODE -ne 0) { throw "Flutter 실패: $args" }
}
Run-Flutter pub get
Run-Flutter analyze
Run-Flutter test
Run-Flutter build windows --release
New-Item -ItemType Directory -Force -Path dist | Out-Null
# exe만 복사하지 않는다. DLL과 data 폴더를 포함한 Release 전체가 필요하다.
Compress-Archive -Path 'build/windows/x64/runner/Release/*' -DestinationPath 'dist/WebP-Studio-Windows.zip' -Force
