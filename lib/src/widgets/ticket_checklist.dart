import 'package:perfect_board/src/models/ticket.dart';
import 'package:flutter/material.dart';
import 'package:perfect_board/src/l10n.dart';
import 'package:gap/gap.dart';

/// La checklist di una scheda: le cose da fare dentro la card.
///
/// Sta in un array sul documento, non in una sottocollection: sono poche righe
/// e vanno lette insieme alla card (il contatore "2/5" si vede sulla board).
/// Ogni modifica riscrive l'array intero, che per quattro voci è più semplice
/// e più prevedibile di un aggiornamento chirurgico.
///
/// Non scrive da sé: [onSave] riceve la lista intera. Il dettaglio la manda
/// a Firestore, la pagina di apertura la tiene in memoria finché la scheda
/// non esiste — stesso widget, stesso aspetto, due destinazioni.
class TicketChecklist extends StatefulWidget {
  final List<ChecklistItem> items;
  final void Function(List<ChecklistItem> items) onSave;

  const TicketChecklist({
    super.key,
    required this.items,
    required this.onSave,
  });

  @override
  State<TicketChecklist> createState() => _TicketChecklistState();
}

class _TicketChecklistState extends State<TicketChecklist> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save(List<ChecklistItem> items) => widget.onSave(items);

  void _add() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    _save([...widget.items, ChecklistItem(text: text)]);
  }

  void _toggle(int index) {
    final items = [...widget.items];
    items[index] = items[index].copyWith(done: !items[index].done);
    _save(items);
  }

  void _remove(int index) => _save([...widget.items]..removeAt(index));

  @override
  Widget build(BuildContext context) {
    final done = widget.items.where((i) => i.done).length;
    final total = widget.items.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (total > 0) ...[
          Row(
            children: [
              Expanded(child: LinearProgressIndicator(value: done / total)),
              const Gap(12),
              Text('$done/$total',
                  style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
          const Gap(4),
          for (var i = 0; i < total; i++)
            _ChecklistRow(
              item: widget.items[i],
              onToggle: () => _toggle(i),
              onRemove: () => _remove(i),
            ),
        ],
        const Gap(8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                onSubmitted: (_) => _add(),
                decoration: InputDecoration(
                  hintText: bt('checklistHint'),
                  isDense: true,
                ),
              ),
            ),
            const Gap(8),
            IconButton.filledTonal(
              tooltip: bt('add'),
              icon: const Icon(Icons.add),
              onPressed: _add,
            ),
          ],
        ),
      ],
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  final ChecklistItem item;
  final VoidCallback onToggle;
  final VoidCallback onRemove;

  const _ChecklistRow({
    required this.item,
    required this.onToggle,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CheckboxListTile(
      value: item.done,
      onChanged: (_) => onToggle(),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        item.text,
        style: item.done
            ? TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                decoration: TextDecoration.lineThrough,
              )
            : null,
      ),
      secondary: IconButton(
        tooltip: bt('remove'),
        visualDensity: VisualDensity.compact,
        iconSize: 18,
        icon: const Icon(Icons.close),
        onPressed: onRemove,
      ),
    );
  }
}
