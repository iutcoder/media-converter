import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webp_studio/main.dart';

void main() {
  testWidgets('초기 화면과 작은 창에서 레이아웃이 정상이다', (tester) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const WebpStudio());
    expect(find.text('WebP Studio'), findsOneWidget);
    expect(find.text('PNG 파일을 여기에 놓으세요'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '0개 변환하기'))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(680, 660);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
