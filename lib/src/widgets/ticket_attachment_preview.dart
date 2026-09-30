import 'dart:convert';
import 'dart:developer';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:perfect_board/src/models/ticket.dart';
import 'package:perfect_board/src/open_url.dart';
import 'package:flutter/material.dart';
import 'package:perfect_board/src/widgets/ticket_ui.dart';
import 'package:perfect_board/src/l10n.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';
import 'package:video_player/video_player.dart';

/// Come si guarda un allegato. Si decide dal tipo e, se il tipo manca o è
/// generico (i file caricati prima che il tipo venisse riconosciuto sono
/// `application/octet-stream`), dall'estensione del nome.
enum _PreviewKind { image, pdf, video, text, none }

_PreviewKind _kindOf(TicketAttachment attachment) {
  final type = attachment.contentType.toLowerCase();
  final name = attachment.name.toLowerCase();
  final ext = name.contains('.') ? name.split('.').last : '';

  if (type.startsWith('image/') ||
      const ['png', 'jpg', 'jpeg', 'gif', 'webp'].contains(ext)) {
    return _PreviewKind.image;
  }
  if (type == 'application/pdf' || ext == 'pdf') return _PreviewKind.pdf;
  if (type.startsWith('video/') ||
      const ['mp4', 'mov', 'webm', 'm4v'].contains(ext)) {
    return _PreviewKind.video;
  }
  if (type.startsWith('text/') ||
      type == 'application/json' ||
      const ['txt', 'log', 'json', 'csv', 'md'].contains(ext)) {
    return _PreviewKind.text;
  }
  return _PreviewKind.none;
}

/// Apre l'anteprima di [attachments], partendo da quello in [initialIndex].
/// Le frecce (a schermo o da tastiera) passano agli altri senza chiudere.
Future<void> showTicketAttachmentPreview(
  BuildContext context, {
  required List<TicketAttachment> attachments,
  int initialIndex = 0,
}) {
  if (attachments.isEmpty) return Future.value();
  return showDialog<void>(
    context: context,
    builder: (_) => _PreviewDialog(
      attachments: attachments,
      initialIndex: initialIndex.clamp(0, attachments.length - 1),
    ),
  );
}

class _PreviewDialog extends StatefulWidget {
  final List<TicketAttachment> attachments;
  final int initialIndex;

  const _PreviewDialog({required this.attachments, required this.initialIndex});

  @override
  State<_PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<_PreviewDialog> {
  late int _index = widget.initialIndex;

  TicketAttachment get _current => widget.attachments[_index];
  bool get _hasPrev => _index > 0;
  bool get _hasNext => _index < widget.attachments.length - 1;

  void _go(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= widget.attachments.length) return;
    setState(() => _index = next);
  }

