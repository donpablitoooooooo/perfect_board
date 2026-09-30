import 'package:flutter/material.dart';
import 'package:perfect_board/src/models/ticket.dart';

/// L'aspetto della board viene dal tema Material 3 dell'app
/// (`Theme.of(context).colorScheme`): chiaro o scuro, qualunque colore seme.
///
/// [BoardTheme] serve solo a cambiare ciò che il `ColorScheme` non dice:
/// il fondo di colonne e card e i colori di stati ed etichette. Si aggiunge
/// alle estensioni del tema dell'app; ogni campo lasciato `null` prende il
/// default.
///
/// ```dart
/// ThemeData(
///   colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
///   extensions: const [
///     BoardTheme(statusColors: {TicketStatus.nuova: Colors.indigo}),
///   ],
/// )
/// ```
@immutable
class BoardTheme extends ThemeExtension<BoardTheme> {
  /// Fondo delle colonne della board.
  final Color? columnColor;

  /// Fondo delle card, delle bolle dei commenti e dei riquadri in evidenza.
  final Color? cardColor;

  /// Colore per stato; quelli che mancano restano i default.
  final Map<TicketStatus, Color>? statusColors;

  /// Colore per etichetta; quelle che mancano restano i default.
  final Map<TicketLabel, Color>? labelColors;

  const BoardTheme({
    this.columnColor,
    this.cardColor,
    this.statusColors,
    this.labelColors,
  });

  @override
  BoardTheme copyWith({
    Color? columnColor,
    Color? cardColor,
    Map<TicketStatus, Color>? statusColors,
    Map<TicketLabel, Color>? labelColors,
  }) =>
      BoardTheme(
        columnColor: columnColor ?? this.columnColor,
        cardColor: cardColor ?? this.cardColor,
        statusColors: statusColors ?? this.statusColors,
        labelColors: labelColors ?? this.labelColors,
      );

  @override
  BoardTheme lerp(covariant BoardTheme? other, double t) {
    if (other == null) return this;
    return BoardTheme(
      columnColor: Color.lerp(columnColor, other.columnColor, t),
      cardColor: Color.lerp(cardColor, other.cardColor, t),
      statusColors: t < 0.5 ? statusColors : other.statusColors,
      labelColors: t < 0.5 ? labelColors : other.labelColors,
    );
  }
}

/// I colori della board risolti per un contesto: i ruoli del `ColorScheme`
/// con i nomi che servono qui, più le sostituzioni di [BoardTheme].
class BoardColors {
  final ColorScheme scheme;
  final BoardTheme? _ext;

  BoardColors._(this.scheme, this._ext);

  factory BoardColors.of(BuildContext context) {
    final theme = Theme.of(context);
    return BoardColors._(theme.colorScheme, theme.extension<BoardTheme>());
  }

  /// Accento: link, icone attive, cornice delle schermate.
  Color get accent => scheme.primary;
  Color get onAccent => scheme.onPrimary;

  /// Testo principale e secondario.
  Color get text => scheme.onSurface;
  Color get subtle => scheme.onSurfaceVariant;

  /// Fondo della pagina e dei dialog.
  Color get background => scheme.surface;

  /// Fondo "incassato": miniature, chip, campi.
  Color get sunken => scheme.surfaceContainer;

  /// Fondo "sollevato": barretta delle schermate, menu.
  Color get raised => scheme.surfaceContainerHigh;

  Color get column => _ext?.columnColor ?? scheme.surfaceContainerLow;
  Color get card => _ext?.cardColor ?? scheme.surfaceContainerHighest;

  /// Bordi e separatori.
  Color get outline => scheme.outlineVariant;

  Color get error => scheme.error;

  /// Velo sopra l'app (fuori dalla cornice delle schermate).
  Color get scrim => scheme.scrim;

  Color status(TicketStatus status) =>
      _ext?.statusColors?[status] ?? status.color;

  Color label(TicketLabel label) => _ext?.labelColors?[label] ?? label.color;
}

extension BoardColorsContext on BuildContext {
  /// I colori della board per questo contesto.
  BoardColors get board => BoardColors.of(this);
}
