#!/usr/bin/env bash
# Builds the example against a real project and publishes it on Firebase
# Hosting. / Compila l'esempio su un progetto vero e lo pubblica su Firebase
# Hosting.
#
#   cp web_config.example.json web_config.json   # then fill it / poi compilalo
#   ./deploy_web.sh            # rules + hosting / regole + hosting
#   ./deploy_web.sh --hosting-only
set -euo pipefail
cd "$(dirname "$0")"

config=web_config.json
if [[ ! -f $config ]]; then
  echo "Missing $config: copy web_config.example.json and fill it with the" >&2
  echo "web app config from the Firebase console." >&2
  exit 1
fi
project=$(sed -n 's/.*"FIREBASE_PROJECT_ID" *: *"\([^"]*\)".*/\1/p' "$config")
if [[ -z $project || $project == your-project-id ]]; then
  echo "FIREBASE_PROJECT_ID not set in $config" >&2
  exit 1
fi

flutter build web --release --dart-define-from-file="$config"

if [[ ${1:-} != --hosting-only ]]; then
  (cd ../firebase && firebase deploy --only firestore:rules,storage --project "$project")
fi
firebase deploy --only hosting --project "$project"

echo
echo "https://$project.web.app"
