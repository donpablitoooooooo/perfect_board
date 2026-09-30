/**
 * Pulizia delle board demo.
 *
 * Chi prova la board con "Try the demo" entra con un login anonimo e lavora
 * in una board privata: le sue schede portano `sandbox` = il suo uid (vedi
 * firestore.rules). Ogni notte si smontano le board demo più vecchie di un
 * giorno — schede, commenti e tutto quello che c'è sotto — e si tolgono gli
 * utenti anonimi che non entrano da un giorno. Le schede vere non hanno
 * `sandbox` e qui non vengono nemmeno lette.
 *
 * `cleanDemo` è separata dal trigger per poterla provare sull'emulatore.
 */

const {onSchedule} = require('firebase-functions/v2/scheduler');
const {logger} = require('firebase-functions/v2');
const admin = require('firebase-admin');

const REGION = process.env.BOARD_FUNCTIONS_REGION || 'europe-west1';
const MAX_AGE_MS = 24 * 60 * 60 * 1000;

async function cleanDemo(now = Date.now()) {
  const cutoff = now - MAX_AGE_MS;
  const db = admin.firestore();

  // Tutte le schede demo (`sandbox` non vuoto), poi l'età in memoria: sono
  // poche, e così non serve un indice composto.
  const snap = await db.collection('Tickets').where('sandbox', '>', '').get();
  let tickets = 0;
  for (const d of snap.docs) {
    const created = d.get('createdAt');
    const at = created && created.toMillis ? created.toMillis() : 0;
    if (at > cutoff) continue;
    // Anche le sottocollection: Firestore non cancella a cascata.
    await db.recursiveDelete(d.ref);
    tickets++;
  }

  let users = 0;
  let pageToken;
  do {
    const page = await admin.auth().listUsers(1000, pageToken);
    const stale = page.users
      .filter((u) => u.providerData.length === 0 && !u.email)
      .filter((u) => {
        const last = Date.parse(
          u.metadata.lastRefreshTime || u.metadata.lastSignInTime ||
            u.metadata.creationTime,
        );
        return !(last > cutoff);
      })
      .map((u) => u.uid);
    if (stale.length) {
      await admin.auth().deleteUsers(stale);
      users += stale.length;
    }
    pageToken = page.pageToken;
  } while (pageToken);

  return {tickets, users};
}

exports.cleanDemo = cleanDemo;

exports.demoCleanup = onSchedule(
  {schedule: 'every day 04:00', timeZone: 'Europe/Rome', region: REGION},
  async () => {
    const {tickets, users} = await cleanDemo();
    logger.info(`Demo: ${tickets} schede e ${users} utenti anonimi tolti`);
  },
);
