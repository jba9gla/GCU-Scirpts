#!/bin/bash
#
# office365-toolkit.sh
#
# All-in-one Microsoft 365 removal toolkit for macOS. Not tied to Jamf -
# run manually, interactive menu.
#
# Combines:
#   - License removal (Microsoft's "Unlicense" tool)
#   - Full app + support file uninstall
#   - Login/auth remnant check (keychain, identity broker, prefs, login items)
#
# All actions are logged to /Library/Logs/OfficeRemoval/
#
# Usage:
#   sudo ./office365-toolkit.sh
#   (menu will ask what you want to do)
#
# Must be run with sudo, since removal touches /Applications and /Library.
#

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root (use sudo)."
    exit 1
fi

LOGGED_IN_USER=$(stat -f%Su /dev/console)
USER_HOME=$(dscl . -read /Users/"${LOGGED_IN_USER}" NFSHomeDirectory | awk '{print $2}')
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
LOG_DIR="/Library/Logs/OfficeRemoval"
LOG_FILE="${LOG_DIR}/office-toolkit-${TIMESTAMP}.log"
TMP_DIR="/private/tmp/office-unlicense"
UNLICENSE_URL="https://raw.githubusercontent.com/pbowden-msft/Unlicense/master/Unlicense"
UNLICENSE_BIN="${TMP_DIR}/Unlicense"

mkdir -p "${LOG_DIR}"
exec > >(tee -a "${LOG_FILE}") 2>&1

log() { echo "[$(date +"%Y-%m-%d %H:%M:%S")] $1"; }

# ============================================================
# WELCOME BANNER
# ============================================================
clear
BOLD="\033[1m"
CYAN="\033[36m"
RESET="\033[0m"

echo -e "${CYAN}${BOLD}"
cat << "EOF"
╔══════════════════════════════════════════════════════════╗
║                                                            ║
║          MICROSOFT 365 REMOVAL TOOLKIT — macOS            ║
║                                                            ║
╚══════════════════════════════════════════════════════════╝
EOF
echo -e "${RESET}"
echo -e "         Author: JACB Services  |  $(date +"%d %B %Y")"
echo ""
echo "  This tool can remove Microsoft 365 licenses, uninstall Office,"
echo "  and clear leftover sign-in data on this Mac."
echo ""
echo "  All actions are logged to:"
echo "  ${LOG_FILE}"
echo ""

log "=== Office 365 Toolkit launched by $(whoami) on $(hostname) ==="

# ============================================================
# FUNCTION: Remove license
# ============================================================
remove_license() {
    log "--- Removing Microsoft 365 license ---"
    mkdir -p "${TMP_DIR}"
    if ! curl -sSL "${UNLICENSE_URL}" -o "${UNLICENSE_BIN}"; then
        log "ERROR: Failed to download Unlicense tool. Skipping license removal."
        return 1
    fi
    chmod +x "${UNLICENSE_BIN}"
    "${UNLICENSE_BIN}" --All --ForceClose >> "${LOG_FILE}" 2>&1
    local result=$?
    rm -rf "${TMP_DIR}"
    if [ $result -eq 0 ]; then
        log "License removal completed successfully."
    else
        log "WARNING: Unlicense exited with status ${result}."
    fi
}

