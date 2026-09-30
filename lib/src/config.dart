import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';

/// Chi sta usando la board: finisce come autore di schede, commenti e
/// allegati. La board non sa niente di come l'app gestisce il login.
class BoardUser {
  final String uid;
  final String name;
  final String email;

  const BoardUser({required this.uid, required this.name, this.email = ''});
}

/// Un risultato nella ricerca di un collegamento.
class BoardRefHit {
  final String id;
  final String label;
  final String subtitle;

  /// Testo su cui filtra la ricerca in memoria (già in minuscolo).
  final String haystack;

  const BoardRefHit({
    required this.id,
    required this.label,
    this.subtitle = '',
    String? haystack,
  }) : haystack = haystack ?? '';
}

/// Una cosa dell'app a cui una scheda può riferirsi: un cliente, un ordine,
/// una pagina… La board salva solo `{kind, id, label}`; come si cerca e come
/// si chiama è compito dell'app, che registra le sue sorgenti con
/// [PerfectBoard.configure].
abstract class BoardRefSource {
  const BoardRefSource();

  /// Chiave salvata su Firestore (`refs[].kind`): non si traduce e non si
  /// cambia, o le schede vecchie perdono il collegamento.
  String get kind;

  /// Nome mostrato sul bottone e in testa alla ricerca.
  String get label;

  IconData get icon;

  /// Suggerimento nel campo di ricerca.
  String get searchHint => '';

  /// Collection Firestore dei documenti collegati, se ce n'è una: l'export
  /// la scrive accanto all'id, così chi legge sa dove andare a guardare.
  String? get collection => null;

  /// Elenco iniziale, filtrato poi in memoria mentre si scrive.
  Future<List<BoardRefHit>> load();

  /// Ricerca sul server per un testo, per le sorgenti troppo grandi da
  /// caricare intere. `null` (il default) = si filtra in memoria [load].
  Future<List<BoardRefHit>>? search(String text) => null;
}

/// La configurazione della board, da impostare all'avvio dell'app.
class PerfectBoard {
  PerfectBoard._();

  static BoardUser Function() _currentUser =
      () => const BoardUser(uid: '', name: 'Admin');
  static String Function() _locale =
      () => PlatformDispatcher.instance.locale.languageCode;
  static List<BoardRefSource> _refSources = const [];
  static String _basePath = '/tickets';

  /// [currentUser] è chiamato ogni volta che serve l'autore, quindi segue
  /// login e logout senza riconfigurare. [locale] idem: di solito legge la
  /// lingua scelta nell'app. [basePath] è dove l'app monta le rotte della
  /// board (vedi `perfectBoardRoutes`).
  static void configure({
    required BoardUser Function() currentUser,
    String Function()? locale,
    List<BoardRefSource> refSources = const [],
    String basePath = '/tickets',
  }) {
    _currentUser = currentUser;
    if (locale != null) _locale = locale;
    _refSources = List.unmodifiable(refSources);
    _basePath = basePath;
  }

  static BoardUser get user => _currentUser();

  /// Codice lingua (`it`, `en`…) per i testi della board.
  static String get locale => _locale();

  static List<BoardRefSource> get refSources => _refSources;

  static BoardRefSource? refSource(String kind) {
    for (final s in _refSources) {
      if (s.kind == kind) return s;
    }
    return null;
  }

  static String get basePath => _basePath;
}
