import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:homeline/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Unconfigured installation starts without fake calls', (
    tester,
  ) async {
    app.main();
    await tester.pumpAndSettle();
    expect(find.textContaining('尚未配置电话服务器'), findsOneWidget);
    expect(find.text('通话中'), findsNothing);
  });
}
