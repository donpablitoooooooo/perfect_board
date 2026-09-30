import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:perfect_board/src/models/ticket.dart';
import 'package:perfect_board/src/config.dart';
import 'package:perfect_board/src/widgets/ticket_attachment_preview.dart';
import 'package:perfect_board/src/local_attachments.dart';
import 'package:perfect_board/src/widgets/ticket_attachments.dart';
import 'package:perfect_board/src/widgets/ticket_fields.dart';
import 'package:perfect_board/src/widgets/ticket_screenshot.dart';
import 'package:perfect_board/src/widgets/ticket_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:perfect_board/src/l10n.dart';
import 'package:gap/gap.dart';

/// I commenti di una segnalazione: il canale fra chi l'ha aperta e chi la
/// lavora.
///
/// Li vedono tutti gli admin — è la differenza con la timeline di lavorazione,
/// che resta a chi ha il claim. Un commento non si modifica e non si cancella:
/// si risponde. Serve a poter rileggere una discussione e capirla, invece di
/// trovare buchi dove qualcuno ha ripulito.
///
/// Un commento può portarsi dietro dei file. Finiscono fra gli allegati della
/// scheda come gli altri (stesso conteggio, stesso export, stessa pulizia
/// quando la scheda si elimina) con in più il `commentId`, che serve a
/// mostrarli anche sotto il commento che li ha portati.
/// Commento lasciato a metà per andare a scattare una schermata: la pagina
/// si smonta mentre si naviga, e al ritorno testo e file devono esserci.
class _CommentDraft {
  final String text;
  final List<PlatformFile> files;

  const _CommentDraft(this.text, this.files);
}

final Map<String, _CommentDraft> _commentDrafts = {};

class TicketComments extends StatefulWidget {
  final String ticketId;

  /// Titolo della scheda, per la barretta delle schermate.
  final String ticketTitle;

  const TicketComments({
    super.key,
    required this.ticketId,
    required this.ticketTitle,
  });

  @override
  State<TicketComments> createState() => _TicketCommentsState();
}

class _TicketCommentsState extends State<TicketComments> {
  final TextEditingController _controller = TextEditingController();
  final List<PlatformFile> _files = [];
  bool _sending = false;

  String get _draftKey => 'comment:${widget.ticketId}';

  @override
  void initState() {
    super.initState();
    final draft = _commentDrafts.remove(widget.ticketId);
    if (draft != null) {
      _controller.text = draft.text;
      _files.addAll(draft.files);
    }
    _files.addAll(TicketScreenshot.takeShots(_draftKey));
    TicketScreenshot.shotsChanged.addListener(_pullShots);
  }

  @override
  void dispose() {
    TicketScreenshot.shotsChanged.removeListener(_pullShots);
    if (TicketScreenshot.isActiveFor(_draftKey)) {
      _commentDrafts[widget.ticketId] =
          _CommentDraft(_controller.text, List.of(_files));
    }
    _controller.dispose();
    super.dispose();
  }

  /// Schermata scattata senza lasciare la pagina: il widget è ancora qui.
  void _pullShots() {
    final shots = TicketScreenshot.takeShots(_draftKey);
    if (shots.isNotEmpty && mounted) setState(() => _files.addAll(shots));
  }

  void _startScreenshot() {
    TicketScreenshot.start(TicketScreenshotTarget.draft(
      draftKey: _draftKey,
      title: widget.ticketTitle,
      returnTo: '${PerfectBoard.basePath}/detail/${widget.ticketId}',
    ));
    ticketToast(context, bt('screenshotStarted'));
  }

  CollectionReference<Map<String, dynamic>> get _comments =>
      FirebaseFirestore.instance
          .collection('Tickets')
          .doc(widget.ticketId)
          .collection('Comments');

  CollectionReference<Map<String, dynamic>> get _attachments =>
      FirebaseFirestore.instance
          .collection('Tickets')
          .doc(widget.ticketId)
          .collection('Attachments');

