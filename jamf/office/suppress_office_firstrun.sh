#!/bin/bash
###############################################################################
# suppress_office_firstrun.sh
# Suppresses first-run dialogs and splash screens for Microsoft Office on macOS
# Tested against: Office 365 / Microsoft 365 (16.x)
#
# Deploy via Jamf Pro as a postinstall script (runs as root).
# If deploying as a standalone postinstall, the script detects all human users
# and applies settings for each.
###############################################################################

# ── Logging ──────────────────────────────────────────────────────────────────
LOG="/var/log/suppress_office_firstrun.log"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S')  $*" | tee -a "$LOG"; }

log "===== suppress_office_firstrun.sh started ====="

# ── Identify target users ─────────────────────────────────────────────────────
# When run from Jamf the logged-in user is passed as $3; fall back to dscl scan.
CURRENT_USER="$3"

if [[ -z "$CURRENT_USER" || "$CURRENT_USER" == "root" ]]; then
    CURRENT_USER=$(stat -f "%Su" /dev/console 2>/dev/null)
fi

# Build a list: the console user plus any other human accounts
HUMAN_USERS=()
while IFS= read -r u; do
    [[ "$u" =~ ^(root|nobody|daemon|_.*) ]] && continue
    [[ -d "/Users/$u" ]] && HUMAN_USERS+=("$u")
done < <(dscl . list /Users)

# Make sure the console user is first (most likely to be relevant)
if [[ -n "$CURRENT_USER" && "$CURRENT_USER" != "root" ]]; then
    HUMAN_USERS=("$CURRENT_USER" "${HUMAN_USERS[@]/$CURRENT_USER}")
    # De-duplicate
    SEEN=()
    UNIQUE_USERS=()
    for u in "${HUMAN_USERS[@]}"; do
        [[ " ${SEEN[*]} " == *" $u "* ]] && continue
        SEEN+=("$u"); UNIQUE_USERS+=("$u")
    done
    HUMAN_USERS=("${UNIQUE_USERS[@]}")
fi

log "Applying settings for users: ${HUMAN_USERS[*]}"

