import 'dart:developer';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:perfect_board/src/models/ticket.dart';
import 'package:perfect_board/src/config.dart';
import 'package:perfect_board/src/local_attachments.dart';
import 'package:perfect_board/src/widgets/ticket_attachment_preview.dart';
import 'package:perfect_board/src/widgets/ticket_screenshot.dart';
import 'package:perfect_board/src/widgets/ticket_ui.dart';
import 'package:perfect_board/src/board_file.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:perfect_board/src/l10n.dart';

/// Oltre questa soglia il caricamento si rifiuta: gli allegati servono a far
/// capire un problema, non ad archiviare video.
const int kTicketAttachmentMaxBytes = 15 * 1024 * 1024;

/// Tipo del contenuto dall'estensione: senza, il browser scarica tutto come
/// binario e nessuna anteprima funziona.
String ticketAttachmentContentType(String? extension) {
  switch (extension?.toLowerCase()) {
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'pdf':
      return 'application/pdf';
    case 'txt':
    case 'log':
      return 'text/plain';
    case 'json':
      return 'application/json';
    case 'csv':
      return 'text/csv';
    case 'md':
      return 'text/markdown';
    case 'mp4':
    case 'm4v':
      return 'video/mp4';
    case 'mov':
      return 'video/quicktime';
    case 'webm':
      return 'video/webm';
    default:
      return 'application/octet-stream';
  }
}

/// Carica un allegato su una segnalazione: il file su Storage, i metadati in
/// `Tickets/{id}/Attachments`.
///
/// Sta qui e non dentro il widget perché la usano in tre: il riquadro degli
/// allegati, il form di apertura, che carica quello che hai scelto appena la
/// segnalazione esiste (prima non c'è un id sotto cui metterlo), e i commenti,
/// che passano [commentId] per ritrovare i propri file.
///
/// Solleva l'eccezione: chi chiama decide cosa dire all'utente.
Future<void> uploadTicketAttachment({
  required String ticketId,
  required BoardFile file,
  String? commentId,
}) async {
  final bytes = file.bytes;
  if (bytes.length > kTicketAttachmentMaxBytes) {
    throw StateError('File too large: ${file.name}');
  }

  final contentType = ticketAttachmentContentType(file.extension);

  // Account demo: il file resta in memoria, niente Storage.
  if (PerfectBoard.isDemo) {
    LocalAttachments.add(
      ticketId: ticketId,
      name: file.name,
      contentType: contentType,
      bytes: bytes,
      uploadedByName: PerfectBoard.user.name,
      commentId: commentId,
    );
    return;
  }

  // Il timestamp nel nome serve alle regole di Storage, che vietano la
  // sovrascrittura: due file omonimi non devono darsi fastidio.
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final safeName = file.name.replaceAll(RegExp(r'[^\w\.\-]'), '_');

  final upload = await FirebaseStorage.instance
      .ref('uploads/tickets/$ticketId/${stamp}_$safeName')
      .putData(bytes, SettableMetadata(contentType: contentType));

  await FirebaseFirestore.instance
      .collection('Tickets')
      .doc(ticketId)
      .collection('Attachments')
      .add({
    'name': file.name,
    'url': await upload.ref.getDownloadURL(),
    // Il percorso a parte: l'export usa questo, non il link con il token.
    'path': upload.ref.fullPath,
    'contentType': contentType,
    'size': bytes.length,
    'uploadedBy': {
      'uid': PerfectBoard.user.uid,
      'name': PerfectBoard.user.name,
    },
    if (commentId != null) 'commentId': commentId,
    'createdAt': FieldValue.serverTimestamp(),
  });
}

/// Allegati di una segnalazione: schermate, log, PDF.
///
/// I file vanno su Storage sotto `uploads/tickets/...`, dove le regole già in
/// essere danno lettura e scrittura agli admin (e vietano la sovrascrittura,
/// per questo il nome porta un timestamp). In Firestore restano solo i
/// metadati, così la lista si legge senza interrogare Storage.
class TicketAttachments extends StatefulWidget {
  final String ticketId;

  /// Titolo della scheda, per la barretta delle schermate.
  final String ticketTitle;

  const TicketAttachments({
    super.key,
    required this.ticketId,
    required this.ticketTitle,
  });

  @override
  State<TicketAttachments> createState() => _TicketAttachmentsState();
}

class _TicketAttachmentsState extends State<TicketAttachments> {
  bool _uploading = false;

  // Uno stream solo: la lista si ridisegna anche quando cambiano gli
  // allegati in memoria, e un nuovo abbonamento a ogni giro farebbe
  // lampeggiare il caricamento.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream =
      _attachments.orderBy('createdAt').snapshots();

  CollectionReference<Map<String, dynamic>> get _attachments =>
      FirebaseFirestore.instance
          .collection('Tickets')
          .doc(widget.ticketId)
          .collection('Attachments');

