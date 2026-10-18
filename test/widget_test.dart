import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:homeline/app/app.dart';

void main() {
  testWidgets('Unconfigured app tells the truth about server setup', (
    tester,
  ) async {
    await tester.pumpWidget(const SetupRequiredApp());
    expect(find.textContaining('尚未配置电话服务器'), findsOneWidget);
    expect(find.text('通话中'), findsNothing);
  });
  testWidgets(
    'Runtime setup rejects insecure endpoints without storage or networking',
    (tester) async {
      await tester.pumpWidget(const SetupRequiredApp());
      await tester.enterText(find.byType(TextField), 'http://example.com');
      await tester.tap(find.text('连接服务器'));
      await tester.pumpAndSettle();
      expect(find.textContaining('地址无效'), findsOneWidget);
    },
  );
}