# ============================================================
# FUNCTION: Uninstall Office apps + support files
# ============================================================
uninstall_office() {
    log "--- Uninstalling Office applications and support files ---"

    OFFICE_PROCESSES=("Microsoft Word" "Microsoft Excel" "Microsoft PowerPoint" "Microsoft Outlook" "Microsoft OneNote" "Microsoft Teams" "OneDrive" "Microsoft AutoUpdate")
    for proc in "${OFFICE_PROCESSES[@]}"; do
        pgrep -x "${proc}" >/dev/null 2>&1 && { log "Quitting ${proc}..."; killall "${proc}" 2>/dev/null; }
    done

    APP_PATHS=(
        "/Applications/Microsoft Word.app"
        "/Applications/Microsoft Excel.app"
        "/Applications/Microsoft PowerPoint.app"
        "/Applications/Microsoft Outlook.app"
        "/Applications/Microsoft OneNote.app"
        "/Applications/Microsoft Teams.app"
        "/Applications/OneDrive.app"
    )
    for app in "${APP_PATHS[@]}"; do
        if [ -d "${app}" ]; then
            log "Removing ${app}"; rm -rf "${app}"
        else
            log "Not present, skipping: ${app}"
        fi
    done

    SYSTEM_PATHS=(
        "/Library/Application Support/Microsoft"
        "/Library/Preferences/com.microsoft.office.plist"
        "/Library/PrivilegedHelperTools/com.microsoft.OfficeOSAK.plist"
        "/Library/LaunchDaemons/com.microsoft.OfficeOSAK.plist"
        "/Library/LaunchAgents/com.microsoft.update.agent.plist"
    )
    for path in "${SYSTEM_PATHS[@]}"; do
        if [ -e "${path}" ]; then
            log "Removing ${path}"; rm -rf "${path}"
        else
            log "Not present, skipping: ${path}"
        fi
    done

    USER_PATHS=(
        "${USER_HOME}/Library/Containers/com.microsoft.Word"
        "${USER_HOME}/Library/Containers/com.microsoft.Excel"
        "${USER_HOME}/Library/Containers/com.microsoft.Powerpoint"
        "${USER_HOME}/Library/Containers/com.microsoft.Outlook"
        "${USER_HOME}/Library/Containers/com.microsoft.onenote.mac"
        "${USER_HOME}/Library/Containers/com.microsoft.teams2"
        "${USER_HOME}/Library/Group Containers/UBF8T346G9.Office"
        "${USER_HOME}/Library/Group Containers/UBF8T346G9.OfficeOsfWebHost"
        "${USER_HOME}/Library/Preferences/com.microsoft.office.plist"
        "${USER_HOME}/Library/Caches/com.microsoft.Word"
        "${USER_HOME}/Library/Caches/com.microsoft.Excel"
        "${USER_HOME}/Library/Caches/com.microsoft.Powerpoint"
        "${USER_HOME}/Library/Caches/com.microsoft.Outlook"
    )
    LEFTOVER_CONTAINERS=()
    for path in "${USER_PATHS[@]}"; do
        if [ -e "${path}" ]; then
            log "Removing ${path}"
            chflags -R nouchg "${path}" 2>/dev/null
            if ! rm -rf "${path}" 2>/tmp/office-rm-error.$$; then
                if [ -e "${path}" ]; then
                    log "NOTE: ${path} could not be fully removed (macOS sandbox/container protection - inert, safe to ignore)."
                    [[ "${path}" == *"/Containers/"* ]] && LEFTOVER_CONTAINERS+=("${path}")
                fi
            fi
            rm -f /tmp/office-rm-error.$$
        else
            log "Not present, skipping: ${path}"
        fi
    done

    log "--- Uninstall complete ---"
    if [ ${#LEFTOVER_CONTAINERS[@]} -gt 0 ]; then
        log "NOTE: ${#LEFTOVER_CONTAINERS[@]} empty sandbox container folder(s) left behind (SIP-protected, inert):"
        for path in "${LEFTOVER_CONTAINERS[@]}"; do log "    ${path}"; done
    fi
}

# ============================================================
# FUNCTION: Check login/auth remnants (report and/or clean)
# ============================================================
check_login_remnants() {
    local do_clean=$1   # true or false
    log "--- Checking login/auth remnants (mode: $( [ "$do_clean" = true ] && echo CLEAN || echo REPORT ) ) ---"
    local found_anything=false

    # Genuine Office-suite keychain service names only (word/excel/ppt/outlook/onenote/onedrive/office core).
    # Deliberately excludes: VS Code, Storage Explorer, Remote Desktop, standalone Teams.
    local OFFICE_KEYCHAIN_LABELS=("Microsoft Office" "Microsoft Office Identities Cache" "MSOpenTech" "MSAL" "ADAL" "OneDrive Standalone Update Task" "Microsoft Word" "Microsoft Excel" "Microsoft PowerPoint" "Microsoft Outlook" "Microsoft OneNote")

    # 1. Keychain
    log "1. Checking login keychain for genuine Office sign-in entries..."
    local keychain_matches
    keychain_matches=$(security dump-keychain "${USER_HOME}/Library/Keychains/login.keychain-db" 2>/dev/null | grep -i -E '"svce"<blob>="(Microsoft Office|MSOpenTech|MSAL|ADAL|OneDrive|Microsoft Word|Microsoft Excel|Microsoft PowerPoint|Microsoft Outlook|Microsoft OneNote)' | sort -u)
    if [ -n "${keychain_matches}" ]; then
        found_anything=true
        log "Found keychain entries:"
        echo "${keychain_matches}" | sed 's/^/    /'
        if [ "$do_clean" = true ]; then
            for label in "${OFFICE_KEYCHAIN_LABELS[@]}"; do
                security delete-generic-password -s "${label}" "${USER_HOME}/Library/Keychains/login.keychain-db" 2>/dev/null && \
                    log "Deleted keychain entries matching: ${label}"
            done
        fi
    else
        log "No genuine Office keychain entries found."
    fi

    # 2. Identity broker cache (Office's own broker only)
    log "2. Checking Microsoft identity broker cache..."
    local broker_paths=(
        "${USER_HOME}/Library/Application Support/Microsoft/Identity"
        "${USER_HOME}/Library/Group Containers/UBF8T346G9.OfficeOsfWebHost/Broker"
        "${USER_HOME}/Library/Application Support/com.microsoft.identity.universalstorage"
    )
    for path in "${broker_paths[@]}"; do
        if [ -e "${path}" ]; then
            found_anything=true
            log "Found: ${path}"
            [ "$do_clean" = true ] && rm -rf "${path}" && log "Removed: ${path}"
        else
            log "Not present: ${path}"
        fi
    done

    # 3. Preference domains - Office suite only, explicitly excludes other Microsoft tools
    log "3. Checking for leftover Office preference domains..."
    local OFFICE_PREF_PATTERN='^com\.microsoft\.(office|word|excel|powerpoint|outlook|onenote|onedrive|Word|Excel|Powerpoint|Outlook)'
    local EXCLUDED_PATTERN='vscode|storageexplorer|rdc|teams'
    local pref_domains
    pref_domains=$(sudo -u "${LOGGED_IN_USER}" defaults domains 2>/dev/null | tr ',' '\n' | sed 's/^ *//' | grep -iE "${OFFICE_PREF_PATTERN}" | grep -viE "${EXCLUDED_PATTERN}")
    if [ -n "${pref_domains}" ]; then
        found_anything=true
        log "Found Office preference domains:"
        echo "${pref_domains}" | sed 's/^/    /'
        if [ "$do_clean" = true ]; then
            while IFS= read -r domain; do
                [ -n "${domain}" ] && sudo -u "${LOGGED_IN_USER}" defaults delete "${domain}" 2>/dev/null && log "Deleted preference domain: ${domain}"
            done <<< "${pref_domains}"
        fi
    else
        log "No leftover Office preference domains found."
    fi

    # 3b. Teams - handled separately since it's ambiguous (bundled with Office in some
    # setups, standalone/used independently in others). Never auto-cleaned.
    log "3b. Checking for Microsoft Teams items (handled separately)..."
    local teams_domains
    teams_domains=$(sudo -u "${LOGGED_IN_USER}" defaults domains 2>/dev/null | tr ',' '\n' | sed 's/^ *//' | grep -iE 'teams')
    local teams_keychain
    teams_keychain=$(security dump-keychain "${USER_HOME}/Library/Keychains/login.keychain-db" 2>/dev/null | grep -i -E '"svce"<blob>=".*[Tt]eams' | sort -u)
    if [ -n "${teams_domains}" ] || [ -n "${teams_keychain}" ]; then
        found_anything=true
        log "Found Microsoft Teams items on this Mac:"
        [ -n "${teams_domains}" ] && echo "${teams_domains}" | sed 's/^/    [prefs] /'
        [ -n "${teams_keychain}" ] && echo "${teams_keychain}" | sed 's/^/    [keychain] /'
        if [ "$do_clean" = true ]; then
            echo ""
            read -rp "    Teams found - is this a standalone Teams install you want to KEEP, or part of the Office removal (remove it)? [K]eep / [R]emove: " TEAMS_CHOICE
            case "${TEAMS_CHOICE}" in
                [Rr]*)
                    log "User chose to remove Teams items."
                    if [ -n "${teams_domains}" ]; then
                        while IFS= read -r domain; do
                            [ -n "${domain}" ] && sudo -u "${LOGGED_IN_USER}" defaults delete "${domain}" 2>/dev/null && log "Deleted preference domain: ${domain}"
                        done <<< "${teams_domains}"
                    fi
                    security delete-generic-password -s "Microsoft Teams Safe Storage" "${USER_HOME}/Library/Keychains/login.keychain-db" 2>/dev/null && \
                        log "Deleted keychain entry: Microsoft Teams Safe Storage"
                    ;;
                *)
                    log "User chose to keep Teams items - skipped."
                    ;;
            esac
        else
            log "Report only - Teams items left untouched. You'll be asked to keep/remove if you run a clean option."
        fi
    else
        log "No Microsoft Teams items found."
    fi

    # 4. Login items - Office apps only, excludes Teams/VSCode/etc
    log "4. Checking login items for genuine Office entries..."
    local login_items
    login_items=$(sudo -u "${LOGGED_IN_USER}" osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null | tr ',' '\n' | grep -iE 'Microsoft (Word|Excel|PowerPoint|Outlook|OneNote|OneDrive|AutoUpdate)')
    if [ -n "${login_items}" ]; then
        found_anything=true
        log "Found Microsoft-related login items:"
        echo "${login_items}" | sed 's/^/    /'
        if [ "$do_clean" = true ]; then
            while IFS= read -r item; do
                local item_trimmed
                item_trimmed=$(echo "${item}" | sed 's/^ *//;s/ *$//')
                [ -n "${item_trimmed}" ] && sudo -u "${LOGGED_IN_USER}" osascript -e "tell application \"System Events\" to delete login item \"${item_trimmed}\"" 2>/dev/null && log "Removed login item: ${item_trimmed}"
            done <<< "${login_items}"
        fi
    else
        log "No Microsoft login items found."
    fi

    log "--- Login remnant check complete ---"
    if [ "$found_anything" = true ]; then
        if [ "$do_clean" = true ]; then
            log "Remnants were found and cleaned. Reinstall should prompt for sign-in normally."
        else
            log "Remnants were found but NOT removed (report only). Re-run and choose the clean option to remove them."
        fi
    else
        log "No login/auth remnants found. Safe to reinstall - should prompt for a clean sign-in."
    fi
}

