#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

print_usage() {
  cat <<EOF
Usage:
  ${SCRIPT_NAME} dump [--depth N] [--max-nodes N]
  ${SCRIPT_NAME} counts [--depth N] [--max-nodes N]
  ${SCRIPT_NAME} focused
  ${SCRIPT_NAME} help

Notes:
  - Requires Hammerspoon with hs.ipc enabled in init.lua.
  - Requires hs CLI in PATH (or set HS_BIN to its full path).
  - Open an Outlook compose window before running this script.
EOF
}

require_value() {
  local flag="${1:-}"
  local value="${2:-}"
  if [[ -z "$value" ]]; then
    echo "Missing value for ${flag}" >&2
    exit 1
  fi
}

hs_bin="${HS_BIN:-$(command -v hs || true)}"
if [[ -z "${hs_bin}" ]]; then
  echo "hs CLI not found. Install/enable Hammerspoon CLI first." >&2
  exit 1
fi

if [[ $# -eq 0 ]]; then
  print_usage
  exit 1
fi

cmd="$1"
shift

depth="6"
max_nodes="700"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --depth)
      require_value "$1" "${2:-}"
      depth="$2"
      shift 2
      ;;
    --max-nodes)
      require_value "$1" "${2:-}"
      max_nodes="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

case "$cmd" in
  help|-h|--help)
    print_usage
    ;;
  focused)
    "${hs_bin}" -c "if not OutlookAX then print('OutlookAX module not loaded. Reload Hammerspoon config first.'); return end; OutlookAX.focused()"
    ;;
  dump)
    "${hs_bin}" -c "if not OutlookAX then print('OutlookAX module not loaded. Reload Hammerspoon config first.'); return end; OutlookAX.dumpCompose(${depth}, ${max_nodes})"
    ;;
  counts)
    "${hs_bin}" -c "if not OutlookAX then print('OutlookAX module not loaded. Reload Hammerspoon config first.'); return end; OutlookAX.fieldCounts(${depth}, ${max_nodes})"
    ;;
  *)
    echo "Unknown command: ${cmd}" >&2
    print_usage
    exit 1
    ;;
esac
