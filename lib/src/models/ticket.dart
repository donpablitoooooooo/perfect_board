import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:perfect_board/src/config.dart';
import 'package:perfect_board/src/l10n.dart';

/// Stati di una segnalazione (collection `Tickets`).
///
/// Il giro è volutamente semi-manuale: si apre dal backoffice, Claude prende in
/// carico da sessione (scrivendo branch e note con `functions/board.js`),
/// l'admin verifica e sposta a mano in "Approved" dopo il deploy. Nessun
/// passaggio di stato avviene per conto suo.
enum TicketStatus {
  /// Arrivata, nessuno l'ha ancora guardata.
  nuova,

  /// Claude (o l'admin) ha bisogno di una risposta prima di procedere.
  daChiarire,

  /// Qualcuno ci sta lavorando.
  inCarico,

  /// Lavoro finito e pushato sul branch: tocca all'admin verificare e
  /// deployare.
  pronta,

  /// Deployata e verificata. Ce la mette l'admin, a mano, dopo il rilascio.
  fatto,

  /// Non si fa (duplicata, non è un bug, fuori scope).
  scartata;

  /// Valore salvato su Firestore. Snake case per leggibilità da CLI.
  String get key => switch (this) {
        TicketStatus.nuova => 'nuova',
        TicketStatus.daChiarire => 'da_chiarire',
        TicketStatus.inCarico => 'in_carico',
        TicketStatus.pronta => 'pronta',
        TicketStatus.fatto => 'fatto',
        TicketStatus.scartata => 'scartata',
      };

  /// Etichetta mostrata in board, nella lingua scelta nel backoffice (blocco
  /// `tickets` in `assets/languagesFile`). Le [key] non si traducono: sono
  /// quelle salvate su Firestore, e rinominarle vorrebbe dire migrare i dati.
  String get label => switch (this) {
        TicketStatus.nuova => bt('statusNew'),
        TicketStatus.daChiarire => bt('statusNeedsInfo'),
        TicketStatus.inCarico => bt('statusInProgress'),
        TicketStatus.pronta => bt('statusReady'),
        TicketStatus.fatto => bt('statusApproved'),
        TicketStatus.scartata => bt('statusDiscarded'),
      };

  /// Un colore per stato, lo stesso su chip, colonne e card.
  Color get color => switch (this) {
        TicketStatus.nuova => Colors.blue,
        TicketStatus.daChiarire => Colors.orange,
        TicketStatus.inCarico => Colors.purple,
        TicketStatus.pronta => Colors.yellow.shade700,
        TicketStatus.fatto => Colors.green,
        TicketStatus.scartata => Colors.grey,
      };

  static TicketStatus fromKey(String? value) {
    return TicketStatus.values.firstWhere(
      (s) => s.key == value,
      orElse: () => TicketStatus.nuova,
    );
  }

  /// Colonne della board, nell'ordine in cui si attraversano. "Scartata" non è
  /// una colonna: è un'azione dal dettaglio, e le scartate si vedono col
  /// filtro dedicato.
  static List<TicketStatus> get boardColumns => const [
        TicketStatus.nuova,
        TicketStatus.daChiarire,
        TicketStatus.inCarico,
        TicketStatus.pronta,
        TicketStatus.fatto,
      ];
}

/// Etichette: tre, facoltative e non esclusive.
///
/// Erano otto e c'era anche un tipo (bug / richiesta) da scegliere
/// all'apertura: due tassonomie per una board che le trattava allo stesso
/// modo. Ora "BUG APP" si legge da solo, e una card con la sola APP è una
/// richiesta senza doverlo dichiarare. Le etichette sparite restano scritte
/// sui documenti vecchi: [fromKey] le ignora, la card resta valida.
///
/// Vocabolario chiuso per scelta: un campo libero si riempie di "backoffice",
/// "Backoffice" e "bakcoffice" in tre giorni.
enum TicketLabel {
  bug('bug', 'labelBug', Colors.redAccent),
  // Indaco chiaro (indigoAccent[100]): quello pieno spariva sul navy.
  app('app', 'labelApp', Color(0xFF8C9EFF)),
  backoffice('backoffice', 'labelBackoffice', Colors.teal);

  const TicketLabel(this.key, this._labelKey, this.color);

  /// Chiave salvata su Firestore: non si traduce.
  final String key;

  final String _labelKey;
  final Color color;

  String get label => bt(_labelKey);

  /// `null` per una chiave che non conosciamo: un'etichetta rimossa dal
  /// vocabolario non deve far sparire la segnalazione che la portava.
  static TicketLabel? fromKey(String? value) {
    for (final l in TicketLabel.values) {
      if (l.key == value) return l;
    }
    return null;
  }

