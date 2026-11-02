#!/bin/sh
# @raycast.schemaVersion 1
# @raycast.title Local IP Address
# @raycast.mode compact
# @raycast.icon 🌐
# @raycast.description This Mac's address on the local network
iface=$(route -n get default 2>/dev/null | awk '/interface:/ {print $2}')
ipconfig getifaddr "${iface:-en0}" || echo "Not connected"
