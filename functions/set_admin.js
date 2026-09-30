/**
 * Fa diventare admin della board un utente già registrato: custom claim
 * `admin: true` ed email segnata come verificata, le due cose che chiedono le
 * regole. L'utente deve rifare il login per ricevere il claim nuovo.
 *
 * USO
 *   BOARD_PROJECT_ID=il-tuo-progetto node functions/set_admin.js persona@example.com
 *   … --remove   toglie il claim
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
  if (!projectId) fail('BOARD_PROJECT_ID mancante.');
  if (!email || email.startsWith('--')) {
    fail('Uso: node functions/set_admin.js persona@example.com [--remove]');
  }

  const key = credentials();
  if (key && key.project_id !== projectId) {
    fail(`La chiave è del progetto "${key.project_id}", non di ${projectId}.`);
  }
  admin.initializeApp({
    projectId,
    ...(key ? {credential: admin.credential.cert(key)} : {}),
  });

  const user = await admin.auth().getUserByEmail(email).catch(() => null);
  if (!user) fail(`Nessun utente con email ${email}: crealo prima dalla console.`);

  const claims = {...(user.customClaims || {})};
  if (remove) delete claims.admin;
  else claims.admin = true;
  await admin.auth().setCustomUserClaims(user.uid, claims);
  if (!remove && !user.emailVerified) {
    await admin.auth().updateUser(user.uid, {emailVerified: true});
  }
  console.log(`✓ ${email} ${remove ? 'non è più' : 'è'} admin della board. ` +
    'Deve rifare il login.');
}

main().catch((e) => fail(e.message));
