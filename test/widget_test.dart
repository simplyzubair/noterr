import 'package:flutter_test/flutter_test.dart';
import 'package:noterr/app/noterr_app.dart';

void main() {
  testWidgets('starts in local unlock flow', (tester) async {
    await tester.pumpWidget(const NoterrApp(hasCloud: false));

    expect(find.text('Noterr'), findsNothing);
    expect(find.text('Unlock notes'), findsOneWidget);
  });
}
