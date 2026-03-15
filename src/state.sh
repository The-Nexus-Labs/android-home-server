STATE_FILE="$BOOTSTRAP_STATE_PATH"

state_load() {
  if [[ -f "$STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE"
  fi
}

state_has() {
  local key=$1
  [[ "${!key:-0}" == "1" ]]
}

state_mark_complete() {
  local key=$1
  mkdir -p "$ARTIFACT_ROOT"
  touch "$STATE_FILE"
  if ! grep -q "^${key}=1$" "$STATE_FILE" 2>/dev/null; then
    printf '%s=1\n' "$key" >> "$STATE_FILE"
  fi
  printf -v "$key" '1'
  export "$key"
}