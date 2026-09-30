# perfect_board — example

Minimal app wired to the **Firebase emulators**, so it runs without a real
project. / App minima collegata agli **emulatori Firebase**: gira senza un
progetto vero.

```bash
# 1. emulators, from the repo root / emulatori, dalla radice del repo
cd firebase
firebase emulators:start --only auth,firestore,storage --project demo-perfect-board

# 2. in another terminal: the admin user / in un altro terminale: l'utente admin
example/seed_admin.sh            # admin@example.com / password

# 3. the app / l'app
cd example
flutter create --platforms web .
flutter run -d chrome
```

The seed script creates a user with a verified email and the `admin` claim,
as the rules require. / Lo script crea un utente con email verificata e il
claim `admin`, come chiedono le regole.

The Cloud Functions (comment and attachment counters) are not needed to try
the board. / Le Cloud Functions (contatori di commenti e allegati) non servono
per provare la board.
