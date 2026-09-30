/**
 * Verifica delle regole Firestore della board.
 *
 * Il punto che va tenuto fermo: le schede le vedono e le muovono tutti gli
 * admin, e nessun altro. Dentro, due cose non si riscrivono nemmeno volendo:
 * un commento e un allegato già caricato. È una regola, non una scelta della
 * UI — e questo file è ciò che lo dimostra.
 *
 * USO
 *   cd functions && npm run test:rules
 *
 * Gira dentro l'emulatore Firestore (serve Java). Non tocca il progetto vero.
 */

const {readFileSync} = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const {
  doc,
  getDoc,
  setDoc,
  addDoc,
  collection,
  deleteDoc,
  getDocs,
  query,
  where,
} = require('firebase/firestore');

let passed = 0;
let failed = 0;

async function check(name, promise) {
  try {
    await promise;
    console.log(`  ok   ${name}`);
    passed++;
  } catch (e) {
    console.log(`  FAIL ${name}\n       ${e.message}`);
    failed++;
  }
}

/** Host e porta dell'emulatore, come li passa `firebase emulators:exec`. */
function emulator() {
  const value = process.env.FIRESTORE_EMULATOR_HOST;
  if (!value) {
    console.error(
      '✗ Emulatore non attivo. Lancia con: npm run test:rules',
    );
    process.exit(1);
  }
  const [host, port] = value.split(':');
  return {host: host, port: Number(port)};
}

