import 'dart:convert';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:perfect_board/src/models/ticket.dart';
import 'package:perfect_board/src/widgets/ticket_ui.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:perfect_board/src/l10n.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';

/// Esporta una scheda in un colpo solo, pronta da dare a Claude.
///
/// Markdown, non JSON: è la forma in cui un modello legge senza sforzo e in
/// cui un umano rilegge senza scorrere parentesi. Il pezzo che conta sono gli
/// **id veri** accanto a ogni collegamento (`Orders/b19c05de`): con quelli
/// Claude va a leggere il documento invece di chiedere di cosa si parla.
///
/// Gli allegati sono elencati con nome, tipo, peso e **percorso su Storage**,
/// mai con il link di download: quel link porta un token che apre il file a
/// chiunque lo legga, e l'export finisce incollato in chat. Chi lavora la
/// scheda li scarica con `node functions/board.js files <id>`, che usa la
/// chiave di servizio del progetto.

/// Compone il markdown della scheda. Separata dalla UI perché è la parte che
/// vale la pena leggere e, un domani, riusare dalla CLI.
String buildTicketMarkdown({
  required Ticket ticket,
  required List<TicketComment> comments,
  required List<TicketAttachment> attachments,
}) {
  final out = StringBuffer();
  String date(DateTime? value) =>
      value != null ? dateTimeFormat.format(value) : '—';

  out.writeln('# [#${ticket.shortId}] ${ticket.title}');
  out.writeln();
  out.writeln('- Stato: ${ticket.status.label}');
  if (ticket.labels.isNotEmpty) {
    out.writeln('- Etichette: ${ticket.labels.map((l) => l.label).join(', ')}');
  }
  if (ticket.dueAt != null) {
    out.writeln(
      '- Scadenza: ${dateFormat.format(ticket.dueAt!)}'
      '${ticket.isOverdue ? ' (scaduta)' : ''}',
    );
  }
  out.writeln(
    '- Aperta da: ${ticket.createdByName}'
    '${ticket.createdByEmail.isNotEmpty ? ' <${ticket.createdByEmail}>' : ''}'
    ', ${date(ticket.createdAt)}',
  );
  out.writeln();
  out.writeln('## Descrizione');
  out.writeln();
  out.writeln(ticket.body.isEmpty ? '—' : ticket.body);

  if (ticket.refs.isNotEmpty) {
    out.writeln();
    out.writeln('## Collegati');
    out.writeln();
    for (final ref in ticket.refs) {
      // L'id della collection sta accanto all'etichetta: è quello che rende
      // il collegamento qualcosa su cui si può andare a guardare.
      final collection = ref.source?.collection;
      out.writeln('- ${ref.kindLabel}: ${ref.label} — '
          '${collection == null ? ref.id : '$collection/${ref.id}'}');
    }
  }

  if (ticket.checklist.isNotEmpty) {
    out.writeln();
    out.writeln('## Checklist');
    out.writeln();
    for (final item in ticket.checklist) {
      out.writeln('- [${item.done ? 'x' : ' '}] ${item.text}');
    }
  }

  if (comments.isNotEmpty) {
    out.writeln();
    out.writeln('## Commenti');
    out.writeln();
    for (final comment in comments) {
      out.writeln('**${comment.authorName}**, ${date(comment.createdAt)}');
      if (comment.text.isNotEmpty) out.writeln(comment.text);
      // I file del commento stanno anche nella lista "Allegati" in fondo:
      // qui basta il nome, per sapere a quale parte della discussione
      // appartengono.
      final files =
          attachments.where((a) => a.commentId == comment.id).toList();
      if (files.isNotEmpty) {
        out.writeln('Allegati: ${files.map((a) => a.name).join(', ')}');
      }
      out.writeln();
    }
  }

  if (attachments.isNotEmpty) {
    out.writeln();
    out.writeln('## Allegati');
    out.writeln();
    for (final attachment in attachments) {
      out.writeln('- ${attachment.name} (${attachment.contentType}, '
          '${attachment.readableSize}) — `${attachment.storagePath}`');
    }
    out.writeln();
    out.writeln('Per scaricarli: `node functions/board.js files '
        '${ticket.shortId}`');
  }

  return out.toString();
}

/// Legge commenti e allegati, compone il markdown e lo mostra: da lì si copia
/// o si scarica.
Future<void> showTicketExport(BuildContext context, Ticket ticket) async {
  String markdown;
  try {
    final doc = FirebaseFirestore.instance.collection('Tickets').doc(ticket.id);
    final results = await Future.wait([
      doc.collection('Comments').orderBy('createdAt').get(),
      doc.collection('Attachments').orderBy('createdAt').get(),
    ]);
    markdown = buildTicketMarkdown(
      ticket: ticket,
      comments: results[0]
          .docs
          .map((d) => TicketComment.fromFirestore(d.id, d.data()))
          .toList(),
      attachments: results[1]
          .docs
          .map((d) => TicketAttachment.fromFirestore(d.id, d.data()))
          .toList(),
    );
  } catch (e) {
    log('Ticket export error: $e');
    if (context.mounted) ticketToast(context, bt('exportFailed'));
    return;
  }

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(bt('export')),
      content: SizedBox(
        width: 720,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              bt('exportHint'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const Gap(14),
            Expanded(
              child: Card.outlined(
                margin: EdgeInsets.zero,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(14),
                  child: SizedBox(
                    width: double.infinity,
                    child: SelectableText(
                      markdown,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(bt('cancel')),
        ),
        TextButton.icon(
          icon: const Icon(Icons.download_outlined),
          label: Text(bt('exportDownload')),
          onPressed: () async {
            // Estensione nel nome e MimeType.other: è la firma che usano
            // già gli altri due export del backoffice (excel_export.dart,
            // generate_qrcodes_dialog.dart).
            await FileSaver.instance.saveFile(
              name: 'scheda-${ticket.shortId}.md',
              bytes: Uint8List.fromList(utf8.encode(markdown)),
              mimeType: MimeType.other,
            );
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          },
        ),
        FilledButton.icon(
          icon: const Icon(Icons.copy),
          label: Text(bt('exportCopy')),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: markdown));
            Navigator.pop(dialogContext);
            if (context.mounted) {
              ticketToast(context, bt('exportCopied'));
            }
          },
        ),
      ],
    ),
  );
}
