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
/// Componenti Material 3 standard: colori, forme e tipografia vengono dal
/// tema dell'app.
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
    // L'account demo legge solo la sua board privata (le regole non gli
    // lasciano leggere altro, e una query più larga verrebbe rifiutata
    // intera). Niente orderBy lì: servirebbe un indice composto, e le
    // colonne si ordinano comunque da sole. Gli altri non vedono le board
    // demo.
    final sandbox = PerfectBoard.sandbox;
    final tickets = FirebaseFirestore.instance.collection('Tickets');
    final query = sandbox != null
        ? tickets.where('sandbox', isEqualTo: sandbox)
        : tickets.orderBy('createdAt', descending: true);
    _sub = query.snapshots().listen((snap) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _tickets = snap.docs
            .where((d) => sandbox != null || d.data()['sandbox'] == null)
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
      appBar: AppBar(
        title: Text(bt('title')),
        actions: [
          TextButton.icon(
            onPressed: () => setState(() => _showScartate = !_showScartate),
            icon: Icon(
                _showScartate ? Icons.visibility_off : Icons.visibility),
            label: Text(bt('discarded', {'count': '${scartate.length}'})),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: () => context.push('${PerfectBoard.basePath}/new'),
            icon: const Icon(Icons.add),
            label: Text(bt('newCard')),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSearchAndFilters(),
            const SizedBox(height: 16),
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
    );
  }

  /// Ricerca e filtro per etichetta. Le etichette sono tre: stanno tutte in
  /// fila, senza menu a tendina da aprire per scoprire cosa c'è dentro.
  Widget _buildSearchAndFilters() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SearchBar(
            hintText: bt('search'),
            leading: const Icon(Icons.search),
            elevation: const WidgetStatePropertyAll(0),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        const SizedBox(width: 8),
        FilterChip(
          label: Text(bt('filterAll')),
          selected: _labelFilter == null,
          onSelected: (_) => setState(() => _labelFilter = null),
        ),
        for (final label in TicketLabel.values)
          FilterChip(
            label: Text(label.label),
            selected: _labelFilter == label,
            selectedColor: context.board.label(label).withAlpha(50),
            onSelected: (_) => setState(() => _labelFilter = label),
          ),
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
    final theme = Theme.of(context);
    final statusColor = context.board.status(status);

    // Bersaglio di riserva su tutta la colonna: prende i rilasci che non
    // cadono su uno spazio fra le card, e le mette in fondo.
    return DragTarget<Ticket>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) =>
          _move(details.data, status, index: tickets.length),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return Card.filled(
          margin: EdgeInsets.zero,
          color: hovering
              ? Color.alphaBlend(
                  statusColor.withAlpha(24), context.board.column)
              : context.board.column,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        status.label,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    Badge.count(
                      count: tickets.length,
                      backgroundColor: statusColor,
                    ),
                  ],
                ),
                Divider(color: statusColor, thickness: 2, height: 16),
                Expanded(
                  child: tickets.isEmpty
                      ? _DropSlot(
                          status: status,
                          onAccept: (ticket) =>
                              _move(ticket, status, index: 0),
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
          ),
        );
      },
    );
  }

  Widget _buildDraggableCard(Ticket ticket) {
    void open() =>
        context.push('${PerfectBoard.basePath}/detail/${ticket.id}');
    return Draggable<Ticket>(
      data: ticket,
      feedback: Material(
        type: MaterialType.transparency,
        child: Opacity(
          opacity: 0.9,
          child: SizedBox(width: 260, child: _TicketCard(ticket: ticket)),
        ),
      ),
      // Il vuoto al posto di partenza, senza toccare la lista: la card resta
      // nell'albero, quindi il drag finisce sempre come deve.
      childWhenDragging: const SizedBox.shrink(),
      child: _TicketCard(ticket: ticket, onTap: open),
    );
  }

  /// Una card scartata, con il cestino sopra: qui l'eliminazione ha senso,
  /// perché ci si arriva già avendo deciso che la scheda non serve. Dal
  /// dettaglio si elimina comunque: questo è solo il modo corto.
  Widget _buildScartataCard(Ticket ticket) {
    return Stack(
      children: [
        _buildDraggableCard(ticket),
        Positioned(
          top: 4,
          right: 4,
          child: IconButton.filledTonal(
            visualDensity: VisualDensity.compact,
            tooltip: bt('delete'),
            onPressed: () => confirmAndDeleteTicket(context, ticket),
            icon: const Icon(Icons.delete_outline, size: 18),
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
      height: 150,
      child: DragTarget<Ticket>(
        onWillAcceptWithDetails: (details) =>
            details.data.status != TicketStatus.scartata,
        onAcceptWithDetails: (details) =>
            _move(details.data, TicketStatus.scartata),
        builder: (context, candidate, rejected) {
          final hovering = candidate.isNotEmpty;
          return Card.outlined(
            margin: EdgeInsets.zero,
            color: hovering ? context.board.column : null,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: scartate.isEmpty
                  ? Center(
                      child: TicketEmpty(hovering
                          ? bt('dropToDiscard')
                          : bt('nothingDiscarded')),
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
    final color = context.board.status(status);
    return DragTarget<Ticket>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        if (expanded) {
          return Center(child: TicketEmpty(hovering ? bt('dropHere') : '—'));
        }
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: hovering ? 40 : 8,
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: hovering ? color.withAlpha(40) : null,
            borderRadius: BorderRadius.circular(12),
            border: hovering ? Border.all(color: color) : null,
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
  final VoidCallback? onTap;

  const _TicketCard({required this.ticket, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // "Pronta" chiede un'azione a chi la legge: bordo del suo colore.
    final ready = ticket.status == TicketStatus.pronta;
    return Card(
      margin: EdgeInsets.zero,
      color: context.board.card,
      clipBehavior: Clip.antiAlias,
      shape: ready
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: context.board.status(ticket.status)),
            )
          : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (ticket.labels.isNotEmpty) ...[
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final label in ticket.labels)
                      TicketChip(
                        label: label.label,
                        color: context.board.label(label),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              Text(
                ticket.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 8),
              _badge(
                context,
                Icons.schedule,
                ticket.statusAgeLabel,
                color: ticket.statusAgeColor,
              ),
              _buildBadges(context),
            ],
          ),
        ),
      ),
    );
  }

  /// Scadenza e checklist: la riga compare solo se c'è almeno una delle
  /// due, così una card appena aperta resta pulita.
  Widget _buildBadges(BuildContext context) {
    final badges = <Widget>[];

    if (ticket.dueAt != null) {
      badges.add(_badge(
        context,
        Icons.event_outlined,
        dateFormat.format(ticket.dueAt!),
        color: ticket.dueColor,
      ));
    }
    if (ticket.checklist.isNotEmpty) {
      badges.add(_badge(context, Icons.checklist,
          '${ticket.checklistDone}/${ticket.checklist.length}'));
    }

    if (badges.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(spacing: 12, runSpacing: 4, children: badges),
    );
  }

  Widget _badge(BuildContext context, IconData icon, String text,
      {Color? color}) {
    final tint = color ?? context.board.subtle;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: tint),
        const SizedBox(width: 4),
        Text(text,
            style:
                Theme.of(context).textTheme.labelMedium?.copyWith(color: tint)),
      ],
    );
  }
}