# ── Per-user preferences ──────────────────────────────────────────────────────
for USER in "${HUMAN_USERS[@]}"; do
    USER_HOME="/Users/$USER"
    [[ -d "$USER_HOME" ]] || continue
    log "Processing user: $USER"

    # Helper: write a pref as that user (so ownership stays correct)
    pref_write() {
        # pref_write <domain> <key> <type> <value>
        sudo -u "$USER" defaults write "$1" "$2" "$3" "$4" 2>>"$LOG"
    }

    # ── Microsoft Office Suite ────────────────────────────────────────────────
    OFFICE_DOMAIN="com.microsoft.office"

    # Suppress the "What's New" / first-run experience
    pref_write "$OFFICE_DOMAIN" "FirstRunExperienceCompletedO15"            -bool true
    pref_write "$OFFICE_DOMAIN" "ShowWhatsNewOnLaunch"                      -bool false
    pref_write "$OFFICE_DOMAIN" "AcceptedEULAVersion"                       -int  1
    pref_write "$OFFICE_DOMAIN" "HasSeenOptInDialog"                        -bool true
    pref_write "$OFFICE_DOMAIN" "HasUserSeenEnterpriseFREDialog"            -bool true
    pref_write "$OFFICE_DOMAIN" "SendAllTelemetryEnabled"                   -bool false

    # ── Word ─────────────────────────────────────────────────────────────────
    WORD_DOMAIN="com.microsoft.Word"
    pref_write "$WORD_DOMAIN" "kSubUIAppCompletedFirstRunSetup1507"         -bool true
    pref_write "$WORD_DOMAIN" "SendAllTelemetryEnabled"                     -bool false
    pref_write "$WORD_DOMAIN" "FirstRunExperienceCompletedO15"              -bool true
    pref_write "$WORD_DOMAIN" "ShowWhatsNewOnLaunch"                        -bool false

    # ── Excel ─────────────────────────────────────────────────────────────────
    EXCEL_DOMAIN="com.microsoft.Excel"
    pref_write "$EXCEL_DOMAIN" "kSubUIAppCompletedFirstRunSetup1507"        -bool true
    pref_write "$EXCEL_DOMAIN" "SendAllTelemetryEnabled"                    -bool false
    pref_write "$EXCEL_DOMAIN" "FirstRunExperienceCompletedO15"             -bool true
    pref_write "$EXCEL_DOMAIN" "ShowWhatsNewOnLaunch"                       -bool false

    # ── PowerPoint ───────────────────────────────────────────────────────────
    PPT_DOMAIN="com.microsoft.Powerpoint"
    pref_write "$PPT_DOMAIN" "kSubUIAppCompletedFirstRunSetup1507"          -bool true
    pref_write "$PPT_DOMAIN" "SendAllTelemetryEnabled"                      -bool false
    pref_write "$PPT_DOMAIN" "FirstRunExperienceCompletedO15"               -bool true
    pref_write "$PPT_DOMAIN" "ShowWhatsNewOnLaunch"                         -bool false

    # ── Outlook ──────────────────────────────────────────────────────────────
    OUTLOOK_DOMAIN="com.microsoft.Outlook"
    pref_write "$OUTLOOK_DOMAIN" "FirstRunExperienceCompletedO15"           -bool true
    pref_write "$OUTLOOK_DOMAIN" "ShowWhatsNewOnLaunch"                     -bool false
    pref_write "$OUTLOOK_DOMAIN" "kSubUIAppCompletedFirstRunSetup1507"      -bool true
    pref_write "$OUTLOOK_DOMAIN" "SendAllTelemetryEnabled"                  -bool false
    pref_write "$OUTLOOK_DOMAIN" "AutoDiscoverEnabled"                      -bool false
    # Suppress the "set as default mail app" nag
    pref_write "$OUTLOOK_DOMAIN" "DefaultEmailClientPromptDisabled"         -bool true

    # ── OneNote ──────────────────────────────────────────────────────────────
    ONENOTE_DOMAIN="com.microsoft.onenote.mac"
    pref_write "$ONENOTE_DOMAIN" "FirstRunExperienceCompletedO15"           -bool true
    pref_write "$ONENOTE_DOMAIN" "ShowWhatsNewOnLaunch"                     -bool false
    pref_write "$ONENOTE_DOMAIN" "kSubUIAppCompletedFirstRunSetup1507"      -bool true
    pref_write "$ONENOTE_DOMAIN" "SendAllTelemetryEnabled"                  -bool false

    # ── Teams (Classic / New) ─────────────────────────────────────────────────
    TEAMS_DOMAIN="com.microsoft.teams"
    pref_write "$TEAMS_DOMAIN" "FirstLaunchAfterInstall"                    -bool false

    # ── Microsoft AutoUpdate ─────────────────────────────────────────────────
    # Prevent MAU from nagging users at first launch (managed via Jamf anyway)
    MAU_DOMAIN="com.microsoft.autoupdate2"
    pref_write "$MAU_DOMAIN" "HowToCheck"                                   -string "Manual"
    pref_write "$MAU_DOMAIN" "DisableInsiderCheckbox"                       -bool   true
    pref_write "$MAU_DOMAIN" "StartDaemonOnAppLaunch"                       -bool   false

    log "  Preferences written for $USER"
done

# ── System-wide PLIST (optional managed pref approach) ───────────────────────
# These land in /Library/Preferences and apply to all users without needing
# per-user iteration. Useful as belt-and-braces alongside the above.
MANAGED_PREFS_DIR="/Library/Managed Preferences"
mkdir -p "$MANAGED_PREFS_DIR"

GLOBAL_DOMAINS=(
    "com.microsoft.office"
    "com.microsoft.Word"
    "com.microsoft.Excel"
    "com.microsoft.Powerpoint"
    "com.microsoft.Outlook"
    "com.microsoft.onenote.mac"
)

for DOMAIN in "${GLOBAL_DOMAINS[@]}"; do
    defaults write "/Library/Preferences/$DOMAIN" "ShowWhatsNewOnLaunch"              -bool false
    defaults write "/Library/Preferences/$DOMAIN" "FirstRunExperienceCompletedO15"    -bool true
    defaults write "/Library/Preferences/$DOMAIN" "kSubUIAppCompletedFirstRunSetup1507" -bool true
    log "Global pref written for $DOMAIN"
done

# ── Done ──────────────────────────────────────────────────────────────────────
log "===== suppress_office_firstrun.sh completed ====="
exit 0
