#!/usr/bin/env bash

set -u
set -o pipefail

usage() {
  cat <<EOF
Usage: $0 switch [options]
  --display NUMBER           m1ddc display number (default: 1)
  --input-a CODE             First input code (default: 15)
  --input-b CODE             Second input code (default: 25)
  --keyfob-volume-uuid UUID   Eject this volume if mounted before switching
  --m1ddc PATH               m1ddc executable (default: /opt/homebrew/bin/m1ddc)
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  switch)
    shift
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac

display_number=1
input_a=15
input_b=25
keyfob_volume_uuid=""
m1ddc_binary="/opt/homebrew/bin/m1ddc"

while (($#)); do
  case "$1" in
    --display)
      display_number="${2:?missing value for --display}"
      shift 2
      ;;
    --input-a)
      input_a="${2:?missing value for --input-a}"
      shift 2
      ;;
    --input-b)
      input_b="${2:?missing value for --input-b}"
      shift 2
      ;;
    --keyfob-volume-uuid)
      keyfob_volume_uuid="${2-}"
      shift 2
      ;;
    --m1ddc)
      m1ddc_binary="${2:?missing value for --m1ddc}"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 64
      ;;
  esac
done

eject_keyfob_if_mounted() {
  local disk_info mount_point parent_disk

  [[ -n "$keyfob_volume_uuid" ]] || return 0
  if ! disk_info=$(/usr/sbin/diskutil info -plist "$keyfob_volume_uuid" 2>/dev/null); then
    return 0
  fi

  mount_point=$(printf '%s' "$disk_info" | /usr/bin/plutil -extract MountPoint raw -o - - 2>/dev/null) || return 0
  [[ -n "$mount_point" ]] || return 0

  if ! parent_disk=$(printf '%s' "$disk_info" | /usr/bin/plutil -extract ParentWholeDisk raw -o - - 2>/dev/null); then
    echo "Could not identify the mounted KEYFOB disk; monitor input was not changed." >&2
    return 1
  fi

  if ! /usr/sbin/diskutil eject "/dev/$parent_disk" >/dev/null 2>&1; then
    echo "KEYFOB could not be ejected; monitor input was not changed." >&2
    return 1
  fi

  echo "KEYFOB was safely ejected."
}

if [[ ! -x "$m1ddc_binary" ]]; then
  echo "m1ddc is required at $m1ddc_binary." >&2
  exit 69
fi

current_output=$("$m1ddc_binary" display "$display_number" get input 2>/dev/null) || {
  echo "Could not read the Dell monitor input; nothing was changed." >&2
  exit 1
}

if [[ "$current_output" =~ ^[[:space:]]*([0-9]+)[[:space:]]*$ ]]; then
  current_input="${BASH_REMATCH[1]}"
else
  echo "Dell monitor input was unreadable: $current_output" >&2
  exit 1
fi

# This Dell can report input 25 as 0x1919 (6425). Keep the write code at 25.
case "$current_input" in
  3855) current_input=15 ;;
  6425) current_input=25 ;;
esac

case "$current_input" in
  "$input_a") target_input="$input_b" ;;
  "$input_b") target_input="$input_a" ;;
  *)
    echo "Dell monitor input $current_input is not configured ($input_a or $input_b); nothing was changed." >&2
    exit 1
    ;;
esac

eject_keyfob_if_mounted || exit 1

if ! "$m1ddc_binary" display "$display_number" set input "$target_input"; then
  echo "Dell input switch failed." >&2
  exit 1
fi

echo "Dell input switched from $current_input to $target_input."
