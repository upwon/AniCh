import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:xs/src/widgets/navbar.dart';

void main() {
  testWidgets('main navigation stays available on the anime page',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    await tester.pumpWidget(const GetMaterialApp(
      home: Scaffold(
        bottomNavigationBar: AppMainNavBar(selectedRoute: '/bangumi'),
      ),
    ));

    expect(find.text('图片'), findsOneWidget);
    expect(find.text('番剧'), findsOneWidget);
    expect(find.text('缓存'), findsOneWidget);
    expect(find.text('历史'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(null);
  });
}