  static List<TicketLabel> fromList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((v) => TicketLabel.fromKey(v?.toString()))
        .whereType<TicketLabel>()
        .toList();
  }
}

/// Un riferimento: il tipo, l'id del documento e l'etichetta da mostrare.
///
/// L'etichetta è denormalizzata apposta. Senza, la board farebbe una lettura
/// in più per ogni riferimento di ogni riga solo per scrivere "Box 427/2024";
/// e la ricerca in cima alla board non potrebbe trovare una segnalazione dal
/// numero del box, che è metà del motivo per cui i riferimenti esistono.
class TicketRef {
  /// Il tipo, cioè la `kind` di una [BoardRefSource] registrata dall'app.
  final String kind;
  final String id;
  final String label;

  const TicketRef({
    required this.kind,
    required this.id,
    required this.label,
  });

  /// Chiave piatta per le query: `box:abc123`. Sta in un array a parte
  /// (`refKeys`) perché su un array di mappe non si fa `array-contains`.
  String get key => '$kind:$id';

  Map<String, dynamic> toMap() =>
      {'kind': kind, 'id': id, 'label': label};

  /// La sorgente dell'app per questo tipo; `null` se l'app non la registra
  /// (più): il collegamento resta, con un'icona generica.
  BoardRefSource? get source => PerfectBoard.refSource(kind);

  IconData get icon => source?.icon ?? Icons.link;

  /// Nome del tipo ("Cliente", "Ordine"…), o la `kind` grezza.
  String get kindLabel => source?.label ?? kind;

  /// `null` solo per un riferimento rotto (senza tipo o senza id). Un tipo
  /// che l'app non conosce resta: non deve far sparire il collegamento.
  static TicketRef? fromMap(Map<String, dynamic> map) {
    final kind = (map['kind'] ?? '').toString();
    final id = (map['id'] ?? '').toString();
    if (kind.isEmpty || id.isEmpty) return null;
    return TicketRef(
      kind: kind,
      id: id,
      label: (map['label'] ?? id).toString(),
    );
  }

  static List<TicketRef> fromList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map<String, dynamic>>()
        .map(TicketRef.fromMap)
        .whereType<TicketRef>()
        .toList();
  }
}

/// Una voce di checklist. Vive in un array sul documento e non in una
/// sottocollection: sono tre o quattro righe per segnalazione, e così si
/// leggono e si scrivono in un colpo solo con la card.
class ChecklistItem {
  final String text;
  final bool done;

  const ChecklistItem({required this.text, this.done = false});

  ChecklistItem copyWith({String? text, bool? done}) =>
      ChecklistItem(text: text ?? this.text, done: done ?? this.done);

  Map<String, dynamic> toMap() => {'text': text, 'done': done};

  factory ChecklistItem.fromMap(Map<String, dynamic> map) => ChecklistItem(
        text: (map['text'] ?? '').toString(),
        done: map['done'] == true,
      );

  static List<ChecklistItem> fromList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map<String, dynamic>>()
        .map(ChecklistItem.fromMap)
        .toList();
  }
}

/// Una scheda: cos'è, a che punto è, chi l'ha aperta, cosa riguarda,
/// commenti e allegati. La vedono tutti gli admin — non c'è niente di
/// riservato, e la lavorazione non si racconta qui: si esporta.
class Ticket {
  final String id;
  final String title;
  final String body;
  final TicketStatus status;
  final List<TicketLabel> labels;
  final List<TicketRef> refs;
  final List<ChecklistItem> checklist;

  final String createdByName;
  final String createdByEmail;

  /// Ruolo di chi ha segnalato. Oggi sempre `admin` (si segnala dal
  /// backoffice), ma resta esplicito: se un giorno riapriamo un canale
  /// dall'app serve distinguere.
  final String createdByRole;

  /// Scadenza: solo la data, l'ora non ha senso qui.
  final DateTime? dueAt;

  /// Posizione nella colonna, sulla stessa scala dei millisecondi di
  /// `createdAt`: si ordina in modo DECRESCENTE, quindi il valore più alto sta
  /// in cima. Una segnalazione senza `order` (scritta prima che esistesse, o
  /// dalla CLI) ricade su `createdAt`, che è la stessa scala — così non serve
  /// nessuna migrazione.
  final double? order;

  /// Contatori tenuti aggiornati dai trigger (`functions/ticket_events.js`):
  /// servono a mostrare i pallini sulla card senza leggere due
  /// sottocollection per ogni riga della board.
  final int commentCount;
  final int attachmentCount;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? takenAt;
  final DateTime? doneAt;

  /// Quando la scheda è entrata nella colonna in cui sta. Si scrive solo
  /// quando lo stato cambia davvero, non quando la si riordina.
  final DateTime? statusChangedAt;

