import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:perfect_board/src/models/ticket.dart';
import 'package:perfect_board/src/config.dart';
import 'package:perfect_board/src/theme.dart';
import 'package:perfect_board/src/widgets/ticket_delete.dart';
import 'package:perfect_board/src/widgets/ticket_ui.dart';
import 'package:flutter/material.dart';
import 'package:perfect_board/src/l10n.dart';
import 'package:go_router/go_router.dart';

/// Board delle segnalazioni: una colonna per stato, card trascinabili sia fra
/// le colonne sia dentro la stessa, per decidere l'ordine.
///
/// I testi seguono la lingua scelta nel backoffice come il resto del
/// gestionale: stanno nel blocco `tickets` di `assets/languagesFile`.
///
/// Il flusso è semi-manuale per scelta: nessuna card si sposta da sola.
class TicketsPage extends StatefulWidget {
  const TicketsPage({super.key});

  @override
  State<TicketsPage> createState() => _TicketsPageState();
}

class _TicketsPageState extends State<TicketsPage> {
  StreamSubscription? _sub;
  bool _loaded = false;
  List<Ticket> _tickets = [];
  String _query = '';
  bool _showScartate = false;

  /// Filtro etichetta: `null` = tutte.
  TicketLabel? _labelFilter;

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

  void _listen() {
    _sub = FirebaseFirestore.instance
        .collection('Tickets')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _tickets = snap.docs
            .map((d) => Ticket.fromFirestore(d.id, d.data()))
            .toList();
      });
    }, onError: (e) {
      log('Tickets stream error: $e');
      if (mounted) setState(() => _loaded = true);
    });
  }

  /// Le card di una colonna, filtrate e nell'ordine deciso a mano: `sortKey`
  /// decrescente, cioè il valore più alto in cima.
  ///
  /// La card che stai trascinando resta nella lista: togliendola smonteremmo
  /// il suo `Draggable`, e senza quello `onDragEnd` non scatta più — la card
  /// spariva dalla board fino al refresh. Il buco al posto giusto lo fa
  /// `childWhenDragging`, che non ha bisogno di saperlo.
  List<Ticket> _column(TicketStatus status) {
    final q = _query.toLowerCase();
    final tickets = _tickets.where((t) {
      if (t.status != status) return false;
      if (_labelFilter != null && !t.labels.contains(_labelFilter)) {
        return false;
      }
      if (q.isEmpty) return true;
      return t.title.toLowerCase().contains(q) ||
          t.body.toLowerCase().contains(q) ||
          t.createdByName.toLowerCase().contains(q) ||
          t.shortId.toLowerCase().contains(q) ||
          // Il numero di un box o di un ordine trova le sue segnalazioni
          // anche se nel testo non l'ha scritto nessuno: è metà del motivo
          // per cui i riferimenti esistono.
          t.refs.any((r) => r.label.toLowerCase().contains(q));
    }).toList();
    tickets.sort((a, b) => b.sortKey.compareTo(a.sortKey));
    return tickets;
  }

  /// Sposta una card in una colonna, a una posizione precisa.
  ///
  /// [index] è il posto fra le card già presenti (0 = in cima). L'ordine è un
  /// numero sulla scala dei millisecondi: per infilarsi in mezzo si prende il
  /// punto medio fra i vicini, che è il trucco più vecchio e più solido per
  /// riordinare senza riscrivere tutta la colonna.
  Future<void> _move(Ticket ticket, TicketStatus target, {int? index}) async {
    // [index] conta gli slot della colonna come la vedi, cioè con dentro
    // anche la card che stai trascinando: se parte da sopra il punto di
    // rilascio, togliendola dai vicini l'indice scala di uno.
    final displayed = _column(target);
    final from = displayed.indexWhere((t) => t.id == ticket.id);
    final siblings = displayed.where((t) => t.id != ticket.id).toList();
    double? order;

    if (index != null) {
      var at = index;
      if (from >= 0 && from < index) at -= 1;
      at = at.clamp(0, siblings.length);
      final above = at > 0 ? siblings[at - 1] : null;
      final below = at < siblings.length ? siblings[at] : null;
      if (above == null && below == null) {
        order = ticket.sortKey;
      } else if (above == null) {
        order = below!.sortKey + 1000;
      } else if (below == null) {
        order = above.sortKey - 1000;
      } else {
        order = (above.sortKey + below.sortKey) / 2;
      }
    }

    if (ticket.status == target && order == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('Tickets')
          .doc(ticket.id)
          .update({
        'status': target.key,
        if (order != null) 'order': order,
        'updatedAt': FieldValue.serverTimestamp(),
        // Solo se cambia colonna: riordinare non azzera il "da quanto".
        if (ticket.status != target)
          'statusChangedAt': FieldValue.serverTimestamp(),
        // Timbriamo il momento del rilascio: è la data che serve a ritrovare
        // in quale release è andata.
        if (target == TicketStatus.fatto && ticket.status != target)
          'doneAt': FieldValue.serverTimestamp(),
      });
      if (mounted && ticket.status != target) {
        ticketToast(context, '#${ticket.shortId} → ${target.label}');
      }
    } catch (e) {
      log('Ticket move error: $e');
      if (mounted) ticketToast(context, bt('moveFailed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scartate =
        _tickets.where((t) => t.status == TicketStatus.scartata).toList();

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(scartate.length),
              const SizedBox(height: 20),
              Expanded(
                child: !_loaded
                    ? const Center(child: CircularProgressIndicator())
                    : _buildBoard(),
              ),
              if (_showScartate) ...[
                const SizedBox(height: 12),
                _buildScartate(scartate),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(int scartateCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeaderRow(scartateCount),
        const SizedBox(height: 12),
        _buildFilters(),
      ],
    );
  }

  Widget _buildHeaderRow(int scartateCount) {
    return Row(
      children: [
        Text(bt('title'),
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 22)),
        const SizedBox(width: 24),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(15, 0, 15, 0),
            child: SizedBox(
              height: 40,
              child: TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: bt('search'),
                  prefixIcon: const Icon(Icons.search, size: 25),
                ),
              ),
            ),
          ),
        ),
        TextButton.icon(
          onPressed: () => setState(() => _showScartate = !_showScartate),
          icon: Icon(
            _showScartate ? Icons.visibility_off : Icons.visibility,
            size: 18,
            color: subtitleColor,
          ),
          label: Text(
            bt('discarded', {'count': '$scartateCount'}),
            style: const TextStyle(color: subtitleColor, fontSize: 13),
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton(
          style: ButtonStyle(
            elevation: WidgetStateProperty.all(0),
          ),
          onPressed: () => context.push('${PerfectBoard.basePath}/new'),
          child: Text(bt('newCard')),
        ),
      ],
    );
  }

  /// Le etichette sono tre: stanno tutte in fila, senza menu a tendina da
  /// aprire per scoprire cosa c'è dentro.
  Widget _buildFilters() {
    Widget chip(String label, TicketLabel? value, Color color) {
      final selected = _labelFilter == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          selectedColor: color.withAlpha(40),
          side: BorderSide(color: selected ? color : subtitleColor),
          onSelected: (_) => setState(() => _labelFilter = value),
        ),
      );
    }

    return Row(
      children: [
        chip(bt('filterAll'), null, tertiaryColor),
        for (final label in TicketLabel.values)
          chip(label.label, label, label.color),
      ],
    );
  }

  Widget _buildBoard() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final status in TicketStatus.boardColumns) ...[
          Expanded(child: _buildColumn(status)),
          if (status != TicketStatus.boardColumns.last)
            const SizedBox(width: 12),
        ],
      ],
    );
  }

  Widget _buildColumn(TicketStatus status) {
    final tickets = _column(status);

    // Bersaglio di riserva su tutta la colonna: prende i rilasci che non
    // cadono su uno spazio fra le card, e le mette in fondo.
    return DragTarget<Ticket>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) =>
          _move(details.data, status, index: tickets.length),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        // La colonna ha il suo fondo (softBlack, un tono sotto le card):
        // senza, su uno sfondo navy uniforme non si vede dove finisce.
        return Container(
          decoration: BoxDecoration(
            color: hovering
                ? Color.alphaBlend(status.color.withAlpha(20), softBlack)
                : softBlack,
            border: Border.all(
              color: hovering ? status.color.withAlpha(120) : Colors.transparent,
            ),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: status.color, width: 2),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        status.label.toUpperCase(),
                        style: const TextStyle(
                            color: lightTextColor,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1),
                      ),
                    ),
                    Text('${tickets.length}',
                        style: const TextStyle(
                            color: subtitleColor, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: tickets.isEmpty
                    ? _DropSlot(
                        status: status,
                        onAccept: (ticket) => _move(ticket, status, index: 0),
                        expanded: true,
                      )
                    : ListView(
                        children: [
                          _DropSlot(
                            status: status,
                            onAccept: (ticket) =>
                                _move(ticket, status, index: 0),
                          ),
                          for (var i = 0; i < tickets.length; i++) ...[
                            _buildDraggableCard(tickets[i]),
                            _DropSlot(
                              status: status,
                              onAccept: (ticket) =>
                                  _move(ticket, status, index: i + 1),
                            ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDraggableCard(Ticket ticket) {
    final card = _TicketCard(ticket: ticket);
    return Draggable<Ticket>(
      data: ticket,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.9,
          child: SizedBox(width: 260, child: card),
        ),
      ),
      // Il vuoto al posto di partenza, senza toccare la lista: la card resta
      // nell'albero, quindi il drag finisce sempre come deve.
      childWhenDragging: const SizedBox.shrink(),
      child: InkWell(
        onTap: () => context.push('${PerfectBoard.basePath}/detail/${ticket.id}'),
        child: card,
      ),
    );
  }

  /// Una card scartata, con il cestino sopra: qui l'eliminazione ha senso,
  /// perché ci si arriva già avendo deciso che la scheda non serve. Dal
  /// dettaglio si elimina comunque: questo è solo il modo corto.
  Widget _buildScartataCard(Ticket ticket) {
    final card = _buildDraggableCard(ticket);
    return Stack(
      children: [
        card,
        Positioned(
          top: 2,
          right: 2,
          child: Material(
            color: pureBlack,
            child: InkWell(
              onTap: () => confirmAndDeleteTicket(context, ticket),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.delete_outline,
                    size: 16, color: subtitleColor),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Zona "scartate": è anche il bersaglio per scartare trascinando, quindi
  /// esiste anche quando è vuota — altrimenti la prima segnalazione da
  /// scartare non avrebbe dove cadere.
  Widget _buildScartate(List<Ticket> scartate) {
    return SizedBox(
      height: 130,
      child: DragTarget<Ticket>(
        onWillAcceptWithDetails: (details) =>
            details.data.status != TicketStatus.scartata,
        onAcceptWithDetails: (details) =>
            _move(details.data, TicketStatus.scartata),
        builder: (context, candidate, rejected) {
          final hovering = candidate.isNotEmpty;
          return Container(
            decoration: BoxDecoration(
              color: hovering ? Colors.grey.withAlpha(20) : Colors.transparent,
              border: Border.all(color: hovering ? Colors.grey : cardColor),
            ),
            padding: const EdgeInsets.all(8),
            child: scartate.isEmpty
                ? Center(
                    child: Text(
                      hovering
                          ? bt('dropToDiscard')
                          : bt('nothingDiscarded'),
                      style: const TextStyle(
                          color: subtitleColor, fontSize: 13),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: scartate.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => SizedBox(
                      width: 260,
                      child: _buildScartataCard(scartate[i]),
                    ),
                  ),
          );
        },
      ),
    );
  }
}

/// Lo spazio fra due card: è lì che si rilascia per decidere la posizione.
/// A riposo è una fessura di pochi pixel, in hover si apre e si illumina.
class _DropSlot extends StatelessWidget {
  final TicketStatus status;
  final void Function(Ticket ticket) onAccept;
  final bool expanded;

  const _DropSlot({
    required this.status,
    required this.onAccept,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<Ticket>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        if (expanded) {
          return Center(
            child: Text(
              hovering ? bt('dropHere') : '—',
              style: const TextStyle(color: subtitleColor, fontSize: 13),
            ),
          );
        }
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: hovering ? 34 : 8,
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: hovering ? status.color.withAlpha(40) : Colors.transparent,
            border: hovering
                ? Border.all(color: status.color.withAlpha(140))
                : null,
          ),
        );
      },
    );
  }
}

/// Card della board, quattro righe dall'alto in basso: etichette, titolo,
/// da quanto è in questa colonna, scadenza e checklist. Chi l'ha aperta,
/// quando e cosa riguarda stanno nel dettaglio: sulla board serve capire a
/// colpo d'occhio cosa è fermo e cosa scade.
class _TicketCard extends StatelessWidget {
  final Ticket ticket;

  const _TicketCard({required this.ticket});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        border: Border.all(
          color: ticket.status == TicketStatus.pronta
              ? ticket.status.color.withAlpha(120)
              : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ticket.labels.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final label in ticket.labels)
                  TicketChip(
                    label: label.label,
                    color: label.color,
                    dense: true,
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Text(
            ticket.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: lightTextColor, fontSize: 14, height: 1.35),
          ),
          const SizedBox(height: 8),
          _badge(
            Icons.schedule,
            ticket.statusAgeLabel,
            color: ticket.statusAgeColor,
            fontSize: 12,
          ),
          _buildBadges(),
        ],
      ),
    );
  }

  /// Scadenza e checklist: la riga compare solo se c'è almeno una delle
  /// due, così una card appena aperta resta pulita.
  Widget _buildBadges() {
    final badges = <Widget>[];

    if (ticket.dueAt != null) {
      badges.add(_badge(
        Icons.event_outlined,
        dateFormat.format(ticket.dueAt!),
        color: ticket.dueColor,
      ));
    }
    if (ticket.checklist.isNotEmpty) {
      badges.add(_badge(Icons.checklist,
          '${ticket.checklistDone}/${ticket.checklist.length}'));
    }

    if (badges.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(spacing: 12, runSpacing: 4, children: badges),
    );
  }

  Widget _badge(IconData icon, String text,
      {Color? color, double fontSize = 11}) {
    final tint = color ?? subtitleColor;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: tint),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: tint, fontSize: fontSize)),
      ],
    );
  }
}
