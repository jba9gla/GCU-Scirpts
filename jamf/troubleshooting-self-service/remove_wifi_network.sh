#!/bin/bash
# Self Service: let a standard user remove a saved Wi-Fi network.
# Runs as root from Jamf; dialogs are shown in the logged-in user's session.
# Uses swiftDialog if installed, otherwise falls back to plain AppleScript dialogs.

# Networks users must NEVER be able to remove.
# Any SSID starting with a protected prefix is blocked (case-insensitive).
PROTECTED_PREFIXES=("NGCU_")
# Exact-match SSIDs that are also protected (none: users may remove eduroam).
PROTECTED=()

DIALOG="/usr/local/bin/dialog"
TITLE="Remove Wi-Fi Network"

is_protected() {
  local ssid_lc prefix_lc p
  ssid_lc=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  for prefix in "${PROTECTED_PREFIXES[@]}"; do
    prefix_lc=$(echo "$prefix" | tr '[:upper:]' '[:lower:]')
    [[ "$ssid_lc" == "$prefix_lc"* ]] && return 0
  done
  for p in "${PROTECTED[@]}"; do
    [ "$1" = "$p" ] && return 0
  done
  return 1
}

LOG="/var/log/remove_wifi_network.log"
log() { echo "$(date '+%F %T') $*" | tee -a "$LOG"; }

# Report back to Jamf Pro: stdout above lands in the policy log, and an inventory
# update on exit refreshes the extension attribute that reads this log.
JAMF="/usr/local/bin/jamf"
RECON=0
JSON_FILE=""
cleanup() {
  [ -n "$JSON_FILE" ] && rm -f "$JSON_FILE"
  [ "$RECON" -eq 1 ] && [ -x "$JAMF" ] && "$JAMF" recon >/dev/null 2>&1
}
trap cleanup EXIT

IFACE=$(/usr/sbin/networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2; exit}')
[ -z "$IFACE" ] && { log "No Wi-Fi interface found"; exit 1; }

CONSOLE_USER=$(/usr/bin/stat -f%Su /dev/console)
CONSOLE_UID=$(/usr/bin/id -u "$CONSOLE_USER")
[ "$CONSOLE_USER" = "root" ] && { log "No user logged in"; exit 1; }

run_as_user() { /bin/launchctl asuser "$CONSOLE_UID" /usr/bin/sudo -u "$CONSOLE_USER" "$@"; }

# show_message "message" "SF symbol" "osascript icon"
show_message() {
  if [ -x "$DIALOG" ]; then
    run_as_user "$DIALOG" --title "$TITLE" --message "$1" --icon "SF=$2" \
      --button1text "OK" --ontop --moveable >/dev/null 2>&1
  else
    run_as_user /usr/bin/osascript -e "display dialog \"${1//\"/\\\"}\" with title \"$TITLE\" buttons {\"OK\"} default button 1 with icon $3" >/dev/null 2>&1
  fi
}

# Saved networks, minus the header line and any protected SSIDs
NETWORKS=()
while IFS= read -r line; do
  ssid="$(echo "$line" | sed 's/^[[:space:]]*//')"
  [ -z "$ssid" ] && continue
  is_protected "$ssid" || NETWORKS+=("$ssid")
done < <(/usr/sbin/networksetup -listpreferredwirelessnetworks "$IFACE" | tail -n +2)

if [ ${#NETWORKS[@]} -eq 0 ]; then
  show_message "There are no saved Wi-Fi networks you can remove." "wifi" "note"
  exit 0
fi

CHOICE=""
if [ -x "$DIALOG" ]; then
  # Build swiftDialog JSON (escape backslashes and quotes in SSIDs)
  VALUES=""
  for n in "${NETWORKS[@]}"; do
    esc=$(printf '%s' "$n" | sed 's/\\/\\\\/g; s/"/\\"/g')
    VALUES="${VALUES}\"${esc}\","
  done
  VALUES="${VALUES%,}"
  JSON_FILE=$(/usr/bin/mktemp /private/var/tmp/removewifi.XXXXXX)
  cat > "$JSON_FILE" <<EOF
{
  "title": "$TITLE",
  "message": "Choose a saved Wi-Fi network to remove from this Mac.",
  "icon": "SF=wifi.slash",
  "selectitems": [ { "title": "Network", "values": [ $VALUES ] } ],
  "button1text": "Remove",
  "button2text": "Cancel",
  "ontop": true,
  "moveable": true
}
EOF
  /bin/chmod 644 "$JSON_FILE"
  OUTPUT=$(run_as_user "$DIALOG" --jsonfile "$JSON_FILE" --json 2>/dev/null)
  RC=$?
  [ $RC -ne 0 ] && { log "Cancelled by $CONSOLE_USER"; exit 0; }
  CHOICE=$(echo "$OUTPUT" | /usr/bin/plutil -extract "Network.selectedValue" raw -o - - 2>/dev/null)
else
  AS_LIST=$(printf '"%s", ' "${NETWORKS[@]}")
  AS_LIST="{${AS_LIST%, }}"
  CHOICE=$(run_as_user /usr/bin/osascript -e \
    "choose from list $AS_LIST with title \"$TITLE\" with prompt \"Select a network to remove:\" OK button name \"Remove\" cancel button name \"Cancel\"")
  [ "$CHOICE" = "false" ] && CHOICE=""
fi

[ -z "$CHOICE" ] && { log "Cancelled or no selection by $CONSOLE_USER"; exit 0; }

# Re-check against the protected list (belt and braces)
if is_protected "$CHOICE"; then
  log "Blocked removal of protected network: $CHOICE"; RECON=1
  show_message "This network is managed by GCU and can't be removed." "lock" "stop"
  exit 1
fi

if /usr/sbin/networksetup -removepreferredwirelessnetwork "$IFACE" "$CHOICE"; then
  log "$CONSOLE_USER removed '$CHOICE' from $IFACE"; RECON=1
  show_message "Removed: $CHOICE" "checkmark.circle" "note"
else
  log "FAILED to remove '$CHOICE' from $IFACE"; RECON=1
  show_message "Could not remove: $CHOICE" "exclamationmark.triangle" "stop"
  exit 1
fi
exit 0
