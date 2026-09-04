#!/usr/bin/env bash

set -u
set -o pipefail

action="${1:-}"
if [[ -z "$action" ]]; then
  echo "Usage: $0 {switch|connect} [options]" >&2
  exit 64
fi
shift

display_number=1
input_a=15
input_b=25
keyfob_volume_uuid=""
blueutil_binary="/opt/homebrew/bin/blueutil"
m1ddc_binary="/opt/homebrew/bin/m1ddc"
connect_attempts=5
devices=()

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
    --blueutil)
      blueutil_binary="${2:?missing value for --blueutil}"
      shift 2
      ;;
    --m1ddc)
      m1ddc_binary="${2:?missing value for --m1ddc}"
      shift 2
      ;;
    --connect-attempts)
      connect_attempts="${2:?missing value for --connect-attempts}"
      shift 2
      ;;
    --device)
      devices+=("${2:?missing value for --device}")
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 64
      ;;
  esac
done

if [[ "$action" != "switch" && "$action" != "connect" ]]; then
  echo "Unknown action: $action" >&2
  exit 64
fi

if ((${#devices[@]} > 0)) && [[ ! -x "$blueutil_binary" ]]; then
  echo "blueutil is required at $blueutil_binary; install it with: brew install blueutil" >&2
  exit 69
fi

bluetooth_state() {
  local address="$1"
  local state

  if ! state=$("$blueutil_binary" --is-connected "$address"); then
    return 1
  fi
  printf '%s' "$state"
}

connect_device() {
  local address="$1"
  local attempt state

  for ((attempt = 1; attempt <= connect_attempts; attempt++)); do
    state=$(bluetooth_state "$address") || return 1
    if [[ "$state" == "1" ]]; then
      return 0
    fi

    "$blueutil_binary" --connect "$address" >/dev/null || true
    /bin/sleep 0.75
  done

  state=$(bluetooth_state "$address") || return 1
  [[ "$state" == "1" ]]
}

connect_devices() {
  local address
  local failed=()

  for address in "${devices[@]}"; do
    if ! connect_device "$address"; then
      failed+=("$address")
    fi
  done

  if ((${#failed[@]} > 0)); then
    echo "Could not connect Bluetooth device(s): ${failed[*]}" >&2
    return 1
  fi

  echo "Magic Trackpad and Mouse are connected to this Mac."
}

disconnect_devices() {
  local address state check
  local disconnected=()

  for address in "${devices[@]}"; do
    state=$(bluetooth_state "$address") || {
      echo "Could not read Bluetooth state for $address; monitor input was not changed." >&2
      connect_addresses "${disconnected[@]}" >/dev/null 2>&1 || true
      return 1
    }

    if [[ "$state" != "1" ]]; then
      continue
    fi

    if ! "$blueutil_binary" --disconnect "$address" >/dev/null 2>&1; then
      echo "Could not disconnect Bluetooth device $address; monitor input was not changed." >&2
      connect_addresses "${disconnected[@]}" >/dev/null 2>&1 || true
      return 1
    fi

    for _ in {1..10}; do
      check=$(bluetooth_state "$address") || check="unknown"
      [[ "$check" == "0" ]] && break
      /bin/sleep 0.2
    done

    if [[ "$check" != "0" ]]; then
      echo "Bluetooth device $address did not disconnect; monitor input was not changed." >&2
      connect_addresses "${disconnected[@]}" >/dev/null 2>&1 || true
      return 1
    fi
    disconnected+=("$address")
  done
}

connect_addresses() {
  local address
  local saved_devices=("${devices[@]}")
  devices=("$@")
  connect_devices
  local status=$?
  devices=("${saved_devices[@]}")
  return "$status"
}

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

if [[ "$action" == "connect" ]]; then
  connect_devices
  exit $?
fi

if [[ ! -x "$m1ddc_binary" ]]; then
  echo "m1ddc is required at $m1ddc_binary." >&2
  exit 69
fi

current_output=$("$m1ddc_binary" display "$display_number" get input 2>/dev/null) || {
  echo "Could not read the Dell monitor input; nothing was disconnected or switched." >&2
  exit 1
}

if [[ "$current_output" =~ ([0-9]+) ]]; then
  current_input="${BASH_REMATCH[1]}"
else
  echo "Dell monitor input was unreadable: $current_output" >&2
  exit 1
fi

case "$current_input" in
  "$input_a") target_input="$input_b" ;;
  "$input_b") target_input="$input_a" ;;
  *)
    echo "Dell monitor input $current_input is not configured ($input_a or $input_b); nothing was changed." >&2
    exit 1
    ;;
esac

eject_keyfob_if_mounted || exit 1
disconnect_devices || exit 1

if ! "$m1ddc_binary" display "$display_number" set input "$target_input"; then
  connect_devices >/dev/null 2>&1 || true
  echo "Dell input switch failed; attempted to reconnect the Trackpad and Mouse to this Mac." >&2
  exit 1
fi

echo "Dell input switched from $current_input to $target_input; the displayed Mac will claim the Trackpad and Mouse."
