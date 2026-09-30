import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:perfect_board/perfect_board.dart';

/// Esempio minimo: emulatori Firebase, un utente admin finto, la board e una
/// sorgente di collegamenti fatta a mano.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Con gli emulatori bastano valori finti; il projectId "demo-" dice agli
  // emulatori che non esiste un progetto vero dietro.
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'demo-key',
      appId: '1:0:web:0',
      messagingSenderId: '0',
      projectId: 'demo-perfect-board',
      storageBucket: 'demo-perfect-board.appspot.com',
    ),
  );
  await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
  FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
  await FirebaseStorage.instance.useStorageEmulator('localhost', 9199);

  // L'utente lo crea `seed_admin.sh` sull'emulatore: email verificata e
  // claim `admin`, come chiedono le regole della board.
  await FirebaseAuth.instance.signInWithEmailAndPassword(
    email: 'admin@example.com',
    password: 'password',
  );

  PerfectBoard.configure(
    currentUser: () => BoardUser(
      uid: FirebaseAuth.instance.currentUser?.uid ?? '',
      name: 'Demo Admin',
      email: 'admin@example.com',
    ),
    locale: () => 'en',
    refSources: const [_PagesRefSource()],
  );

  runApp(const ExampleApp());
}

final _navigatorKey = GlobalKey<NavigatorState>();

final _router = GoRouter(
  navigatorKey: _navigatorKey,
  initialLocation: '/tickets',
  routes: perfectBoardRoutes(),
);

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'perfect_board',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B4183),
          brightness: Brightness.dark,
        ),
      ),
      routerConfig: _router,
      builder: (context, child) => TicketScreenshotHost(
        navigatorKey: _navigatorKey,
        router: _router,
        child: child!,
      ),
    );
  }
}

/// Una sorgente di collegamenti senza database: le "pagine" di un'app
/// immaginaria. Nella tua app qui leggeresti clienti, ordini, prodotti…
class _PagesRefSource extends BoardRefSource {
  const _PagesRefSource();

  @override
  String get kind => 'page';

  @override
  String get label => 'Page';

  @override
  IconData get icon => Icons.web_outlined;

  @override
  String get searchHint => 'Page name';

  @override
  Future<List<BoardRefHit>> load() async => const [
        BoardRefHit(id: 'home', label: 'Home'),
        BoardRefHit(id: 'checkout', label: 'Checkout'),
        BoardRefHit(id: 'settings', label: 'Settings'),
      ];
}
