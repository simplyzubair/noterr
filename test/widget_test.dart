import 'package:flutter_test/flutter_test.dart';
import 'package:noterr/app/noterr_app.dart';

void main() {
  testWidgets('starts by trying the saved device passphrase', (tester) async {
    await tester.pumpWidget(const NoterrApp(hasCloud: false));

    // AuthGate attempts unlockSavedDevice() on every start, cloud or not, so
    // the first frame is its auto-unlock screen rather than the PIN entry.
    // Secure storage is unavailable under flutter_test, so the attempt never
    // resolves and this is as far as the flow gets here.
    expect(find.text('Noterr'), findsNothing);
    expect(find.text('Opening Noterr'), findsOneWidget);
  });
}
