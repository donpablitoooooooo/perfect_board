import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:perfect_board/src/models/ticket.dart';
import 'package:perfect_board/src/theme.dart';
import 'package:perfect_board/src/widgets/ticket_attachments.dart';
import 'package:perfect_board/src/widgets/ticket_checklist.dart';
import 'package:perfect_board/src/widgets/ticket_comments.dart';
import 'package:perfect_board/src/widgets/ticket_delete.dart';
import 'package:perfect_board/src/widgets/ticket_export.dart';
import 'package:perfect_board/src/widgets/ticket_fields.dart';
import 'package:perfect_board/src/widgets/ticket_refs.dart';
import 'package:perfect_board/src/widgets/ticket_ui.dart';
import 'package:flutter/material.dart';
import 'package:perfect_board/src/l10n.dart';
import 'package:gap/gap.dart';

/// Una scheda aperta: la stessa pagina con cui la si crea, con dentro i
/// valori.
///
/// Una colonna sola. L'unico comando che serve qui dentro è lo **stato**, e
/// sta in barra: tenere una colonna a destra per un menu a tendina era
/// sprecato, e così il corpo prende tutta la larghezza.
///
/// Niente branch, niente note private, niente timeline: servivano a passare
/// il lavoro a Claude, e adesso lo fa il bottone **Esporta** in un colpo solo.
class TicketDetailPage extends StatefulWidget {
  final String? ticketId;

  const TicketDetailPage({super.key, required this.ticketId});

  @override
  State<TicketDetailPage> createState() => _TicketDetailPageState();
}

class _TicketDetailPageState extends State<TicketDetailPage> {
  StreamSubscription? _sub;
  Ticket? _ticket;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  DocumentReference<Map<String, dynamic>> get _doc =>
      FirebaseFirestore.instance.collection('Tickets').doc(widget.ticketId);

  void _listen() {
    if (widget.ticketId == null) {
      setState(() => _loaded = true);
      return;
    }
    _sub = _doc.snapshots().listen((snap) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _ticket = snap.exists
            ? Ticket.fromFirestore(snap.id, snap.data() ?? {})
            : null;
      });
    }, onError: (e) {
      log('Ticket detail error: $e');
      if (mounted) setState(() => _loaded = true);
    });
  }

  /// Ogni modifica passa da qui: un solo posto che sa scrivere, un solo
  /// messaggio quando non ci riesce.
  Future<void> _update(Map<String, dynamic> data, [String? done]) async {
    try {
      await _doc.update({...data, 'updatedAt': FieldValue.serverTimestamp()});
      if (done != null && mounted) ticketToast(context, done);
    } catch (e) {
      log('Ticket update error: $e');
      if (mounted) ticketToast(context, bt('changeFailed'));
    }
  }

  Future<void> _setStatus(TicketStatus status) async {
    final ticket = _ticket;
    if (ticket == null || ticket.status == status) return;
    await _update({
      'status': status.key,
      'statusChangedAt': FieldValue.serverTimestamp(),
      if (status == TicketStatus.fatto) 'doneAt': FieldValue.serverTimestamp(),
    }, bt('statusChanged', {'status': status.label}));
  }

  Future<void> _delete(Ticket ticket) async {
    final gone = await confirmAndDeleteTicket(context, ticket);
    if (!gone || !mounted) return;
    // Lo stream sul documento appena cancellato farebbe lampeggiare
    // "Scheda non trovata": si chiude prima di tornare in bacheca.
    _sub?.cancel();
    Navigator.pop(context);
  }

  /// I riferimenti viaggiano in due campi: la lista leggibile e le chiavi
  /// piatte, che servono a poter chiedere un domani "le schede di questo box".
  Future<void> _saveRefs(List<TicketRef> refs) => _update({
        'refs': refs.map((r) => r.toMap()).toList(),
        'refKeys': refs.map((r) => r.key).toList(),
      });

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final ticket = _ticket;
    if (ticket == null) {
      return Scaffold(
        body: Center(
          child: Text(bt('notFound'),
              style: const TextStyle(color: subtitleColor)),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(ticket),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: SizedBox(width: 860, child: _buildBody(ticket)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Ticket ticket) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 24, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: cardColor)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: tertiaryColor),
            onPressed: () => Navigator.pop(context),
          ),
          const Gap(8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ticket.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
                const Gap(2),
                Text(
                  '#${ticket.shortId} · ${ticket.createdByName} · '
                  '${ticket.createdAt != null ? dateTimeFormat.format(ticket.createdAt!) : '—'}',
                  style: const TextStyle(color: subtitleColor, fontSize: 12),
                ),
              ],
            ),
          ),
          const Gap(16),
          _buildStatusPicker(ticket),
          const Gap(12),
          OutlinedButton.icon(
            icon: const Icon(Icons.download_outlined, size: 16),
            label: Text(bt('export')),
            onPressed: () => showTicketExport(context, ticket),
          ),
          const Gap(4),
          IconButton(
            tooltip: bt('deleteTooltip'),
            icon: const Icon(Icons.delete_outline,
                size: 18, color: subtitleColor),
            onPressed: () => _delete(ticket),
          ),
        ],
      ),
    );
  }

  /// Lo stato: l'unica cosa che si cambia da qui, quindi sta sempre in vista
  /// e col suo colore addosso.
  Widget _buildStatusPicker(Ticket ticket) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: cardColor,
        border: Border.all(color: ticket.status.color.withAlpha(140)),
      ),
      child: DropdownButton<TicketStatus>(
        value: ticket.status,
        underline: const SizedBox(),
        items: [
          for (final status in TicketStatus.values)
            DropdownMenuItem(
              value: status,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: status.color, shape: BoxShape.circle),
                  ),
                  const Gap(10),
                  Text(status.label,
                      style: const TextStyle(
                          color: lightTextColor, fontSize: 13)),
                ],
              ),
            ),
        ],
        onChanged: (value) {
          if (value != null) _setStatus(value);
        },
      ),
    );
  }

  Widget _buildBody(Ticket ticket) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Titolo e descrizione come nella pagina di apertura, ma si
        // correggono sul posto: si salva uscendo dal campo.
        _EditableText(
          value: ticket.title,
          label: bt('fieldTitle'),
          style: const TextStyle(
              color: lightTextColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              height: 1.3),
          onSave: (text) => _update({'title': text}, bt('saved')),
        ),
        const Gap(20),
        _EditableText(
          value: ticket.body,
          label: bt('fieldBody'),
          maxLines: 8,
          style: const TextStyle(
              color: lightTextColor, fontSize: 15, height: 1.6),
          onSave: (text) => _update({'body': text}, bt('saved')),
        ),

        const Gap(20),
        const Divider(),

        TicketField(
          label: bt('labels'),
          child: TicketLabelsField(
            selected: ticket.labels.toSet(),
            onToggle: (label, on) {
              final labels = ticket.labels.toSet();
              if (on) {
                labels.add(label);
              } else {
                labels.remove(label);
              }
              _update({'labels': labels.map((l) => l.key).toList()});
            },
          ),
        ),
        const Divider(),

        TicketField(
          label: bt('dueDate'),
          child: TicketDueField(
            dueAt: ticket.dueAt,
            overdue: ticket.isOverdue,
            onPick: (value) => _update(
                {'dueAt': Timestamp.fromDate(value)}, bt('dueSet')),
            onClear: () => _update(
                {'dueAt': FieldValue.delete()}, bt('dueCleared')),
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
                onPicked: (ref) {
                  if (ticket.refs.any((r) => r.key == ref.key)) return;
                  _saveRefs([...ticket.refs, ref]);
                },
              ),
              if (ticket.refs.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 12, top: 4),
                  child: Text(
                    bt('linksHint'),
                    style:
                        const TextStyle(color: subtitleColor, fontSize: 12),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TicketRefChips(
                    refs: ticket.refs,
                    onRemove: (ref) => _saveRefs(
                      ticket.refs.where((r) => r.key != ref.key).toList(),
                    ),
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
            items: ticket.checklist,
            onSave: (items) =>
                _update({'checklist': items.map((i) => i.toMap()).toList()}),
          ),
        ),
        const Divider(),

        TicketField(
          label: bt('attachments'),
          alignTop: true,
          child: TicketAttachments(
            ticketId: ticket.id,
            ticketTitle: ticket.title,
          ),
        ),

        const Gap(24),
        const Divider(),
        const Gap(16),
        Text(
          bt('sectionComments').toUpperCase(),
          style: const TextStyle(
            color: tertiaryColor,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const Gap(14),
        TicketComments(
          ticketId: ticket.id,
          ticketTitle: ticket.title,
        ),
        const Gap(24),
      ],
    );
  }
}

