import 'package:flutter_test/flutter_test.dart';
import 'package:noterr/app/noterr_app.dart';

void main() {
  testWidgets('starts in local unlock flow', (tester) async {
    await tester.pumpWidget(const NoterrApp(hasCloud: false));

    // The unlock screen opens in its loading state while it checks whether a
    // PIN already exists. Secure storage is unavailable under flutter_test, so
    // this is as far as the flow gets here.
    expect(find.text('Noterr'), findsNothing);
    expect(find.text('Opening Noterr…'), findsOneWidget);
  });
}
