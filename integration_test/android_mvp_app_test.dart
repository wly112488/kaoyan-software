import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kaoyan_review/app/app_services.dart';
import 'package:kaoyan_review/app/app_shell.dart';
import 'package:kaoyan_review/data/local/app_database.dart';
import 'package:kaoyan_review/features/review/review_item_detail_page.dart';
import 'package:kaoyan_review/features/settings/diagnostics_page.dart';
import 'package:kaoyan_review/runtime/notification_tap_bus.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final tapBus = NotificationTapBus.instance;

  testWidgets(
    'Android MVP persists entries and opens Diagnostics and tapped items',
    (tester) async {
      tapBus.takePendingItemId();
      var services = await AppServices.openProduction();
      final unique = DateTime.now().microsecondsSinceEpoch;
      final topic = await services.topics.createTopic(
        name: 'Android 验收 $unique',
        now: DateTime.now(),
      );
      final item = await services.reviewItems.createReviewItem(
        content: 'Android local persistence verification $unique',
        topicId: topic.id,
        enabled: true,
        now: DateTime.now(),
      );
      final secondItem = await services.reviewItems.createReviewItem(
        content: 'Android second item verification $unique',
        topicId: topic.id,
        enabled: true,
        now: DateTime.now().add(const Duration(seconds: 1)),
      );

      await tester.pumpWidget(MaterialApp(home: AppShell(services: services)));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text(item.content), findsOneWidget);
      expect(find.text(secondItem.content), findsOneWidget);

      await tester.tap(find.text('主题'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('主题管理'), findsOneWidget);
      expect(find.text(topic.name), findsOneWidget);
      expect(find.textContaining('2 条复习内容'), findsOneWidget);
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('提醒设置'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await services.close();
      services = await AppServices.openProduction();
      await tester.pumpWidget(MaterialApp(home: AppShell(services: services)));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text(item.content), findsOneWidget);
      expect(find.text(secondItem.content), findsOneWidget);
      await tester.tap(find.text('主题'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('主题管理'), findsOneWidget);
      expect(find.text(topic.name), findsOneWidget);
      expect(find.textContaining('2 条复习内容'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('提醒设置'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.text('主题'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('主题管理'), findsOneWidget);
      expect(find.textContaining('2 条复习内容'), findsOneWidget);
      await tester.tap(find.text('复习'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      tapBus.record(item.id);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.byType(ReviewItemDetailPage), findsOneWidget);
      expect(find.text(item.content), findsWidgets);

      await tester.pageBack();
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.tap(find.text('诊断信息'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.byType(DiagnosticsPage), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await services.close();
      final reopened = await AppDatabase.openProduction();
      try {
        final persisted = await AppServices(store: reopened).reviewItems
            .getReviewItem(item.id);
        expect(persisted?.content, item.content);
      } finally {
        await reopened.close();
        tapBus.takePendingItemId();
      }
    },
  );
}
