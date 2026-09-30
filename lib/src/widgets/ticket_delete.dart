import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:perfect_board/src/models/ticket.dart';
import 'package:perfect_board/src/widgets/ticket_ui.dart';
import 'package:flutter/material.dart';
import 'package:perfect_board/src/l10n.dart';

/// Elimina una segnalazione, davvero.
///
/// È un'altra cosa da "Scartata": quella è una colonna, e si torna indietro
/// trascinando. Qui non si torna indietro — per questo il bottone lo vede
/// solo chi lavora le segnalazioni, mentre agli altri admin resta lo scarto,
/// che è reversibile.
///
/// Qui si cancella **solo** il documento della segnalazione. Il resto —
/// commenti, allegati, lavorazione, timeline e i file su Storage — lo smonta
/// il trigger `ticketDeleted` (`functions/ticket_events.js`): Firestore non
/// cancella a cascata, e le regole tengono apposta commenti e note non
/// cancellabili dal client. La pulizia gira quindi con l'Admin SDK, che le
/// regole non le passa.
///
/// Ritorna `true` se la segnalazione non c'è più.
Future<bool> confirmAndDeleteTicket(BuildContext context, Ticket ticket) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(bt('deleteTitle')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('#${ticket.shortId} · ${ticket.title}'),
          const SizedBox(height: 12),
          Text(
            bt('deleteBody'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(bt('cancel')),
        ),
        // Azione distruttiva: FilledButton nei colori "error" del tema.
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(bt('delete')),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;

  try {
    await FirebaseFirestore.instance
        .collection('Tickets')
        .doc(ticket.id)
        .delete();
    if (context.mounted) ticketToast(context, bt('deleted'));
    return true;
  } catch (e) {
    log('Ticket delete error: $e');
    if (context.mounted) ticketToast(context, bt('deleteFailed'));
    return false;
  }
}
