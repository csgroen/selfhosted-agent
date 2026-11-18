# Self-hosted coding agent (Ollama + OpenCode)

Run a local AI coding agent on your own GPU. Nothing leaves the cluster.

- **Model:** any [Ollama](https://ollama.com) model. The default is Qwen3.6 35B-A3B (mixture of experts: 35B parameters in total, 3B active per token, ~22 GB).
- **Agent:** [OpenCode](https://opencode.ai), a terminal coding agent that reads and writes files, runs commands and uses skills.
- **No root needed**

```
opencode ──► 127.0.0.1:11500  Ollama (qwen3.6-agent) ──► GPU
```

Tested with Ollama 0.34.2, OpenCode 2.0.19 and Qwen3.6 35B-A3B on an NVIDIA L40S (48 GB), in a Slurm cluster.

---

## Requirements

| | |
|---|---|
| GPU | NVIDIA. The default model needs **≥ 24 GB VRAM** for 128k context (L40S, A100, H100/H200…). With less, lower `MODEL_CTX` (min. 64k for OpenCode) or pick a smaller model |
| Disk | ~25 GB for the default model (in `models/`, or wherever `OLLAMA_MODELS` points) |
| RAM | ~32 GB |
| Software | `bash`, `curl`, `tar` with zstd support |
| Network | Internet access during setup (Ollama, OpenCode and model downloads) |

## Files

| File | Role |
|---|---|
| `env.sh` | All settings (model, context size, port, threads) and environment variables |
| `setup.sh` | One-time install: Ollama, model, OpenCode, OpenCode config. Idempotent |
| `start.sh` / `stop.sh` | Start/stop the Ollama server (your own processes only) |
| `modelfiles/agent.Modelfile` | Sampling settings applied on top of the base model |
| `opencode.json.template` | OpenCode provider config, filled in by `setup.sh` |
| `examples/skills/` | An example OpenCode skill (pseudobulk differential expression in R) |

---

## Step by step (on SLURM node)

### 1. Get a GPU node

On a Slurm cluster, start an interactive job with one GPU. Adapt the partition and GPU type to
your cluster (`sinfo -o "%P %G"` lists them). Example:

```bash
srun --partition=gpu --gres=gpu:l40s:1 --cpus-per-task=12 --mem=64G --time=8:00:00 --pty bash
nvidia-smi        # check that the GPU is visible
```

On a workstation with a GPU, skip this step.

### 2. Get the code

```bash
git clone <this repo> selfhosted-agent
cd selfhosted-agent
```

Put it somewhere with enough free space for the model.
You can also keep the code here and put the model elsewhere: `export OLLAMA_MODELS=/big/disk/ollama-models`.

### 3. (Optional) Change the settings

Settings live at the top of `env.sh`. You can edit them there or export them before running a script:

| Variable | Default | Notes |
|---|---|---|
| `MODEL_BASE` | `qwen3.6:35b-a3b` | Any model from [ollama.com/library](https://ollama.com/library) |
| `MODEL_NAME` | `<base>-agent` (`qwen3.6-agent`) | Name of the tuned copy that OpenCode uses |
| `MODEL_CTX` | `131072` | Context window. OpenCode needs ≥ 64k |
| `OLLAMA_PORT` | `11500` | **Change it if someone else runs Ollama on the same node**, as ports are shared between users. Avoid 11434, Ollama's default |
| `CPU_THREADS` | `12` | CPU threads outside Slurm (inside Slurm, `SLURM_CPUS_PER_TASK` is used) |
| `OLLAMA_MODELS` | `./models` | Where the weights are stored |
| `OLLAMA_KEEP_ALIVE` | `30m` | How long the model stays in VRAM after the last request |

### 4. Run the setup

```bash
bash setup.sh
```

This script:

1. **Installs Ollama** by downloading the standalone Linux build and unpacking it into `./bin` and `./lib`:
   ```bash
   curl -fL https://ollama.com/download/ollama-linux-amd64.tar.zst | tar --zstd -x -C .
   ```
2. **Starts the server** (`start.sh`). It listens on `127.0.0.1` only, so other users on the node can't reach it. Logs go to `logs/`.
3. **Downloads the model** with `ollama pull $MODEL_BASE` (~22 GB for the default, ~15–25 min at 15 MB/s).
   If the download is interrupted, rerun `setup.sh` and it will resume.
4. **Creates the agent model** `$MODEL_NAME` from `modelfiles/agent.Modelfile`. It uses the same weights (no extra disk space)
   with sampling settings for coding/agentic work. The defaults are Qwen's recommended settings for thinking mode
   (temperature 0.6, top_p 0.95, top_k 20).
5. **Installs OpenCode** (`curl -fsSL https://opencode.ai/install.sh | bash`, into `~/.opencode/bin`).
6. **Writes `~/.config/opencode/opencode.json`** from `opencode.json.template`. If you already have a different config,
   it's backed up first. The config declares one OpenAI-compatible provider, `ollama`, at
   `http://127.0.0.1:$OLLAMA_PORT/v1`, with `$MODEL_NAME` as the default model.

### 5. Check that it works

```bash
source env.sh
ollama list                       # qwen3.6:35b-a3b and qwen3.6-agent
ollama run "$MODEL_NAME" "Say hello in one word."
ollama ps                         # should show 100% GPU
```

The first request loads the model into VRAM, which takes ~30–60 s. Requests that follow are fast.
If `ollama ps` shows a CPU/GPU split, the model doesn't fit: lower `MODEL_CTX`, pick a smaller model or use a bigger GPU.

### 6. Use the agent

```bash
source /path/to/selfhosted-agent/env.sh    # puts ollama and opencode on PATH
cd /path/to/your/project
opencode
```

Inside OpenCode, `/models` shows the active model. It should be `qwen3.6-agent` (or your `MODEL_NAME`).
You can also run a one-shot task: `opencode run "Summarise what this repository does"`.

### 7. Stop it when you're done

```bash
bash stop.sh
```

This frees the GPU. The next time, you only need steps 1 and 6 plus `bash start.sh`:

```bash
srun --partition=gpu --gres=gpu:l40s:1 --cpus-per-task=12 --mem=64G --pty bash
bash /path/to/selfhosted-agent/start.sh
source /path/to/selfhosted-agent/env.sh
cd my-project && opencode
```

In an orchestrated environment, ending the job also kills the server.

---

## Switching models

1. Set `MODEL_BASE` in `env.sh`, for example `qwen3:14b` for a 16 GB GPU.
2. Check the model card for its recommended sampling settings and update `modelfiles/agent.Modelfile`.
3. Rerun `bash setup.sh`. It pulls the new model, creates `<base>-agent` and rewrites the OpenCode config.

For good results, pick a model that supports tool calling (look for the *tools* tag on ollama.com) and
a context window of at least 64k. If it's not a thinking model, remove `"reasoning": true` from
`opencode.json.template`. To free disk space, remove the old models with `ollama rm <name>`.

---

## Teaching the agent new skills

OpenCode loads *skills* from `.opencode/skills/<name>/SKILL.md` in the project, or from
`~/.config/opencode/skills/` for all projects. A skill is a Markdown file with a `name`
and a `description`. The description tells the agent when to use the skill. The body holds the
instructions and can point to scripts that come with the skill.

`examples/skills/pseudobulk-de/` is a full example. It tells the agent to use donor-level pseudobulk
DESeq2 rather than cell-level tests when comparing conditions in single-cell data, and it ships
template R scripts that the agent fills in and runs. To use it in a project:

```bash
mkdir -p my-project/.opencode/skills
cp -r examples/skills/pseudobulk-de my-project/.opencode/skills/
```

Small local models follow short, explicit skills much better than open-ended prompts. Template scripts
where the agent only edits a SETTINGS block are more reliable than asking it to write the analysis
from scratch.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `server did not come up` | Read the newest `logs/ollama-*.log`. Usually the port is taken: change `OLLAMA_PORT` |
| `address already in use` | Another program or user is on that port. Pick another `OLLAMA_PORT`, rerun `setup.sh` (it rewrites the OpenCode config) |
| Very slow answers, `ollama ps` shows CPU | There's no GPU available, or the model + context don't fit in VRAM |
| `warning: no GPU visible here` | Same as above |
| OpenCode says the context is too small | Keep `MODEL_CTX` ≥ 65536 |
| Agent loops or repeats itself | Check the sampling settings in `modelfiles/agent.Modelfile` against the model card, and start a fresh session |
