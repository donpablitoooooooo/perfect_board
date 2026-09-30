# perfect_board

*[Read in English](README.md)*

Una board kanban per schede di lavoro (bug, richieste, domande) per app
Flutter su Firebase, pensata per lavorare **insieme a Claude Code**: qualcuno
apre una scheda da dentro l'app, allega schermate annotate del punto esatto, e
una sessione Claude la legge, fa domande sulla scheda, fa il lavoro e la
dichiara pronta.

È nata dentro un backoffice vero, dove è stata usata ogni giorno prima di
diventare questo pacchetto.

## Cosa c'è

- **Board** con le colonne *Nuove → Da chiarire → In lavorazione → Pronta per
  i test → Approvata* (più *Scartata*). Le card si trascinano fra le colonne;
  ognuna mostra da quanto è nella colonna (giorni di calendario: arancio da 7,
  rosso da 14) e la scadenza.
- **Dettaglio della scheda**: titolo e descrizione modificabili sul posto,
  etichette (BUG / App / Backoffice), scadenza, checklist, **collegamenti** a
  documenti dell'app (un cliente, un ordine…), allegati con anteprima
  (immagini, PDF, video, testo), commenti (dal più recente) con i loro
  allegati.
- **Schermate dell'app stessa**: una cornice spostabile e ridimensionabile
  resta sopra mentre navighi; trascinando dentro disegni in rosso, premi
  *Scatta* e il PNG va fra gli allegati. Funziona dalla scheda, da *Nuova
  scheda* e da un commento.
- **Export in Markdown** di una scheda, pronto da incollare in una sessione
  Claude (con i percorsi degli allegati, mai i link di download con token).
- **CLI** (`functions/board.js`) per elencare, leggere, commentare, fare
  domande, dichiarare pronto e scaricare gli allegati, da terminale o da una
  sessione Claude.
- **Comando per Claude Code** (`.claude/commands/segnalazioni.md`) che guida
  Claude sulle schede: leggi, proponi, chiedi, lavora, dichiara pronto — mai
  merge o deploy da solo.
- **Cloud Functions** che tengono i contatori di commenti e allegati e
  ripuliscono tutto quando una scheda si elimina, più le **regole di
  sicurezza** con i loro test.

Testi in **italiano e inglese**; le chiavi su Firestore non cambiano con la
lingua.

## Provarla

**Demo online**: <https://perfect-board-3ce55.web.app> (serve il login da
admin: è un'istanza vera, non una sandbox pubblica).

`example/` gira sugli emulatori Firebase o sul tuo progetto: vedi
[example/README.md](example/README.md).

## Requisiti

- Flutter ≥ 3.27, `go_router` per la navigazione.
- Firebase: Auth, Firestore, Storage, Cloud Functions (contatori e pulizia).
- Gli admin sono gli utenti con il custom claim `admin: true` ed email
  verificata.

## Installazione

```yaml
# pubspec.yaml
dependencies:
  perfect_board:
    git:
      url: https://github.com/donpablitoooooooo/perfect_board
      ref: main
```

## Integrazione

```dart
import 'package:perfect_board/perfect_board.dart';

// 1. All'avvio, dopo Firebase.initializeApp:
PerfectBoard.configure(
  currentUser: () => BoardUser(
    uid: FirebaseAuth.instance.currentUser?.uid ?? '',
    name: mioProfilo?.nome ?? 'Admin',
    email: FirebaseAuth.instance.currentUser?.email ?? '',
  ),
  locale: () => 'it',            // o la lingua scelta nell'app
  refSources: const [OrdiniRefSource()],   // facoltativo, vedi sotto
  basePath: '/tickets',
);

// 2. Rotte (anche dentro una ShellRoute):
final router = GoRouter(
  navigatorKey: rootNavigatorKey,
  routes: [
    ...perfectBoardRoutes(),
    // le tue rotte
  ],
);

// 3. Schermate: avvolgi tutta l'app.
MaterialApp.router(
  routerConfig: router,
  builder: (context, child) => TicketScreenshotHost(
    navigatorKey: rootNavigatorKey,
    router: router,
    child: child!,
  ),
);
```

Poi metti un collegamento a `/tickets` nel menu, solo per gli admin.

### Aspetto

La board usa solo componenti **Material 3** standard (AppBar, SearchBar,
Card, FilterChip, InputChip, DropdownMenu, CheckboxListTile, FilledButton,
SnackBar…) e prende colori, forme e tipografia dal tema dell'app: chiaro o
scuro, qualunque colore seme. Per cambiare ciò che il `ColorScheme` non
copre, aggiungi un `BoardTheme` alle estensioni del tema:

