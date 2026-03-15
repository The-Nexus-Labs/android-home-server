#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)

usage() {
  cat <<'EOF'
usage: ./src/run-step.sh <step-key> [run|apply|test|guide|name] [step-args...]

Examples:
  ./src/run-step.sh prepare-assets apply --download
  ./src/run-step.sh unlock-bootloader run
  ./src/run-step.sh disable-system-updater apply status
EOF
}

[[ $# -ge 1 ]] || {
  usage
  exit 1
}

step_key=$1
shift

action=${1:-run}
if [[ $# -gt 0 ]]; then
  shift
fi

if [[ "$action" == "name" || "$action" == "guide" ]]; then
  STEPS_ROOT="$PROJECT_ROOT/src/steps"
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/step.sh"
  if ! step_file=$(step_resolve_file "$step_key"); then
    exit 1
  fi
  step_load_module "$step_file"
  if [[ "$action" == "name" ]]; then
    step_name
  else
    step_run_indented step_guide "$@"
  fi
  exit 0
fi

# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/state.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/step.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/runtime.sh"

if ! step_file=$(step_resolve_file "$step_key"); then
  exit 1
fi
step_run_action "$step_file" "$action" "$@"