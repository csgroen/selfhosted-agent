#!/usr/bin/env bash
# Start the Ollama server in the background (skips it if it is already running).
# Run it on the GPU node. Usage: bash start.sh
set -euo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
source "$DIR/env.sh"
mkdir -p "$DIR/logs"

nvidia-smi >/dev/null 2>&1 || echo ">>> warning: no GPU visible here, the model would run on CPU (use a GPU node)"

# Server (only looks at your own processes: other users may run Ollama on the same node)
if pgrep -u "$USER" -f "(^|/)ollama serve" >/dev/null; then
  echo ">>> server already running"
else
  LOG="$DIR/logs/ollama-$(date +%Y%m%d-%H%M%S).log"
  echo ">>> starting server on $OLLAMA_HOST, log: $LOG"
  nohup ollama serve > "$LOG" 2>&1 &
fi
timeout 60 bash -c "until curl -sf http://$OLLAMA_HOST/api/version >/dev/null; do sleep 1; done" \
  || { echo ">>> server did not come up, see $DIR/logs/"; exit 1; }

echo ">>> ready: opencode   |   stop with: bash $DIR/stop.sh"
