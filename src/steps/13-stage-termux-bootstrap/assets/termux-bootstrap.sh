#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

DEFAULT_PASS="${1:-__TERMUX_SSH_PASSWORD__}"
SSH_PORT="${2:-__TERMUX_SSH_PORT__}"

ensure_termux_packages() {
  local missing=()

  if ! command -v sshd >/dev/null 2>&1 || ! command -v passwd >/dev/null 2>&1; then
    missing+=(openssh)
  fi

  if ! command -v sv-enable >/dev/null 2>&1; then
    missing+=(termux-services)
  fi

  if [[ "${#missing[@]}" -gt 0 ]]; then
    pkg update -y
    pkg install -y "${missing[@]}"
  fi
}

require_termux_root() {
  if ! command -v su >/dev/null 2>&1; then
    echo "Magisk root is not available inside Termux yet."
    echo "Open Magisk, grant root to Termux, then rerun ./setup.sh"
    return 1
  fi

  if ! su -c true >/dev/null 2>&1; then
    echo "Termux does not have root permission yet."
    echo "Open Magisk, grant root to Termux, then rerun ./setup.sh"
    return 1
  fi

  return 0
}

start_sshd() {
  if command -v su >/dev/null 2>&1 && su -c true >/dev/null 2>&1; then
    su -c 'pkill -x sshd >/dev/null 2>&1 || true' >/dev/null 2>&1 || true
  fi

  pkill sshd 2>/dev/null || true

  if command -v sv-enable >/dev/null 2>&1; then
    sv-enable sshd >/dev/null 2>&1 || true
    sv up sshd >/dev/null 2>&1 || true
  fi

  if ! pgrep -u "$(id -u)" -x sshd >/dev/null 2>&1; then
    sshd
  fi
}

configure_sshd() {
  local sshd_config

  sshd_config="$PREFIX/etc/ssh/sshd_config"
  [[ -f "$sshd_config" ]] || {
    echo "OpenSSH did not create $sshd_config"
    return 1
  }

  if grep -Eq '^[#[:space:]]*Port ' "$sshd_config"; then
    sed -Ei "s|^[#[:space:]]*Port .*|Port ${SSH_PORT}|" "$sshd_config"
  else
    printf '\nPort %s\n' "$SSH_PORT" >> "$sshd_config"
  fi

  sed -Ei '/^[[:space:]]*(AddressFamily|ListenAddress)[[:space:]]+/d' "$sshd_config"
}

mkdir -p ~/.termux/boot
cat > ~/.termux/boot/10-home-server.sh <<EOF
#!/data/data/com.termux/files/usr/bin/bash
source "\$PREFIX/etc/profile"
termux-wake-lock || true
if command -v su >/dev/null 2>&1 && su -c true >/dev/null 2>&1; then
  su -c 'pkill -x sshd >/dev/null 2>&1 || true' >/dev/null 2>&1 || true
fi
pkill sshd 2>/dev/null || true
if command -v sv-enable >/dev/null 2>&1; then
  sv-enable sshd >/dev/null 2>&1 || true
  sv up sshd >/dev/null 2>&1 || true
fi
if ! pgrep -u "$(id -u)" -x sshd >/dev/null 2>&1; then
  sshd
fi
EOF
chmod 700 ~/.termux/boot/10-home-server.sh

ensure_termux_packages
configure_sshd

rm -f "$HOME/.termux_authinfo"
printf '%s\n%s\n' "$DEFAULT_PASS" "$DEFAULT_PASS" | passwd
termux-wake-lock || true
require_termux_root || exit 1
start_sshd

whoami > "$HOME/ssh-user.txt"
(
  ip -4 addr show wlan0 2>/dev/null \
    | awk '/inet /{print $2}' \
    | cut -d/ -f1 \
    | head -n1 \
    > "$HOME/ssh-ip.txt"
) || true

echo "Bootstrap complete"
