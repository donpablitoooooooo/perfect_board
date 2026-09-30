import 'package:perfect_board/src/models/ticket.dart';
import 'package:perfect_board/src/widgets/ticket_attachments.dart';
import 'package:file_picker/file_picker.dart';
import 'package:perfect_board/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:perfect_board/src/l10n.dart';

/// I campi facoltativi di una scheda, uguali mentre la apri e mentre la
/// rileggi.
///
/// Stanno qui e non dentro le due pagine perché sono le stesse: la pagina
/// nuova tiene i valori in memoria, il dettaglio li scrive su Firestore, e
/// l'unica differenza è cosa fa la callback.

/// Una riga: etichetta a sinistra, contenuto a destra.
///
/// La colonna fissa a sinistra è quello che dà aria: l'occhio scende
/// sull'elenco delle etichette invece di cercare dove comincia ogni campo.
class TicketField extends StatelessWidget {
  final String label;
  final Widget child;

  /// Per i campi alti (collegamenti, checklist) l'etichetta va in cima e non
  /// a metà.
  final bool alignTop;

  const TicketField({
    super.key,
    required this.label,
    required this.child,
    this.alignTop = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment:
            alignTop ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 140,
            child: Padding(
              padding: EdgeInsets.only(top: alignTop ? 8 : 0),
              child: Text(
                label,
                style: const TextStyle(color: subtitleColor, fontSize: 13),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Le tre etichette, sempre tutte in vista: si accendono e si spengono con un
/// tocco, senza dialoghi da aprire per scoprire cosa c'è dentro.
class TicketLabelsField extends StatelessWidget {
  final Set<TicketLabel> selected;
  final void Function(TicketLabel label, bool on) onToggle;

  const TicketLabelsField({
    super.key,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final label in TicketLabel.values)
          FilterChip(
            label: Text(label.label),
            selected: selected.contains(label),
            selectedColor: label.color.withAlpha(40),
            side: BorderSide(
              color: selected.contains(label) ? label.color : subtitleColor,
            ),
            onSelected: (on) => onToggle(label, on),
          ),
      ],
    );
  }
}

/// La scadenza: si mette con un tocco e si toglie con la ✕. Rossa quando è
/// passata, che è l'unico momento in cui deve saltare all'occhio.
class TicketDueField extends StatelessWidget {
  final DateTime? dueAt;
  final bool overdue;
  final void Function(DateTime value) onPick;
  final VoidCallback onClear;

  const TicketDueField({
    super.key,
    required this.dueAt,
    required this.onPick,
    required this.onClear,
    this.overdue = false,
  });

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: dueAt ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked != null) onPick(picked);
  }

  @override
  Widget build(BuildContext context) {
    final value = dueAt;
    return Row(
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.event_outlined, size: 16),
          label: Text(
            value != null ? dateFormat.format(value) : bt('dueNone'),
            style: TextStyle(
              color: overdue ? Colors.redAccent : tertiaryColor,
              fontSize: 13,
            ),
          ),
          onPressed: () => _pick(context),
        ),
        if (value != null)
          IconButton(
            tooltip: bt('dueCleared'),
            icon: const Icon(Icons.close, size: 16, color: subtitleColor),
            onPressed: onClear,
          ),
      ],
    );
  }
}

/// Un file scelto mentre apri la scheda, prima che la scheda esista.
class TicketPickedFileChip extends StatelessWidget {
  final PlatformFile file;
  final VoidCallback onRemove;

  const TicketPickedFileChip(
      {super.key, required this.file, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final size = file.size;
    final readable = size < 1024 * 1024
        ? '${(size / 1024).round()} KB'
        : '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    final type = ticketAttachmentContentType(file.extension);
    final bytes = file.bytes;

    // Stesso riquadro di un allegato già caricato (`TicketAttachmentTile`):
    // la miniatura c'è da subito, non solo dopo l'invio. L'immagine viene
    // dai byte già in memoria, ridotta alla misura del riquadro.
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 96,
            width: double.infinity,
            decoration: BoxDecoration(
              color: pureBlack,
              border: Border.all(color: cardColor),
            ),
            child: type.startsWith('image/') && bytes != null
                ? Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    cacheWidth: 300,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      color: subtitleColor,
                    ),
                  )
                : Icon(
                    type.startsWith('video/')
                        ? Icons.movie_outlined
                        : Icons.insert_drive_file_outlined,
                    color: subtitleColor,
                    size: 32),
          ),
          const SizedBox(height: 6),
          Text(
            file.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: lightTextColor, fontSize: 12),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  readable,
                  style: const TextStyle(color: subtitleColor, fontSize: 11),
                ),
              ),
              InkWell(
                onTap: onRemove,
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
