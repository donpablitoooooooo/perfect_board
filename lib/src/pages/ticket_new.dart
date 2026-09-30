import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:perfect_board/src/models/ticket.dart';
import 'package:perfect_board/src/config.dart';
import 'package:perfect_board/src/widgets/ticket_attachments.dart';
import 'package:perfect_board/src/widgets/ticket_checklist.dart';
import 'package:perfect_board/src/widgets/ticket_fields.dart';
import 'package:perfect_board/src/widgets/ticket_refs.dart';
import 'package:perfect_board/src/widgets/ticket_screenshot.dart';
import 'package:perfect_board/src/widgets/ticket_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:perfect_board/src/l10n.dart';
import 'package:gap/gap.dart';

/// Apertura di una scheda, a pagina intera.
///
/// Era un dialogo: con etichette, scadenza, collegamenti, checklist e
/// allegati ci stava stretto, e soprattutto era un secondo impianto da
/// mantenere accanto al dettaglio. Ora è la stessa pagina del dettaglio, con
/// gli stessi campi negli stessi posti — si impara una volta sola.
///
/// Obbligatori titolo e descrizione, e basta: il resto aiuta chi la lavora,
/// ma non deve fermare chi la sta aprendo.
/// Scheda lasciata a metà per andare a scattare una schermata: la pagina si
/// smonta mentre si naviga il backoffice, e al ritorno tutto deve esserci.
class _NewTicketDraft {
  final String title;
  final String body;
  final Set<TicketLabel> labels;
  final List<TicketRef> refs;
  final List<ChecklistItem> checklist;
  final List<PlatformFile> files;
  final DateTime? dueAt;

  const _NewTicketDraft({
    required this.title,
    required this.body,
    required this.labels,
    required this.refs,
    required this.checklist,
    required this.files,
    required this.dueAt,
  });
}

_NewTicketDraft? _draft;

const String _draftKey = 'new';

class TicketNewPage extends StatefulWidget {
  const TicketNewPage({super.key});

  @override
  State<TicketNewPage> createState() => _TicketNewPageState();
}