async function main() {
  const {host, port} = emulator();
  const env = await initializeTestEnvironment({
    projectId: 'perfect-board-rules-test',
    firestore: {
      rules: readFileSync(
        path.join(__dirname, '..', 'firebase', 'firestore.rules'),
        'utf8',
      ),
      host: host,
      port: port,
    },
  });
  await env.clearFirestore();

  // Token come li emette Firebase Auth: isAuthenticated() pretende che la mail
  // sia verificata, quindi senza `email_verified` non passerebbe nulla e i
  // test sembrerebbero verdi per il motivo sbagliato.
  const worker = env
    .authenticatedContext('worker-uid', {
      email_verified: true,
      email: 'worker@example.com',
      admin: true,
    })
    .firestore();
  const altroAdmin = env
    .authenticatedContext('admin-uid', {
      email_verified: true,
      email: 'admin@example.com',
      admin: true,
    })
    .firestore();
  // Login anonimo, come il "Try the demo" dell'esempio.
  const anonimo1 = (uid) =>
    env
      .authenticatedContext(uid, {firebase: {sign_in_provider: 'anonymous'}})
      .firestore();
  const demo = anonimo1('demo-uid');
  const cliente = env
    .authenticatedContext('cliente-uid', {
      email_verified: true,
      email: 'mario@example.com',
      user: true,
    })
    .firestore();
  const anonimo = env.unauthenticatedContext().firestore();

  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'Tickets/t1'), {
      title: 'Non si apre la box',
      type: 'bug',
      status: 'nuova',
      createdBy: {uid: 'admin-uid', name: 'George', role: 'admin'},
    });
    await setDoc(doc(db, 'Tickets/t1/Comments/c1'), {
      author: {uid: 'admin-uid', name: 'George'},
      text: 'Succede anche a me.',
    });
    await setDoc(doc(db, 'Tickets/s1'), {
      title: 'La mia prova',
      status: 'nuova',
      sandbox: 'demo-uid',
    });
    await setDoc(doc(db, 'Tickets/s2'), {
      title: 'La prova di un altro',
      status: 'nuova',
      sandbox: 'altro-demo-uid',
    });
    await setDoc(doc(db, 'Tickets/t1/Attachments/a1'), {
      name: 'schermata.png',
      url: 'https://example.com/schermata.png',
      contentType: 'image/png',
    });
  });

  console.log('\nLa scheda: la vedono tutti gli admin');
  await check(
    'un admin legge la scheda',
    assertSucceeds(getDoc(doc(altroAdmin, 'Tickets/t1'))),
  );
  await check(
    'un admin ne cambia lo stato (trascina la card)',
    assertSucceeds(
      setDoc(doc(altroAdmin, 'Tickets/t1'), {status: 'pronta'}, {merge: true}),
    ),
  );
  await check(
    'un admin ne apre una nuova',
    assertSucceeds(
      addDoc(collection(altroAdmin, 'Tickets'), {
        title: 'Vorrei un filtro per data',
        type: 'richiesta',
        status: 'nuova',
      }),
    ),
  );
  await check(
    'un cliente NON legge le schede',
    assertFails(getDoc(doc(cliente, 'Tickets/t1'))),
  );
  await check(
    'un anonimo NON legge le schede',
    assertFails(getDoc(doc(anonimo, 'Tickets/t1'))),
  );

  console.log('\nCommenti e allegati: il canale comune fra admin');
  await check(
    'un altro admin legge i commenti',
    assertSucceeds(getDoc(doc(altroAdmin, 'Tickets/t1/Comments/c1'))),
  );
  await check(
    'un altro admin commenta',
    assertSucceeds(
      addDoc(collection(altroAdmin, 'Tickets/t1/Comments'), {
        author: {uid: 'admin-uid', name: 'George'},
        text: 'Aggiungo un dettaglio',
      }),
    ),
  );
  await check(
    'un commento non si riscrive',
    assertFails(
      setDoc(doc(altroAdmin, 'Tickets/t1/Comments/c1'), {text: 'altro'}),
    ),
  );
  await check(
    'un commento non si cancella',
    assertFails(deleteDoc(doc(worker, 'Tickets/t1/Comments/c1'))),
  );
  await check(
    'un altro admin vede gli allegati',
    assertSucceeds(getDoc(doc(altroAdmin, 'Tickets/t1/Attachments/a1'))),
  );
  await check(
    'un altro admin toglie un allegato',
    assertSucceeds(deleteDoc(doc(altroAdmin, 'Tickets/t1/Attachments/a1'))),
  );
  await check(
    'un cliente NON legge i commenti',
    assertFails(getDoc(doc(cliente, 'Tickets/t1/Comments/c1'))),
  );

  console.log('\nDemo (anonimo): solo la sua board privata, niente file');
  await check(
    'il demo legge una sua scheda',
    assertSucceeds(getDoc(doc(demo, 'Tickets/s1'))),
  );
  await check(
    'il demo elenca la sua board',
    assertSucceeds(
      getDocs(query(collection(demo, 'Tickets'), where('sandbox', '==', 'demo-uid'))),
    ),
  );
  await check(
    'il demo NON elenca tutte le schede',
    assertFails(getDocs(collection(demo, 'Tickets'))),
  );
  await check(
    'il demo NON legge le schede vere',
    assertFails(getDoc(doc(demo, 'Tickets/t1'))),
  );
  await check(
    'il demo NON legge la board di un altro demo',
    assertFails(getDoc(doc(demo, 'Tickets/s2'))),
  );
  await check(
    'il demo apre una scheda nella sua board',
    assertSucceeds(
      addDoc(collection(demo, 'Tickets'), {title: 'x', sandbox: 'demo-uid'}),
    ),
  );
  await check(
    'il demo NON apre schede fuori dalla sua board',
    assertFails(addDoc(collection(demo, 'Tickets'), {title: 'x'})),
  );
  await check(
    'il demo NON apre schede nella board di un altro',
    assertFails(
      addDoc(collection(demo, 'Tickets'), {title: 'x', sandbox: 'altro-demo-uid'}),
    ),
  );
  await check(
    'il demo sposta una sua scheda',
    assertSucceeds(
      setDoc(doc(demo, 'Tickets/s1'), {status: 'in_carico'}, {merge: true}),
    ),
  );
  await check(
    'il demo NON porta una scheda fuori dalla sua board',
    assertFails(
      setDoc(doc(demo, 'Tickets/s1'), {sandbox: 'altro-demo-uid'}, {merge: true}),
    ),
  );
  await check(
    'il demo commenta una sua scheda',
    assertSucceeds(
      addDoc(collection(demo, 'Tickets/s1/Comments'), {text: 'Provo'}),
    ),
  );
  await check(
    'il demo NON commenta le schede vere',
    assertFails(addDoc(collection(demo, 'Tickets/t1/Comments'), {text: 'x'})),
  );
  await check(
    'il demo NON registra allegati',
    assertFails(
      addDoc(collection(demo, 'Tickets/s1/Attachments'), {name: 'x.png'}),
    ),
  );
  await check(
    'il demo NON elimina la scheda di un altro',
    assertFails(deleteDoc(doc(demo, 'Tickets/s2'))),
  );
  await check(
    'il demo elimina una sua scheda',
    assertSucceeds(deleteDoc(doc(demo, 'Tickets/s1'))),
  );

  console.log('\nEliminare: la scheda sì, i pezzi no (li toglie il trigger)');
  await check(
    'un admin elimina la scheda',
    assertSucceeds(deleteDoc(doc(altroAdmin, 'Tickets/t1'))),
  );
  await check(
    'ma i commenti restano fuori portata del client',
    assertFails(deleteDoc(doc(worker, 'Tickets/t1/Comments/c1'))),
  );

  await env.cleanup();
  console.log(`\n${passed} verifiche passate, ${failed} fallite`);
  process.exit(failed === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
