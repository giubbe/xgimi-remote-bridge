#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
KEY="$BASE_DIR/xgimi-key.sh"

DELAY="0.15"

"$KEY" home
sleep  1
"$KEY" home
sleep  1

"$KEY" right
sleep "$DELAY"
"$KEY" right
sleep "$DELAY"
"$KEY" right
sleep "$DELAY"
"$KEY" right
sleep "$DELAY"
"$KEY" right
sleep "$DELAY"

"$KEY" ok