  const Ticket({
    required this.id,
    required this.title,
    required this.body,
    required this.status,
    required this.createdByName,
    required this.createdByEmail,
    required this.createdByRole,
    this.labels = const [],
    this.refs = const [],
    this.checklist = const [],
    this.dueAt,
    this.order,
    this.commentCount = 0,
    this.attachmentCount = 0,
    this.createdAt,
    this.updatedAt,
    this.takenAt,
    this.doneAt,
    this.statusChangedAt,
  });

  /// Id corto usato ovunque nella UI e dalla CLI (`#a1b2c3`): l'id Firestore
  /// per intero è illeggibile e non serve a nessuno.
  String get shortId => id.length <= 6 ? id : id.substring(0, 6);

  /// Chiave di ordinamento nella colonna (decrescente: più alto = più in
  /// alto). Vedi [order].
  double get sortKey =>
      order ?? (createdAt?.millisecondsSinceEpoch.toDouble() ?? 0);

  /// Da quando la scheda è nella colonna. Le schede scritte prima di
  /// `statusChangedAt` ripiegano sulla data più vicina che hanno: la presa
  /// in carico, l'approvazione, altrimenti l'apertura (esatta per le
  /// "Nuove", per eccesso per le altre finché non cambiano colonna).
  DateTime? get statusSince =>
      statusChangedAt ??
      switch (status) {
        TicketStatus.inCarico => takenAt,
        TicketStatus.fatto => doneAt,
        _ => null,
      } ??
      createdAt;

  /// Giorni di calendario nella colonna attuale: spostata ieri sera vale 1
  /// già stamattina, anche se non sono passate 24 ore.
  int get daysInStatus => daysInStatusAt(DateTime.now());

  int daysInStatusAt(DateTime now) {
    final since = statusSince?.toLocal();
    if (since == null) return 0;
    // Date in UTC solo per contare i giorni: così il cambio dell'ora legale
    // non fa perdere o guadagnare un giorno.
    final from = DateTime.utc(since.year, since.month, since.day);
    final to = DateTime.utc(now.year, now.month, now.day);
    return to.difference(from).inDays;
  }

  /// Da quanto è ferma, a parole: "oggi", "da 3 giorni", "da 2 settimane".
  String get statusAgeLabel {
    final d = daysInStatus;
    if (d < 1) return bt('ageToday');
    if (d < 7) {
      return d == 1
          ? bt('ageOneDay')
          : bt('ageDays', {'n': '$d'});
    }
    if (d < 30) {
      final w = d ~/ 7;
      return w == 1
          ? bt('ageOneWeek')
          : bt('ageWeeks', {'n': '$w'});
    }
    final m = d ~/ 30;
    return m == 1
        ? bt('ageOneMonth')
        : bt('ageMonths', {'n': '$m'});
  }

  /// Colore del tempo nella colonna: si accende solo dove una scheda ferma
  /// è un problema. In "Nuove" aspetta che la si guardi, in "Approvata" e
  /// "Scartata" è finita. Null = colore normale.
  Color? get statusAgeColor {
    const watched = [
      TicketStatus.daChiarire,
      TicketStatus.inCarico,
      TicketStatus.pronta,
    ];
    if (!watched.contains(status)) return null;
    final d = daysInStatus;
    if (d >= 14) return Colors.redAccent;
    if (d >= 7) return Colors.orange;
    return null;
  }

