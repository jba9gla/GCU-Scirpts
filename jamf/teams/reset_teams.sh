#!/bin/bash

echo "Starting Teams Reset for macOS..."

# 1. Force Quit Teams and related processes
echo "Closing Teams and Background Processes..."
osascript -e 'tell application "Microsoft Teams" to quit' 2>/dev/null
killall "Microsoft Teams" 2>/dev/null
killall "TeamsTableMarker" 2>/dev/null

# 2. Clear Teams Cache (New and Classic)
# Note: This removes local temporary data but NOT your personal account settings stored in the cloud.
echo "Clearing Cache..."
rm -rf ~/Library/Group\ Containers/UBF8T346G9.com.microsoft.teams
rm -rf ~/Library/Containers/com.microsoft.teams2
rm -rf ~/Library/Application\ Support/Microsoft/Teams

# 3. Targeted Keychain Cleanup
# This removes the specific 'OneAuth' and 'AdalCache' tokens that cause the login loop.
echo "Removing cached credentials from Keychain..."
/usr/bin/security delete-generic-password -s "OneAuthAccount" 2>/dev/null
/usr/bin/security delete-generic-password -l "Microsoft Teams Identities Cache" 2>/dev/null
/usr/bin/security delete-generic-password -l "com.microsoft.adalcache" 2>/dev/null

echo "Reset Complete. Please restart Teams and sign in with your Personal account."
