#!/bin/bash
# Cisco Secure Client 5.1.10.233 — VPN-only install + preconfigured profile
# Jamf script parameters:
#   $4 = VPN display name (default: "GCU VPN")
#   $5 = VPN host/FQDN (default: "vpn.gcu.ac.uk")
#   $6 = Exact pkg filename (optional, e.g., "Cisco Secure Client 5.1.10.233.pkg")

set -euo pipefail

VPN_NAME="${4:-GCU VPN}"
VPN_HOST="${5:-vpn.gcu.ac.uk}"
PKG_NAME_OVERRIDE="${6:-}"

WR="/Library/Application Support/JAMF/Waiting Room"
DL="/Library/Application Support/JAMF/Downloads"
PKG_PATH=""
CHOICES_PLIST=""
PROFILE_DIR="/opt/cisco/secureclient/vpn/profile"
PROFILE_PATH="$PROFILE_DIR/GCU-VPN.xml"

log() { echo "[CSC] $*"; }

cleanup() {
  [[ -n "${CHOICES_PLIST}" && -f "${CHOICES_PLIST}" ]] && rm -f "${CHOICES_PLIST}" || true
}
trap cleanup EXIT

find_pkg_in() {
  local base="$1"
  # Prefer explicit filename if provided
  if [[ -n "$PKG_NAME_OVERRIDE" && -f "$base/$PKG_NAME_OVERRIDE" ]]; then
    echo "$base/$PKG_NAME_OVERRIDE"
    return 0
  fi
  # Try common names, then any .pkg as last resort
  for pat in "Cisco Secure Client*.pkg" "AnyConnect*.pkg" "*.pkg"; do
    if compgen -G "$base/$pat" >/dev/null; then
      ls -1t "$base"/$pat | head -n1
      return 0
    fi
  done
  return 1
}

# Locate package in common Jamf caches
if PKG_PATH="$(find_pkg_in "$WR")"; then
  :
elif PKG_PATH="$(find_pkg_in "$DL")"; then
  :
else
  log "ERROR: Package not found in:
  - $WR
  - $DL

Fix:
  • Add the Cisco Secure Client 5.1.10.233 pkg to the policy (Packages -> Action: Cache).
  • Ensure this script runs with Priority: After.
  • Or pass the exact filename as parameter 6 (e.g., \"Cisco Secure Client 5.1.10.233.pkg\")."
  exit 1
fi

log "Using package: $PKG_PATH"

# Create Choices XML: VPN only ON, everything else OFF
CHOICES_PLIST="$(mktemp /private/tmp/csc_choices.XXXXXX.plist)"
cat > "$CHOICES_PLIST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
  <!-- VPN ON -->
  <dict>
    <key>choiceIdentifier</key><string>choice_anyconnect_vpn</string>
    <key>choiceAttribute</key><string>selected</string>
    <key>attributeSetting</key><integer>1</integer>
  </dict>

  <!-- Everything else OFF -->
  <dict><key>choiceIdentifier</key><string>choice_dart</string><key>choiceAttribute</key><string>selected</string><key>attributeSetting</key><integer>0</integer></dict>
  <dict><key>choiceIdentifier</key><string>choice_secure_firewall_posture</string><key>choiceAttribute</key><string>selected</string><key>attributeSetting</key><integer>0</integer></dict>
  <dict><key>choiceIdentifier</key><string>choice_iseposture</string><key>choiceAttribute</key><string>selected</string><key>attributeSetting</key><integer>0</integer></dict>
  <dict><key>choiceIdentifier</key><string>choice_nvm</string><key>choiceAttribute</key><string>selected</string><key>attributeSetting</key><integer>0</integer></dict>
  <dict><key>choiceIdentifier</key><string>choice_secure_umbrella</string><key>choiceAttribute</key><string>selected</string><key>attributeSetting</key><integer>0</integer></dict>
  <dict><key>choiceIdentifier</key><string>choice_thousandeyes</string><key>choiceAttribute</key><string>selected</string><key>attributeSetting</key><integer>0</integer></dict>
  <dict><key>choiceIdentifier</key><string>choice_duo</string><key>choiceAttribute</key><string>selected</string><key>attributeSetting</key><integer>0</integer></dict>
  <dict><key>choiceIdentifier</key><string>choice_zta</string><key>choiceAttribute</key><string>selected</string><key>attributeSetting</key><integer>0</integer></dict>
</array>
</plist>
PLIST

log "Installing Cisco Secure Client (VPN-only)…"
installer -applyChoiceChangesXML "$CHOICES_PLIST" -pkg "$PKG_PATH" -target /

# Write preconfigured VPN profile with DNS restoration
log "Creating VPN profile at: $PROFILE_PATH"
mkdir -p "$PROFILE_DIR"
cat > "$PROFILE_PATH" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<AnyConnectProfile xmlns="http://schemas.xmlsoap.org/encoding/">
  <ClientInitialization>
    <UseStartBeforeLogon UserControllable="false">false</UseStartBeforeLogon>
    <AutomaticCertSelection UserControllable="false">false</AutomaticCertSelection>
    <ShowPreConnectMessage>false</ShowPreConnectMessage>
    <CertificateStore>All</CertificateStore>
    <ProxySettings>Native</ProxySettings>
  </ClientInitialization>
  <ServerList>
    <HostEntry>
      <HostName>${VPN_NAME}</HostName>
      <HostAddress>${VPN_HOST}</HostAddress>
      <PrimaryProtocol>SSL</PrimaryProtocol>
    </HostEntry>
  </ServerList>
  
  <!-- DNS Restoration Settings - fixes Jamf Security Cloud DNS conflict -->
  <AutoConnectOnStart UserControllable="false">false</AutoConnectOnStart>
  <RestoreOnDisconnect>
    <RestoreDNSDomainName>true</RestoreDNSDomainName>
    <RestoreDNSServers>true</RestoreDNSServers>
    <RestoreWINSServers>true</RestoreWINSServers>
  </RestoreOnDisconnect>
  
  <!-- Prevent Cisco from overriding local DNS when disconnected -->
  <BypassDownloader>
    <HostDetection>false</HostDetection>
  </BypassDownloader>
</AnyConnectProfile>
XML

chown root:wheel "$PROFILE_PATH"
chmod 0644 "$PROFILE_PATH"

log "Install complete. DNS restoration configured for Jamf Security Cloud compatibility."
exit 0