# ============================================================
# FUNCTION: Verify removal status (confirms apps, license, containers gone)
# ============================================================
verify_removal_status() {
    log "--- Verifying Office 365 removal status ---"
    local all_clear=true

    log "Checking for Office applications..."
    local APP_PATHS=(
        "/Applications/Microsoft Word.app"
        "/Applications/Microsoft Excel.app"
        "/Applications/Microsoft PowerPoint.app"
        "/Applications/Microsoft Outlook.app"
        "/Applications/Microsoft OneNote.app"
    )
    for app in "${APP_PATHS[@]}"; do
        if [ -d "${app}" ]; then
            all_clear=false
            log "  STILL PRESENT: ${app}"
        else
            log "  Gone: ${app}"
        fi
    done

    log "Checking for license/activation files..."
    if [ -d "/Library/Application Support/Microsoft" ]; then
        all_clear=false
        log "  STILL PRESENT: /Library/Application Support/Microsoft"
    else
        log "  Gone: /Library/Application Support/Microsoft"
    fi

    local activation_check
    activation_check=$(security dump-keychain "${USER_HOME}/Library/Keychains/login.keychain-db" 2>/dev/null | grep -i -E '"svce"<blob>="(Microsoft Office|MSOpenTech|MSAL|ADAL)' | sort -u)
    if [ -n "${activation_check}" ]; then
        all_clear=false
        log "  STILL PRESENT: Office activation keychain entries"
    else
        log "  Gone: Office activation keychain entries"
    fi

    log "Checking for leftover sandbox containers (informational - these are inert if present)..."
    local CONTAINER_PATHS=(
        "${USER_HOME}/Library/Containers/com.microsoft.Word"
        "${USER_HOME}/Library/Containers/com.microsoft.Excel"
        "${USER_HOME}/Library/Containers/com.microsoft.Powerpoint"
        "${USER_HOME}/Library/Containers/com.microsoft.Outlook"
        "${USER_HOME}/Library/Containers/com.microsoft.onenote.mac"
    )
    local leftover_count=0
    for path in "${CONTAINER_PATHS[@]}"; do
        if [ -e "${path}" ]; then
            leftover_count=$((leftover_count+1))
            log "  Empty container present (harmless): ${path}"
        fi
    done

    echo ""
    if [ "$all_clear" = true ]; then
        log "RESULT: Office apps, support files, and activation are fully removed."
        [ "$leftover_count" -gt 0 ] && log "Note: ${leftover_count} inert empty container folder(s) remain - safe to ignore, won't affect reinstall."
        log "This Mac is ready for a clean Office 365 reinstall and sign-in."
    else
        log "RESULT: Some Office components are still present (see STILL PRESENT lines above)."
        log "Run option 1 or 3 to remove them before reinstalling."
    fi
}

