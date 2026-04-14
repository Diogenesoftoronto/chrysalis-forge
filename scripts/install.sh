#!/usr/bin/env bash
set -euo pipefail

REPO="diogenesoftoronto/chrysalis-forge"
PACKAGE="chrysalis-forge"
BIN="chrysalis"
MIN_NODE_MAJOR=20
MIN_NODE_MINOR=19
MIN_NODE_PATCH=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()  { printf "${CYAN}=>${RESET} %s\n" "$1"; }
ok()    { printf "${GREEN}✓${RESET} %s\n" "$1"; }
warn()  { printf "${YELLOW}!${RESET} %s\n" "$1"; }
err()   { printf "${RED}✗${RESET} %s\n" "$1" >&2; }

parse_semver() {
  local version="${1#v}"
  IFS='.' read -r major minor patch <<< "$version"
  echo "${major:-0} ${minor:-0} ${patch:-0}"
}

version_gte() {
  local a_major a_minor a_patch b_major b_minor b_patch
  read -r a_major a_minor a_patch <<< "$(parse_semver "$1")"
  read -r b_major b_minor b_patch <<< "$(parse_semver "$2")"
  (( a_major > b_major )) && return 0
  (( a_major == b_major && a_minor > b_minor )) && return 0
  (( a_major == b_major && a_minor == b_minor && a_patch >= b_patch )) && return 0
  return 1
}

ensure_node() {
  if ! command -v node &>/dev/null; then
    err "Node.js is not installed."
    info "Install it from https://nodejs.org or via your package manager, then re-run this script."
    exit 1
  fi

  local node_version
  node_version="$(node --version)"
  if ! version_gte "$node_version" "${MIN_NODE_MAJOR}.${MIN_NODE_MINOR}.${MIN_NODE_PATCH}"; then
    err "Node.js ${MIN_NODE_MAJOR}.${MIN_NODE_MINOR}.${MIN_NODE_PATCH}+ required (found ${node_version})."
    info "Upgrade: https://nodejs.org"
    exit 1
  fi
  ok "Node.js ${node_version}"
}

ensure_npm() {
  if ! command -v npm &>/dev/null; then
    err "npm is not installed."
    info "It should ship with Node.js — reinstall or update Node."
    exit 1
  fi
  ok "npm $(npm --version)"
}

latest_version() {
  local version
  version="$(npm view "$PACKAGE" version 2>/dev/null)" || true
  if [[ -z "$version" ]]; then
    version="$(npm view "${PACKAGE}@latest" version 2>/dev/null)" || true
  fi
  if [[ -z "$version" ]]; then
    err "Could not determine latest version of ${PACKAGE} from npm."
    exit 1
  fi
  echo "$version"
}

current_installed_version() {
  npm list -g "$PACKAGE" --depth=0 --json 2>/dev/null \
    | grep '"version"' \
    | head -1 \
    | sed 's/.*"version": *"\([^"]*\)".*/\1/' || true
}

install_global() {
  local version="$1"
  shift
  info "Installing ${PACKAGE}@${version} globally..."
  npm install -g "${PACKAGE}@${version}" "$@"
  ok "${PACKAGE}@${version} installed."
}

add_to_path() {
  local npm_prefix
  npm_prefix="$(npm config get prefix 2>/dev/null)" || return 0
  local bin_dir="${npm_prefix}/bin"
  if [[ ":$PATH:" != *":${bin_dir}:"* ]]; then
    warn "npm global bin directory not in PATH: ${bin_dir}"
    info "Add it to your shell profile:"
    echo ""
    echo "  export PATH=\"${bin_dir}:\$PATH\""
    echo ""
  fi
}

main() {
  printf "${BOLD}chrysalis forge${RESET} installer\n\n"

  local version=""
  local npm_args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force|-f)
        npm_args+=("--force")
        shift
        ;;
      --version|-v)
        if [[ $# -gt 1 ]]; then
          version="$2"
          shift 2
        else
          err "--version requires a value"
          exit 1
        fi
        ;;
      --prefix)
        if [[ $# -gt 1 ]]; then
          npm_args+=("--prefix" "$2")
          shift 2
        else
          err "--prefix requires a value"
          exit 1
        fi
        ;;
      --help|-h)
        echo "Usage: curl -fsSL https://raw.githubusercontent.com/${REPO}/main/scripts/install.sh | bash -s -- [options]"
        echo ""
        echo "Options:"
        echo "  --version VERSION   Install a specific version (default: latest)"
        echo "  --force, -f         Force reinstall even if already installed"
        echo "  --prefix DIR        npm install prefix"
        echo "  --help, -h          Show this help"
        exit 0
        ;;
      *)
        err "Unknown option: $1"
        exit 1
        ;;
    esac
  done

  ensure_node
  ensure_npm

  if [[ -z "$version" ]]; then
    version="$(latest_version)"
  fi
  ok "Installing version: ${version}"

  local existing
  existing="$(current_installed_version)" || true
  if [[ -n "$existing" ]]; then
    warn "Existing global installation: ${existing}"
  fi

  install_global "$version" "${npm_args[@]}"

  add_to_path

  if command -v "$BIN" &>/dev/null; then
    ok "${BIN} is available."
    printf "\n${GREEN}${BOLD}Ready.${RESET} Run ${CYAN}${BIN} --help${RESET} to get started.\n"
  else
    warn "${BIN} not found in PATH after install."
    add_to_path
  fi
}

main "$@"
