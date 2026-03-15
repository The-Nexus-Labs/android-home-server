STEPS_ROOT="$PROJECT_ROOT/src/steps"

step_fail() {
  if declare -F die >/dev/null 2>&1; then
    die "$1"
  fi
  printf '[x] %s\n' "$1" >&2
  exit 1
}

step_default_state_key() {
  local raw
  raw=$(step_id | tr '[:lower:]-' '[:upper:]_')
  printf 'STATE_%s\n' "$raw"
}

step_resolve_dir() {
  local key=$1
  local -a matches=()

  if [[ -d "$key" ]]; then
    printf '%s\n' "$key"
    return 0
  fi

  shopt -s nullglob
  matches=("$STEPS_ROOT"/??-"$key")
  shopt -u nullglob

  if [[ "${#matches[@]}" -ne 1 ]]; then
    step_fail "unable to resolve step: $key"
  fi

  printf '%s\n' "${matches[0]}"
}

step_resolve_file() {
  local key=$1
  local dir

  if ! dir=$(step_resolve_dir "$key"); then
    return 1
  fi

  printf '%s/step.sh\n' "$dir"
}

step_reset_module() {
  unset -f step_id step_name step_is_done step_apply step_guide step_state_key 2>/dev/null || true
}

step_load_module() {
  local file=$1

  step_reset_module
  # shellcheck disable=SC1090
  source "$file"

  declare -F step_id >/dev/null 2>&1 || step_fail "step module is missing step_id(): $file"
  declare -F step_name >/dev/null 2>&1 || step_fail "step module is missing step_name(): $file"
  declare -F step_is_done >/dev/null 2>&1 || step_fail "step module is missing step_is_done(): $file"
  declare -F step_apply >/dev/null 2>&1 || step_fail "step module is missing step_apply(): $file"
  declare -F step_guide >/dev/null 2>&1 || step_fail "step module is missing step_guide(): $file"
}

step_current_state_key() {
  if declare -F step_state_key >/dev/null 2>&1; then
    step_state_key
    return 0
  fi
  step_default_state_key
}

step_run_indented() {
  (
    log() {
      printf '%s\n' "$*"
    }

    warn() {
      printf '%s\n' "$*" >&2
    }

    die() {
      printf '%s\n' "$*" >&2
      exit 1
    }

    print_manual_block() {
      local text=$1
      local line

      if [[ -r /dev/tty && -w /dev/tty ]]; then
        printf '\n' > /dev/tty
        while IFS= read -r line || [[ -n "$line" ]]; do
          printf '    %s\n' "$line" > /dev/tty
        done <<< "$text"
        printf '\n' > /dev/tty
        return 0
      fi

      printf '\n%s\n\n' "$text"
    }

    "$@"
  ) > >(sed 's/^/    /') 2> >(sed 's/^/    /' >&2)
}

step_run_action() {
  local file=$1
  local action=${2:-run}

  shift 2 || true
  step_load_module "$file"

  case "$action" in
    run)
      if step_is_done "$@"; then
        print_step_detail "$(step_name) is already complete."
        return 0
      fi
      step_run_indented step_apply "$@"
      ;;
    apply)
      step_run_indented step_apply "$@"
      ;;
    test)
      step_is_done "$@"
      ;;
    guide)
      step_run_indented step_guide "$@"
      ;;
    name)
      step_name
      ;;
    *)
      step_fail "unsupported step action: $action"
      ;;
  esac
}