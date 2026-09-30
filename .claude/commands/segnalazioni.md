---
description: Apre la Bacheca e lavora le schede aperte
---

Lavora le schede della board (collection Firestore `Tickets` del progetto
indicato da `BOARD_PROJECT_ID`), usando la CLI `node functions/board.js`. In interfaccia si chiamano **schede**
(*card*) e la sezione è la **Bacheca** (*Board*): nel codice e nella CLI
restano `Ticket*` e "segnalazioni", non è una svista. Il giro è semi-manuale:
tu proponi e scrivi codice, l'utente decide e deploya.

Di solito non parti da qui: l'utente preme **Esporta** sulla scheda e ti
incolla il markdown, che contiene già tutto — descrizione, collegamenti con
gli id, checklist, commenti, allegati. Se ce l'hai, salta alla 2.

## 1. Guarda cosa c'è

```bash
node functions/board.js list
node functions/board.js list --label=bug
```

Se l'utente ha indicato una scheda (`/segnalazioni #a1b2c3`), salta alla 2 con
quell'id. Altrimenti mostra le `nuova` e `da_chiarire` e chiedi da quale
partire — non sceglierla da solo.

## 2. Leggila per intero

```bash
node functions/board.js show <id>
```

`show` stampa anche i **commenti** e i **collegamenti**. I commenti sono dove
si aggiungono i dettagli, e spesso è lì che sta la risposta; i collegamenti
(`collegati tipo:id …`) dicono su quale dato guardare — l'id
accanto all'etichetta è quello vero, usalo per andare a leggere il documento.

Poi guarda il codice **prima** di proporre.

- Se **qualcosa non funziona**: la descrizione è un sintomo, non una diagnosi.
  Cerca il punto esatto che lo spiega, non fermarti al primo candidato
  plausibile. Se c'è un documento collegato, parti da quel dato.
- Se **si chiede un cambiamento**: guarda come è fatto oggi ciò che si vuole
  cambiare, e di' cosa tocchi e cosa si porta dietro. Se è una richiesta
  grossa, proponi come spezzarla invece di aprire un branch da dieci file.

## 3. Proponi, non partire in quarta

Riporta all'utente, in chat: cosa hai trovato, cosa proponi e quanto è grosso.
Se serve una sua decisione o un'informazione che non sta nel codice, chiedi —
e registra la domanda sulla scheda, così resta attaccata e non solo in chat:

```bash
node functions/board.js ask <id> "la domanda"        # + porta la scheda in "Da chiarire"
node functions/board.js comment <id> "una risposta"  # solo un commento
```

Aspetta la sua risposta. Non aprire branch e non toccare file prima dell'ok.

## 4. Lavora

Branch e commit come sempre, ma **il branch non si registra più sulla
scheda**: quel canale non esiste più. Se vuoi che resti scritto dove stai
lavorando, mettilo in un commento.

Quando hai finito e pushato:

```bash
node functions/board.js ready <id> --note="Cosa ho cambiato e come si verifica."
```

`--note` diventa un commento sulla scheda, che leggono tutti gli admin.

## 5. Fermati qui

Non mergiare, non deployare, non spostare la scheda in "Approvata": lo fa
l'utente dalla bacheca dopo il rilascio. Chiudi dicendo su quale branch è il
lavoro e come si verifica.

## Note

- La CLI scrive con l'Admin SDK: servono `BOARD_PROJECT_ID` e una chiave
  **di quel progetto** (`BOARD_SERVICE_ACCOUNT`, `functions/serviceAccountKey.json`
  o `GOOGLE_APPLICATION_CREDENTIALS`): una chiave di un altro progetto la CLI
  la rifiuta. Se manca, dillo e fermati — non aggirarla scrivendo da altre
  parti.
- Gli allegati nell'export hanno solo il percorso su Storage, non il link:
  per guardarli `node functions/board.js files <id>` li scarica in
  `ticket-files/<id>/`, poi li apri da lì. Non chiedere i link di download e
  non stamparli: aprono il file a chiunque li legga.
- Non ci sono note private: quello che scrivi lo leggono tutti gli admin.
- Etichette, collegamenti, scadenza e checklist si mettono dall'app:
  dalla CLI si leggono e basta.
- La board segue la lingua dell'app (`PerfectBoard.configure(locale: …)`),
  le chiavi su Firestore no: `ready` porta la scheda
  in "Pronta per i test" / "Ready for testing", `fatto` è "Approvata" /
  "Approved".
- Non eliminare schede: il cestino è nell'app ed è dell'utente.
