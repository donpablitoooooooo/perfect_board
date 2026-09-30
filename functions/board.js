/**
 * perfect_board — CLI di lavoro.
 *
 * È il ponte fra la board (collection Firestore `Tickets`) e chi lavora la
 * segnalazione da riga di comando (tipicamente una sessione Claude Code).
 * Scrive con l'Admin SDK, quindi salta le regole Firestore: teniamolo fuori
 * dal client.
 *
 * Il flusso è volutamente semi-manuale: la CLI legge, commenta e dichiara
 * pronto. Lo spostamento finale in "Approvata" lo fa un admin a mano dalla
 * board, dopo il deploy — così nessuna scheda risulta chiusa prima che il
 * codice sia davvero in produzione.
 *
 * USO
 *   node functions/board.js list [--status=nuova] [--label=bug] [--json]
 *   node functions/board.js show <id>
 *   node functions/board.js comment <id> "testo"
 *   node functions/board.js ask  <id> "domanda per l'admin"
 *   node functions/board.js ready <id> [--note="..."]
 *   node functions/board.js status <id> <stato>
 *   node functions/board.js files <id> [--out=cartella]
 *
 * <id> è l'id corto mostrato in board (le prime 6 lettere, con o senza '#'):
 * l'id Firestore intero funziona ugualmente.
 *
 * PROGETTO: `BOARD_PROJECT_ID` (obbligatoria) dice su quale progetto Firebase
 * lavorare; `BOARD_STORAGE_BUCKET` il bucket degli allegati, se non è quello
 * di default (`<progetto>.firebasestorage.app`).
 *
 * CREDENZIALI, nell'ordine in cui vengono cercate:
 *   1. `BOARD_SERVICE_ACCOUNT` — il JSON della service account per intero in
 *      una variabile d'ambiente, o lo stesso JSON in base64. Serve dove un
 *      file non si può mettere, per esempio in una sessione remota o in CI.
 *   2. `serviceAccountKey.json` accanto a questo file.
 *   3. `GOOGLE_APPLICATION_CREDENTIALS`, cioè le credenziali di default
 *      dell'ambiente.
 *
 * Qualunque sia la fonte, una chiave di un progetto diverso da
 * `BOARD_PROJECT_ID` viene rifiutata prima di toccare qualunque dato: con più
 * progetti sulla stessa macchina è facile passare la chiave sbagliata.
 */

const path = require('path');
const admin = require('firebase-admin');

const COLLECTION = 'Tickets';

/** L'unico progetto Firebase su cui questa CLI accetta di scrivere. */
const PROJECT_ID = process.env.BOARD_PROJECT_ID || '';

/** Il bucket degli allegati (`uploads/tickets/...`). */
const STORAGE_BUCKET =
  process.env.BOARD_STORAGE_BUCKET || `${PROJECT_ID}.firebasestorage.app`;

/** Etichette valide. Stesse di `TicketLabel.key` in lib/src/models/ticket.dart. */
const LABELS = ['bug', 'app', 'backoffice'];

/** Stati validi. Stessi valori di `TicketStatus.key` in lib/src/models/ticket.dart. */
const STATUSES = [
  'nuova',
  'da_chiarire',
  'in_carico',
  'pronta',
  'fatto',
  'scartata',
];

// ── Bootstrap ───────────────────────────────────────────────────────────────

