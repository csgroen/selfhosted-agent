# Settings and environment for the self-hosted agent.
# Sourced by setup.sh / start.sh; in a new shell run: source env.sh
# Every value can be overridden by exporting it before sourcing this file.

AGENT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

: "${MODEL_BASE:=qwen3.6:35b-a3b}"           # Ollama model to pull. Default: Qwen3.6 MoE, 35B total / 3B active, ~22 GB
: "${MODEL_NAME:=${MODEL_BASE%%:*}-agent}"  # name of the tuned copy that OpenCode uses (here: qwen3.6-agent)
: "${MODEL_CTX:=131072}"                    # context window; OpenCode needs >= 64k
: "${OLLAMA_PORT:=11500}"                   # pick another one if a colleague already uses it on the same node
: "${CPU_THREADS:=12}"                      # used when not inside a Slurm job

export PATH=$AGENT_DIR/bin:$HOME/.opencode/bin:$PATH
export OLLAMA_MODELS=${OLLAMA_MODELS:-$AGENT_DIR/models}
export OLLAMA_HOST=127.0.0.1:$OLLAMA_PORT
export OLLAMA_CONTEXT_LENGTH=$MODEL_CTX
export OLLAMA_FLASH_ATTENTION=1
export OLLAMA_KEEP_ALIVE=${OLLAMA_KEEP_ALIVE:-30m}
export LLAMA_ARG_THREADS=${SLURM_CPUS_PER_TASK:-$CPU_THREADS}
export AGENT_DIR MODEL_BASE MODEL_NAME MODEL_CTX OLLAMA_PORT
