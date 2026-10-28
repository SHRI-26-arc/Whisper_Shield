import 'package:flutter_test/flutter_test.dart';

import 'package:whisper_shield/main.dart';

void main() {
  testWidgets('Whisper Shield home screen renders', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const WhisperShieldApp());

    expect(find.text('Whisper Shield'), findsOneWidget);
    expect(find.text('SOS'), findsOneWidget);
  });
}