function initFirebase() {
  if (!PROJECT_ID) {
    fail(
      'BOARD_PROJECT_ID mancante: dimmi su quale progetto Firebase lavorare ' +
        '(es. BOARD_PROJECT_ID=my-app-123 node functions/board.js list).',
    );
  }
  if (process.env.BOARD_SERVICE_ACCOUNT) {
    // Il JSON tale e quale, oppure codificato in base64: le variabili
    // d'ambiente delle sessioni cloud non digeriscono spazi e virgolette
    // (la chiave privata ne è piena), il base64 è una riga di soli
    // caratteri sicuri.
    const raw = process.env.BOARD_SERVICE_ACCOUNT.trim();
    const text = raw.startsWith('{') ?
      raw :
      Buffer.from(raw, 'base64').toString('utf8');
    let parsed;
    try {
      parsed = JSON.parse(text);
    } catch (e) {
      fail(
        'BOARD_SERVICE_ACCOUNT non contiene né JSON né JSON in base64 ' +
          'validi: ' + e.message,
      );
    }
    checkProject(parsed.project_id, 'BOARD_SERVICE_ACCOUNT');
    admin.initializeApp({
      credential: admin.credential.cert(parsed),
      projectId: PROJECT_ID,
      storageBucket: STORAGE_BUCKET,
    });
    return;
  }

  try {
    const serviceAccount = require('./serviceAccountKey.json');
    checkProject(serviceAccount.project_id, 'serviceAccountKey.json');
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      projectId: PROJECT_ID,
      storageBucket: STORAGE_BUCKET,
    });
    return;
  } catch (e) {
    if (e.code !== 'MODULE_NOT_FOUND') throw e;
  }

  const adc = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!adc) {
    fail(
      'Credenziali mancanti: serve BOARD_SERVICE_ACCOUNT, oppure ' +
        'serviceAccountKey.json in ' +
        path.dirname(__filename) +
        ', oppure GOOGLE_APPLICATION_CREDENTIALS nell\'ambiente.',
    );
  }
  let adcProject;
  try {
    adcProject = JSON.parse(require('fs').readFileSync(adc, 'utf8')).project_id;
  } catch (e) {
    // Credenziali utente (gcloud auth) senza project_id: vale il projectId
    // forzato qui sotto.
  }
  if (adcProject) checkProject(adcProject, 'GOOGLE_APPLICATION_CREDENTIALS');
  admin.initializeApp({projectId: PROJECT_ID, storageBucket: STORAGE_BUCKET});
}

/**
 * Rifiuta credenziali di un progetto diverso da BOARD_PROJECT_ID: una chiave
 * di un altro progetto finita qui per sbaglio scriverebbe sulla sua board.
 * @param {string|undefined} projectId project_id letto dalle credenziali
 * @param {string} source da dove vengono, per il messaggio di errore
 */
function checkProject(projectId, source) {
  if (projectId !== PROJECT_ID) {
    fail(
      `${source} è del progetto "${projectId}", non di ${PROJECT_ID}. ` +
        'Mi fermo prima di toccare dati di un altro progetto.',
    );
  }
}

function fail(message) {
  console.error(`✗ ${message}`);
  process.exit(1);
}

// ── Argomenti ───────────────────────────────────────────────────────────────

/**
 * Divide gli argomenti in posizionali e flag `--chiave=valore` / `--flag`.
 * @param {string[]} argv argomenti grezzi, senza node e nome script
 * @return {{positional: string[], flags: Object}}
 */
function parseArgs(argv) {
  const positional = [];
  const flags = {};
  for (const arg of argv) {
    if (!arg.startsWith('--')) {
      positional.push(arg);
      continue;
    }
    const [key, ...rest] = arg.slice(2).split('=');
    flags[key] = rest.length ? rest.join('=') : true;
  }
  return {positional, flags};
}

// ── Lettura ─────────────────────────────────────────────────────────────────

/**
 * Trova una segnalazione da id corto (6 caratteri, con o senza '#') o intero.
 * @param {string} rawId id come lo scrive l'utente
 * @return {Promise<FirebaseFirestore.DocumentSnapshot>}
 */
/**
 * Il percorso su Storage di un allegato. Quelli nuovi lo hanno in `path`;
 * i vecchi solo dentro il link di download (`.../o/<percorso>?alt=media`).
 * Il link intero non si stampa mai: il token che porta apre il file a
 * chiunque lo legga.
 * @param {Object} data i dati del documento in `Attachments`
 * @return {string} il percorso, o stringa vuota
 */
function attachmentPath(data) {
  if (data.path) return data.path;
  const match = /\/o\/([^?]+)/.exec(data.url || '');
  if (!match) return '';
  try {
    return decodeURIComponent(match[1]);
  } catch (e) {
    return '';
  }
}

