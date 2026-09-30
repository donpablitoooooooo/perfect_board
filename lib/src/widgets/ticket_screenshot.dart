import 'dart:developer';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:intl/intl.dart';
import 'package:perfect_board/src/theme.dart';
import 'package:perfect_board/src/widgets/ticket_attachments.dart';
import 'package:perfect_board/src/widgets/ticket_ui.dart';
import 'package:perfect_board/src/board_file.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:perfect_board/src/l10n.dart';
import 'package:flutter/rendering.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

/// Chi sta aspettando una schermata.
///
/// Con [ticketId] (riquadro allegati del dettaglio) il PNG si carica subito
/// sulla scheda. Con [draftKey] (scheda nuova, commento) resta in memoria
/// fino a quando la pagina lo riprende con [TicketScreenshot.takeShots]:
/// là i file partono insieme al resto, con "Apri" o "Commenta".
class TicketScreenshotTarget {
  final String title;

  /// Dove porta "Torna alla scheda".
  final String returnTo;
  final String? ticketId;
  final String? draftKey;

  const TicketScreenshotTarget.upload({
    required String this.ticketId,
    required this.title,
    required this.returnTo,
  }) : draftKey = null;

  const TicketScreenshotTarget.draft({
    required String this.draftKey,
    required this.title,
    required this.returnTo,
  }) : ticketId = null;
}

/// Schermate del backoffice da allegare a una scheda.
///
/// Il bottone nel dettaglio accende la sessione ([start]); da lì si naviga il
/// backoffice come sempre, con la cornice e la barretta di
/// [TicketScreenshotHost] sopra. "Scatta" fotografa quello che sta nella
/// cornice, carica il PNG fra gli allegati con la stessa funzione della
/// graffetta e torna alla scheda.
class TicketScreenshot {
  TicketScreenshot._();

  static final ValueNotifier<TicketScreenshotTarget?> session =
      ValueNotifier(null);

  static void start(TicketScreenshotTarget target) {
    session.value = target;
  }

  /// Vero se la sessione aperta aspetta le schermate di [draftKey]: la
  /// pagina che si smonta salva la bozza solo in quel caso.
  static bool isActiveFor(String draftKey) =>
      session.value?.draftKey == draftKey;

  /// Chiude la sessione di [draftKey], se è quella aperta: la bozza è stata
  /// inviata o abbandonata, non c'è più niente da aspettare.
  static void endFor(String draftKey) {
    if (isActiveFor(draftKey)) session.value = null;
  }

  static final Map<String, List<BoardFile>> _shots = {};

  /// Scatta ogni volta che una schermata va in una bozza: la pagina, se è
  /// ancora montata (si è scattato senza cambiare pagina), la riprende subito.
  static final ValueNotifier<int> shotsChanged = ValueNotifier(0);

  static void _addShot(String draftKey, BoardFile file) {
    _shots.putIfAbsent(draftKey, () => []).add(file);
    shotsChanged.value++;
  }

  /// Le schermate di [draftKey] non ancora riprese; le toglie dalla memoria.
  static List<BoardFile> takeShots(String draftKey) =>
      _shots.remove(draftKey) ?? const [];
}

/// Avvolge tutta l'app (dal `builder` del `MaterialApp`).
///
/// Il `RepaintBoundary` è quello che si fotografa. La cornice di mira e la
/// barretta in basso stanno fuori, quindi non finiscono nella schermata. Un
/// passo solo: "Scatta" fotografa quello che sta dentro la cornice, lo
/// allega e torna alla scheda. Sta fuori dal Navigator: per i toast usa
/// [navigatorKey], per tornare alla scheda [router].
class TicketScreenshotHost extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  final GoRouter router;

  const TicketScreenshotHost({
    super.key,
    required this.child,
    required this.navigatorKey,
    required this.router,
  });

  @override
  State<TicketScreenshotHost> createState() => _TicketScreenshotHostState();
}

/// Margini della cornice all'inizio: in basso lascia libera la barretta.
const EdgeInsets _kFrameStart = EdgeInsets.fromLTRB(24, 24, 24, 88);
const Size _kFrameMin = Size(120, 80);

/// Spessore della fascia del bordo che si afferra per spostare la cornice,
/// e lato del quadratino d'angolo che la ridimensiona.
const double _kGrip = 14;
const double _kHandle = 32;

class _TicketScreenshotHostState extends State<TicketScreenshotHost> {
  final GlobalKey _boundaryKey = GlobalKey();