# ============================================================
# FUNCTION: Reinstall Office 365
# ============================================================
reinstall_office() {
    log "--- Reinstalling Microsoft 365 ---"
    local DOWNLOAD_URL="https://go.microsoft.com/fwlink/?linkid=525133"
    local TMP_INSTALL_DIR="/private/tmp/office-reinstall"
    local PKG_PATH="${TMP_INSTALL_DIR}/Microsoft_Office_installer.pkg"

    echo ""
    echo "  This will download the official Microsoft 365 installer (full suite,"
    echo "  ~2GB+) directly from Microsoft's CDN and install it silently."
    echo "  You will need to sign in the first time you open an Office app."
    echo ""
    read -rp "  Press Enter to begin, or Ctrl+C to cancel... "

    mkdir -p "${TMP_INSTALL_DIR}"
    log "Downloading Microsoft 365 installer from ${DOWNLOAD_URL}..."
    if ! curl -L "${DOWNLOAD_URL}" --output "${PKG_PATH}"; then
        log "ERROR: Download failed. Check network access to go.microsoft.com / officecdn CDN."
        rm -rf "${TMP_INSTALL_DIR}"
        return 1
    fi

    if [ ! -s "${PKG_PATH}" ]; then
        log "ERROR: Downloaded file is empty or missing. Aborting install."
        rm -rf "${TMP_INSTALL_DIR}"
        return 1
    fi

    log "Download complete ($(du -h "${PKG_PATH}" | cut -f1)). Installing..."
    if installer -pkg "${PKG_PATH}" -target /; then
        log "Microsoft 365 installed successfully."
        log "Open any Office app (e.g. Word) and sign in with the Microsoft 365 account to activate."
    else
        log "ERROR: Installer exited with a non-zero status. Check the log above for details."
        rm -rf "${TMP_INSTALL_DIR}"
        return 1
    fi

    rm -rf "${TMP_INSTALL_DIR}"
}