async function findTicket(rawId) {
  if (!rawId) fail('Manca l\'id della segnalazione.');
  const id = rawId.replace(/^#/, '').trim();
  const db = admin.firestore();

  // Prima l'id intero: se esiste, è quello e basta.
  const direct = await db.collection(COLLECTION).doc(id).get();
  if (direct.exists) return direct;

  // Altrimenti prefisso: la collection è piccola, una scansione costa nulla e
  // evita di tenere in giro un campo id duplicato.
  const all = await db.collection(COLLECTION).get();
  const matches = all.docs.filter((d) => d.id.startsWith(id));
  if (matches.length === 0) fail(`Nessuna segnalazione con id "${rawId}".`);
  if (matches.length > 1) {
    fail(
      `"${rawId}" è ambiguo: ${matches.map((d) => d.id).join(', ')}. ` +
        'Usa l\'id intero.',
    );
  }
  return matches[0];
}

/**
 * Data e ora in ora italiana, `AAAA-MM-GG HH:MM`. Non in UTC: una scadenza
 * scelta nel backoffice è la mezzanotte italiana, che in UTC è ancora il
 * giorno prima (27/09 diventava "scade 2026-09-26").
 * @param {FirebaseFirestore.Timestamp} value
 * @return {string}
 */
function fmtDate(value) {
  if (!value || typeof value.toDate !== 'function') return '—';
  // 'sv-SE' è il formato ISO leggibile: "2026-09-27 00:00".
  return value
    .toDate()
    .toLocaleString('sv-SE', {timeZone: 'Europe/Rome'})
    .slice(0, 16);
}

function summarize(doc) {
  const d = doc.data() || {};
  return {
    id: doc.id.slice(0, 6),
    fullId: doc.id,
    status: d.status || 'nuova',
    labels: Array.isArray(d.labels) ? d.labels : [],
    refs: Array.isArray(d.refs)
      ? d.refs.map((r) => `${r.kind || '?'}:${r.label || r.id || '?'}`)
      : [],
    title: d.title || '',
    from: (d.createdBy && d.createdBy.name) || '—',
    dueAt: d.dueAt ? fmtDate(d.dueAt).slice(0, 10) : null,
    comments: d.commentCount || 0,
    attachments: d.attachmentCount || 0,
    createdAt: fmtDate(d.createdAt),
  };
}

// ── Comandi ─────────────────────────────────────────────────────────────────

async function cmdList(flags) {
  let query = admin.firestore().collection(COLLECTION);
  if (flags.status) {
    if (!STATUSES.includes(flags.status)) {
      fail(`Stato "${flags.status}" sconosciuto. Validi: ${STATUSES.join(', ')}`);
    }
    query = query.where('status', '==', flags.status);
  }
  const snap = await query.get();

  // Ordiniamo lato client: con il filtro su status, ordinare su createdAt
  // richiederebbe un indice composito in più solo per la CLI.
  let rows = snap.docs
    .map((doc) => summarize(doc))
    .sort((a, b) => (a.createdAt < b.createdAt ? 1 : -1));

  if (flags.label) {
    if (!LABELS.includes(flags.label)) {
      fail(
        `Etichetta "${flags.label}" sconosciuta. ` +
          `Valide: ${LABELS.join(', ')}`,
      );
    }
    // Filtrato qui e non nella query: evita l'indice composito status+labels.
    rows = rows.filter((r) => r.labels.includes(flags.label));
  }

  if (flags.json) {
    console.log(JSON.stringify(rows, null, 2));
    return;
  }

  if (rows.length === 0) {
    console.log('Nessuna segnalazione.');
    return;
  }

  for (const status of STATUSES) {
    const inStatus = rows.filter((r) => r.status === status);
    if (inStatus.length === 0) continue;
    console.log(`\n${status.toUpperCase()} (${inStatus.length})`);
    for (const r of inStatus) {
      const labels = r.labels.length ? `  {${r.labels.join(' ')}}` : '';
      const extra = [
        r.dueAt ? `scade ${r.dueAt}` : null,
        r.comments ? `${r.comments} commenti` : null,
      ]
        .filter(Boolean)
        .join(' · ');
      console.log(`  #${r.id}  ${r.title}${labels}`);
      console.log(
        `         ${r.from} · ${r.createdAt}${extra ? '  ' + extra : ''}`,
      );
      if (r.refs.length) console.log(`         ↳ ${r.refs.join('  ')}`);
    }
  }
  console.log('');
}

async function cmdShow(positional, flags) {
  const doc = await findTicket(positional[0]);
  const d = doc.data() || {};
  const comments = await doc.ref
    .collection('Comments')
    .orderBy('createdAt')
    .get();
  const attachments = await doc.ref.collection('Attachments').get();

  if (flags.json) {
    console.log(
      JSON.stringify(
        {
          ...summarize(doc),
          body: d.body || '',
          checklist: Array.isArray(d.checklist) ? d.checklist : [],
          comments: comments.docs.map((c) => ({
            id: c.id,
            author: (c.data().author || {}).name || '?',
            text: c.data().text,
            at: fmtDate(c.data().createdAt),
          })),
          attachments: attachments.docs.map((a) => ({
            name: a.data().name,
            path: attachmentPath(a.data()),
            commentId: a.data().commentId || null,
          })),
        },
        null,
        2,
      ),
    );
    return;
  }

  const from = d.createdBy || {};
  console.log(`\n#${doc.id.slice(0, 6)}  ${d.title || ''}`);
  console.log(`stato    ${d.status || 'nuova'}`);
  console.log(
    `etichette ${
      Array.isArray(d.labels) && d.labels.length ? d.labels.join(', ') : '—'
    }`,
  );
  console.log(
    `collegati ${
      Array.isArray(d.refs) && d.refs.length
        ? d.refs.map((r) => `${r.kind}:${r.label || r.id}`).join(', ')
        : '—'
    }`,
  );
  console.log(`scadenza ${d.dueAt ? fmtDate(d.dueAt).slice(0, 10) : '—'}`);
  console.log(`da       ${from.name || '—'} <${from.email || '—'}> (${from.role || '—'})`);
  console.log(`creata   ${fmtDate(d.createdAt)}`);
  console.log(`\n${d.body || '—'}\n`);

  const checklist = Array.isArray(d.checklist) ? d.checklist : [];
  if (checklist.length) {
    console.log('— checklist —');
    for (const item of checklist) {
      console.log(`  [${item.done ? 'x' : ' '}] ${item.text}`);
    }
    console.log('');
  }

  if (!attachments.empty) {
    console.log('— allegati —');
    for (const a of attachments.docs) {
      console.log(`  ${a.data().name}  ${attachmentPath(a.data())}`);
    }
    console.log(`  (per scaricarli: node functions/board.js files ${doc.id.slice(0, 6)})`);
    console.log('');
  }

  // I commenti sono la conversazione con chi ha aperto la scheda: è lì che
  // di solito sta la risposta che serve.
  if (!comments.empty) {
    console.log('— commenti —');
    for (const c of comments.docs) {
      const cd = c.data();
      console.log(`\n[${(cd.author || {}).name || '?'}] ${fmtDate(cd.createdAt)}`);
      if (cd.text) console.log(cd.text);
      // I file caricati col commento: il link completo è fra gli allegati.
      const files = attachments.docs.filter((a) => a.data().commentId === c.id);
      if (files.length) {
        console.log(`(allegati: ${files.map((a) => a.data().name).join(', ')})`);
      }
    }
    console.log('');
  }
}

/**
 * Un commento nel canale comune: lo vede chi ha aperto la segnalazione la
 * prossima volta che apre la board. Da usare per rispondere a una domanda,
 * non per raccontare la lavorazione — quella è `note`.
 * @param {string[]} positional id e testo
 * @return {Promise<void>}
 */
async function cmdComment(positional) {
  const doc = await findTicket(positional[0]);
  const text = positional.slice(1).join(' ').trim();
  if (!text) fail('Manca il testo del commento.');
  await addComment(doc.ref, text);
  console.log(`✓ commento pubblicato su #${doc.id.slice(0, 6)}`);
}

/**
 * Scrive un commento sulla scheda. È l'unico canale: le note private non
 * esistono più, quello che Claude ha da dire lo leggono tutti.
 * @param {FirebaseFirestore.DocumentReference} ref documento della scheda
 * @param {string} text testo
 * @return {Promise<void>}
 */
async function addComment(ref, text) {
  await ref.collection('Comments').add({
    author: {uid: 'claude', name: 'Claude'},
    text: text,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

/**
 * `statusChangedAt` solo se la scheda cambia davvero colonna: è il "da
 * quanto" che la board mostra sulla card, e un secondo `ask` sulla stessa
 * scheda non deve azzerarlo.
 * @param {FirebaseFirestore.DocumentSnapshot} doc la scheda com'è ora
 * @param {string} next lo stato in cui va
 * @return {Object} il campo da aggiungere all'update, o niente
 */
function statusStamp(doc, next) {
  if ((doc.data() || {}).status === next) return {};
  return {statusChangedAt: admin.firestore.FieldValue.serverTimestamp()};
}

async function cmdAsk(positional) {
  const doc = await findTicket(positional[0]);
  const text = positional.slice(1).join(' ').trim();
  if (!text) fail('Manca la domanda.');
  await doc.ref.update({
    status: 'da_chiarire',
    ...statusStamp(doc, 'da_chiarire'),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await addComment(doc.ref, text);
  console.log(`✓ #${doc.id.slice(0, 6)} → da_chiarire`);
}

async function cmdReady(positional, flags) {
  const doc = await findTicket(positional[0]);
  await doc.ref.update({
    status: 'pronta',
    ...statusStamp(doc, 'pronta'),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  if (flags.note && flags.note !== true) await addComment(doc.ref, flags.note);
  console.log(`✓ #${doc.id.slice(0, 6)} → pronta`);
}

async function cmdStatus(positional) {
  const doc = await findTicket(positional[0]);
  const status = positional[1];
  if (!STATUSES.includes(status)) {
    fail(`Stato "${status}" sconosciuto. Validi: ${STATUSES.join(', ')}`);
  }
  if (status === 'fatto') {
    fail(
      'In "fatto" ci va l\'admin dalla board, dopo il deploy. ' +
        'Da qui usa "ready".',
    );
  }
  await doc.ref.update({
    status: status,
    ...statusStamp(doc, status),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  console.log(`✓ #${doc.id.slice(0, 6)} → ${status}`);
}

/**
 * Scarica gli allegati di una scheda in una cartella locale, con la chiave di
 * servizio: è il modo di guardarli senza mettere in giro i link pubblici.
 * Di default in `ticket-files/<id>/` (ignorata da git), accanto a dove lanci
 * il comando.
 * @param {string[]} positional l'id della scheda
 * @param {Object} flags `--out=cartella` per scegliere dove
 * @return {Promise<void>}
 */
async function cmdFiles(positional, flags) {
  const fs = require('fs');
  const doc = await findTicket(positional[0]);
  const shortId = doc.id.slice(0, 6);
  const attachments = await doc.ref
    .collection('Attachments')
    .orderBy('createdAt')
    .get();
  if (attachments.empty) {
    console.log(`#${shortId}: nessun allegato.`);
    return;
  }

  const out = path.resolve(
    flags.out && flags.out !== true ?
      flags.out :
      path.join(process.cwd(), 'ticket-files', shortId),
  );
  fs.mkdirSync(out, {recursive: true});

  const bucket = admin.storage().bucket();
  let n = 0;
  for (const a of attachments.docs) {
    const data = a.data();
    const source = attachmentPath(data);
    if (!source) {
      console.log(`  ✗ ${data.name}: percorso su Storage sconosciuto`);
      continue;
    }
    // Il numero davanti tiene l'ordine e separa due file con lo stesso nome.
    n += 1;
    const safe = String(data.name || path.basename(source))
      .replace(/[\\/:*?"<>|]/g, '_');
    const target = path.join(out, `${String(n).padStart(2, '0')}_${safe}`);
    try {
      await bucket.file(source).download({destination: target});
      console.log(`  ✓ ${target}`);
    } catch (e) {
      console.log(`  ✗ ${data.name}: ${e.message}`);
    }
  }
}

function usage() {
  console.log(
    [
      'perfect_board — CLI',
      '',
      '  node functions/board.js list [--status=<stato>] [--label=<etichetta>] [--json]',
      '  node functions/board.js show <id> [--json]',
      '  node functions/board.js comment <id> "testo"',
      '  node functions/board.js ask <id> "domanda"',
      '  node functions/board.js ready <id> [--note="..."]',
      '  node functions/board.js status <id> <stato>',
      '  node functions/board.js files <id> [--out=cartella]',
      '',
      `Stati:     ${STATUSES.join(', ')}`,
      `Etichette: ${LABELS.join(', ')}`,
      '"fatto" lo mette l\'admin dalla bacheca, dopo il deploy.',
    ].join('\n'),
  );
}

// ── Entry point ─────────────────────────────────────────────────────────────

async function main() {
  const {positional, flags} = parseArgs(process.argv.slice(2));
  const command = positional.shift();

  if (!command || command === 'help' || flags.help) {
    usage();
    return;
  }

  initFirebase();

  switch (command) {
    case 'list':
      return cmdList(flags);
    case 'show':
      return cmdShow(positional, flags);

    case 'comment':
      return cmdComment(positional);
    case 'ask':
      return cmdAsk(positional);
    case 'ready':
      return cmdReady(positional, flags);
    case 'status':
      return cmdStatus(positional);
    case 'files':
      return cmdFiles(positional, flags);

    default:
      usage();
      fail(`Comando "${command}" sconosciuto.`);
  }
}

main()
  .then(() => process.exit(0))
  .catch((e) => fail(e.message || String(e)));
