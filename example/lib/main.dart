import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:perfect_board/perfect_board.dart';

/// Esempio minimo di perfect_board.
///
/// Di default gira sugli **emulatori** (vedi README). Per un progetto vero si
/// passano i valori della "configurazione web" della console Firebase con
/// `--dart-define` (niente chiavi nel repo):
///
///   flutter run -d chrome \
///     --dart-define=FIREBASE_PROJECT_ID=... \
///     --dart-define=FIREBASE_API_KEY=... \
///     --dart-define=FIREBASE_APP_ID=... \
///     --dart-define=FIREBASE_SENDER_ID=... \
///     --dart-define=FIREBASE_AUTH_DOMAIN=... \
///     --dart-define=FIREBASE_STORAGE_BUCKET=...
const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

/// Account demo facoltativo (vedi README): se c'è, il login mostra un
/// bottone per entrare con quello.
const _demoEmail = String.fromEnvironment('DEMO_EMAIL');
const _demoPassword = String.fromEnvironment('DEMO_PASSWORD');

/// Il claim `demo` dell'utente di adesso, letto a ogni nuovo token.
bool _isDemo = false;
const _useEmulators = _projectId == '';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: _useEmulators
        // Con gli emulatori bastano valori finti; il projectId "demo-" dice
        // agli emulatori che non c'è un progetto vero dietro.
        ? const FirebaseOptions(
            apiKey: 'demo-key',
            appId: '1:0:web:0',
            messagingSenderId: '0',
            projectId: 'demo-perfect-board',
            storageBucket: 'demo-perfect-board.appspot.com',
          )
        : const FirebaseOptions(
            apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
            appId: String.fromEnvironment('FIREBASE_APP_ID'),
            messagingSenderId: String.fromEnvironment('FIREBASE_SENDER_ID'),
            projectId: _projectId,
            authDomain: String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
            storageBucket: String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
          ),
  );
  if (_useEmulators) {
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
    await FirebaseStorage.instance.useStorageEmulator('localhost', 9199);
    // L'utente lo crea `seed_admin.sh` sull'emulatore: email verificata e
    // claim `admin`, come chiedono le regole della board.
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: 'admin@example.com',
      password: 'password',
    );
  }

  FirebaseAuth.instance.idTokenChanges().listen((user) async {
    final token = await user?.getIdTokenResult();
    _isDemo = token?.claims?['demo'] == true;
  });

  PerfectBoard.configure(
    currentUser: () {
      final user = FirebaseAuth.instance.currentUser;
      return BoardUser(
        uid: user?.uid ?? '',
        name: user?.displayName ?? user?.email ?? 'Admin',
        email: user?.email ?? '',
      );
    },
    locale: () => 'en',
    refSources: const [_PagesRefSource()],
    demo: () => _isDemo,
  );

  runApp(const ExampleApp());
}

final _navigatorKey = GlobalKey<NavigatorState>();

final _router = GoRouter(
  navigatorKey: _navigatorKey,
  initialLocation: '/tickets',
  refreshListenable: _AuthChanges(),
  redirect: (context, state) {
    final signedIn = FirebaseAuth.instance.currentUser != null;
    if (!signedIn && state.matchedLocation != '/login') return '/login';
    if (signedIn && state.matchedLocation == '/login') return '/tickets';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const _LoginPage()),
    ...perfectBoardRoutes(),
  ],
);

/// Riporta il router a controllare il login quando cambia l'utente.
class _AuthChanges extends ChangeNotifier {
  _AuthChanges() {
    FirebaseAuth.instance.authStateChanges().listen((_) => notifyListeners());
  }
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'perfect_board',
      // La board prende colori e forme dal tema Material 3 dell'app: prova
      // a cambiare il colore seme o a passare al tema scuro del sistema.
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.dark,
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

/// Login con email e password. L'utente deve avere l'email verificata e il
/// claim `admin` (vedi `functions/set_admin.js`), o le regole non lo fanno
/// leggere.
class _LoginPage extends StatefulWidget {
  const _LoginPage();

  @override
  State<_LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<_LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;

  Future<void> _signIn({String? email, String? password}) async {
    setState(() => _error = null);
    try {
      final credential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email ?? _email.text.trim(),
        password: password ?? _password.text,
      );
      // Il claim prima di entrare nella board, non un attimo dopo.
      final token = await credential.user?.getIdTokenResult();
      _isDemo = token?.claims?['demo'] == true;
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? e.code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
                onSubmitted: (_) => _signIn(),
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: _signIn, child: const Text('Sign in')),
              if (_demoEmail != '') ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () =>
                      _signIn(email: _demoEmail, password: _demoPassword),
                  child: const Text('Try the demo'),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ],
            ],
          ),
        ),
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
