#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

if ! command -v su >/dev/null 2>&1; then
  echo "Magisk root is not available inside Termux yet."
  echo "Open Magisk, grant root to Termux, then rerun ./grant-root.sh"
  exit 1
fi

if ! su -c true >/dev/null 2>&1; then
  echo "Termux does not have root permission yet."
  echo "Approve the Termux root request in Magisk, then rerun ./grant-root.sh"
  exit 1
fi

printf 'granted\n' > "$HOME/termux-root-enabled.txt"
echo "Termux root is enabled"