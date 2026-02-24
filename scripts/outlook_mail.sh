#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
US=$'\x1f'

print_usage() {
  cat <<EOF
Usage:
  ${SCRIPT_NAME} search [--folder NAME] [--topic TEXT|--query TEXT] [--from TEXT] [--to TEXT] [--unread] [--limit N] [--scan-limit N] [--scope SCOPE] [--work-hosts CSV]
  ${SCRIPT_NAME} read --id ID [--folder NAME] [--scope SCOPE] [--work-hosts CSV]
  ${SCRIPT_NAME} summarize --id ID [--folder NAME] [--scope SCOPE] [--work-hosts CSV]
  ${SCRIPT_NAME} prioritize [--folder NAME] [--topic TEXT|--query TEXT] [--from TEXT] [--to TEXT] [--unread] [--top N] [--scan-limit N] [--vip CSV] [--scope SCOPE] [--work-hosts CSV]
  ${SCRIPT_NAME} help

Notes:
  - Uses Outlook AppleScript model (no Graph API required).
  - Folder shortcuts: inbox, sent, drafts, deleted, junk, outbox.
  - Scope defaults to "work". Configure OUTLOOK_WORK_HOSTS=host1,host2 or pass --work-hosts.
  - Use --scope any to bypass host scoping for testing.
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

normalize_host() {
  local raw="${1:-}"
  local lower
  lower="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  printf '%s' "$lower" | sed -E 's/[^a-z0-9]+/_/g; s/^_+//; s/_+$//'
}

contains_csv_value() {
  local needle="${1:-}"
  local csv="${2:-}"
  local item=""
  IFS=',' read -r -a __items <<<"$csv"
  for item in "${__items[@]}"; do
    item="$(normalize_host "$item")"
    if [[ -n "$item" && "$item" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

current_host_normalized() {
  local host_raw=""
  host_raw="$(scutil --get LocalHostName 2>/dev/null || true)"
  if [[ -z "$host_raw" ]]; then
    host_raw="$(hostname 2>/dev/null || true)"
  fi
  normalize_host "$host_raw"
}

enforce_scope() {
  local scope="${1:-work}"
  local work_hosts="${2:-${OUTLOOK_WORK_HOSTS:-}}"
  local current_host
  current_host="$(current_host_normalized)"

  if [[ "$scope" == "any" ]]; then
    return 0
  fi

  if [[ "$scope" != "work" ]]; then
    echo "Unsupported --scope '$scope'. Use work or any." >&2
    exit 1
  fi

  if [[ -z "$work_hosts" ]]; then
    echo "[scope] OUTLOOK_WORK_HOSTS not set; proceeding on host '${current_host}'." >&2
    return 0
  fi

  if ! contains_csv_value "$current_host" "$work_hosts"; then
    echo "[scope] Host '${current_host}' is not in OUTLOOK_WORK_HOSTS/--work-hosts allowlist." >&2
    exit 1
  fi
}

resolve_folder_key() {
  local folder="${1:-inbox}"
  local lower
  lower="$(printf '%s' "$folder" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    inbox|sent|drafts|deleted|junk|outbox)
      printf '%s' "$lower"
      ;;
    *)
      printf '%s' "$folder"
      ;;
  esac
}

shorten() {
  local text="${1:-}"
  local max_len="${2:-40}"
  if (( ${#text} <= max_len )); then
    printf '%s' "$text"
    return
  fi
  printf '%s...' "${text:0:max_len-3}"
}

to_lower() {
  printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'
}

fetch_messages() {
  local folder_key="$1"
  local query="$2"
  local from_filter="$3"
  local to_filter="$4"
  local unread_only="$5"
  local limit="$6"
  local scan_limit="$7"

  osascript - "$folder_key" "$query" "$from_filter" "$to_filter" "$unread_only" "$limit" "$scan_limit" <<'APPLESCRIPT'
on replaceText(findText, replaceValue, sourceText)
  set AppleScript's text item delimiters to findText
  set chunks to text items of sourceText
  set AppleScript's text item delimiters to replaceValue
  set replacedText to chunks as text
  set AppleScript's text item delimiters to ""
  return replacedText
end replaceText

on normalizeText(valueText)
  if valueText is missing value then return ""
  set t to valueText as text
  set t to my replaceText(return, " ", t)
  set t to my replaceText(linefeed, " ", t)
  set t to my replaceText(tab, " ", t)
  set t to my replaceText((ASCII character 31), " ", t)
  return t
end normalizeText

on joinList(theList, delimiterText)
  set AppleScript's text item delimiters to delimiterText
  set outText to theList as text
  set AppleScript's text item delimiters to ""
  return outText
end joinList

on recipientAddressList(recList)
  set outList to {}
  repeat with rec in recList
    set addrText to ""
    try
      set addrText to address of rec
    on error
      try
        set addrRecord to |email address| of rec
        set addrText to address of addrRecord
      on error
        set addrText to ""
      end try
    end try
    if addrText is not "" then set end of outList to (my normalizeText(addrText))
  end repeat
  return my joinList(outList, ",")
end recipientAddressList

on boolText(v)
  if v as boolean then
    return "true"
  end if
  return "false"
end boolText

on folderFromKey(folderKey)
  tell application "Microsoft Outlook"
    if folderKey is "inbox" then return inbox
    if folderKey is "sent" then return sent items
    if folderKey is "drafts" then return drafts
    if folderKey is "deleted" then return deleted items
    if folderKey is "junk" then return junk mail
    if folderKey is "outbox" then return outbox

    set matches to (every mail folder whose name is folderKey)
    if (count of matches) = 0 then
      error "Unknown folder: " & folderKey
    end if
    return item 1 of matches
  end tell
end folderFromKey

on run argv
  set folderKey to item 1 of argv
  set queryFilter to item 2 of argv
  set fromFilter to item 3 of argv
  set toFilter to item 4 of argv
  set unreadOnlyText to item 5 of argv
  set resultLimit to (item 6 of argv) as integer
  set scanLimit to (item 7 of argv) as integer
  set unreadOnly to (unreadOnlyText is "true")

  if resultLimit < 1 then set resultLimit to 1
  if scanLimit < resultLimit then set scanLimit to resultLimit

  tell application "Microsoft Outlook"
    set targetFolder to my folderFromKey(folderKey)
    set folderName to my normalizeText(name of targetFolder)
    set allMsgs to messages of targetFolder
    set totalCount to count of allMsgs
    set maxScan to scanLimit
    if maxScan > totalCount then set maxScan to totalCount
    set outLines to {}

    repeat with i from 1 to maxScan
      set m to item i of allMsgs
      set subjectText to ""
      set senderAddressText to ""
      set senderNameText to ""
      set toRecipientsText to ""
      set ccRecipientsText to ""
      set receivedText to ""
      set sentText to ""
      set isReadText to "false"
      set priorityText to ""
      set bodySnippet to ""

      try
        set subjectText to my normalizeText(subject of m)
      end try
      try
        set senderAddressText to my normalizeText(address of sender of m)
      end try
      try
        set senderNameText to my normalizeText(name of sender of m)
      end try
      try
        set toRecipientsText to my recipientAddressList(to recipients of m)
      end try
      try
        set ccRecipientsText to my recipientAddressList(cc recipients of m)
      end try
      try
        set receivedText to my normalizeText((time received of m) as text)
      end try
      try
        set sentText to my normalizeText((time sent of m) as text)
      end try
      try
        set isReadText to my boolText(is read of m)
      end try
      try
        set priorityText to my normalizeText((priority of m) as text)
      end try
      try
        set plainBody to plain text content of m
        if plainBody is not missing value then
          if (length of plainBody) > 700 then
            set bodySnippet to my normalizeText(text 1 thru 700 of plainBody)
          else
            set bodySnippet to my normalizeText(plainBody)
          end if
        end if
      end try

      set includeItem to true
      ignoring case
        if queryFilter is not "" then
          if subjectText does not contain queryFilter and bodySnippet does not contain queryFilter then set includeItem to false
        end if
        if includeItem and fromFilter is not "" then
          if senderAddressText does not contain fromFilter and senderNameText does not contain fromFilter then set includeItem to false
        end if
        if includeItem and toFilter is not "" then
          if toRecipientsText does not contain toFilter and ccRecipientsText does not contain toFilter then set includeItem to false
        end if
      end ignoring

      if includeItem and unreadOnly then
        if isReadText is "true" then set includeItem to false
      end if

      if includeItem then
        set messageIdText to ""
        try
          set messageIdText to (id of m) as text
        on error
          set messageIdText to ""
        end try

        set rowFields to {messageIdText, folderName, subjectText, senderNameText, senderAddressText, toRecipientsText, ccRecipientsText, receivedText, sentText, isReadText, priorityText, bodySnippet}
        set end of outLines to my joinList(rowFields, (ASCII character 31))
        if (count of outLines) >= resultLimit then exit repeat
      end if
    end repeat

    return my joinList(outLines, linefeed)
  end tell
end run
APPLESCRIPT
}

fetch_message_by_id() {
  local message_id="$1"
  local folder_key="$2"

  osascript - "$message_id" "$folder_key" <<'APPLESCRIPT'
on replaceText(findText, replaceValue, sourceText)
  set AppleScript's text item delimiters to findText
  set chunks to text items of sourceText
  set AppleScript's text item delimiters to replaceValue
  set replacedText to chunks as text
  set AppleScript's text item delimiters to ""
  return replacedText
end replaceText

on normalizeText(valueText)
  if valueText is missing value then return ""
  set t to valueText as text
  set t to my replaceText(return, " ", t)
  set t to my replaceText(linefeed, " ", t)
  set t to my replaceText(tab, " ", t)
  set t to my replaceText((ASCII character 31), " ", t)
  return t
end normalizeText

on joinList(theList, delimiterText)
  set AppleScript's text item delimiters to delimiterText
  set outText to theList as text
  set AppleScript's text item delimiters to ""
  return outText
end joinList

on recipientAddressList(recList)
  set outList to {}
  repeat with rec in recList
    set addrText to ""
    try
      set addrText to address of rec
    on error
      try
        set addrRecord to |email address| of rec
        set addrText to address of addrRecord
      on error
        set addrText to ""
      end try
    end try
    if addrText is not "" then set end of outList to (my normalizeText(addrText))
  end repeat
  return my joinList(outList, ",")
end recipientAddressList

on folderFromKey(folderKey)
  tell application "Microsoft Outlook"
    if folderKey is "" then return missing value
    if folderKey is "inbox" then return inbox
    if folderKey is "sent" then return sent items
    if folderKey is "drafts" then return drafts
    if folderKey is "deleted" then return deleted items
    if folderKey is "junk" then return junk mail
    if folderKey is "outbox" then return outbox
    set matches to (every mail folder whose name is folderKey)
    if (count of matches) = 0 then return missing value
    return item 1 of matches
  end tell
end folderFromKey

on boolText(v)
  if v as boolean then
    return "true"
  end if
  return "false"
end boolText

on run argv
  set msgId to (item 1 of argv) as integer
  set folderKey to item 2 of argv

  tell application "Microsoft Outlook"
    set msgRef to missing value
    if folderKey is not "" then
      set f to my folderFromKey(folderKey)
      if f is not missing value then
        set candidates to (every message of f whose id is msgId)
        if (count of candidates) > 0 then set msgRef to item 1 of candidates
      end if
    end if

    if msgRef is missing value then
      set globalCandidates to (every message whose id is msgId)
      if (count of globalCandidates) = 0 then
        error "Message id not found: " & (msgId as text)
      end if
      set msgRef to item 1 of globalCandidates
    end if

    set folderName to ""
    set subjectText to ""
    set senderAddressText to ""
    set senderNameText to ""
    set toRecipientsText to ""
    set ccRecipientsText to ""
    set receivedText to ""
    set sentText to ""
    set isReadText to "false"
    set priorityText to ""
    set snippetText to ""
    set bodyText to ""

    try
      set folderName to my normalizeText(name of folder of msgRef)
    end try
    try
      set subjectText to my normalizeText(subject of msgRef)
    end try
    try
      set senderAddressText to my normalizeText(address of sender of msgRef)
    end try
    try
      set senderNameText to my normalizeText(name of sender of msgRef)
    end try
    try
      set toRecipientsText to my recipientAddressList(to recipients of msgRef)
    end try
    try
      set ccRecipientsText to my recipientAddressList(cc recipients of msgRef)
    end try
    try
      set receivedText to my normalizeText((time received of msgRef) as text)
    end try
    try
      set sentText to my normalizeText((time sent of msgRef) as text)
    end try
    try
      set isReadText to my boolText(is read of msgRef)
    end try
    try
      set priorityText to my normalizeText((priority of msgRef) as text)
    end try
    try
      set rawBody to plain text content of msgRef
      if rawBody is not missing value then
        set bodyText to my normalizeText(rawBody)
        if (length of bodyText) > 800 then
          set snippetText to text 1 thru 800 of bodyText
        else
          set snippetText to bodyText
        end if
      end if
    end try

    if (length of bodyText) > 6000 then
      set bodyText to text 1 thru 6000 of bodyText
    end if

    set rowFields to {(id of msgRef) as text, folderName, subjectText, senderNameText, senderAddressText, toRecipientsText, ccRecipientsText, receivedText, sentText, isReadText, priorityText, snippetText, bodyText}
    return my joinList(rowFields, (ASCII character 31))
  end tell
end run
APPLESCRIPT
}

print_search_table() {
  local raw="$1"
  local line=""
  local count=0
  printf "%-10s %-5s %-20s %-20s %-10s %-18s %s\n" "ID" "READ" "FROM" "SUBJECT" "PRIORITY" "FOLDER" "RECEIVED/SENT"
  printf "%-10s %-5s %-20s %-20s %-10s %-18s %s\n" "----------" "-----" "--------------------" "--------------------" "----------" "------------------" "------------------------------"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    IFS="$US" read -r id folder subject sender_name sender_addr to_list cc_list received sent is_read priority snippet <<<"$line"
    count=$((count + 1))
    local from_display="$sender_addr"
    if [[ -z "$from_display" ]]; then
      from_display="$sender_name"
    fi
    local when_display="$received"
    if [[ -z "$when_display" ]]; then
      when_display="$sent"
    fi
    printf "%-10s %-5s %-20s %-20s %-10s %-18s %s\n" \
      "$(shorten "$id" 10)" \
      "$([[ "$is_read" == "true" ]] && printf 'yes' || printf 'no')" \
      "$(shorten "$from_display" 20)" \
      "$(shorten "$subject" 20)" \
      "$(shorten "$priority" 10)" \
      "$(shorten "$folder" 18)" \
      "$(shorten "$when_display" 30)"
  done <<<"$raw"

  if (( count == 0 )); then
    echo "(no matching messages)"
  fi
}

print_message_detail() {
  local raw="$1"
  IFS="$US" read -r id folder subject sender_name sender_addr to_list cc_list received sent is_read priority snippet body <<<"$raw"
  echo "ID: ${id}"
  echo "Folder: ${folder}"
  echo "Subject: ${subject}"
  echo "From: ${sender_name} <${sender_addr}>"
  echo "To: ${to_list}"
  echo "Cc: ${cc_list}"
  echo "Received: ${received}"
  echo "Sent: ${sent}"
  echo "Read: ${is_read}"
  echo "Priority: ${priority}"
  echo
  echo "Body Preview:"
  echo "${body:-${snippet}}"
}

keyword_match_bonus() {
  local text_lc="$1"
  local bonus=0
  local kw
  for kw in "urgent" "asap" "critical" "action required" "today" "eod" "incident" "outage" "sev1" "sev 1" "deadline"; do
    if [[ "$text_lc" == *"$kw"* ]]; then
      bonus=$((bonus + 10))
    fi
  done
  printf '%s' "$bonus"
}

compute_priority_score() {
  local subject="$1"
  local snippet="$2"
  local sender="$3"
  local to_list="$4"
  local is_read="$5"
  local priority="$6"
  local vip_csv="$7"

  local score=0
  local reason=()
  local subject_lc snippet_lc sender_lc priority_lc all_lc
  subject_lc="$(to_lower "$subject")"
  snippet_lc="$(to_lower "$snippet")"
  sender_lc="$(to_lower "$sender")"
  priority_lc="$(to_lower "$priority")"
  all_lc="${subject_lc} ${snippet_lc}"

  if [[ "$is_read" != "true" ]]; then
    score=$((score + 20))
    reason+=("unread")
  fi

  if [[ "$priority_lc" == *"high"* ]]; then
    score=$((score + 20))
    reason+=("high-priority-flag")
  elif [[ "$priority_lc" == *"low"* ]]; then
    score=$((score - 5))
    reason+=("low-priority-flag")
  fi

  local vip
  IFS=',' read -r -a __vip_items <<<"$vip_csv"
  for vip in "${__vip_items[@]}"; do
    vip="$(to_lower "$vip")"
    [[ -z "$vip" ]] && continue
    if [[ "$sender_lc" == *"$vip"* ]]; then
      score=$((score + 35))
      reason+=("vip-sender")
      break
    fi
  done

  local kw_bonus
  kw_bonus="$(keyword_match_bonus "$all_lc")"
  if (( kw_bonus > 0 )); then
    score=$((score + kw_bonus))
    reason+=("urgency-keywords")
  fi

  if [[ "$sender_lc" == *"no-reply"* || "$sender_lc" == *"noreply"* || "$sender_lc" == *"newsletter"* ]]; then
    score=$((score - 20))
    reason+=("likely-bulk")
  fi

  if [[ "$to_list" == *","* ]]; then
    score=$((score - 5))
    reason+=("many-recipients")
  fi

  local reasons_joined
  reasons_joined="$(IFS=','; echo "${reason[*]}")"
  printf '%s\t%s' "$score" "$reasons_joined"
}

priority_bucket() {
  local score="$1"
  if (( score >= 55 )); then
    printf 'P1'
  elif (( score >= 30 )); then
    printf 'P2'
  else
    printf 'P3'
  fi
}

cmd_search() {
  local folder="inbox"
  local query=""
  local from_filter=""
  local to_filter=""
  local unread_only="false"
  local limit="25"
  local scan_limit="300"
  local scope="work"
  local work_hosts="${OUTLOOK_WORK_HOSTS:-}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --folder)
        require_value "$1" "${2:-}"
        folder="$2"
        shift 2
        ;;
      --query|--topic)
        require_value "$1" "${2:-}"
        query="$2"
        shift 2
        ;;
      --from)
        require_value "$1" "${2:-}"
        from_filter="$2"
        shift 2
        ;;
      --to)
        require_value "$1" "${2:-}"
        to_filter="$2"
        shift 2
        ;;
      --unread)
        unread_only="true"
        shift
        ;;
      --limit)
        require_value "$1" "${2:-}"
        limit="$2"
        shift 2
        ;;
      --scan-limit)
        require_value "$1" "${2:-}"
        scan_limit="$2"
        shift 2
        ;;
      --scope)
        require_value "$1" "${2:-}"
        scope="$2"
        shift 2
        ;;
      --work-hosts)
        require_value "$1" "${2:-}"
        work_hosts="$2"
        shift 2
        ;;
      *)
        echo "Unknown option for search: $1" >&2
        exit 1
        ;;
    esac
  done

  enforce_scope "$scope" "$work_hosts"
  local folder_key
  folder_key="$(resolve_folder_key "$folder")"

  local raw
  raw="$(fetch_messages "$folder_key" "$query" "$from_filter" "$to_filter" "$unread_only" "$limit" "$scan_limit")"
  print_search_table "$raw"
}