```dart
ThemeData(
  colorSchemeSeed: Colors.teal,
  extensions: const [
    BoardTheme(
      columnColor: Color(0xFFF1F4F8),   // fondo delle colonne
      cardColor: Colors.white,          // fondo delle card
      statusColors: {TicketStatus.nuova: Colors.indigo},
      labelColors: {TicketLabel.bug: Colors.deepOrange},
    ),
  ],
)
```

Ogni campo è facoltativo; quello che non metti segue il tema.

### Collegamenti ai tuoi documenti

Una scheda può puntare a documenti dell'app. Registra una sorgente per tipo:

```dart
class OrdiniRefSource extends BoardRefSource {
  const OrdiniRefSource();

  @override
  String get kind => 'order';          // salvato su Firestore: non rinominarlo
  @override
  String get label => 'Ordine';
  @override
  IconData get icon => Icons.receipt_long_outlined;
  @override
  String get searchHint => 'Numero ordine';
  @override
  String? get collection => 'Orders'; // scritta accanto all'id nell'export

  // Elenco iniziale, filtrato in memoria mentre si scrive.
  @override
  Future<List<BoardRefHit>> load() async {
    final snap = await FirebaseFirestore.instance
        .collection('Orders').orderBy('number', descending: true)
        .limit(30).get();
    return [for (final d in snap.docs)
      BoardRefHit(id: d.id, label: '#${d['number']}')];
  }

  // Facoltativo: ricerca sul server per le raccolte troppo grandi.
  @override
  Future<List<BoardRefHit>>? search(String text) => null;
}
```

I collegamenti di un tipo che l'app non registra (più) restano sulla scheda,
con un'icona generica.

## Configurazione Firebase

1. **Regole**: `firebase/firestore.rules` e `firebase/storage.rules`. Se hai
   già le tue regole, copia dentro i blocchi `Tickets` e `uploads/tickets`.
2. **Functions**: deploya `functions/` (o riesporta i quattro trigger di
   `functions/index.js` dalle tue functions). La regione di default è
   `europe-west1`; `BOARD_FUNCTIONS_REGION` per cambiarla, in base alla
   località del database.
3. **CORS** sul bucket, per l'anteprima di PDF e testo nel browser:
   `gsutil cors set firebase/cors.example.json gs://IL-TUO-BUCKET` (prima
   correggi le origini). Senza, l'anteprima ripiega su "apri in una nuova
   scheda".
4. **Test delle regole** (servono Java e la CLI di Firebase):
   `cd functions && npm install && npm run test:rules`.

## Admin

Gli admin sono gli utenti con il custom claim `admin: true` e l'email
verificata. `functions/set_admin.js` imposta entrambi per un utente esistente:

```bash
BOARD_PROJECT_ID=il-tuo-progetto node functions/set_admin.js tu@example.com
```

## CLI

```bash
cd functions && npm install
export BOARD_PROJECT_ID=il-tuo-progetto
export BOARD_SERVICE_ACCOUNT="$(base64 -i serviceAccountKey.json)"  # o il JSON
node board.js list
node board.js show <id>
node board.js comment <id> "testo"
node board.js ask <id> "domanda"      # sposta anche in "Da chiarire"
node board.js ready <id> --note="…"   # sposta in "Pronta per i test"
node board.js files <id>              # scarica gli allegati in ticket-files/<id>/
```

Una chiave di un progetto diverso da `BOARD_PROJECT_ID` viene rifiutata prima
di toccare qualunque dato.

## Lavorare con Claude Code

Copia `.claude/commands/segnalazioni.md` nella cartella `.claude/commands/` del
tuo repo: `/segnalazioni` elenca le schede, `/segnalazioni #a1b2c3` ne lavora
una. Oppure premi **Esporta** su una scheda e incolla il Markdown nella
sessione.

## Dati

- `Tickets/{id}`: `title`, `body`, `status` (`nuova`, `da_chiarire`,
  `in_carico`, `pronta`, `fatto`, `scartata`), `labels`, `refs`
  (`{kind, id, label}`) + `refKeys`, `checklist`, `dueAt`, `order`,
  `statusChangedAt`, `createdBy`, contatori.
- `Tickets/{id}/Comments`, `Tickets/{id}/Attachments` (metadati; i file su
  Storage sotto `uploads/tickets/{id}/`).

## Prossimi passi

- Pubblicazione su pub.dev.

## Licenza

[Apache 2.0](LICENSE).
