#!/bin/sh
# @raycast.schemaVersion 1
# @raycast.title Copy UUID
# @raycast.mode silent
# @raycast.icon 🆔
# @raycast.description Copies a new lowercase UUID
uuidgen | tr 'A-Z' 'a-z' | tr -d '\n' | pbcopy
