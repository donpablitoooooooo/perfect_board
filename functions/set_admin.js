/**
 * Fa diventare admin della board un utente già registrato: custom claim
 * `admin: true` ed email segnata come verificata, le due cose che chiedono le
 * regole. L'utente deve rifare il login per ricevere il claim nuovo.
 *
 * USO
 *   BOARD_PROJECT_ID=il-tuo-progetto node functions/set_admin.js persona@example.com
 *   … --demo     account dimostrativo: admin, ma senza file e senza
 *                eliminare schede (claim `demo`, vedi firestore.rules)
 *   … --remove   toglie i claim
 *
 * Credenziali come board.js: BOARD_SERVICE_ACCOUNT (JSON o base64),
 * serviceAccountKey.json accanto a questo file, o
 * GOOGLE_APPLICATION_CREDENTIALS. Una chiave di un altro progetto è rifiutata.
 */

const admin = require('firebase-admin');

function fail(message) {
  console.error(`✗ ${message}`);
  process.exit(1);
}

function credentials() {
  const raw = (process.env.BOARD_SERVICE_ACCOUNT || '').trim();
  if (raw) {
    return JSON.parse(
      raw.startsWith('{') ? raw : Buffer.from(raw, 'base64').toString('utf8'),
    );
  }
  try {
    return require('./serviceAccountKey.json');
  } catch (e) {
    if (e.code !== 'MODULE_NOT_FOUND') throw e;
    return null;
  }
}

async function main() {
  const projectId = process.env.BOARD_PROJECT_ID || '';
  const email = process.argv[2];
  const remove = process.argv.includes('--remove');
  const demo = process.argv.includes('--demo');
  if (!projectId) fail('BOARD_PROJECT_ID mancante.');
  if (!email || email.startsWith('--')) {
    fail('Uso: node functions/set_admin.js persona@example.com [--remove]');
  }

  const key = credentials();
  if (!key && !process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    fail('Nessuna chiave: salva la chiave del service account come ' +
      'functions/serviceAccountKey.json (console Firebase → Impostazioni ' +
      'progetto → Account di servizio → Genera nuova chiave privata), ' +
      'oppure usa BOARD_SERVICE_ACCOUNT o GOOGLE_APPLICATION_CREDENTIALS.');
  }
  if (key && key.project_id !== projectId) {
    fail(`La chiave è del progetto "${key.project_id}", non di ${projectId}.`);
  }
  admin.initializeApp({
    projectId,
    ...(key ? {credential: admin.credential.cert(key)} : {}),
  });

  // Solo "utente non trovato" vuol dire che manca: gli altri errori
  // (credenziali, rete) vanno mostrati per quello che sono.
  const user = await admin.auth().getUserByEmail(email).catch((e) => {
    if (e.code === 'auth/user-not-found') return null;
    throw e;
  });
  if (!user) fail(`Nessun utente con email ${email}: crealo prima dalla console.`);

  const claims = {...(user.customClaims || {})};
  if (remove) {
    delete claims.admin;
    delete claims.demo;
  } else {
    claims.admin = true;
    if (demo) claims.demo = true;
    else delete claims.demo;
  }
  await admin.auth().setCustomUserClaims(user.uid, claims);
  if (!remove && !user.emailVerified) {
    await admin.auth().updateUser(user.uid, {emailVerified: true});
  }
  const role = remove ? 'non è più admin' : demo ? 'è l\'account demo' : 'è admin';
  console.log(`✓ ${email} ${role} della board. Deve rifare il login.`);
}

main().catch((e) => fail(e.message));
