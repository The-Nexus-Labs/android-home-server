supports_color() {
  [[ -z "${NO_COLOR:-}" ]] || return 1
  [[ -n "${FORCE_COLOR:-}" ]] && return 0
  [[ -n "${CLICOLOR_FORCE:-}" ]] && return 0
  [[ -t 1 || -n "${TERM_PROGRAM:-}" ]]
  [[ "${TERM:-}" != 'dumb' ]]
}

color_yellow() {
  supports_color || return 1
  if command -v tput >/dev/null 2>&1; then
    tput setaf 3
    return 0
  fi
  printf '\033[33m'
}

color_cyan() {
  supports_color || return 1
  if command -v tput >/dev/null 2>&1; then
    tput setaf 6
    return 0
  fi
  printf '\033[36m'
}

color_green() {
  supports_color || return 1
  if command -v tput >/dev/null 2>&1; then
    tput setaf 2
    return 0
  fi
  printf '\033[32m'
}

color_red() {
  supports_color || return 1
  if command -v tput >/dev/null 2>&1; then
    tput setaf 1
    return 0
  fi
  printf '\033[31m'
}

color_bold() {
  supports_color || return 1
  if command -v tput >/dev/null 2>&1; then
    tput bold
    return 0
  fi
  printf '\033[1m'
}

color_reset() {
  supports_color || return 1
  if command -v tput >/dev/null 2>&1; then
    tput sgr0
    return 0
  fi
  printf '\033[0m'
}

log() {
  printf '[+] %s\n' "$*"
}

warn() {
  printf '[!] %s\n' "$*" >&2
}

die() {
  printf '[x] %s\n' "$*" >&2
  exit 1
}

print_step_header() {
  local text=$1
  local yellow reset

  yellow=$(color_yellow 2>/dev/null || true)
  reset=$(color_reset 2>/dev/null || true)
  printf '\n%s[+] %s%s\n' "$yellow" "$text" "$reset"
}

print_step_detail() {
  printf '    %s\n' "$1"
}

print_bootstrap_header() {
  local device_name=$1
  local device_model=$2
  local device_codename=$3
  local cyan bold reset

  cyan=$(color_cyan 2>/dev/null || true)
  bold=$(color_bold 2>/dev/null || true)
  reset=$(color_reset 2>/dev/null || true)

  printf '%s%sAndroid Home Server Bootstrap%s\n' "$bold" "$cyan" "$reset"
  printf '  Device: %s\n' "$device_name"
  printf '  Model: %s (%s)\n\n' "$device_model" "$device_codename"
}