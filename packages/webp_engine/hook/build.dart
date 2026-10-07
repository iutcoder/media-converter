import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

// 코덱 소스를 앱과 함께 빌드한다. 사용자 PC에는 별도 설치가 필요 없다.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    const root = 'vendor/libwebp';
    final sources = <String>[];
    for (final dir in [
      'src/dec',
      'src/enc',
      'src/dsp',
      'src/utils',
      'sharpyuv',
    ]) {
      final files = Directory.fromUri(input.packageRoot.resolve('$root/$dir'))
          .listSync();
      sources.addAll(
        files
            .whereType<File>()
            .where((f) => f.path.endsWith('.c'))
            .map((f) => '$root/$dir/${f.uri.pathSegments.last}'),
      );
    }
    sources.sort();
    // C 코덱과 C++ 래퍼를 각 언어로 컴파일한 뒤 정적으로 연결한다.
    await CBuilder.library(
      name: 'webp_static',
      sources: sources,
      includes: [root],
      defines: {'WEBP_USE_THREAD': null},
      linkModePreference: LinkModePreference.static,
    ).run(input: input, output: output);
    await CBuilder.library(
      name: 'webp_engine',
      assetName: 'webp_engine.dart',
      sources: ['src/encoder.cpp'],
      includes: [root],
      language: Language.cpp,
      libraries: ['webp_static'],
      libraryDirectories: [input.outputDirectory.toFilePath()],
    ).run(input: input, output: output);
  });
}
