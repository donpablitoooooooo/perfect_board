import 'package:flutter/foundation.dart';
import 'package:perfect_board/src/models/ticket.dart';

/// Gli allegati di un account demo: stanno solo qui, in memoria, e spariscono
/// ricaricando la pagina. Nessun file del demo arriva su Storage (le regole
/// non lo lascerebbero passare comunque), ma chi prova la board vede lo
/// stesso miniature, anteprime e allegati nei commenti.
class LocalAttachments {
  LocalAttachments._();

  static final Map<String, List<TicketAttachment>> _byTicket = {};
  static int _next = 0;

  /// Suona a ogni aggiunta o rimozione: chi mostra gli allegati lo ascolta
  /// accanto allo stream di Firestore.
  static final ValueNotifier<int> changes = ValueNotifier(0);

  static List<TicketAttachment> of(String ticketId) =>
      List.unmodifiable(_byTicket[ticketId] ?? const <TicketAttachment>[]);

  static void add({
    required String ticketId,
    required String name,
    required String contentType,
    required Uint8List bytes,
    required String uploadedByName,
    String? commentId,
  }) {
    (_byTicket[ticketId] ??= []).add(TicketAttachment(
      id: 'local-${_next++}',
      name: name,
      url: '',
      contentType: contentType,
      size: bytes.length,
      uploadedByName: uploadedByName,
      createdAt: DateTime.now(),
      commentId: commentId,
      bytes: bytes,
    ));
    changes.value++;
  }

  static void remove(String ticketId, String attachmentId) {
    _byTicket[ticketId]?.removeWhere((a) => a.id == attachmentId);
    changes.value++;
  }

  @visibleForTesting
  static void clear() {
    _byTicket.clear();
    changes.value++;
  }
}
