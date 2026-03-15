#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
COMMON_DIR="$SCRIPT_DIR/common"

DEFAULT_PROFILE_FILE="$PROJECT_ROOT/config/cheetah.env"
GLOBAL_ENV_FILE="$PROJECT_ROOT/config/global.env"

# shellcheck disable=SC1091
source "$COMMON_DIR/output.sh"
# shellcheck disable=SC1091
source "$COMMON_DIR/device.sh"
# shellcheck disable=SC1091
source "$COMMON_DIR/bootstrap.sh"
# shellcheck disable=SC1091
source "$COMMON_DIR/wifi.sh"
# shellcheck disable=SC1091
source "$COMMON_DIR/magisk.sh"

configure_platform_tools_path

