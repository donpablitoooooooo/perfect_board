import 'dart:developer';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:perfect_board/src/models/ticket.dart';
import 'package:perfect_board/src/config.dart';
import 'package:perfect_board/src/theme.dart';
import 'package:perfect_board/src/widgets/ticket_attachment_preview.dart';
import 'package:perfect_board/src/widgets/ticket_screenshot.dart';
import 'package:perfect_board/src/widgets/ticket_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:perfect_board/src/l10n.dart';
import 'package:gap/gap.dart';

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
  required PlatformFile file,
  String? commentId,
}) async {
  final bytes = file.bytes;
  if (bytes == null) throw StateError('File not readable: ${file.name}');
  if (bytes.length > kTicketAttachmentMaxBytes) {
    throw StateError('File too large: ${file.name}');
  }

  // Il timestamp nel nome serve alle regole di Storage, che vietano la
  // sovrascrittura: due file omonimi non devono darsi fastidio.
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final safeName = file.name.replaceAll(RegExp(r'[^\w\.\-]'), '_');
  final contentType = ticketAttachmentContentType(file.extension);

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

  CollectionReference<Map<String, dynamic>> get _attachments =>
      FirebaseFirestore.instance
          .collection('Tickets')
          .doc(widget.ticketId)
          .collection('Attachments');

  Future<void> _pickAndUpload() async {
    if (_uploading) return;
    try {
      final picked = await FilePicker.platform.pickFiles(
        withData: true,
        allowMultiple: true,
      );
      if (picked == null || picked.files.isEmpty) return;

      final tooBig = picked.files
          .where((f) => (f.bytes?.length ?? 0) > kTicketAttachmentMaxBytes)
          .toList();
      if (tooBig.isNotEmpty) {
        if (mounted) {
          ticketToast(context, bt('tooLarge'));
        }
        return;
      }

      setState(() => _uploading = true);
      for (final file in picked.files) {
        await uploadTicketAttachment(
          ticketId: widget.ticketId,
          file: file,
        );
      }
      if (mounted) {
        ticketToast(
          context,
          picked.files.length == 1
              ? bt('uploaded')
              : bt('uploadedMany', {'count': '${picked.files.length}'}),
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
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(bt('remove')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

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
                _uploading ? Icons.hourglass_empty : Icons.attach_file,
                size: 16,
                color: tertiaryColor,
              ),
              label: Text(
                _uploading
                    ? bt('uploading')
                    : bt('addFiles'),
                style: const TextStyle(color: tertiaryColor, fontSize: 13),
              ),
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
              icon: const Icon(
                Icons.photo_camera,
                size: 16,
                color: tertiaryColor,
              ),
              label: Text(
                bt('screenshot'),
                style: const TextStyle(color: tertiaryColor, fontSize: 13),
              ),
            ),
          ],
        ),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _attachments.orderBy('createdAt').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _hint(bt('attachmentsUnavailable'));
          }
          if (!snapshot.hasData) return _hint('…');

          final attachments = snapshot.data!.docs
              .map((d) => TicketAttachment.fromFirestore(d.id, d.data()))
              .toList();
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
      ],
    );
  }

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Text(
          text,
          style: const TextStyle(color: subtitleColor, fontSize: 12),
        ),
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
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onOpen,
            child: Container(
              height: 96,
              width: double.infinity,
              decoration: BoxDecoration(
                color: pureBlack,
                border: Border.all(color: cardColor),
              ),
              child: attachment.isImage
                  ? CachedNetworkImage(
                      imageUrl: attachment.url,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const Icon(
                        Icons.broken_image_outlined,
                        color: subtitleColor,
                      ),
                    )
                  : Icon(
                      attachment.contentType.startsWith('video/')
                          ? Icons.movie_outlined
                          : Icons.insert_drive_file_outlined,
                      color: subtitleColor,
                      size: 32),
            ),
          ),
          const Gap(6),
          Text(
            attachment.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: lightTextColor, fontSize: 12),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  attachment.readableSize,
                  style: const TextStyle(color: subtitleColor, fontSize: 11),
                ),
              ),
              if (onDelete != null)
                InkWell(
                  onTap: onDelete,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 14, color: subtitleColor),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
