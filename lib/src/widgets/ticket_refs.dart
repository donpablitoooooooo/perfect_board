import 'dart:developer';

import 'package:perfect_board/src/config.dart';
import 'package:perfect_board/src/models/ticket.dart';
import 'package:perfect_board/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:perfect_board/src/l10n.dart';
import 'package:gap/gap.dart';

/// I riferimenti di una segnalazione: le cose dell'app di cui parla (un
/// cliente, un ordine…). Si pescano con una ricerca dalle [BoardRefSource]
/// registrate dall'app, così sulla card resta un id vero e non una stringa
/// scritta a mano.
///
/// Firestore non ha la ricerca full-text: la sorgente carica un elenco
/// ([BoardRefSource.load]) e si filtra in memoria. Per le raccolte che
/// crescono senza fine la sorgente può cercare sul server
/// ([BoardRefSource.search]): lì si parte dall'elenco iniziale e a ogni
/// tasto si chiede al server.

/// Apre la ricerca e ritorna il riferimento scelto, o `null` se si chiude.
Future<TicketRef?> pickTicketRef(
  BuildContext context,
  BoardRefSource source,
) {
  return showDialog<TicketRef>(
    context: context,
    builder: (dialogContext) => _RefPicker(source: source),
  );
}

class _RefPicker extends StatefulWidget {
  final BoardRefSource source;

  const _RefPicker({required this.source});

  @override
  State<_RefPicker> createState() => _RefPickerState();
}

class _RefPickerState extends State<_RefPicker> {
  final TextEditingController _controller = TextEditingController();
  List<BoardRefHit> _hits = [];
  bool _loading = true;

  /// Vero se l'ultima lista viene dal server: allora non si rifiltra.
  bool _fromServer = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final hits = await widget.source.load();
      if (!mounted) return;
      setState(() {
        _hits = hits;
        _fromServer = false;
        _loading = false;
      });
    } catch (e) {
      log('Ticket ref load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Ricerca sul server, se la sorgente la offre. Ritorna falso se no.
  bool _search(String text) {
    final future = widget.source.search(text.trim());
    if (future == null) return false;
    setState(() => _loading = true);
    future.then((hits) {
      if (!mounted) return;
      setState(() {
        _hits = hits;
        _fromServer = true;
        _loading = false;
      });
    }).catchError((Object e) {
      log('Ticket ref search error: $e');
      if (mounted) setState(() => _loading = false);
    });
    return true;
  }

  List<BoardRefHit> get _filtered {
    final q = _controller.text.trim().toLowerCase();
    final hits = q.isEmpty || _fromServer
        ? _hits
        : _hits
            .where((h) => (h.haystack.isEmpty
                    ? '${h.label} ${h.subtitle}'.toLowerCase()
                    : h.haystack)
                .contains(q))
            .toList();
    return hits;
  }

  @override
  Widget build(BuildContext context) {
    final results = _filtered;
    final source = widget.source;

    return AlertDialog(
      title: Text(source.label),
      content: SizedBox(
        width: 460,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: source.searchHint.isEmpty
                    ? bt('search')
                    : source.searchHint,
                prefixIcon: const Icon(Icons.search, size: 20),
              ),
              onChanged: (value) {
                if (value.trim().isEmpty) {
                  if (_fromServer) {
                    _load();
                  } else {
                    setState(() {});
                  }
                } else if (!_search(value)) {
                  setState(() {});
                }
              },
            ),
            const Gap(12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : results.isEmpty
                      ? Center(
                          child: Text(
                            bt('noResults'),
                            style: const TextStyle(
                                color: subtitleColor, fontSize: 13),
                          ),
                        )
                      : ListView.builder(
                          itemCount: results.length,
                          itemBuilder: (_, i) {
                            final hit = results[i];
                            return ListTile(
                              dense: true,
                              leading: Icon(source.icon,
                                  size: 18, color: subtitleColor),
                              title: Text(
                                hit.label,
                                style: const TextStyle(
                                    color: lightTextColor, fontSize: 13),
                              ),
                              subtitle: hit.subtitle.isEmpty
                                  ? null
                                  : Text(
                                      hit.subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: subtitleColor, fontSize: 11),
                                    ),
                              onTap: () => Navigator.pop(
                                context,
                                TicketRef(
                                  kind: source.kind,
                                  id: hit.id,
                                  label: hit.label,
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(bt('cancel')),
        ),
      ],
    );
  }
}

/// Un bottone "aggiungi" per ogni sorgente registrata dall'app.
class TicketRefButtons extends StatelessWidget {
  final void Function(TicketRef ref) onPicked;

  const TicketRefButtons({super.key, required this.onPicked});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      children: [
        for (final source in PerfectBoard.refSources)
          TextButton.icon(
            onPressed: () async {
              final ref = await pickTicketRef(context, source);
              if (ref != null) onPicked(ref);
            },
            icon: Icon(source.icon, size: 16, color: tertiaryColor),
            label: Text(
              source.label,
              style: const TextStyle(color: tertiaryColor, fontSize: 13),
            ),
          ),
      ],
    );
  }
}

/// I riferimenti già attaccati. Senza [onRemove] è sola lettura.
class TicketRefChips extends StatelessWidget {
  final List<TicketRef> refs;
  final void Function(TicketRef ref)? onRemove;

  const TicketRefChips({super.key, required this.refs, this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final ref in refs)
          Container(
            padding: EdgeInsets.only(
              left: 8,
              top: 4,
              bottom: 4,
              right: onRemove == null ? 8 : 0,
            ),
            decoration: BoxDecoration(
              color: pureBlack,
              border: Border.all(color: tertiaryColor.withAlpha(90)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(ref.icon, size: 14, color: subtitleColor),
                const Gap(6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    ref.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: lightTextColor, fontSize: 12),
                  ),
                ),
                if (onRemove != null)
                  InkWell(
                    onTap: () => onRemove!(ref),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child:
                          Icon(Icons.close, size: 14, color: subtitleColor),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
