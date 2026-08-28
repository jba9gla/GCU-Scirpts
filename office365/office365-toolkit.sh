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
PKG_CACHE_DIR="/Library/Application Support/OfficeToolkitCache"

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
# FUNCTION: Clear Safari Microsoft/Office web session data
# ============================================================
clear_safari_microsoft_session() {
    log "--- Clearing Safari Microsoft/Office website data ---"

    echo ""
    echo "  This removes Safari's saved cookies/website data for Microsoft"
    echo "  and Office domains, so apps can no longer silently reuse an"
    echo "  existing web sign-in session."
    echo "  Safari will be closed automatically if it's running."
    echo ""
    read -rp "  Press Enter to continue, or Ctrl+C to cancel... "

    log "Closing Safari..."
    sudo -u "${LOGGED_IN_USER}" osascript -e 'tell application "Safari" to quit' 2>/dev/null
    sleep 2
    pkill -x Safari 2>/dev/null

    local FOUND_ANY=false

    # Safari's per-origin storage under the app container (modern macOS)
    local SAFARI_CONTAINER="${USER_HOME}/Library/Containers/com.apple.Safari/Data/Library/Cookies"
    if [ -d "${SAFARI_CONTAINER}" ]; then
        log "Checking Safari container cookie storage..."
        if [ -f "${SAFARI_CONTAINER}/Cookies.binarycookies" ]; then
            FOUND_ANY=true
            log "Found Safari cookies file. Note: this file stores all sites' cookies together,"
            log "so it cannot be selectively edited by script - only fully cleared."
            read -rp "  Clear ALL Safari cookies (not just Microsoft)? [y/N]: " CLEAR_ALL
            if [[ "${CLEAR_ALL}" =~ ^[Yy] ]]; then
                rm -f "${SAFARI_CONTAINER}/Cookies.binarycookies"
                log "Removed Safari cookies file. All sites will need to sign in again."
            else
                log "Skipped - cookie file left untouched."
            fi
        fi
    fi

    # WebKit per-origin local storage / IndexedDB - these ARE per-domain and safe to target
    local WEBKIT_STORAGE="${USER_HOME}/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteData"
    if [ -d "${WEBKIT_STORAGE}" ]; then
        log "Checking per-domain WebKit website data..."
        local MS_DOMAINS=("microsoft.com" "microsoftonline.com" "office.com" "office365.com" "live.com" "outlook.com")
        for domain_dir in "${WEBKIT_STORAGE}"/*/; do
            for domain in "${MS_DOMAINS[@]}"; do
                if [[ "${domain_dir}" == *"${domain}"* ]]; then
                    FOUND_ANY=true
                    log "Removing website data: ${domain_dir}"
                    rm -rf "${domain_dir}"
                fi
            done
        done
    fi

    if [ "$FOUND_ANY" = false ]; then
        log "No Microsoft/Office Safari website data found (or Safari's sandbox prevented direct access - Full Disk Access for Terminal may be required)."
    else
        log "Safari Microsoft/Office session data cleared."
    fi

    log "You may also want to manually check: Safari > Settings > Passwords, and remove any saved Microsoft/GCU credentials."
    log "Next Outlook/Office launch should now prompt for sign-in instead of reusing a session."
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
# ============================================================
# FUNCTION: Get version of a downloaded .pkg
# ============================================================
get_pkg_version() {
    local pkg_path="$1"
    local version
    version=$(installer -pkginfo -pkg "${pkg_path}" 2>/dev/null | head -1 | awk '{print $NF}')
    if [ -z "${version}" ]; then
        version="unknown"
    fi
    echo "${version}"
}

# ============================================================
# FUNCTION: Download a pkg with caching (skip re-download if cached copy exists)
# Args: $1 = download URL, $2 = cache filename, $3 = friendly name for messages
# Sets: DOWNLOADED_PKG_PATH on success
# ============================================================
download_pkg_cached() {
    local url="$1"
    local cache_filename="$2"
    local friendly_name="$3"
    local cache_path="${PKG_CACHE_DIR}/${cache_filename}"

    mkdir -p "${PKG_CACHE_DIR}"
    DOWNLOADED_PKG_PATH=""

    if [ -f "${cache_path}" ]; then
        local cached_version
        cached_version=$(get_pkg_version "${cache_path}")
        local cache_date
        cache_date=$(stat -f "%Sm" -t "%Y-%m-%d" "${cache_path}")
        echo ""
        log "Found cached ${friendly_name} installer: version ${cached_version}, downloaded ${cache_date}"
        read -rp "  Use cached copy? [Y/n] (n = re-download latest): " USE_CACHE
        if [[ ! "${USE_CACHE}" =~ ^[Nn] ]]; then
            log "Using cached ${friendly_name} installer (v${cached_version})."
            DOWNLOADED_PKG_PATH="${cache_path}"
            return 0
        else
            log "Re-downloading ${friendly_name} as requested..."
            rm -f "${cache_path}"
        fi
    fi

    log "Downloading ${friendly_name} installer from ${url}..."
    if ! curl -L "${url}" --output "${cache_path}"; then
        log "ERROR: Download failed. Check network access."
        rm -f "${cache_path}"
        return 1
    fi

    if [ ! -s "${cache_path}" ]; then
        log "ERROR: Downloaded file is empty or missing."
        rm -f "${cache_path}"
        return 1
    fi

    local new_version
    new_version=$(get_pkg_version "${cache_path}")
    log "Download complete ($(du -h "${cache_path}" | cut -f1)), version ${new_version}. Cached at ${cache_path}"
    DOWNLOADED_PKG_PATH="${cache_path}"
    return 0
}

# ============================================================
# FUNCTION: Download a dmg with caching (generic - not pkg-based)
# Args: $1 = download URL, $2 = cache filename, $3 = friendly name for messages
# Sets: DOWNLOADED_DMG_PATH on success
# ============================================================
download_dmg_cached() {
    local url="$1"
    local cache_filename="$2"
    local friendly_name="$3"
    local cache_path="${PKG_CACHE_DIR}/${cache_filename}"

    mkdir -p "${PKG_CACHE_DIR}"
    DOWNLOADED_DMG_PATH=""

    if [ -f "${cache_path}" ]; then
        local cache_date
        cache_date=$(stat -f "%Sm" -t "%Y-%m-%d" "${cache_path}")
        echo ""
        log "Found cached ${friendly_name} installer, downloaded ${cache_date}."
        read -rp "  Use cached copy? [Y/n] (n = re-download latest): " USE_CACHE
        if [[ ! "${USE_CACHE}" =~ ^[Nn] ]]; then
            log "Using cached ${friendly_name} installer."
            DOWNLOADED_DMG_PATH="${cache_path}"
            return 0
        else
            log "Re-downloading ${friendly_name} as requested..."
            rm -f "${cache_path}"
        fi
    fi

    log "Downloading ${friendly_name} installer from ${url}..."
    if ! curl -L "${url}" --output "${cache_path}"; then
        log "ERROR: Download failed. Check network access."
        rm -f "${cache_path}"
        return 1
    fi

    if [ ! -s "${cache_path}" ]; then
        log "ERROR: Downloaded file is empty or missing."
        rm -f "${cache_path}"
        return 1
    fi

    log "Download complete ($(du -h "${cache_path}" | cut -f1)). Cached at ${cache_path}"
    DOWNLOADED_DMG_PATH="${cache_path}"
    return 0
}

# ============================================================
# FUNCTION: Install Google Chrome
# ============================================================
install_chrome() {
    log "--- Installing Google Chrome ---"
    local DOWNLOAD_URL="https://dl.google.com/chrome/mac/stable/googlechrome.pkg"

    echo ""
    echo "  This will install Google Chrome using a cached copy if one already exists."
    echo ""
    read -rp "  Press Enter to begin, or Ctrl+C to cancel... "

    if ! download_pkg_cached "${DOWNLOAD_URL}" "GoogleChrome.pkg" "Google Chrome"; then
        return 1
    fi

    log "Installing Google Chrome..."
    if installer -pkg "${DOWNLOADED_PKG_PATH}" -target /; then
        log "Google Chrome installed successfully."
    else
        log "ERROR: Installer exited with a non-zero status."
        return 1
    fi
}

# ============================================================
# FUNCTION: Install Brave Browser
# ============================================================
install_brave() {
    log "--- Installing Brave Browser ---"
    local DOWNLOAD_URL="https://brave-browser-downloads.s3.brave.com/latest/Brave-Browser.dmg"
    local VOLNAME="Brave Browser"

    echo ""
    echo "  This will install Brave Browser using a cached copy if one already exists."
    echo ""
    read -rp "  Press Enter to begin, or Ctrl+C to cancel... "

    if ! download_dmg_cached "${DOWNLOAD_URL}" "Brave-Browser.dmg" "Brave Browser"; then
        return 1
    fi

    log "Mounting disk image..."
    hdiutil attach "${DOWNLOADED_DMG_PATH}" -nobrowse -quiet
    if [ ! -d "/Volumes/${VOLNAME}/Brave Browser.app" ]; then
        log "ERROR: Could not find Brave Browser.app inside the disk image."
        hdiutil detach "/Volumes/${VOLNAME}" -quiet 2>/dev/null
        return 1
    fi

    log "Copying Brave Browser.app to /Applications..."
    rm -rf "/Applications/Brave Browser.app"
    ditto -rsrc "/Volumes/${VOLNAME}/Brave Browser.app" "/Applications/Brave Browser.app"

    log "Unmounting disk image..."
    hdiutil detach "/Volumes/${VOLNAME}" -quiet

    log "Brave Browser installed successfully."
}

# ============================================================
# FUNCTION: Install Google Drive
# ============================================================
install_google_drive() {
    log "--- Installing Google Drive ---"
    local DOWNLOAD_URL="https://dl.google.com/drive/GoogleDrive.dmg"
    local VOLNAME="Install Google Drive"

    echo ""
    echo "  This will install Google Drive using a cached copy if one already exists."
    echo ""
    read -rp "  Press Enter to begin, or Ctrl+C to cancel... "

    if ! download_dmg_cached "${DOWNLOAD_URL}" "GoogleDrive.dmg" "Google Drive"; then
        return 1
    fi

    log "Mounting disk image..."
    hdiutil attach "${DOWNLOADED_DMG_PATH}" -nobrowse -quiet
    local PKG_INSIDE
    PKG_INSIDE=$(find "/Volumes/${VOLNAME}" -name "*.pkg" 2>/dev/null | head -1)
    if [ -z "${PKG_INSIDE}" ]; then
        log "ERROR: Could not find installer .pkg inside the disk image."
        hdiutil detach "/Volumes/${VOLNAME}" -quiet 2>/dev/null
        return 1
    fi

    log "Installing Google Drive..."
    if installer -pkg "${PKG_INSIDE}" -target /; then
        log "Google Drive installed successfully."
        log "Open Google Drive from Applications and sign in with the account to use."
    else
        log "ERROR: Installer exited with a non-zero status."
        hdiutil detach "/Volumes/${VOLNAME}" -quiet 2>/dev/null
        return 1
    fi

    log "Unmounting disk image..."
    hdiutil detach "/Volumes/${VOLNAME}" -quiet
}

# ============================================================
# FUNCTION: Install Visual Studio Code
# ============================================================
install_vscode() {
    log "--- Installing Visual Studio Code ---"
    local DOWNLOAD_URL="https://code.visualstudio.com/sha/download?build=stable&os=darwin-universal"
    local cache_path="${PKG_CACHE_DIR}/VSCode-darwin-universal.zip"

    echo ""
    echo "  This will install Visual Studio Code using a cached copy if one already exists."
    echo ""
    read -rp "  Press Enter to begin, or Ctrl+C to cancel... "

    mkdir -p "${PKG_CACHE_DIR}"

    if [ -f "${cache_path}" ]; then
        local cache_date
        cache_date=$(stat -f "%Sm" -t "%Y-%m-%d" "${cache_path}")
        echo ""
        log "Found cached VS Code installer, downloaded ${cache_date}."
        read -rp "  Use cached copy? [Y/n] (n = re-download latest): " USE_CACHE
        if [[ "${USE_CACHE}" =~ ^[Nn] ]]; then
            log "Re-downloading VS Code as requested..."
            rm -f "${cache_path}"
        fi
    fi

    if [ ! -f "${cache_path}" ]; then
        log "Downloading VS Code from ${DOWNLOAD_URL}..."
        if ! curl -L "${DOWNLOAD_URL}" --output "${cache_path}"; then
            log "ERROR: Download failed. Check network access."
            rm -f "${cache_path}"
            return 1
        fi
        if [ ! -s "${cache_path}" ]; then
            log "ERROR: Downloaded file is empty or missing."
            rm -f "${cache_path}"
            return 1
        fi
        log "Download complete ($(du -h "${cache_path}" | cut -f1)). Cached at ${cache_path}"
    fi

    local EXTRACT_DIR="/private/tmp/vscode-extract"
    rm -rf "${EXTRACT_DIR}"
    mkdir -p "${EXTRACT_DIR}"

    log "Extracting VS Code..."
    if ! ditto -xk "${cache_path}" "${EXTRACT_DIR}"; then
        log "ERROR: Failed to extract the downloaded zip."
        rm -rf "${EXTRACT_DIR}"
        return 1
    fi

    if [ ! -d "${EXTRACT_DIR}/Visual Studio Code.app" ]; then
        log "ERROR: Visual Studio Code.app not found after extraction."
        rm -rf "${EXTRACT_DIR}"
        return 1
    fi

    log "Copying Visual Studio Code.app to /Applications..."
    rm -rf "/Applications/Visual Studio Code.app"
    ditto "${EXTRACT_DIR}/Visual Studio Code.app" "/Applications/Visual Studio Code.app"
    rm -rf "${EXTRACT_DIR}"

    log "Visual Studio Code installed successfully."
}


install_cyberduck() {
    log "--- Installing Cyberduck ---"
    echo ""
    echo "  Cyberduck has no fixed direct-download URL (versioned filenames only),"
    echo "  so this uses Homebrew if available, which tracks the correct link itself."
    echo ""

    if command -v brew >/dev/null 2>&1; then
        log "Homebrew found. Installing Cyberduck via 'brew install --cask cyberduck'..."
        if sudo -u "${LOGGED_IN_USER}" brew install --cask cyberduck; then
            log "Cyberduck installed successfully via Homebrew."
        else
            log "ERROR: Homebrew install failed. See output above."
            return 1
        fi
    else
        log "Homebrew not found on this Mac."
        echo ""
        echo "  Opening the official Cyberduck download page instead - Homebrew isn't"
        echo "  installed, and there's no stable direct-download link to script against."
        echo ""
        read -rp "  Press Enter to open the download page... "
        sudo -u "${LOGGED_IN_USER}" open "https://cyberduck.io/download/"
        log "Opened https://cyberduck.io/download/ for manual download."
    fi
}

# ============================================================
# FUNCTION: Clear the pkg cache
# ============================================================
clear_pkg_cache() {
    log "--- Clearing installer cache ---"
    if [ ! -d "${PKG_CACHE_DIR}" ] || [ -z "$(ls -A "${PKG_CACHE_DIR}" 2>/dev/null)" ]; then
        log "Cache is already empty. Nothing to remove."
        return 0
    fi

    echo ""
    echo "  Cached installers:"
    ls -lh "${PKG_CACHE_DIR}" | tail -n +2 | awk '{print "    "$9" ("$5")"}'
    echo ""
    read -rp "  Remove all cached installers? [y/N]: " CONFIRM
    if [[ "${CONFIRM}" =~ ^[Yy] ]]; then
        rm -rf "${PKG_CACHE_DIR:?}"/*
        log "Installer cache cleared."
    else
        log "Cache left untouched."
    fi
}

# ============================================================
# FUNCTION: Install Microsoft Teams (standalone)
# ============================================================
install_teams_standalone() {
    log "--- Installing Microsoft Teams (standalone) ---"
    local DOWNLOAD_URL="https://go.microsoft.com/fwlink/?linkid=869428"

    echo ""
    echo "  This will install the official standalone Microsoft Teams installer,"
    echo "  using a cached copy if one already exists (checked against a fresh"
    echo "  download only if you choose to)."
    echo "  You will need to sign in the first time you open Teams."
    echo ""
    read -rp "  Press Enter to begin, or Ctrl+C to cancel... "

    if ! download_pkg_cached "${DOWNLOAD_URL}" "Teams_installer.pkg" "Microsoft Teams"; then
        return 1
    fi

    log "Installing Microsoft Teams..."
    if installer -pkg "${DOWNLOADED_PKG_PATH}" -target /; then
        log "Microsoft Teams installed successfully."
        log "Open Teams and sign in with the account to activate."
    else
        log "ERROR: Installer exited with a non-zero status. Check the log above for details."
        return 1
    fi
}

# ============================================================
# FUNCTION: Reinstall Office 365 (full suite)
# ============================================================
reinstall_office() {
    log "--- Reinstalling Microsoft 365 ---"
    local DOWNLOAD_URL="https://go.microsoft.com/fwlink/?linkid=525133"

    echo ""
    echo "  This will install the official Microsoft 365 installer (full suite,"
    echo "  ~2GB+), using a cached copy if one already exists."
    echo "  You will need to sign in the first time you open an Office app."
    echo ""
    read -rp "  Press Enter to begin, or Ctrl+C to cancel... "

    if ! download_pkg_cached "${DOWNLOAD_URL}" "Microsoft_Office_installer.pkg" "Microsoft 365"; then
        return 1
    fi

    log "Installing Microsoft 365..."
    if installer -pkg "${DOWNLOADED_PKG_PATH}" -target /; then
        log "Microsoft 365 installed successfully."
        log "Open any Office app (e.g. Word) and sign in with the Microsoft 365 account to activate."
    else
        log "ERROR: Installer exited with a non-zero status. Check the log above for details."
        return 1
    fi
}

# ============================================================
# MENU LOOP
# ============================================================
# ============================================================
# SUBMENU: Removal
# ============================================================
menu_removal() {
    while true; do
        echo ""
        echo "------ Removal ------"
        echo " 1) Remove license + uninstall Office (no login check)"
        echo " 2) Full clean - remove license, uninstall Office, AND clean login/auth remnants"
        echo " 3) Remove license only (keep apps installed) - lets user sign in again"
        echo " b) Back to main menu"
        read -rp "Choose an option: " SUB
        log "=== Removal submenu: option ${SUB} selected ==="
        case "${SUB}" in
            1)
                remove_license
                uninstall_office
                log "--- Action complete ---"
                log "A restart is recommended before reinstalling Office."
                ;;
            2)
                remove_license
                uninstall_office
                check_login_remnants true
                log "--- Action complete ---"
                log "A restart is recommended before reinstalling Office."
                ;;
            3)
                remove_license
                log "--- Action complete ---"
                log "License removed - apps are still installed. Open any Office app and sign in with the account you want to use."
                ;;
            b|B) return ;;
            *) echo "Invalid option, try again." ;;
        esac
    done
}

# ============================================================
# SUBMENU: Login / Auth checks
# ============================================================
menu_login_auth() {
    while true; do
        echo ""
        echo "------ Login / Auth ------"
        echo " 1) Report only - check for login/auth remnants (no changes)"
        echo " 2) Clean - remove login/auth remnants (skip license/uninstall)"
        echo " 3) Verify removal status - confirm Office and license are fully gone"
        echo " 4) Clear Safari Microsoft/Office session - stop silent auto sign-in"
        echo " b) Back to main menu"
        read -rp "Choose an option: " SUB
        log "=== Login/Auth submenu: option ${SUB} selected ==="
        case "${SUB}" in
            1) check_login_remnants false; log "--- Action complete ---" ;;
            2) check_login_remnants true; log "--- Action complete ---" ;;
            3) verify_removal_status; log "--- Action complete ---" ;;
            4) clear_safari_microsoft_session; log "--- Action complete ---" ;;
            b|B) return ;;
            *) echo "Invalid option, try again." ;;
        esac
    done
}

# ============================================================
# SUBMENU: Install / Reinstall
# ============================================================
menu_install() {
    while true; do
        echo ""
        echo "------ Install / Reinstall ------"
        echo " 1) Reinstall Microsoft 365 (full suite) - cached download + silent install"
        echo " 2) Install Microsoft Teams (standalone) - cached download + silent install"
        echo " 3) Install Google Chrome - cached download + silent install"
        echo " 4) Install Brave Browser - cached download + silent install"
        echo " 5) Install Google Drive - cached download + silent install"
        echo " 6) Install Cyberduck - via Homebrew, or browser fallback"
        echo " 7) Install Visual Studio Code - cached download + install"
        echo " b) Back to main menu"
        read -rp "Choose an option: " SUB
        log "=== Install submenu: option ${SUB} selected ==="
        case "${SUB}" in
            1) reinstall_office; log "--- Action complete ---" ;;
            2) install_teams_standalone; log "--- Action complete ---" ;;
            3) install_chrome; log "--- Action complete ---" ;;
            4) install_brave; log "--- Action complete ---" ;;
            5) install_google_drive; log "--- Action complete ---" ;;
            6) install_cyberduck; log "--- Action complete ---" ;;
            7) install_vscode; log "--- Action complete ---" ;;
            b|B) return ;;
            *) echo "Invalid option, try again." ;;
        esac
    done
}

# ============================================================
# SUBMENU: Maintenance
# ============================================================
menu_maintenance() {
    while true; do
        echo ""
        echo "------ Maintenance ------"
        echo " 1) View cached installers"
        echo " 2) Clear cached installers (Office/Teams .pkg files)"
        echo " b) Back to main menu"
        read -rp "Choose an option: " SUB
        log "=== Maintenance submenu: option ${SUB} selected ==="
        case "${SUB}" in
            1)
                echo ""
                echo "Cache directory: ${PKG_CACHE_DIR}"
                if [ -d "${PKG_CACHE_DIR}" ] && [ -n "$(ls -A "${PKG_CACHE_DIR}" 2>/dev/null)" ]; then
                    ls -lh "${PKG_CACHE_DIR}"
                else
                    echo "(empty - no cached installers found)"
                fi
                ;;
            2) clear_pkg_cache; log "--- Action complete ---" ;;
            b|B) return ;;
            *) echo "Invalid option, try again." ;;
        esac
    done
}

# ============================================================
# MAIN MENU LOOP
# ============================================================
while true; do
    echo ""
    echo "=========================================="
    echo " Microsoft 365 Removal Toolkit for macOS"
    echo "=========================================="
    echo " 1) Removal"
    echo " 2) Login / Auth"
    echo " 3) Install / Reinstall"
    echo " 4) Maintenance"
    echo " 0) Exit"
    echo "=========================================="
    read -rp "Choose a category: " CHOICE

    log "=== Main menu: option ${CHOICE} selected ==="

    case "${CHOICE}" in
        1) menu_removal ;;
        2) menu_login_auth ;;
        3) menu_install ;;
        4) menu_maintenance ;;
        0)
            log "=== Exiting toolkit. Log saved at: ${LOG_FILE} ==="
            exit 0
            ;;
        *)
            echo "Invalid option, try again."
            ;;
    esac
done
