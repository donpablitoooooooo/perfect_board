/**
 * Cloud Functions della board: contatori di commenti e allegati sulla card e
 * pulizia a cascata di una scheda eliminata (vedi ticket_events.js).
 *
 * Se l'app ha già le sue functions, basta riesportare questi trigger
 * dal suo index.js.
 */

const admin = require('firebase-admin');

if (!admin.apps.length) admin.initializeApp();

const ticketEvents = require('./ticket_events');

exports.ticketCommentAdded = ticketEvents.ticketCommentAdded;
exports.ticketDeleted = ticketEvents.ticketDeleted;
exports.ticketAttachmentAdded = ticketEvents.ticketAttachmentAdded;
exports.ticketAttachmentRemoved = ticketEvents.ticketAttachmentRemoved;

// Facoltativa, spenta: pulizia notturna delle board demo (login anonimo).
// Per accenderla togli il commento alla riga sotto e rifai il deploy.
// exports.demoCleanup = require('./demo_cleanup').demoCleanup;
