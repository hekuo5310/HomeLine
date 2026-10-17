import 'package:flutter_test/flutter_test.dart';
import 'package:homeline/app/app.dart';

void main() {
  testWidgets('Unconfigured app tells the truth about server setup', (
    tester,
  ) async {
    await tester.pumpWidget(const SetupRequiredApp());
    expect(find.textContaining('尚未配置电话服务器'), findsOneWidget);
    expect(find.text('通话中'), findsNothing);
  });
}
