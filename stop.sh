#!/usr/bin/env bash
# Stop your Ollama server (frees the GPU).
# Only your own processes are stopped: other users' Ollama servers on the node are left alone.
# Usage: bash stop.sh
pkill -u "$USER" -f "(^|/)ollama serve" && echo ">>> server stopped" || echo ">>> server was not running"