  @override
  Widget build(BuildContext context) {
    final many = widget.attachments.length > 1;
    final theme = Theme.of(context);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(1),
      },
      child: Focus(
        autofocus: true,
        child: Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              leading: const CloseButton(),
              title: Text(_current.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              actions: [
                Text(
                  [
                    if (_current.readableSize.isNotEmpty)
                      _current.readableSize,
                    if (many) '${_index + 1} / ${widget.attachments.length}',
                  ].join('  ·  '),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const Gap(8),
                IconButton(
                  tooltip: bt('openInNewTab'),
                  onPressed: _current.url.isEmpty
                      ? null
                      : () => openUrl(_current.url),
                  icon: const Icon(Icons.open_in_new),
                ),
                const Gap(8),
              ],
            ),
            body: Row(
              // stretch: senza, un testo corto finirebbe a metà altezza
              // invece di partire dall'alto.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (many) _arrow(Icons.chevron_left, _hasPrev, -1),
                Expanded(
                  // La chiave fa ripartire il contenuto a ogni cambio: un
                  // video o un PDF non devono restare quelli di prima.
                  child: KeyedSubtree(
                    key: ValueKey(_current.id),
                    child: _body(_current),
                  ),
                ),
                if (many) _arrow(Icons.chevron_right, _hasNext, 1),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _arrow(IconData icon, bool enabled, int delta) {
    return Center(
      child: IconButton(
        iconSize: 32,
        onPressed: enabled ? () => _go(delta) : null,
        icon: Icon(icon),
      ),
    );
  }

  Widget _body(TicketAttachment attachment) {
    if (attachment.url.isEmpty) return _message(bt('previewFailed'));
    switch (_kindOf(attachment)) {
      case _PreviewKind.image:
        return InteractiveViewer(
          maxScale: 6,
          child: Center(
            child: CachedNetworkImage(
              imageUrl: attachment.url,
              fit: BoxFit.contain,
              placeholder: (_, __) => const _Loading(),
              errorWidget: (_, __, ___) =>
                  _message(bt('previewFailed')),
            ),
          ),
        );
      case _PreviewKind.pdf:
        return _BytesLoader(
          url: attachment.url,
          builder: (bytes) => PdfPreview(
            build: (_) async => bytes,
            useActions: false,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            pdfFileName: attachment.name,
          ),
          onError: () => _message(bt('previewFailed')),
        );
      case _PreviewKind.video:
        return _VideoPreview(url: attachment.url);
      case _PreviewKind.text:
        return _BytesLoader(
          url: attachment.url,
          builder: (bytes) => SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: SelectableText(
                utf8.decode(bytes, allowMalformed: true),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontFamily: 'monospace'),
              ),
            ),
          ),
          onError: () => _message(bt('previewFailed')),
        );
      case _PreviewKind.none:
        return _message(bt('noPreview'));
    }
  }

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      );
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

/// Scarica il file e passa i byte a [builder]. PDF e testo vanno letti
/// dentro la pagina, quindi il bucket deve rispondere con i CORS del
/// backoffice (`cors.json`): senza, il browser blocca la lettura e qui si
/// vede [onError], mentre "apri in una nuova scheda" continua a funzionare.
class _BytesLoader extends StatefulWidget {
  final String url;
  final Widget Function(Uint8List bytes) builder;
  final Widget Function() onError;

  const _BytesLoader({
    required this.url,
    required this.builder,
    required this.onError,
  });

  @override
  State<_BytesLoader> createState() => _BytesLoaderState();
}

class _BytesLoaderState extends State<_BytesLoader> {
  late final Future<Uint8List> _bytes = _load();

  Future<Uint8List> _load() async {
    final response = await http.get(Uri.parse(widget.url));
    if (response.statusCode != 200) {
      throw StateError('HTTP ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          log('Ticket attachment preview error: ${snapshot.error}');
          return widget.onError();
        }
        if (!snapshot.hasData) return const _Loading();
        return widget.builder(snapshot.data!);
      },
    );
  }
}

/// Un video: si avvia e si ferma col clic, come ci si aspetta.
class _VideoPreview extends StatefulWidget {
  final String url;

  const _VideoPreview({required this.url});

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  late final VideoPlayerController _controller =
      VideoPlayerController.networkUrl(Uri.parse(widget.url));
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller.initialize().then((_) {
      if (mounted) setState(() {});
    }).catchError((Object e) {
      log('Ticket attachment video error: $e');
      if (mounted) setState(() => _failed = true);
    });
    _controller.addListener(_onTick);
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    final value = _controller.value;
    if (value.isPlaying) {
      _controller.pause();
    } else {
      if (value.position >= value.duration) _controller.seekTo(Duration.zero);
      _controller.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Center(child: TicketEmpty(bt('previewFailed')));
    }
    final value = _controller.value;
    if (!value.isInitialized) return const _Loading();

    return Column(
      children: [
        Expanded(
          child: Center(
            child: GestureDetector(
              onTap: _toggle,
              child: AspectRatio(
                aspectRatio: value.aspectRatio,
                child: VideoPlayer(_controller),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              IconButton.filledTonal(
                onPressed: _toggle,
                icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
              ),
              const Gap(8),
              Expanded(
                child: VideoProgressIndicator(
                  _controller,
                  allowScrubbing: true,
                  colors: VideoProgressColors(
                    playedColor: Theme.of(context).colorScheme.primary,
                    bufferedColor: Theme.of(context)
                        .colorScheme
                        .primary
                        .withAlpha(80),
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