  /// Acceso dallo scatto fino al ritorno alla scheda.
  bool _busy = false;

  /// La cornice, in coordinate logiche della finestra. Null finché non si
  /// conosce la misura della finestra (e a ogni sessione nuova).
  Rect? _frame;

  /// Tratti a mano libera, in coordinate logiche della finestra (non della
  /// cornice: spostandola restano dove sono sullo schermo).
  final List<List<Offset>> _strokes = [];

  @override
  void initState() {
    super.initState();
    TicketScreenshot.session.addListener(_onSession);
  }

  @override
  void dispose() {
    TicketScreenshot.session.removeListener(_onSession);
    super.dispose();
  }

  /// Una sessione nuova (o chiusa) riparte dalla cornice iniziale.
  void _onSession() {
    if (mounted) {
      setState(() {
        _busy = false;
        _frame = null;
        _strokes.clear();
      });
    }
  }

  void _toast(String message) {
    final context = widget.navigatorKey.currentState?.overlay?.context;
    if (context != null && context.mounted) ticketToast(context, message);
  }

  void _backToTicket(TicketScreenshotTarget target) {
    TicketScreenshot.session.value = null;
    // Già sulla scheda (si è scattato senza navigare): niente `go`. La
    // pagina è stata aperta con `push`, e `go` sulla stessa rotta la
    // sostituirebbe con una nuova, vuota: Nuova scheda e commento
    // perderebbero la schermata appena presa e il testo scritto.
    // `state` è la pagina in cima, anche se aperta con push (la
    // `currentConfiguration` darebbe quella sotto).
    final here = widget.router.state.uri.path;
    if (here == Uri.parse(target.returnTo).path) return;
    widget.router.go(target.returnTo);
  }