  Future<void> _pickFiles() async {
    final picked = await FilePicker.platform.pickFiles(
      withData: true,
      allowMultiple: true,
    );
    if (picked == null || picked.files.isEmpty) return;

    final tooBig = <String>[];
    setState(() {
      for (final file in picked.files) {
        if ((file.bytes?.length ?? 0) > kTicketAttachmentMaxBytes) {
          tooBig.add(file.name);
        } else {
          _files.add(file);
        }
      }
    });
    if (tooBig.isNotEmpty && mounted) {
      ticketToast(
        context,
        bt('skippedTooBig', {'files': tooBig.join(', ')}),
      );
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    // Basta anche solo un file: "ecco lo screenshot" non ha bisogno di testo.
    if ((text.isEmpty && _files.isEmpty) || _sending) return;
    setState(() => _sending = true);
    try {
      // L'id del commento serve prima di scriverlo: i file lo portano con sé.
      final ref = _comments.doc();
      for (final file in _files) {
        await uploadTicketAttachment(
          ticketId: widget.ticketId,
          file: file,
          commentId: ref.id,
        );
      }
      await ref.set({
        'author': {
          'uid': PerfectBoard.user.uid,
          'name': PerfectBoard.user.name,
        },
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });
      _controller.clear();
      if (mounted) setState(_files.clear);
    } catch (e) {
      log('Ticket comment error: $e');
      if (mounted) ticketToast(context, bt('commentFailed'));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: bt('commentHint'),
                  ),
                ),
              ),
              const Gap(4),
              IconButton(
                tooltip: bt('addFiles'),
                onPressed: _sending ? null : _pickFiles,
                icon: const Icon(Icons.attach_file),
              ),
              IconButton(
                tooltip: bt('screenshot'),
                onPressed: _sending ? null : _startScreenshot,
                icon: const Icon(Icons.photo_camera_outlined),
              ),
              const Gap(8),
              FilledButton(
                onPressed: _sending ? null : _send,
                child: Text(_sending ? bt('sending') : bt('comment')),
              ),
            ],
          ),
          if (_files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (var i = 0; i < _files.length; i++)
                    TicketPickedFileChip(
                      file: _files[i],
                      onRemove: _sending
                          ? () {}
                          : () => setState(() => _files.removeAt(i)),
                    ),
                ],
              ),
            ),
          const Gap(16),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            // Il più recente in alto, sotto al campo per scrivere: è quasi
            // sempre quello che interessa, e non si scrolla per trovarlo.
            stream:
                _comments.orderBy('createdAt', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return TicketEmpty(bt('commentsUnavailable'));
              }
              if (!snapshot.hasData) {
                return const TicketEmpty('…');
              }
              final comments = snapshot.data!.docs
                  .map((d) => TicketComment.fromFirestore(d.id, d.data()))
                  .toList();
              if (comments.isEmpty) {
                return TicketEmpty(bt('noComments'));
              }
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _attachments.orderBy('createdAt').snapshots(),
                builder: (context, attachmentsSnapshot) {
                  // Se gli allegati non si leggono i commenti restano
                  // leggibili: semplicemente senza file.
                  final byComment = <String, List<TicketAttachment>>{};
                  for (final d in attachmentsSnapshot.data?.docs ??
                      const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
                    final attachment =
                        TicketAttachment.fromFirestore(d.id, d.data());
                    final commentId = attachment.commentId;
                    if (commentId == null) continue;
                    byComment.putIfAbsent(commentId, () => []).add(attachment);
                  }
                  // Più quelli tenuti in memoria dall'account demo.
                  return ValueListenableBuilder<int>(
                    valueListenable: LocalAttachments.changes,
                    builder: (context, _, __) {
                      final all = {
                        for (final e in byComment.entries)
                          e.key: [...e.value],
                      };
                      for (final a in LocalAttachments.of(widget.ticketId)) {
                        final commentId = a.commentId;
                        if (commentId == null) continue;
                        all.putIfAbsent(commentId, () => []).add(a);
                      }
                      return Column(
                        children: [
                          for (final comment in comments) ...[
                            _CommentBubble(
                              comment: comment,
                              attachments: all[comment.id] ?? const [],
                            ),
                            const Gap(10),
                          ],
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),
        ],
    );
  }
}

/// Un commento: `Card.filled` con l'iniziale di chi l'ha scritto. I tuoi
/// hanno il colore "secondario" del tema, così si ritrovano a colpo d'occhio.
class _CommentBubble extends StatelessWidget {
  final TicketComment comment;
  final List<TicketAttachment> attachments;

  const _CommentBubble({required this.comment, this.attachments = const []});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isMine = comment.authorUid == PerfectBoard.user.uid;
    final name = comment.authorName.trim();

    return Card.filled(
      margin: EdgeInsets.zero,
      color: isMine ? scheme.secondaryContainer : scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 16,
              child: Text(name.isEmpty ? '?' : name[0].toUpperCase()),
            ),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(name, style: theme.textTheme.titleSmall),
                      Text(
                        comment.createdAt != null
                            ? dateTimeFormat.format(comment.createdAt!)
                            : bt('now'),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  if (comment.text.isNotEmpty) ...[
                    const Gap(4),
                    SelectableText(comment.text,
                        style: theme.textTheme.bodyMedium),
                  ],
                  if (attachments.isNotEmpty) ...[
                    const Gap(10),
                    Wrap(
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
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
