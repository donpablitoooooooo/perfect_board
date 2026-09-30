# perfect_board

*[Leggi in italiano](README.it.md)*

A kanban board for work cards (bugs, requests, questions) for Flutter apps on
Firebase, designed to be worked **together with Claude Code**: someone opens a
card from inside the app, attaches annotated screenshots of the exact spot, and
a Claude session reads it, asks questions on the card, does the work and marks
it ready.

It was born inside a real back office and has been used there every day before
being extracted into this package.

## What you get

- **Board** with columns *New → Needs info → In progress → Ready for testing →
  Approved* (plus *Discarded*). Drag cards between columns; each card shows how
  long it has been in its column (calendar days: orange after 7, red after 14)
  and its due date.
- **Card detail**: title and description editable in place, labels (BUG / App /
  Backoffice), due date, checklist, **links** to documents of your app (a
  customer, an order…), attachments with preview (images, PDF, video, text),
  comments (newest first) with their own attachments.
- **Screenshots of the app itself**: a movable, resizable frame stays on top
  while you navigate; drag inside it to draw in red, press *Capture* and the PNG
  is attached to the card. Works from the card, from *New card* and from a
  comment.
- **Markdown export** of a card, ready to paste into a Claude session (paths of
  attachments, never download links with tokens).
- **CLI** (`functions/board.js`) to list, read, comment, ask questions, mark as
  ready and download attachments, from a terminal or a Claude session.
- **Claude Code command** (`.claude/commands/segnalazioni.md`) that walks
  Claude through the cards: read, propose, ask, work, mark ready — never merge
  or deploy on its own.
- **Cloud Functions** keeping comment/attachment counters and cleaning up
  everything when a card is deleted, plus **security rules** and their tests.

Texts are in **Italian and English**; Firestore keys never change with the
language.

## Try it

**Live demo**: <https://perfect-board-3ce55.web.app> (admin login required:
it is a real instance, not a public sandbox).

`example/` runs on the Firebase emulators or on your project: see
[example/README.md](example/README.md).

## Requirements

- Flutter ≥ 3.27, `go_router` for navigation.
- Firebase: Auth, Firestore, Storage, Cloud Functions (for counters/cleanup).
- Admins are users with the custom claim `admin: true` and a verified email.

## Install

```yaml
# pubspec.yaml
dependencies:
  perfect_board: ^0.1.0
```

or `flutter pub add perfect_board`.

## Integrate

```dart
import 'package:perfect_board/perfect_board.dart';

// 1. At startup, after Firebase.initializeApp:
PerfectBoard.configure(
  currentUser: () => BoardUser(
    uid: FirebaseAuth.instance.currentUser?.uid ?? '',
    name: myProfile?.name ?? 'Admin',
    email: FirebaseAuth.instance.currentUser?.email ?? '',
  ),
  locale: () => 'en',            // or read your app's language
  refSources: const [OrdersRefSource()],   // optional, see below
  basePath: '/tickets',
);

// 2. Routes (also inside a ShellRoute):
final router = GoRouter(
  navigatorKey: rootNavigatorKey,
  routes: [
    ...perfectBoardRoutes(),
    // your routes
  ],
);

// 3. Screenshots: wrap the whole app.
MaterialApp.router(
  routerConfig: router,
  builder: (context, child) => TicketScreenshotHost(
    navigatorKey: rootNavigatorKey,
    router: router,
    child: child!,
  ),
);
```

Then link `/tickets` from your menu, for admins only.

### Look and feel

The board uses only standard **Material 3** components (AppBar, SearchBar,
Card, FilterChip, InputChip, DropdownMenu, CheckboxListTile, FilledButton,
SnackBar…) and takes colors, shapes and typography from your app's theme:
light or dark, any seed color. To change what the `ColorScheme` does not
cover, add a `BoardTheme` to your theme's extensions:

```dart
ThemeData(
  colorSchemeSeed: Colors.teal,
  extensions: const [
    BoardTheme(
      columnColor: Color(0xFFF1F4F8),   // column background
      cardColor: Colors.white,          // card background
      statusColors: {TicketStatus.nuova: Colors.indigo},
      labelColors: {TicketLabel.bug: Colors.deepOrange},
    ),
  ],
)
```

Every field is optional; what you leave out follows the theme.

### Links to your documents

A card can point to documents of your app. Register one source per kind:

```dart
class OrdersRefSource extends BoardRefSource {
  const OrdersRefSource();

  @override
  String get kind => 'order';          // saved on Firestore: never rename
  @override
  String get label => 'Order';
  @override
  IconData get icon => Icons.receipt_long_outlined;
  @override
  String get searchHint => 'Order number';
  @override
  String? get collection => 'Orders'; // written next to the id in exports

  // Initial list, filtered in memory while typing.
  @override
  Future<List<BoardRefHit>> load() async {
    final snap = await FirebaseFirestore.instance
        .collection('Orders').orderBy('number', descending: true)
        .limit(30).get();
    return [for (final d in snap.docs)
      BoardRefHit(id: d.id, label: '#${d['number']}')];
  }

  // Optional: search on the server for collections too big to load.
  @override
  Future<List<BoardRefHit>>? search(String text) => null;
}
```

Links of a kind the app does not register (any more) stay on the card with a
generic icon.

## Firebase setup

1. **Rules**: `firebase/firestore.rules` and `firebase/storage.rules`. If you
   already have rules, copy the `Tickets` block and `uploads/tickets` block into
   yours.
2. **Functions**: deploy `functions/` (or re-export the four triggers from
   `functions/index.js` in your own functions). Region defaults to
   `europe-west1`; set `BOARD_FUNCTIONS_REGION` to match your database.
3. **CORS** on the bucket, for PDF/text previews in the browser:
   `gsutil cors set firebase/cors.example.json gs://YOUR-BUCKET` (edit origins
   first). Without it, previews fall back to "open in a new tab".
4. **Rule tests** (Java and the Firebase CLI needed):
   `cd functions && npm install && npm run test:rules`.

## Admins

Admins are users with the custom claim `admin: true` and a verified email.
`functions/set_admin.js` sets both for an existing user:

```bash
BOARD_PROJECT_ID=your-project-id node functions/set_admin.js you@example.com
```

## CLI

```bash
cd functions && npm install
export BOARD_PROJECT_ID=your-project-id
export BOARD_SERVICE_ACCOUNT="$(base64 -i serviceAccountKey.json)"  # or JSON
node board.js list
node board.js show <id>
node board.js comment <id> "text"
node board.js ask <id> "question"     # also moves the card to "Needs info"
node board.js ready <id> --note="…"   # moves it to "Ready for testing"
node board.js files <id>              # downloads attachments to ticket-files/<id>/
```

A key of a project other than `BOARD_PROJECT_ID` is refused before touching
any data.

## Working with Claude Code

Copy `.claude/commands/segnalazioni.md` into your repo's `.claude/commands/`:
`/segnalazioni` lists the cards, `/segnalazioni #a1b2c3` works one. Or press
**Export** on a card and paste the Markdown into the session.

## Data model

- `Tickets/{id}`: `title`, `body`, `status` (`nuova`, `da_chiarire`,
  `in_carico`, `pronta`, `fatto`, `scartata`), `labels`, `refs`
  (`{kind, id, label}`) + `refKeys`, `checklist`, `dueAt`, `order`,
  `statusChangedAt`, `createdBy`, counters.
- `Tickets/{id}/Comments`, `Tickets/{id}/Attachments` (metadata; files on
  Storage under `uploads/tickets/{id}/`).

Status keys are Italian for historical reasons: they are data, not text.

## License

[Apache 2.0](LICENSE).
