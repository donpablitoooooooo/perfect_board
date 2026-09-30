import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_board/perfect_board.dart';

Future<BoardColors> _colorsWith(WidgetTester tester, ThemeData theme) async {
  late BoardColors colors;
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: Builder(builder: (context) {
      colors = context.board;
      return const SizedBox();
    }),
  ));
  return colors;
}

void main() {
  testWidgets('senza BoardTheme i colori vengono dal ColorScheme',
      (tester) async {
    final theme = ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal, brightness: Brightness.dark));
    final c = await _colorsWith(tester, theme);
    expect(c.accent, theme.colorScheme.primary);
    expect(c.text, theme.colorScheme.onSurface);
    expect(c.column, theme.colorScheme.surfaceContainerLow);
    expect(c.card, theme.colorScheme.surfaceContainerHighest);
    expect(c.status(TicketStatus.nuova), TicketStatus.nuova.color);
  });

  testWidgets('BoardTheme sostituisce solo quello che dice', (tester) async {
    final theme = ThemeData(extensions: const [
      BoardTheme(
        cardColor: Colors.amber,
        statusColors: {TicketStatus.nuova: Colors.pink},
        labelColors: {TicketLabel.bug: Colors.black},
      ),
    ]);
    final c = await _colorsWith(tester, theme);
    expect(c.card, Colors.amber);
    expect(c.column, theme.colorScheme.surfaceContainerLow);
    expect(c.status(TicketStatus.nuova), Colors.pink);
    expect(c.status(TicketStatus.fatto), TicketStatus.fatto.color);
    expect(c.label(TicketLabel.bug), Colors.black);
    expect(c.label(TicketLabel.app), TicketLabel.app.color);
  });
}
