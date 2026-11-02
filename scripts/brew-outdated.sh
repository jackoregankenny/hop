#!/bin/sh
# @raycast.schemaVersion 1
# @raycast.title Outdated Homebrew Packages
# @raycast.mode fullOutput
# @raycast.icon 🍺
# @raycast.packageName Homebrew
brew outdated --verbose || echo "Homebrew is not installed"
