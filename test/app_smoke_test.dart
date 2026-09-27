import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/main.dart';

void main() {
  testWidgets('builds the Android MVP shell', (tester) async {
    await tester.pumpWidget(const KaoyanReviewApp());

    expect(find.text('考研碎片复习'), findsOneWidget);
  });
}
