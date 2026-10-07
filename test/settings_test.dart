import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webp_studio/main.dart';
import 'package:webp_studio/src/converter.dart';

class DirectoryPicker extends FileSelectorPlatform {
  FileDialogOptions? received;
  @override
  Future<String?> getDirectoryPathWithOptions(FileDialogOptions options) async {
    received = options;
    return '/tmp/selected-output';
  }
}

void main() {
  testWidgets('저장 폴더 선택창에 새 폴더 생성 옵션을 전달한다', (tester) async {
    final original = FileSelectorPlatform.instance;
    final picker = DirectoryPicker();
    FileSelectorPlatform.instance = picker;
    addTearDown(() => FileSelectorPlatform.instance = original);
    tester.view.physicalSize = const Size(1180, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const WebpStudio());
    final button = find.text('저장 폴더 선택');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(picker.received!.canCreateDirectories, true);
    expect(find.text('/tmp/selected-output'), findsOneWidget);
  });
  testWidgets('메타데이터 옵션 변경 시 다른 변환 설정을 보존한다', (tester) async {
    var current = const EncodeOptions(
      lossless: true,
      quality: 90,
      maxEdge: 512,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: OptionsEditor(
                value: current,
                onChanged: (v) => setState(() => current = v),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('색상 프로필(ICC)만 보존'));
    await tester.pump();
    expect(current.keepColorProfile, true);
    expect(current.lossless, true);
    expect(current.quality, 90);
    expect(current.maxEdge, 512);
    expect(tester.takeException(), isNull);
  });
}
