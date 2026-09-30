import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:perfect_board/src/models/ticket.dart';
import 'package:perfect_board/src/theme.dart';
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
          Text(
            '#${ticket.shortId} · ${ticket.title}',
            style: const TextStyle(color: lightTextColor, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Text(
            bt('deleteBody'),
            style: const TextStyle(
                color: subtitleColor, fontSize: 12, height: 1.4),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(bt('cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(bt('delete'),
              style: const TextStyle(color: errorColor)),
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
