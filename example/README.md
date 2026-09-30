# perfect_board — example

## On the emulators / Sugli emulatori

No real project needed. / Non serve un progetto vero.

```bash
# 1. emulators, from the repo root / emulatori, dalla radice del repo
cd firebase
firebase emulators:start --only auth,firestore,storage --project demo-perfect-board

# 2. in another terminal: the admin user / in un altro terminale: l'utente admin
example/seed_admin.sh            # admin@example.com / password

# 3. the app / l'app
cd example && flutter run -d chrome
```

## On your Firebase project / Sul tuo progetto Firebase

1. Console → enable **Authentication** (Email/Password), **Firestore**,
   **Storage**; add a **Web app** and keep its config. / Console → attiva
   **Authentication** (Email/Password), **Firestore**, **Storage**; aggiungi
   una **app Web** e tieni a portata la sua configurazione.
2. Rules / Regole:
   ```bash
   cd firebase
   firebase deploy --only firestore:rules,storage --project YOUR-PROJECT
   ```
3. Create a user in the console (Authentication → Add user), then make it an
   admin / Crea un utente dalla console, poi rendilo admin:
   ```bash
   cd functions && npm install
   BOARD_PROJECT_ID=YOUR-PROJECT node set_admin.js you@example.com
   ```
   (needs a service account key: `BOARD_SERVICE_ACCOUNT` or
   `functions/serviceAccountKey.json` / serve una chiave di service account)
4. Run with the web config / Avvia con la configurazione web:
   ```bash
   cd example
   flutter run -d chrome \
     --dart-define=FIREBASE_PROJECT_ID=... \
     --dart-define=FIREBASE_API_KEY=... \
     --dart-define=FIREBASE_APP_ID=... \
     --dart-define=FIREBASE_SENDER_ID=... \
     --dart-define=FIREBASE_AUTH_DOMAIN=... \
     --dart-define=FIREBASE_STORAGE_BUCKET=...
   ```
5. Publish it on Firebase Hosting / Pubblicalo su Firebase Hosting:
   ```bash
   cd example
   cp web_config.example.json web_config.json   # fill it / compilalo
   ./deploy_web.sh                  # rules + hosting / regole + hosting
   ```
   `web_config.json` is ignored by git; the site ends up on
   `https://YOUR-PROJECT.web.app`. / `web_config.json` è ignorato da git; il
   sito finisce su `https://IL-TUO-PROGETTO.web.app`.
6. Optional, a public demo / Facoltativo, una demo pubblica: console →
   Authentication → Sign-in method → enable **Anonymous** / attiva
   **Anonimo**. The login page already has *Try the demo* / Il login ha già
   *Try the demo*. For the nightly cleanup / Per la pulizia notturna:
   ```bash
   cd functions && npm install && cd ../firebase
   firebase deploy --only functions --project YOUR-PROJECT
   ```
7. Optional / Facoltativo: the same `functions/` deploy also keeps comment
   and attachment counters (Blaze plan) / lo stesso deploy di `functions/`
   tiene anche i contatori di commenti e allegati (piano Blaze).
