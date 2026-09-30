/**
 * Trigger delle segnalazioni.
 *
 * Tiene aggiornati i contatori di commenti e allegati sulla card — sono una
 * cache, e il posto giusto per scriverla è il server: il client dovrebbe
 * leggere due sottocollection per ogni riga della board — e porta via tutto
 * quello che resta attaccato a una segnalazione eliminata.
 *
 * NIENTE notifiche: la board si guarda, non ti insegue.
 *
 * Volutamente NON fa altro: non assegna, non cambia stato, non innesca
 * lavorazioni. Le uniche cose che si muovono da sole qui sono un contatore e
 * una pulizia.
 */

const {
  onDocumentCreated,
  onDocumentDeleted,
} = require('firebase-functions/v2/firestore');
const {logger} = require('firebase-functions/v2');
const admin = require('firebase-admin');

// La regione dei trigger deve essere compatibile con la località del database
// Firestore: cambiala con `BOARD_FUNCTIONS_REGION` se il tuo non è in Europa.
const REGION = process.env.BOARD_FUNCTIONS_REGION || 'europe-west1';

/**
 * Nuovo commento: aggiorna il contatore sulla card.
 *
 * `lastCommentAt` serve a far vedere a colpo d'occhio dove si è parlato di
 * recente senza aprire la sottocollection.
 */
exports.ticketCommentAdded = onDocumentCreated(
  {document: 'Tickets/{ticketId}/Comments/{commentId}', region: REGION},
  async (event) => {
    if (!event.data) return;

    await admin
      .firestore()
      .collection('Tickets')
      .doc(event.params.ticketId)
      .update({
        commentCount: admin.firestore.FieldValue.increment(1),
        lastCommentAt: admin.firestore.FieldValue.serverTimestamp(),
      });
  },
);

/**
 * Segnalazione eliminata: porta via tutto quello che ci stava attaccato.
 *
 * Firestore non cancella a cascata, e le regole tengono apposta commenti e
 * note non cancellabili dal client ("un commento detto è detto"): la pulizia
 * quindi non può stare nel backoffice, o sarebbe metà lavoro con metà
 * permessi. Qui gira con l'Admin SDK, che le regole non le passa — ed è
 * l'unico punto in cui commenti e timeline se ne vanno davvero.
 *
 * Il client cancella solo `Tickets/{id}`; il resto — commenti, allegati,
 * lavorazione, timeline e i file su Storage — lo smonta questo trigger.
 */
exports.ticketDeleted = onDocumentDeleted(
  {document: 'Tickets/{ticketId}', region: REGION},
  async (event) => {
    const ticketId = event.params.ticketId;
    const db = admin.firestore();

    // recursiveDelete su un documento già sparito serve proprio a questo:
    // svuota i discendenti rimasti orfani.
    await Promise.all([
      db.recursiveDelete(db.collection('Tickets').doc(ticketId)),
    ]);

    // I file non sono su Firestore: stanno sotto `uploads/tickets/{id}/`, e
    // lì si va a prefisso. Se fallisce resta qualche file inutile, non un
    // dato sbagliato: si logga e si tira avanti.
    try {
      await admin
        .storage()
        .bucket()
        .deleteFiles({prefix: `uploads/tickets/${ticketId}/`});
    } catch (e) {
      logger.warn(
        `Allegati di ${ticketId} non rimossi da Storage: ${e.message}`,
      );
    }

    logger.info(`Segnalazione ${ticketId} eliminata con tutto il contenuto.`);
  },
);

/** Contatore allegati: sale quando se ne aggiunge uno. */
exports.ticketAttachmentAdded = onDocumentCreated(
  {document: 'Tickets/{ticketId}/Attachments/{attachmentId}', region: REGION},
  async (event) => {
    await admin
      .firestore()
      .collection('Tickets')
      .doc(event.params.ticketId)
      .update({
        attachmentCount: admin.firestore.FieldValue.increment(1),
      });
  },
);

/**
 * Contatore allegati: scende quando se ne toglie uno. Se la segnalazione non
 * c'è più (cancellata con tutto dentro) l'update fallisce, e va bene così:
 * non c'è nessun contatore da correggere.
 */
exports.ticketAttachmentRemoved = onDocumentDeleted(
  {document: 'Tickets/{ticketId}/Attachments/{attachmentId}', region: REGION},
  async (event) => {
    try {
      await admin
        .firestore()
        .collection('Tickets')
        .doc(event.params.ticketId)
        .update({
          attachmentCount: admin.firestore.FieldValue.increment(-1),
        });
    } catch (e) {
      logger.info(
        `Contatore allegati non aggiornato per ${event.params.ticketId}: ` +
          e.message,
      );
    }
  },
);
