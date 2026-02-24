#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

print_usage() {
  cat <<EOF
Usage:
  ${SCRIPT_NAME} focus [--wait SECONDS]
  ${SCRIPT_NAME} new-message [--wait SECONDS]
  ${SCRIPT_NAME} compose --to EMAILS [--subject TEXT] [--body TEXT] [--send] [--focus-wait SECONDS] [--compose-wait SECONDS] [--step-wait SECONDS] [--pre-to-tabs N]
  ${SCRIPT_NAME} compose-ax --to EMAILS [--subject TEXT] [--body TEXT] [--send] [--send-mode METHOD] [--focus-wait SECONDS] [--compose-wait SECONDS] [--step-wait SECONDS]
  ${SCRIPT_NAME} send-current [--wait SECONDS] [--method METHOD]
  ${SCRIPT_NAME} search --query TEXT [--wait SECONDS]
  ${SCRIPT_NAME} help

Notes:
  - Requires Microsoft Outlook on macOS.
  - Requires Accessibility permissions for the calling terminal/agent.
  - Uses GUI keyboard automation; keep Outlook in foreground while running.
  - In current Outlook compose windows, focus starts in To:. Default --pre-to-tabs is 0.
  - METHOD options: keystroke (Cmd+Return) or button (AX click on Send).
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

require_hs_cli() {
  local hs_bin="${HS_BIN:-$(command -v hs || true)}"
  if [[ -z "${hs_bin}" ]]; then
    echo "hs CLI not found. Install/enable Hammerspoon CLI first." >&2
    exit 1
  fi
  echo "${hs_bin}"
}

lua_quote() {
  local value="${1:-}"
  value="${value//\\/\\\\}"
  value="${value//\'/\\\'}"
  value="${value//$'\n'/\\n}"
  printf "'%s'" "$value"
}

action_focus() {
  local wait_seconds="${1:-0.3}"
  osascript - "$wait_seconds" <<'APPLESCRIPT'
on run argv
  set waitSeconds to (item 1 of argv) as real
  tell application "Microsoft Outlook" to activate
  delay waitSeconds
end run
APPLESCRIPT
}

action_new_message() {
  local wait_seconds="${1:-0.7}"
  osascript - "$wait_seconds" <<'APPLESCRIPT'
on run argv
  set waitSeconds to (item 1 of argv) as real
  tell application "Microsoft Outlook" to activate
  delay 0.2

  tell application "System Events"
    tell process "Microsoft Outlook"
      keystroke "n" using command down
    end tell
  end tell

  delay waitSeconds
end run
APPLESCRIPT
}

action_compose() {
  local to_value="$1"
  local subject_value="$2"
  local body_value="$3"
  local send_now="$4"
  local focus_wait="$5"
  local compose_wait="$6"
  local step_wait="$7"
  local pre_to_tabs="$8"

  osascript - "$to_value" "$subject_value" "$body_value" "$send_now" "$focus_wait" "$compose_wait" "$step_wait" "$pre_to_tabs" <<'APPLESCRIPT'
on pasteFromClipboard(textValue, settleDelay)
  set the clipboard to textValue
  tell application "System Events" to keystroke "v" using command down
  delay settleDelay
end pasteFromClipboard

on run argv
  set toValue to item 1 of argv
  set subjectValue to item 2 of argv
  set bodyValue to item 3 of argv
  set sendNow to ((item 4 of argv) is "true")
  set focusWait to (item 5 of argv) as real
  set composeWait to (item 6 of argv) as real
  set stepWait to (item 7 of argv) as real
  set preToTabs to (item 8 of argv) as integer

  tell application "Microsoft Outlook" to activate
  delay focusWait

  tell application "System Events"
    if not (exists process "Microsoft Outlook") then
      error "Outlook process is not available to System Events."
    end if

    tell process "Microsoft Outlook"
      keystroke "n" using command down
      delay composeWait

      repeat preToTabs times
        key code 48
        delay stepWait
      end repeat

      my pasteFromClipboard(toValue, stepWait)
      key code 48
      delay stepWait

      if (length of subjectValue) > 0 then
        my pasteFromClipboard(subjectValue, stepWait)
      end if

      if (length of bodyValue) > 0 then
        key code 48
        delay stepWait
        my pasteFromClipboard(bodyValue, stepWait)
      end if

      if sendNow then
        key code 36 using command down
      end if
    end tell
  end tell
end run
APPLESCRIPT
}

action_send_current() {
  local wait_seconds="${1:-0.2}"
  osascript - "$wait_seconds" <<'APPLESCRIPT'
on run argv
  set waitSeconds to (item 1 of argv) as real
  tell application "Microsoft Outlook" to activate
  delay waitSeconds

  tell application "System Events"
    tell process "Microsoft Outlook"
      key code 36 using command down
    end tell
  end tell
end run
APPLESCRIPT
}

action_send_current_ax() {
  local send_mode="$1"
  local hs_bin
  hs_bin="$(require_hs_cli)"
  local send_mode_lua
  send_mode_lua="$(lua_quote "${send_mode}")"

  "${hs_bin}" -c "if not OutlookAX then print('OutlookAX module not loaded. Reload Hammerspoon config first.'); return end; OutlookAX.sendCurrent(${send_mode_lua})"
}

action_search() {
  local query="$1"
  local wait_seconds="${2:-0.2}"
  osascript - "$query" "$wait_seconds" <<'APPLESCRIPT'
on run argv
  set queryValue to item 1 of argv
  set waitSeconds to (item 2 of argv) as real

  tell application "Microsoft Outlook" to activate
  delay waitSeconds

  tell application "System Events"
    tell process "Microsoft Outlook"
      keystroke "e" using command down
      delay 0.1
      set the clipboard to queryValue
      keystroke "v" using command down
      delay 0.05
      key code 36
    end tell
  end tell
end run
APPLESCRIPT
}

action_compose_ax() {
  local to_value="$1"
  local subject_value="$2"
  local body_value="$3"
  local send_now="$4"
  local send_mode="$5"
  local focus_wait="$6"
  local compose_wait="$7"
  local step_wait="$8"
  local hs_bin
  hs_bin="$(require_hs_cli)"
  local to_lua
  local subject_lua
  local body_lua
  local send_now_lua
  local send_mode_lua
  to_lua="$(lua_quote "${to_value}")"
  subject_lua="$(lua_quote "${subject_value}")"
  body_lua="$(lua_quote "${body_value}")"
  send_now_lua="$(lua_quote "${send_now}")"
  send_mode_lua="$(lua_quote "${send_mode}")"

  "${hs_bin}" -c "if not OutlookAX then print('OutlookAX module not loaded. Reload Hammerspoon config first.'); return end; OutlookAX.compose({to=${to_lua}, subject=${subject_lua}, body=${body_lua}, sendNow=(${send_now_lua}=='true'), sendMode=${send_mode_lua}, focusWait=tonumber('${focus_wait}'), composeWait=tonumber('${compose_wait}'), stepWait=tonumber('${step_wait}')})"
}

main() {
  if [[ $# -eq 0 ]]; then
    print_usage
    exit 1
  fi

  local cmd="$1"
  shift

  case "$cmd" in
    help|-h|--help)
      print_usage
      ;;
    focus)
      local wait_seconds="0.3"
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --wait)
            require_value "$1" "${2:-}"
            wait_seconds="$2"
            shift 2
            ;;
          *)
            echo "Unknown option for focus: $1" >&2
            exit 1
            ;;
        esac
      done
      action_focus "$wait_seconds"
      ;;
    new-message)
      local wait_seconds="0.7"
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --wait)
            require_value "$1" "${2:-}"
            wait_seconds="$2"
            shift 2
            ;;
          *)
            echo "Unknown option for new-message: $1" >&2
            exit 1
            ;;
        esac
      done
      action_new_message "$wait_seconds"
      ;;
    compose)
      local to_value=""
      local subject_value=""
      local body_value=""
      local send_now="false"
      local focus_wait="0.2"
      local compose_wait="0.7"
      local step_wait="0.12"
      local pre_to_tabs="0"

      while [[ $# -gt 0 ]]; do
        case "$1" in
          --to)
            require_value "$1" "${2:-}"
            to_value="$2"
            shift 2
            ;;
          --subject)
            require_value "$1" "${2:-}"
            subject_value="$2"
            shift 2
            ;;
          --body)
            require_value "$1" "${2:-}"
            body_value="$2"
            shift 2
            ;;
          --send)
            send_now="true"
            shift
            ;;
          --focus-wait)
            require_value "$1" "${2:-}"
            focus_wait="$2"
            shift 2
            ;;
          --compose-wait)
            require_value "$1" "${2:-}"
            compose_wait="$2"
            shift 2
            ;;
          --step-wait)
            require_value "$1" "${2:-}"
            step_wait="$2"
            shift 2
            ;;
          --pre-to-tabs)
            require_value "$1" "${2:-}"
            pre_to_tabs="$2"
            shift 2
            ;;
          *)
            echo "Unknown option for compose: $1" >&2
            exit 1
            ;;
        esac
      done

      if [[ -z "$to_value" ]]; then
        echo "--to is required for compose" >&2
        exit 1
      fi

      action_compose "$to_value" "$subject_value" "$body_value" "$send_now" "$focus_wait" "$compose_wait" "$step_wait" "$pre_to_tabs"
      ;;
    compose-ax)
      local to_value=""
      local subject_value=""
      local body_value=""
      local send_now="false"
      local send_mode="keystroke"
      local focus_wait="0.2"
      local compose_wait="0.9"
      local step_wait="0.12"

      while [[ $# -gt 0 ]]; do
        case "$1" in
          --to)
            require_value "$1" "${2:-}"
            to_value="$2"
            shift 2
            ;;
          --subject)
            require_value "$1" "${2:-}"
            subject_value="$2"
            shift 2
            ;;
          --body)
            require_value "$1" "${2:-}"
            body_value="$2"
            shift 2
            ;;
          --send)
            send_now="true"
            shift
            ;;
          --send-mode)
            require_value "$1" "${2:-}"
            send_mode="$2"
            shift 2
            ;;
          --focus-wait)
            require_value "$1" "${2:-}"
            focus_wait="$2"
            shift 2
            ;;
          --compose-wait)
            require_value "$1" "${2:-}"
            compose_wait="$2"
            shift 2
            ;;
          --step-wait)
            require_value "$1" "${2:-}"
            step_wait="$2"
            shift 2
            ;;
          *)
            echo "Unknown option for compose-ax: $1" >&2
            exit 1
            ;;
        esac
      done

      if [[ -z "$to_value" ]]; then
        echo "--to is required for compose-ax" >&2
        exit 1
      fi

      if [[ "$send_mode" != "keystroke" && "$send_mode" != "button" ]]; then
        echo "--send-mode must be 'keystroke' or 'button'" >&2
        exit 1
      fi

      action_compose_ax "$to_value" "$subject_value" "$body_value" "$send_now" "$send_mode" "$focus_wait" "$compose_wait" "$step_wait"
      ;;
    send-current)
      local wait_seconds="0.2"
      local send_method="keystroke"
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --wait)
            require_value "$1" "${2:-}"
            wait_seconds="$2"
            shift 2
            ;;
          --method)
            require_value "$1" "${2:-}"
            send_method="$2"
            shift 2
            ;;
          *)
            echo "Unknown option for send-current: $1" >&2
            exit 1
            ;;
        esac
      done

      if [[ "$send_method" != "keystroke" && "$send_method" != "button" ]]; then
        echo "--method must be 'keystroke' or 'button'" >&2
        exit 1
      fi

      action_focus "$wait_seconds"
      if [[ "$send_method" == "button" ]]; then
        action_send_current_ax "button"
      else
        action_send_current "0"
      fi
      ;;
    search)
      local query=""
      local wait_seconds="0.2"
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --query)
            require_value "$1" "${2:-}"
            query="$2"
            shift 2
            ;;
          --wait)
            require_value "$1" "${2:-}"
            wait_seconds="$2"
            shift 2
            ;;
          *)
            echo "Unknown option for search: $1" >&2
            exit 1
            ;;
        esac
      done

      if [[ -z "$query" ]]; then
        echo "--query is required for search" >&2
        exit 1
      fi

      action_search "$query" "$wait_seconds"
      ;;
    *)
      echo "Unknown command: $cmd" >&2
      print_usage
      exit 1
      ;;
  esac
}

main "$@"
