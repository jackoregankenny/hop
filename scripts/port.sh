#!/bin/sh
# @raycast.schemaVersion 1
# @raycast.title What's on Port
# @raycast.mode fullOutput
# @raycast.icon 🔌
# @raycast.argument1 { "type": "text", "placeholder": "port" }
# @raycast.description Which process is listening on a TCP port
lsof -nP -iTCP:"$1" -sTCP:LISTEN || echo "Nothing is listening on port $1"
