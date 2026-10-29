#!/bin/zsh
set -eu
cd "$(dirname "$0")"

# Override DEVECO_APP if DevEco Studio is installed elsewhere on macOS.
DEVECO_APP="${DEVECO_APP:-/Applications/DevEco-Studio.app}"
NODE_BIN="$DEVECO_APP/Contents/tools/node/bin/node"
HVIGOR_BIN="$DEVECO_APP/Contents/tools/hvigor/bin/hvigorw.js"
if [[ ! -x "$NODE_BIN" || ! -f "$HVIGOR_BIN" ]]; then
  print -u2 'DevEco Studio was not found. Set DEVECO_APP to its application path.'
  exit 1
fi
export JAVA_HOME="${JAVA_HOME:-$DEVECO_APP/Contents/jbr/Contents/Home}"
export DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-$DEVECO_APP/Contents/sdk}"
"$NODE_BIN" "$HVIGOR_BIN" \
  --mode module -p module=entry@default -p product=default \
  -p buildMode=release assembleHap --no-daemon
