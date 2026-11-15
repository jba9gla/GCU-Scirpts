#!/bin/bash
# Jamf Pro extension attribute (String): last 5 entries from the Wi-Fi removal log
LOG="/var/log/remove_wifi_network.log"
if [ -f "$LOG" ]; then
  echo "<result>$(tail -n 5 "$LOG")</result>"
else
  echo "<result>No removals logged</result>"
fi