/// Un campo di testo obbligatorio che si modifica sul posto.
///
/// A riposo è testo e basta, senza la cornice del campo: la pagina resta
/// pulita. Un clic lo apre in modifica; si salva quando si esce dal campo
/// (o con Invio, se è su una riga sola) e solo se il testo è cambiato.
/// Vuoto non si può lasciare: torna com'era.
/// Mentre ci scrivi, gli aggiornamenti che arrivano da Firestore non
/// toccano quello che stai scrivendo; appena esci, il campo si riallinea.
class _EditableText extends StatefulWidget {
  final String value;
  final String label;
  final int maxLines;
  final TextStyle style;
  final Future<void> Function(String text) onSave;

  const _EditableText({
    required this.value,
    required this.label,
    required this.onSave,
    required this.style,
    this.maxLines = 1,
  });

  @override
  State<_EditableText> createState() => _EditableTextState();
}

class _EditableTextState extends State<_EditableText> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);
  final FocusNode _focus = FocusNode();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) return;
      _commit();
      if (mounted) setState(() => _editing = false);
    });
  }

  @override
  void didUpdateWidget(covariant _EditableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    // Scrivi e torni subito in bacheca con la freccia: il campo non ha
    // fatto in tempo a perdere il fuoco, ma la modifica non va persa.
    if (_focus.hasFocus) _commit();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      _controller.text = widget.value;
      return;
    }
    if (text != widget.value) widget.onSave(text);
  }

  @override
  Widget build(BuildContext context) {
    // Un campo vuoto resta campo: altrimenti non ci sarebbe niente da
    // cliccare. Non dovrebbe capitare, sono obbligatori, ma le schede
    // scritte dalla CLI potrebbero non avere la descrizione.
    if (!_editing && widget.value.isNotEmpty) {
      return MouseRegion(
        cursor: SystemMouseCursors.text,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _editing = true),
          child: SizedBox(
            width: double.infinity,
            child: Text(widget.value, style: widget.style),
          ),
        ),
      );
    }

    final multiline = widget.maxLines > 1;
    return TextField(
      controller: _controller,
      focusNode: _focus,
      autofocus: _editing,
      style: widget.style,
      minLines: 1,
      maxLines: widget.maxLines,
      textInputAction:
          multiline ? TextInputAction.newline : TextInputAction.done,
      onSubmitted: multiline ? null : (_) => _focus.unfocus(),
      decoration: InputDecoration(
        labelText: '${widget.label} *',
        alignLabelWithHint: multiline,
      ),
    );
  }
}