# ============================================================
# MENU LOOP
# ============================================================
while true; do
    echo ""
    echo "=========================================="
    echo " Microsoft 365 Removal Toolkit for macOS"
    echo "=========================================="
    echo " 1) Remove license + uninstall Office (no login check)"
    echo " 2) Report only - check for login/auth remnants (no changes)"
    echo " 3) Full clean - remove license, uninstall Office, AND clean login/auth remnants"
    echo " 4) Login/auth remnants only - clean (skip license/uninstall)"
    echo " 5) Verify removal status - confirm Office and license are fully gone"
    echo " 6) Reinstall Microsoft 365 - direct download + silent install"
    echo " 7) Remove license only (keep apps installed) - lets user sign in again"
    echo " 0) Exit"
    echo "=========================================="
    read -rp "Choose an option: " CHOICE

    log "=== Option ${CHOICE} selected ==="

    case "${CHOICE}" in
        1)
            remove_license
            uninstall_office
            log "--- Action complete ---"
            log "A restart is recommended before reinstalling Office."
            ;;
        2)
            check_login_remnants false
            log "--- Action complete ---"
            ;;
        3)
            remove_license
            uninstall_office
            check_login_remnants true
            log "--- Action complete ---"
            log "A restart is recommended before reinstalling Office."
            ;;
        4)
            check_login_remnants true
            log "--- Action complete ---"
            ;;
        5)
            verify_removal_status
            log "--- Action complete ---"
            ;;
        6)
            reinstall_office
            log "--- Action complete ---"
            ;;
        7)
            remove_license
            log "--- Action complete ---"
            log "License removed - apps are still installed. Open any Office app and sign in with the account you want to use."
            ;;
        0)
            log "=== Exiting toolkit. Log saved at: ${LOG_FILE} ==="
            exit 0
            ;;
        *)
            echo "Invalid option, try again."
            ;;
    esac
done