cmd_read() {
  local msg_id=""
  local folder=""
  local scope="work"
  local work_hosts="${OUTLOOK_WORK_HOSTS:-}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id)
        require_value "$1" "${2:-}"
        msg_id="$2"
        shift 2
        ;;
      --folder)
        require_value "$1" "${2:-}"
        folder="$2"
        shift 2
        ;;
      --scope)
        require_value "$1" "${2:-}"
        scope="$2"
        shift 2
        ;;
      --work-hosts)
        require_value "$1" "${2:-}"
        work_hosts="$2"
        shift 2
        ;;
      *)
        echo "Unknown option for read: $1" >&2
        exit 1
        ;;
    esac
  done

  if [[ -z "$msg_id" ]]; then
    echo "--id is required for read" >&2
    exit 1
  fi

  enforce_scope "$scope" "$work_hosts"
  local folder_key
  folder_key="$(resolve_folder_key "$folder")"
  local raw
  raw="$(fetch_message_by_id "$msg_id" "$folder_key")"
  print_message_detail "$raw"
}

cmd_summarize() {
  local msg_id=""
  local folder=""
  local scope="work"
  local work_hosts="${OUTLOOK_WORK_HOSTS:-}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id)
        require_value "$1" "${2:-}"
        msg_id="$2"
        shift 2
        ;;
      --folder)
        require_value "$1" "${2:-}"
        folder="$2"
        shift 2
        ;;
      --scope)
        require_value "$1" "${2:-}"
        scope="$2"
        shift 2
        ;;
      --work-hosts)
        require_value "$1" "${2:-}"
        work_hosts="$2"
        shift 2
        ;;
      *)
        echo "Unknown option for summarize: $1" >&2
        exit 1
        ;;
    esac
  done

  if [[ -z "$msg_id" ]]; then
    echo "--id is required for summarize" >&2
    exit 1
  fi

  enforce_scope "$scope" "$work_hosts"
  local folder_key
  folder_key="$(resolve_folder_key "$folder")"

  local raw
  raw="$(fetch_message_by_id "$msg_id" "$folder_key")"
  IFS="$US" read -r id folder_name subject sender_name sender_addr to_list cc_list received sent is_read priority snippet body <<<"$raw"

  local combined
  combined="$(to_lower "${subject} ${body}")"
  local suggested="P3"
  local why="routine"
  if [[ "$combined" == *"urgent"* || "$combined" == *"asap"* || "$combined" == *"critical"* || "$combined" == *"incident"* || "$combined" == *"outage"* ]]; then
    suggested="P1"
    why="urgency language detected"
  elif [[ "$is_read" != "true" || "$(to_lower "$priority")" == *"high"* ]]; then
    suggested="P2"
    why="unread and/or elevated priority"
  fi

  local action_hint="No explicit action phrase detected."
  if [[ "$combined" == *"please"* || "$combined" == *"can you"* || "$combined" == *"need you"* || "$combined" == *"action required"* ]]; then
    action_hint="Likely requests action from recipient."
  fi

  echo "Summary for message ${id}:"
  echo "- Subject: ${subject}"
  echo "- From: ${sender_name} <${sender_addr}>"
  echo "- Context: $(shorten "${snippet:-$body}" 260)"
  echo "- Action: ${action_hint}"
  echo "- Suggested priority: ${suggested} (${why})"
}

