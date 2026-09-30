import 'dart:ui' as ui;

import 'package:perfect_board/src/widgets/ticket_screenshot.dart';
import 'package:flutter/gestures.dart';
import 'package:perfect_board/src/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

int presses = 0;

void main() {
  Future<GoRouter> pumpApp(WidgetTester tester, String returnTo) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final navKey = GlobalKey<NavigatorState>();
    final router = GoRouter(navigatorKey: navKey, routes: [
      GoRoute(
          path: '/',
          builder: (_, __) => Scaffold(
              body: Center(
                  child: TextButton(
                      onPressed: () => presses++,
                      child: const Text('PAGINA'))))),
      GoRoute(
          path: returnTo,
          builder: (_, __) => const Scaffold(body: Text('RITORNO'))),
    ]);
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: router,
      builder: (c, child) => TicketScreenshotHost(
          navigatorKey: navKey, router: router, child: child!),
    ));
    return router;
  }

  final frame = find.byWidgetPredicate((w) =>
      w is CustomPaint && w.painter.runtimeType.toString() == '_FramePainter');

  testWidgets('cornice e barretta finché la sessione è aperta', (tester) async {
    await pumpApp(tester, '/tickets/detail/T1');
    expect(frame, findsNothing);
    TicketScreenshot.start(const TicketScreenshotTarget.upload(
        ticketId: 'T1', title: 'Bug ordini', returnTo: '/tickets/detail/T1'));
    await tester.pump();
    expect(frame, findsOneWidget);
    expect(find.text(bt('screenshotTake')), findsOneWidget);
    // Dentro la cornice i clic arrivano all'app.
    expect(
        tester
            .hitTestOnBinding(const Offset(640, 400))
            .path
            .any((e) => e.target.runtimeType.toString() == 'RenderParagraph'),
        isTrue);

    await tester.tap(find.text(bt('screenshotBack')));
    await tester.pumpAndSettle();
    expect(find.text('RITORNO'), findsOneWidget);
    expect(TicketScreenshot.session.value, isNull);
    expect(frame, findsNothing);
  });

  testWidgets('Scatta: solo la cornice, dritti alla pagina', (tester) async {
    await pumpApp(tester, '/tickets/new');
    var notified = 0;
    TicketScreenshot.shotsChanged.addListener(() => notified++);
    TicketScreenshot.start(const TicketScreenshotTarget.draft(
        draftKey: 'new', title: 'Nuova scheda', returnTo: '/tickets/new'));
    await tester.pump();

    // Cornice iniziale 24,24 → 1256,712. Dall'angolo in basso a destra la
    // si stringe, poi dal bordo in alto la si sposta.
    await tester.dragFrom(const Offset(1256, 712), const Offset(-256, -212),
        kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.dragFrom(const Offset(500, 24), const Offset(100, 50),
        kind: PointerDeviceKind.mouse);
    await tester.pump();

    await tester.tap(find.text(bt('screenshotTake')));
    await tester.runAsync(() async {
      for (var i = 0; i < 20; i++) {
        await tester.pump();
        await Future.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpAndSettle();

    expect(find.text('RITORNO'), findsOneWidget, reason: 'dritti alla pagina');
    expect(TicketScreenshot.isActiveFor('new'), isFalse);
    expect(notified, 1);

    final shots = TicketScreenshot.takeShots('new');
    expect(shots, hasLength(1));
    expect(shots.single.name, endsWith('.png'));
    final png = shots.single.bytes;
    expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    // Misure dall'intestazione IHDR: quelle della cornice (976×476, a meno
    // del pixel di tolleranza del trascinamento).
    int be(int o) =>
        (png[o] << 24) | (png[o + 1] << 16) | (png[o + 2] << 8) | png[o + 3];
    expect(be(16), inInclusiveRange(970, 980));
    expect(be(20), inInclusiveRange(470, 480));
    expect(TicketScreenshot.takeShots('new'), isEmpty);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('dentro la cornice: il clic va all\'app, il trascinamento disegna',
      (tester) async {
    presses = 0;
    await pumpApp(tester, '/tickets/new');
    TicketScreenshot.start(const TicketScreenshotTarget.draft(
        draftKey: 'new', title: 'Nuova scheda', returnTo: '/tickets/new'));
    await tester.pump();

    await tester.tap(find.text('PAGINA'));
    await tester.pump();
    expect(presses, 1, reason: 'il clic passa all\'app');
    expect(find.text(bt('screenshotClear')), findsNothing);

    // Un tratto orizzontale che parte proprio dal bottone: disegna e non lo
    // preme.
    await tester.dragFrom(
        tester.getCenter(find.text('PAGINA')), const Offset(200, 0),
        kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(presses, 1, reason: 'trascinando non si preme');
    expect(find.text(bt('screenshotClear')), findsOneWidget);

    await tester.tap(find.text(bt('screenshotTake')));
    await tester.runAsync(() async {
      for (var i = 0; i < 20; i++) {
        await tester.pump();
        await Future.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpAndSettle();
    expect(find.text('RITORNO'), findsOneWidget);

    final png = TicketScreenshot.takeShots('new').single.bytes;
    // Il tratto va da (640,400) a (840,400) nella finestra; la cornice parte
    // da (24,24). A metà tratto il pixel è rosso.
    final rgba = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(png);
      final image = (await codec.getNextFrame()).image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final i = ((400 - 24) * image.width + (740 - 24)) * 4;
      final pixel = data!.buffer.asUint8List().sublist(i, i + 4);
      image.dispose();
      return pixel;
    });
    // Il tratto ha il colore `error` del tema (qui il Material 3 di default).
    final ink = ThemeData().colorScheme.error;
    expect(rgba![0], closeTo((ink.r * 255).round(), 8), reason: 'rosso');
    expect(rgba[1], closeTo((ink.g * 255).round(), 8));
    expect(rgba[2], closeTo((ink.b * 255).round(), 8));
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('scatto senza cambiare pagina: la pagina non si perde il file',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final navKey = GlobalKey<NavigatorState>();
    final router = GoRouter(navigatorKey: navKey, routes: [
      GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('BACHECA')),
          routes: [
            GoRoute(path: 'new', builder: (_, __) => const _PendingPage()),
          ]),
    ]);
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: router,
      builder: (c, child) => TicketScreenshotHost(
          navigatorKey: navKey, router: router, child: child!),
    ));
    // Come la Bacheca: "Nuova scheda" si apre con push.
    router.push('/new');
    await tester.pumpAndSettle();
    expect(find.text('FILES 0'), findsOneWidget);

    TicketScreenshot.start(const TicketScreenshotTarget.draft(
        draftKey: 'pending', title: 'Nuova scheda', returnTo: '/new'));
    await tester.pump();
    await tester.tap(find.text(bt('screenshotTake')));
    await tester.runAsync(() async {
      for (var i = 0; i < 20; i++) {
        await tester.pump();
        await Future.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpAndSettle();

    expect(TicketScreenshot.session.value, isNull);
    expect(find.text('FILES 1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
}

/// Una pagina con file in attesa, come Nuova scheda: riprende le schermate
/// della sua bozza.
class _PendingPage extends StatefulWidget {
  const _PendingPage();

  @override
  State<_PendingPage> createState() => _PendingPageState();
}

class _PendingPageState extends State<_PendingPage> {
  int files = 0;

  void _pull() {
    final shots = TicketScreenshot.takeShots('pending');
    if (shots.isNotEmpty && mounted) setState(() => files += shots.length);
  }

  @override
  void initState() {
    super.initState();
    files = TicketScreenshot.takeShots('pending').length;
    TicketScreenshot.shotsChanged.addListener(_pull);
  }

  @override
  void dispose() {
    TicketScreenshot.shotsChanged.removeListener(_pull);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Text('FILES $files'));
}
