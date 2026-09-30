import 'package:flutter/material.dart';

/// Pezzi di interfaccia condivisi dalla board. Solo componenti Material 3
/// standard: forme, colori e tipografia vengono dal tema dell'app.

/// Conferma breve in basso, con lo `SnackBar` del tema. Il contesto deve
/// stare sotto uno `ScaffoldMessenger` (lo mette `MaterialApp`).
void ticketToast(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Un'etichetta colorata: `Chip` compatto tinto con [color].
class TicketChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const TicketChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: icon == null ? null : Icon(icon, color: color),
      label: Text(label),
      labelStyle:
          Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      backgroundColor: color.withAlpha(30),
      side: BorderSide(color: color.withAlpha(120)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      padding: EdgeInsets.zero,
    );
  }
}

/// Stato vuoto discreto.
class TicketEmpty extends StatelessWidget {
  final String text;

  const TicketEmpty(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// Un file come card: miniatura (o icona) sopra, nome e peso sotto, la ✕ per
/// toglierlo. Lo stesso riquadro per un allegato caricato e per un file
/// ancora in attesa di partire.
class TicketFileCard extends StatelessWidget {
  final Widget preview;
  final String name;
  final String size;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final String? removeTooltip;

  const TicketFileCard({
    super.key,
    required this.preview,
    required this.name,
    required this.size,
    this.onTap,
    this.onRemove,
    this.removeTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 160,
      child: Card.outlined(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 96,
                child: ColoredBox(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: preview,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall),
                          Text(size,
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    if (onRemove != null)
                      IconButton(
                        tooltip: removeTooltip,
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        onPressed: onRemove,
                        icon: const Icon(Icons.close),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// L'icona al posto della miniatura per i file che non sono immagini.
class TicketFileIcon extends StatelessWidget {
  final String contentType;

  const TicketFileIcon(this.contentType, {super.key});

  @override
  Widget build(BuildContext context) {
    return Icon(
      contentType.startsWith('video/')
          ? Icons.movie_outlined
          : contentType == 'application/pdf'
              ? Icons.picture_as_pdf_outlined
              : Icons.insert_drive_file_outlined,
      size: 32,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }
}