cmd_prioritize() {
  local folder="inbox"
  local query=""
  local from_filter=""
  local to_filter=""
  local unread_only="false"
  local top_n="15"
  local scan_limit="300"
  local vip_csv="${OUTLOOK_PRIORITY_VIPS:-}"
  local scope="work"
  local work_hosts="${OUTLOOK_WORK_HOSTS:-}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --folder)
        require_value "$1" "${2:-}"
        folder="$2"
        shift 2
        ;;
      --query|--topic)
        require_value "$1" "${2:-}"
        query="$2"
        shift 2
        ;;
      --from)
        require_value "$1" "${2:-}"
        from_filter="$2"
        shift 2
        ;;
      --to)
        require_value "$1" "${2:-}"
        to_filter="$2"
        shift 2
        ;;
      --unread)
        unread_only="true"
        shift
        ;;
      --top)
        require_value "$1" "${2:-}"
        top_n="$2"
        shift 2
        ;;
      --scan-limit)
        require_value "$1" "${2:-}"
        scan_limit="$2"
        shift 2
        ;;
      --vip)
        require_value "$1" "${2:-}"
        vip_csv="$2"
        shift 2
        ;;
      --scope)
        require_value "$1" "${2:-}"
        scope="$2"
        shift 2
        ;;
      --work-hosts)
        require_value "$1" "${2:-}"
        work_hosts="$2"
        shift 2
        ;;
      *)
        echo "Unknown option for prioritize: $1" >&2
        exit 1
        ;;
    esac
  done

  enforce_scope "$scope" "$work_hosts"
  local folder_key
  folder_key="$(resolve_folder_key "$folder")"

  local raw
  raw="$(fetch_messages "$folder_key" "$query" "$from_filter" "$to_filter" "$unread_only" "$top_n" "$scan_limit")"
  local scored_lines=()
  local line=""

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    IFS="$US" read -r id folder_name subject sender_name sender_addr to_list cc_list received sent is_read priority snippet <<<"$line"
    local sender_display="$sender_addr"
    [[ -z "$sender_display" ]] && sender_display="$sender_name"
    local score_reason
    score_reason="$(compute_priority_score "$subject" "$snippet" "$sender_display" "$to_list" "$is_read" "$priority" "$vip_csv")"
    local score="${score_reason%%$'\t'*}"
    local reasons="${score_reason#*$'\t'}"
    local bucket
    bucket="$(priority_bucket "$score")"
    scored_lines+=("${score}"$'\t'"${bucket}"$'\t'"${id}"$'\t'"${sender_display}"$'\t'"${subject}"$'\t'"${priority}"$'\t'"${reasons}")
  done <<<"$raw"

  if [[ ${#scored_lines[@]} -eq 0 ]]; then
    echo "(no matching messages to prioritize)"
    return 0
  fi

  printf "%-6s %-4s %-10s %-24s %-26s %-10s %s\n" "SCORE" "PRI" "ID" "FROM" "SUBJECT" "FLAG" "REASONS"
  printf "%-6s %-4s %-10s %-24s %-26s %-10s %s\n" "------" "----" "----------" "------------------------" "--------------------------" "----------" "------------------------------"
  printf '%s\n' "${scored_lines[@]}" | sort -t $'\t' -k1,1nr | while IFS=$'\t' read -r score bucket id sender_display subject priority reasons; do
    printf "%-6s %-4s %-10s %-24s %-26s %-10s %s\n" \
      "$score" \
      "$bucket" \
      "$(shorten "$id" 10)" \
      "$(shorten "$sender_display" 24)" \
      "$(shorten "$subject" 26)" \
      "$(shorten "$priority" 10)" \
      "$(shorten "$reasons" 30)"
  done
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
    search)
      cmd_search "$@"
      ;;
    read)
      cmd_read "$@"
      ;;
    summarize)
      cmd_summarize "$@"
      ;;
    prioritize)
      cmd_prioritize "$@"
      ;;
    *)
      echo "Unknown command: $cmd" >&2
      print_usage
      exit 1
      ;;
  esac
}

main "$@"