class _TicketNewPageState extends State<TicketNewPage> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();

  final Set<TicketLabel> _labels = {};
  final List<TicketRef> _refs = [];
  final List<ChecklistItem> _checklist = [];
  final List<PlatformFile> _files = [];
  DateTime? _dueAt;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final draft = _draft;
    _draft = null;
    if (draft != null) {
      _title.text = draft.title;
      _body.text = draft.body;
      _labels.addAll(draft.labels);
      _refs.addAll(draft.refs);
      _checklist.addAll(draft.checklist);
      _files.addAll(draft.files);
      _dueAt = draft.dueAt;
    }
    _files.addAll(TicketScreenshot.takeShots(_draftKey));
    TicketScreenshot.shotsChanged.addListener(_pullShots);
  }

  @override
  void dispose() {
    TicketScreenshot.shotsChanged.removeListener(_pullShots);
    if (TicketScreenshot.isActiveFor(_draftKey)) {
      _draft = _NewTicketDraft(
        title: _title.text,
        body: _body.text,
        labels: Set.of(_labels),
        refs: List.of(_refs),
        checklist: List.of(_checklist),
        files: List.of(_files),
        dueAt: _dueAt,
      );
    }
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  /// Schermata scattata senza lasciare la pagina: il form è ancora qui.
  void _pullShots() {
    final shots = TicketScreenshot.takeShots(_draftKey);
    if (shots.isNotEmpty && mounted) setState(() => _files.addAll(shots));
  }

  void _startScreenshot() {
    final title = _title.text.trim();
    TicketScreenshot.start(TicketScreenshotTarget.draft(
      draftKey: _draftKey,
      title: title.isEmpty ? bt('newCard') : title,
      returnTo: '${PerfectBoard.basePath}/new',
    ));
    ticketToast(context, bt('screenshotStarted'));
  }

  /// Uscita senza aprire la scheda: la bozza non serve più.
  void _leave() {
    TicketScreenshot.endFor(_draftKey);
    Navigator.pop(context);
  }

  bool get _canCreate =>
      _title.text.trim().isNotEmpty && _body.text.trim().isNotEmpty;

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

  Future<void> _create() async {
    if (!_canCreate || _saving) return;
    setState(() => _saving = true);
    try {
      final doc = await FirebaseFirestore.instance.collection('Tickets').add({
        'title': _title.text.trim(),
        'body': _body.text.trim(),
        'labels': _labels.map((l) => l.key).toList(),
        'refs': _refs.map((r) => r.toMap()).toList(),
        'refKeys': _refs.map((r) => r.key).toList(),
        'checklist': _checklist.map((i) => i.toMap()).toList(),
        if (_dueAt != null) 'dueAt': Timestamp.fromDate(_dueAt!),
        'status': TicketStatus.nuova.key,
        'statusChangedAt': FieldValue.serverTimestamp(),
        // Stessa scala di createdAt: la scheda nasce in cima alla colonna.
        'order': DateTime.now().millisecondsSinceEpoch.toDouble(),
        'createdBy': {
          'uid': PerfectBoard.user.uid,
          'name': PerfectBoard.user.name,
          'email': PerfectBoard.user.email,
          'role': 'admin',
        },
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Gli allegati arrivano dopo, uno alla volta: se uno non passa la
      // scheda resta comunque aperta — perderla per un file sarebbe il modo
      // peggiore di fallire.
      var failed = 0;
      for (final file in _files) {
        try {
          await uploadTicketAttachment(ticketId: doc.id, file: file);
        } catch (e) {
          log('Ticket create attachment error: $e');
          failed++;
        }
      }

      TicketScreenshot.endFor(_draftKey);
      if (!mounted) return;
      ticketToast(
        context,
        failed == 0
            ? bt('opened')
            : bt('openedWithFailures', {'count': '$failed'}),
      );
      Navigator.pop(context);
    } catch (e) {
      log('Ticket create error: $e');
      if (mounted) {
        setState(() => _saving = false);
        ticketToast(context, bt('createFailed'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _leave),
        title: Text(bt('newCard')),
        actions: [
          TextButton(onPressed: _leave, child: Text(bt('cancel'))),
          const Gap(8),
          FilledButton(
            onPressed: _canCreate && !_saving ? _create : null,
            child: Text(_saving ? bt('sending') : bt('create')),
          ),
          const Gap(16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: SizedBox(width: 860, child: _buildForm()),
        ),
      ),
    );
  }

  Widget _buildForm() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Obbligatori ──
        TextField(
          controller: _title,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: '${bt('fieldTitle')} *',
          ),
        ),
        const Gap(20),
        TextField(
          controller: _body,
          maxLines: 8,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: '${bt('fieldBody')} *',
            alignLabelWithHint: true,
          ),
        ),

        const Gap(28),
        const Divider(),
        const Gap(4),
        Text(
          bt('optional'),
          style: theme.textTheme.titleSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const Gap(4),

        TicketField(
          label: bt('labels'),
          child: TicketLabelsField(
            selected: _labels,
            onToggle: (label, on) => setState(() {
              if (on) {
                _labels.add(label);
              } else {
                _labels.remove(label);
              }
            }),
          ),
        ),
        const Divider(),

        TicketField(
          label: bt('dueDate'),
          child: TicketDueField(
            dueAt: _dueAt,
            onPick: (value) => setState(() => _dueAt = value),
            onClear: () => setState(() => _dueAt = null),
          ),
        ),
        const Divider(),

        TicketField(
          label: bt('sectionLinks'),
          alignTop: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TicketRefButtons(
                onPicked: (ref) => setState(() {
                  if (!_refs.any((r) => r.key == ref.key)) _refs.add(ref);
                }),
              ),
              if (_refs.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: TicketEmpty(bt('linksHint')),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TicketRefChips(
                    refs: _refs,
                    onRemove: (ref) => setState(
                        () => _refs.removeWhere((r) => r.key == ref.key)),
                  ),
                ),
            ],
          ),
        ),
        const Divider(),

        TicketField(
          label: bt('sectionChecklist'),
          alignTop: true,
          child: TicketChecklist(
            items: _checklist,
            onSave: (items) => setState(() {
              _checklist
                ..clear()
                ..addAll(items);
            }),
          ),
        ),
        const Divider(),

        TicketField(
          label: bt('attachments'),
          alignTop: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                children: [
                  TextButton.icon(
                    onPressed: _pickFiles,
                    icon: const Icon(Icons.attach_file),
                    label: Text(bt('addFiles')),
                  ),
                  // Come nel dettaglio: si naviga fino al punto e si scatta;
                  // le schermate tornano qui fra i file da allegare.
                  TextButton.icon(
                    onPressed: _startScreenshot,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(bt('screenshot')),
                  ),
                ],
              ),
              if (_files.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: TicketEmpty(bt('attachmentsHint')),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (var i = 0; i < _files.length; i++)
                        TicketPickedFileChip(
                          file: _files[i],
                          onRemove: () => setState(() => _files.removeAt(i)),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        const Gap(20),
        const Divider(),
        const Gap(10),
        Text(
          '* ${bt('requiredNote')}',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const Gap(24),
      ],
    );
  }
}