  /// Fotografa la cornice, allega il PNG (o lo mette nella bozza) e torna
  /// alla scheda.
  Future<void> _take(TicketScreenshotTarget target) async {
    final frame = _frame;
    if (_busy || frame == null) return;
    final pixelRatio = math.min(MediaQuery.of(context).devicePixelRatio, 2.0);
    final inkColor = context.board.error;
    setState(() => _busy = true);
    try {
      // La cornice sta fuori dal boundary: basta lasciar finire il frame in
      // corso e fotografare.
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('No boundary');
      final bytes = await _capture(
          boundary, frame, pixelRatio, _strokes, inkColor);

      final name =
          'screenshot_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.png';
      final file = BoardFile(name: name, bytes: bytes);
      if (target.ticketId != null) {
        await uploadTicketAttachment(ticketId: target.ticketId!, file: file);
      } else {
        TicketScreenshot._addShot(target.draftKey!, file);
      }
      _forgetDecodedImages();
      if (!mounted) return;
      _backToTicket(target);
      _toast(target.ticketId != null
          ? bt('screenshotSaved')
          : bt('screenshotAdded'));
    } catch (e) {
      log('Ticket screenshot error: $e');
      _forgetDecodedImages();
      _toast(bt('screenshotFailed'));
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Il PNG di quello che sta dentro [frame]. Le immagini intermedie stanno
  /// nella memoria grafica e si liberano subito: se restano, dopo qualche
  /// scatto il browser perde il contesto WebGL e l'app si disegna nera.
  Future<Uint8List> _capture(
    RenderRepaintBoundary boundary,
    Rect frame,
    double pixelRatio,
    List<List<Offset>> strokes,
    Color ink,
  ) async {
    final full = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final src = Rect.fromLTRB(
        frame.left * pixelRatio,
        frame.top * pixelRatio,
        frame.right * pixelRatio,
        frame.bottom * pixelRatio,
      ).intersect(
          Offset.zero & Size(full.width.toDouble(), full.height.toDouble()));
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..drawImageRect(full, src, Offset.zero & src.size, Paint());
      // Il disegno sta fuori dal boundary: si ripassa sopra il ritaglio.
      canvas
        ..scale(pixelRatio)
        ..translate(-frame.left, -frame.top);
      _paintStrokes(canvas, strokes, ink);
      final picture = recorder.endRecording();
      final cropped =
          await picture.toImage(src.width.round(), src.height.round());
      picture.dispose();
      try {
        final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('PNG encoding failed');
        return data.buffer.asUint8List();
      } finally {
        cropped.dispose();
      }
    } finally {
      full.dispose();
    }
  }

  /// Lo scatto può far ricreare al browser il contesto grafico: le immagini
  /// decodificate prima (miniature degli allegati, anteprime) restano legate
  /// a quello vecchio e si disegnano nere. Flutter le tiene in cache e le
  /// ridà a ogni pagina che le chiede, quindi restavano nere fino al
  /// ricaricamento. Svuotata la cache, si ridecodificano sul contesto nuovo
  /// (i file li ridà la cache HTTP del browser, non si riscaricano).
  void _forgetDecodedImages() {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  }

  /// Tiene la cornice dentro la finestra e non più piccola del minimo.
  Rect _clampFrame(Rect r, Size size) {
    final w = r.width.clamp(_kFrameMin.width, size.width);
    final h = r.height.clamp(_kFrameMin.height, size.height);
    final left = r.left.clamp(0.0, size.width - w);
    final top = r.top.clamp(0.0, size.height - h);
    return Rect.fromLTWH(left, top, w, h);
  }

  void _move(Offset delta, Size size) {
    final frame = _frame;
    if (frame == null) return;
    setState(() => _frame = _clampFrame(frame.shift(delta), size));
  }

  /// Ridimensiona dall'angolo [corner] (`Alignment.topLeft` ecc.): quello
  /// opposto resta fermo.
  void _resize(Alignment corner, Offset delta, Size size) {
    final f = _frame;
    if (f == null) return;
    var l = f.left, t = f.top, r = f.right, b = f.bottom;
    if (corner.x < 0) {
      l = (l + delta.dx).clamp(0.0, r - _kFrameMin.width);
    } else {
      r = (r + delta.dx).clamp(l + _kFrameMin.width, size.width);
    }
    if (corner.y < 0) {
      t = (t + delta.dy).clamp(0.0, b - _kFrameMin.height);
    } else {
      b = (b + delta.dy).clamp(t + _kFrameMin.height, size.height);
    }
    setState(() => _frame = Rect.fromLTRB(l, t, r, b));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(key: _boundaryKey, child: widget.child),
        ),
        ValueListenableBuilder<TicketScreenshotTarget?>(
          valueListenable: TicketScreenshot.session,
          builder: (context, target, _) {
            if (target == null) return const SizedBox.shrink();
            return Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = constraints.biggest;
                  final frame = _clampFrame(
                    _frame ?? _kFrameStart.deflateRect(Offset.zero & size),
                    size,
                  );
                  _frame = frame;
                  return Stack(
                    children: [
                      ..._buildFrame(frame, size),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 16,
                        child: Center(child: _buildBar(target)),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  /// La cornice: fuori un velo scuro, sul bordo le fasce che la spostano e
  /// negli angoli i quadratini che la ridimensionano. Dentro non c'è niente,
  /// quindi i clic arrivano all'app e si continua a navigare.
  List<Widget> _buildFrame(Rect frame, Size size) {
    Widget grip(Rect r, MouseCursor cursor, GestureDragUpdateCallback onPan) =>
        Positioned.fromRect(
          rect: r,
          child: MouseRegion(
            cursor: cursor,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: onPan,
            ),
          ),
        );
    void move(DragUpdateDetails d) => _move(d.delta, size);
    const g = _kGrip / 2;
    return [
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            painter: _FramePainter(
              frame,
              _strokes,
              accent: context.board.accent,
              ink: context.board.error,
              scrim: context.board.scrim,
            ),
          ),
        ),
      ),
      // Dentro la cornice: trascinando si disegna. È "translucent", quindi
      // anche l'app sotto riceve il puntatore: un clic senza muoversi resta
      // suo (si naviga), appena ci si muove vince il disegno, che sta sopra
      // e arriva per primo.
      Positioned.fromRect(
        rect: frame,
        child: RawGestureDetector(
          behavior: HitTestBehavior.translucent,
          gestures: {
            PanGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
              () => PanGestureRecognizer(),
              (r) => r
                ..dragStartBehavior = DragStartBehavior.down
                ..onStart = (d) {
                  setState(() => _strokes.add([d.globalPosition]));
                }
                ..onUpdate = (d) {
                  setState(() => _strokes.last.add(d.globalPosition));
                },
            ),
          },
        ),
      ),
      // Bordi: spostano.
      grip(Rect.fromLTRB(frame.left, frame.top - g, frame.right, frame.top + g),
          SystemMouseCursors.move, move),
      grip(
          Rect.fromLTRB(
              frame.left, frame.bottom - g, frame.right, frame.bottom + g),
          SystemMouseCursors.move,
          move),
      grip(
          Rect.fromLTRB(
              frame.left - g, frame.top, frame.left + g, frame.bottom),
          SystemMouseCursors.move,
          move),
      grip(
          Rect.fromLTRB(
              frame.right - g, frame.top, frame.right + g, frame.bottom),
          SystemMouseCursors.move,
          move),
      // Angoli: ridimensionano.
      for (final corner in const [
        Alignment.topLeft,
        Alignment.topRight,
        Alignment.bottomLeft,
        Alignment.bottomRight,
      ])
        grip(
          Rect.fromCenter(
            center: corner.withinRect(frame),
            width: _kHandle,
            height: _kHandle,
          ),
          corner.x * corner.y < 0
              ? SystemMouseCursors.resizeUpRightDownLeft
              : SystemMouseCursors.resizeUpLeftDownRight,
          (d) => _resize(corner, d.delta, size),
        ),
    ];
  }