  Future<void> _pickAndUpload() async {
    if (_uploading) return;
    try {
      final (:files, :tooBig) =
          await pickBoardFiles(maxBytes: kTicketAttachmentMaxBytes);
      if (files.isEmpty && tooBig.isEmpty) return;
      if (tooBig.isNotEmpty) {
        if (mounted) {
          ticketToast(context, bt('tooLarge'));
        }
        return;
      }

      setState(() => _uploading = true);
      for (final file in files) {
        await uploadTicketAttachment(
          ticketId: widget.ticketId,
          file: file,
        );
      }
      if (mounted) {
        ticketToast(
          context,
          files.length == 1
              ? bt('uploaded')
              : bt('uploadedMany', {'count': '${files.length}'}),
        );
      }
    } catch (e) {
      log('Ticket attachment error: $e');
      if (mounted) ticketToast(context, bt('uploadFailed'));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _delete(TicketAttachment attachment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(bt('removeAttachment')),
        content: Text(attachment.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(bt('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(bt('remove')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (attachment.isLocal) {
      LocalAttachments.remove(widget.ticketId, attachment.id);
      if (mounted) ticketToast(context, bt('attachmentRemoved'));
      return;
    }

    try {
      // Prima il file, poi la riga: se il file non c'è più (o non si può
      // togliere) la riga resterebbe a puntare al nulla.
      await FirebaseStorage.instance.refFromURL(attachment.url).delete();
    } catch (e) {
      log('Ticket attachment storage delete error: $e');
    }
    try {
      await _attachments.doc(attachment.id).delete();
      if (mounted) ticketToast(context, bt('attachmentRemoved'));
    } catch (e) {
      log('Ticket attachment delete error: $e');
      if (mounted) ticketToast(context, bt('removeFailed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          children: [
            TextButton.icon(
              onPressed: _uploading ? null : _pickAndUpload,
              icon: Icon(
                  _uploading ? Icons.hourglass_empty : Icons.attach_file),
              label: Text(_uploading ? bt('uploading') : bt('addFiles')),
            ),
            // Schermata del backoffice: si naviga fino al punto e si scatta
            // dalla barretta in basso (ticket_screenshot.dart).
            TextButton.icon(
              onPressed: () {
                TicketScreenshot.start(TicketScreenshotTarget.upload(
                  ticketId: widget.ticketId,
                  title: widget.ticketTitle,
                  returnTo: '${PerfectBoard.basePath}/detail/${widget.ticketId}',
                ));
                ticketToast(context, bt('screenshotStarted'));
              },
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(bt('screenshot')),
            ),
          ],
        ),
        if (PerfectBoard.isDemo) _hint(bt('demoAttachments')),
        ValueListenableBuilder<int>(
        valueListenable: LocalAttachments.changes,
        builder: (context, _, __) =>
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _hint(bt('attachmentsUnavailable'));
          }
          if (!snapshot.hasData) return _hint('…');

          final attachments = [
            ...snapshot.data!.docs
                .map((d) => TicketAttachment.fromFirestore(d.id, d.data())),
            ...LocalAttachments.of(widget.ticketId),
          ];
          if (attachments.isEmpty) {
            return _hint(bt('attachmentsHint'));
          }

          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 0; i < attachments.length; i++)
                  TicketAttachmentTile(
                    attachment: attachments[i],
                    onOpen: () => showTicketAttachmentPreview(
                      context,
                      attachments: attachments,
                      initialIndex: i,
                    ),
                    onDelete: () => _delete(attachments[i]),
                  ),
              ],
            ),
          );
          },
        ),
        ),
      ],
    );
  }

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.only(left: 12),
        child: TicketEmpty(text),
      );
}

/// Una miniatura: l'immagine se è un'immagine, altrimenti un'icona col nome.
/// Senza [onDelete] niente crocetta: sotto un commento l'allegato si guarda,
/// e se va tolto si toglie dal riquadro degli allegati.
class TicketAttachmentTile extends StatelessWidget {
  final TicketAttachment attachment;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;

  const TicketAttachmentTile({
    super.key,
    required this.attachment,
    required this.onOpen,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return TicketFileCard(
      name: attachment.name,
      size: attachment.readableSize,
      onTap: onOpen,
      onRemove: onDelete,
      removeTooltip: bt('removeAttachment'),
      preview: attachment.isImage && attachment.bytes != null
          ? Image.memory(
              attachment.bytes!,
              fit: BoxFit.cover,
              cacheWidth: 320,
              errorBuilder: (_, __, ___) =>
                  TicketFileIcon(attachment.contentType),
            )
          : attachment.isImage
          ? CachedNetworkImage(
              imageUrl: attachment.url,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) =>
                  TicketFileIcon(attachment.contentType),
            )
          : TicketFileIcon(attachment.contentType),
    );
  }
}
