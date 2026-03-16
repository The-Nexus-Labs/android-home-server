resolve_profile_file() {
  local requested_profile=${PROFILE:-}
  local connected_codename candidate

  if [[ -n "$requested_profile" ]]; then
    if [[ -f "$requested_profile" ]]; then
      printf '%s\n' "$requested_profile"
      return 0
    fi

    candidate="$PROJECT_ROOT/$requested_profile"
    [[ -f "$candidate" ]] || {
      printf '[x] profile file not found: %s\n' "$requested_profile" >&2
      exit 1
    }
    printf '%s\n' "$candidate"
    return 0
  fi

  if [[ "${COMMON_SKIP_DEVICE_DISCOVERY:-0}" != "1" ]] && connected_codename=$(resolve_connected_codename); then
    candidate="$PROJECT_ROOT/config/${connected_codename}.env"
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  printf '%s\n' "$DEFAULT_PROFILE_FILE"
}

PROFILE_FILE=$(resolve_profile_file)

if [[ -f "$GLOBAL_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$GLOBAL_ENV_FILE"
fi

if [[ -f "$PROJECT_ROOT/config/local.env" ]]; then
  # shellcheck disable=SC1091
  source "$PROJECT_ROOT/config/local.env"
fi
# shellcheck disable=SC1090
source "$PROFILE_FILE"

ARTIFACT_ROOT="$PROJECT_ROOT/artifacts/$DEVICE_CODENAME"
MANIFEST_PATH="$ARTIFACT_ROOT/manifest.json"
DOWNLOAD_DIR="$ARTIFACT_ROOT/downloads"
GRAPHENEOS_ROOT="$ARTIFACT_ROOT/grapheneos"
GRAPHENEOS_RELEASE_DIR="$GRAPHENEOS_ROOT/release"
PLATFORM_TOOLS_DIR="$GRAPHENEOS_ROOT/platform-tools"
BOOTSTRAP_STATE_PATH="$ARTIFACT_ROOT/bootstrap-interactive.state"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

configure_platform_tools_path() {
  if [[ -d "$PLATFORM_TOOLS_DIR" ]]; then
    PATH="$PLATFORM_TOOLS_DIR:$PATH"
    export PATH
  fi
}

ensure_dirs() {
  mkdir -p "$ARTIFACT_ROOT" "$DOWNLOAD_DIR" "$GRAPHENEOS_ROOT" "$GRAPHENEOS_RELEASE_DIR"
}

require_manifest() {
  [[ -f "$MANIFEST_PATH" ]] || die "manifest not found; run ./src/run-step.sh prepare-assets apply --manifest-only first"
}

manifest_value() {
  local key=$1
  python3 - <<'PY' "$MANIFEST_PATH" "$key"
import json, sys
manifest_path, key = sys.argv[1], sys.argv[2]
with open(manifest_path, 'r', encoding='utf-8') as f:
    data = json.load(f)
parts = key.split('.')
cur = data
for part in parts:
    cur = cur[part]
print(cur)
PY
}

maybe_prompt_destructive() {
  local prompt=$1
  local answer

  if [[ "${FORCE:-0}" == "1" ]]; then
    return 0
  fi

  if [[ -r /dev/tty && -w /dev/tty ]]; then
    printf '    %s [y/N] ' "$prompt" > /dev/tty
    read -r answer < /dev/tty
  else
    printf '    %s [y/N] ' "$prompt"
    read -r answer
  fi

  [[ "$answer" == "y" || "$answer" == "Y" ]]
}

wait_for_enter() {
  local prompt=${1:-Press Enter to continue}
  if [[ "${FORCE:-0}" == "1" ]]; then
    return 0
  fi

  if [[ -r /dev/tty && -w /dev/tty ]]; then
    printf '    %s' "$prompt" > /dev/tty
    read -r _ < /dev/tty
  else
    printf '    %s' "$prompt"
    read -r _
  fi
}

print_manual_block() {
  printf '\n%s\n\n' "$1"
}