  Widget _buildBar(TicketScreenshotTarget target) {
    final theme = Theme.of(context);
    return Card(
      elevation: 6,
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_camera_outlined, color: theme.colorScheme.primary),
            const Gap(12),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bt('screenshotFor', {'title': target.title}),
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      bt('screenshotFrame'),
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
            const Gap(16),
            FilledButton.icon(
              onPressed: _busy ? null : () => _take(target),
              icon: const Icon(Icons.photo_camera),
              label: Text(_busy ? bt('uploading') : bt('screenshotTake')),
            ),
            const Gap(8),
            if (_strokes.isNotEmpty)
              TextButton(
                onPressed: _busy ? null : () => setState(_strokes.clear),
                child: Text(bt('screenshotClear')),
              ),
            TextButton(
              onPressed: _busy ? null : () => _backToTicket(target),
              child: Text(bt('screenshotBack')),
            ),
          ],
        ),
      ),
    );
  }
}

/// La cornice di mira: velo scuro fuori, bordo sottile e angoli spessi.
/// I tratti a mano libera: rossi, spessi abbastanza da vedersi nel PNG.
void _paintStrokes(Canvas canvas, List<List<Offset>> strokes, Color ink) {
  final paint = Paint()
    ..color = ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  for (final stroke in strokes) {
    if (stroke.length == 1) {
      canvas.drawCircle(
          stroke.first, 1.5, Paint()..color = ink);
      continue;
    }
    final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
    for (final p in stroke.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, paint);
  }
}

class _FramePainter extends CustomPainter {
  final Rect frame;
  final List<List<Offset>> strokes;
  final Color accent;
  final Color ink;
  final Color scrim;

  const _FramePainter(
    this.frame,
    this.strokes, {
    required this.accent,
    required this.ink,
    required this.scrim,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Il velo sono quattro fasce attorno alla cornice. Con una differenza
    // di tracciati (Path.combine) CanvasKit a volte scuriva anche l'interno.
    final veil = Paint()..color = scrim.withValues(alpha: 0.35);
    canvas
      ..drawRect(Rect.fromLTRB(0, 0, size.width, frame.top), veil)
      ..drawRect(Rect.fromLTRB(0, frame.bottom, size.width, size.height), veil)
      ..drawRect(Rect.fromLTRB(0, frame.top, frame.left, frame.bottom), veil)
      ..drawRect(
          Rect.fromLTRB(frame.right, frame.top, size.width, frame.bottom),
          veil);
    canvas.drawRect(
      frame,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    const arm = 28.0;
    final paint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final l = frame.left, t = frame.top, r = frame.right, b = frame.bottom;
    for (final corner in [
      [Offset(l, t + arm), Offset(l, t), Offset(l + arm, t)],
      [Offset(r - arm, t), Offset(r, t), Offset(r, t + arm)],
      [Offset(r, b - arm), Offset(r, b), Offset(r - arm, b)],
      [Offset(l + arm, b), Offset(l, b), Offset(l, b - arm)],
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(corner[0].dx, corner[0].dy)
          ..lineTo(corner[1].dx, corner[1].dy)
          ..lineTo(corner[2].dx, corner[2].dy),
        paint,
      );
    }
    _paintStrokes(canvas, strokes, ink);
  }

  // I tratti crescono sul posto (stessa lista): si ridisegna sempre, costa
  // poco e la cornice cambia comunque a ogni trascinamento.
  @override
  bool shouldRepaint(_FramePainter old) => true;
}
