#!/usr/bin/env bash
# One-time setup: Ollama + model + OpenCode config, then starts the server (via start.sh).
# Idempotent: rerun it any time. Run it on a GPU node. Usage: bash setup.sh
# Day to day, just use: bash start.sh  /  bash stop.sh
set -euo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
source "$DIR/env.sh"
mkdir -p "$OLLAMA_MODELS" "$DIR/logs"

# 1. Ollama (standalone Linux build, unpacked into ./bin and ./lib, no root needed)
if ! command -v ollama >/dev/null; then
  echo ">>> installing ollama into $DIR"
  module load curl 2>/dev/null || true
  curl -fL https://ollama.com/download/ollama-linux-amd64.tar.zst | tar --zstd -x -C "$DIR"
fi

# 2. Server
bash "$DIR/start.sh"

# 3. Model (~22 GB for the default)
if ! ollama list | grep "^$MODEL_BASE" >/dev/null; then
  echo ">>> downloading $MODEL_BASE"
  ollama pull "$MODEL_BASE"
fi
# Same weights under a new name (no extra disk) with the sampling settings of modelfiles/agent.Modelfile
if ! ollama list | grep "^$MODEL_NAME:" >/dev/null; then
  MF=$(mktemp)
  sed "s|@MODEL_BASE@|$MODEL_BASE|" "$DIR/modelfiles/agent.Modelfile" > "$MF"
  ollama create "$MODEL_NAME" -f "$MF"
  rm -f "$MF"
fi

# 4. OpenCode + config
command -v opencode >/dev/null || { echo ">>> installing opencode"; curl -fsSL https://opencode.ai/install.sh | bash; }
CFG=~/.config/opencode/opencode.json
mkdir -p "$(dirname "$CFG")"
NEW=$(sed -e "s/@PORT@/$OLLAMA_PORT/g" -e "s/@CTX@/$MODEL_CTX/g" -e "s|@MODEL_NAME@|$MODEL_NAME|g" "$DIR/opencode.json.template")
if [ -f "$CFG" ] && [ "$(cat "$CFG")" != "$NEW" ]; then
  cp "$CFG" "$CFG.bak.$(date +%Y%m%d-%H%M%S)"
  echo ">>> existing $CFG backed up"
fi
echo "$NEW" > "$CFG"

echo ">>> setup done: cd into your project and run: opencode   |   stop with: bash $DIR/stop.sh"