  /// Colore della scadenza: rossa se passata, arancio se mancano due giorni
  /// o meno. Null = colore normale.
  Color? get dueColor {
    final due = dueAt;
    if (due == null) return null;
    if (isOverdue) return Colors.redAccent;
    if (status == TicketStatus.fatto || status == TicketStatus.scartata) {
      return null;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(due.year, due.month, due.day);
    if (day.difference(today).inDays <= 2) return Colors.orange;
    return null;
  }

  /// Quante voci di checklist sono spuntate.
  int get checklistDone => checklist.where((c) => c.done).length;

  /// Scaduta, cioè la data è passata e la segnalazione non è chiusa: una
  /// scadenza su una card in "Fatto" non è un problema di nessuno.
  bool get isOverdue {
    final due = dueAt;
    if (due == null) return false;
    if (status == TicketStatus.fatto || status == TicketStatus.scartata) {
      return false;
    }
    final today = DateTime.now();
    return due.isBefore(DateTime(today.year, today.month, today.day));
  }

  factory Ticket.fromFirestore(String id, Map<String, dynamic> data) {
    DateTime? date(dynamic value) =>
        value is Timestamp ? value.toDate() : null;

    final createdBy = (data['createdBy'] as Map<String, dynamic>?) ?? const {};

    return Ticket(
      id: id,
      title: (data['title'] ?? '').toString(),
      body: (data['body'] ?? '').toString(),
      status: TicketStatus.fromKey(data['status']?.toString()),
      labels: TicketLabel.fromList(data['labels']),
      refs: TicketRef.fromList(data['refs']),
      checklist: ChecklistItem.fromList(data['checklist']),
      createdByName: (createdBy['name'] ?? '').toString(),
      createdByEmail: (createdBy['email'] ?? '').toString(),
      createdByRole: (createdBy['role'] ?? '').toString(),
      dueAt: date(data['dueAt']),
      order: (data['order'] as num?)?.toDouble(),
      commentCount: (data['commentCount'] as num?)?.toInt() ?? 0,
      attachmentCount: (data['attachmentCount'] as num?)?.toInt() ?? 0,
      createdAt: date(data['createdAt']),
      updatedAt: date(data['updatedAt']),
      takenAt: date(data['takenAt']),
      doneAt: date(data['doneAt']),
      statusChangedAt: date(data['statusChangedAt']),
    );
  }
}

/// Un commento: la conversazione su una scheda. Sta in
/// `Tickets/{id}/Comments` e lo leggono e scrivono tutti gli admin. Non si
/// modifica e non si cancella: si risponde.
class TicketComment {
  final String id;
  final String authorUid;
  final String authorName;
  final String text;
  final DateTime? createdAt;

  const TicketComment({
    required this.id,
    required this.authorUid,
    required this.authorName,
    required this.text,
    this.createdAt,
  });

  factory TicketComment.fromFirestore(String id, Map<String, dynamic> data) {
    final author = (data['author'] as Map<String, dynamic>?) ?? const {};
    return TicketComment(
      id: id,
      authorUid: (author['uid'] ?? '').toString(),
      authorName: (author['name'] ?? 'Admin').toString(),
      text: (data['text'] ?? '').toString(),
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
    );
  }
}

/// Un allegato. Il file vive su Storage sotto `uploads/tickets/...`, dove le
/// regole già in essere danno lettura e scrittura agli admin; qui ne teniamo
/// solo i metadati, in `Tickets/{id}/Attachments`.
class TicketAttachment {
  final String id;
  final String name;
  final String url;
  final String contentType;
  final int size;
  final String uploadedByName;
  final DateTime? createdAt;

  /// Il commento con cui è stato caricato, se è arrivato da lì. Gli allegati
  /// stanno comunque tutti in `Attachments`: il commento li mostra, ma il
  /// conteggio, l'export e la pulizia a cascata restano uno solo.
  final String? commentId;

  /// Dove sta il file su Storage (`uploads/tickets/<id>/<file>`). È l'unico
  /// riferimento che finisce nell'export: il link con il token apre il file
  /// a chiunque lo abbia, il percorso no — serve la chiave di servizio.
  final String storagePath;

  /// Il contenuto, per i file tenuti solo in memoria (account demo, vedi
  /// `PerfectBoard.isDemo`): non hanno né link né percorso su Storage.
  final Uint8List? bytes;

  const TicketAttachment({
    required this.id,
    required this.name,
    required this.url,
    required this.contentType,
    required this.size,
    required this.uploadedByName,
    this.createdAt,
    this.commentId,
    this.storagePath = '',
    this.bytes,
  });

  bool get isLocal => bytes != null;

  /// Il percorso dentro il link di download (`…/o/<percorso>?alt=media…`):
  /// serve agli allegati caricati prima che `path` venisse salvato.
  static String pathFromUrl(String url) {
    final match = RegExp(r'/o/([^?]+)').firstMatch(url);
    if (match == null) return '';
    try {
      return Uri.decodeComponent(match.group(1)!);
    } catch (_) {
      return '';
    }
  }

  bool get isImage => contentType.startsWith('image/');

  /// Dimensione leggibile. Niente pacchetti per tre righe di aritmetica.
  String get readableSize {
    if (size <= 0) return '';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).round()} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  factory TicketAttachment.fromFirestore(
      String id, Map<String, dynamic> data) {
    final uploadedBy = (data['uploadedBy'] as Map<String, dynamic>?) ?? const {};
    return TicketAttachment(
      id: id,
      name: (data['name'] ?? 'attachment').toString(),
      url: (data['url'] ?? '').toString(),
      contentType: (data['contentType'] ?? '').toString(),
      size: (data['size'] as num?)?.toInt() ?? 0,
      uploadedByName: (uploadedBy['name'] ?? '').toString(),
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
      commentId: data['commentId'] as String?,
      storagePath: (data['path'] as String?) ??
          pathFromUrl((data['url'] ?? '').toString()),
    );
  }
}
