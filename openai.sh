#!/usr/bin/env bash
# ai.sh - Final autonomous AI orchestrator
# Features:
#  - prompt/URL fetch (or analyze ./*)
#  - DAG-aware ordering with level parallelism
#  - per-file concurrent streaming of all models
#  - auto-tuned model ordering via scoreboard + memory
#  - safe approval hook before applying patches (AUTO_APPROVE=true to bypass)
#  - per-model scoring (meta-eval using core), scoreboard updates
#  - intelligent merge (diff + patch fallback) and backups
#  - persistent memory (ai_memory.json), scoreboard (ai_scoreboard.json)
#  - automatic helper tool generation

set -euo pipefail
IFS=$'\n\t'

# ----------------------------
# CONFIGURATION (tweakable)
# ----------------------------
PROJECT_ROOT="${PROJECT_ROOT:$(pwd)}"
OLLAMA_HOST="${OLLAMA_HOST:localhost:11434}"
MAX_PARALLEL_JOBS="${MAX_PARALLEL_JOBS:8}"
TMP_DIR="${TMP_DIR:$PROJECT_ROOT/.ai_tmp}"
RESULTS_DIR="${RESULTS_DIR:$PROJECT_ROOT/ai_results}"
TOOLS_DIR="${TOOLS_DIR:$PROJECT_ROOT/ai_tools}"
BACKUP_DIR="${BACKUP_DIR:$PROJECT_ROOT/backup_$(date +%Y%m%d_%H%M%S)}"
MEMORY_FILE="${MEMORY_FILE:$PROJECT_ROOT/ai_memory.json}"
SCOREBOARD_FILE="${SCOREBOARD_FILE:$PROJECT_ROOT/ai_scoreboard.json}"
MODELS=("deepseek-v3.1:671b-cloud" "cube" "core" "loop" "wave" "line" "coin" "code" "work")
AUTO_APPROVE="${AUTO_APPROVE:true}"  # set to "true" to skip interactive approval

mkdir -p "$TMP_DIR" "$RESULTS_DIR" "$TOOLS_DIR" "$BACKUP_DIR"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'

log(){ printf "%b [%s] %s\n" "${CYAN}" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"; }
logv(){ printf "%b [%s] VERBOSE: %s%b\n" "${GREEN}" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "${NC}"; }
err(){ printf "%b%s%b\n" "${RED}" "$1" "${NC}"; }
fatal(){ err "$1"; exit 1; }

# ----------------------------
# Dependency check
# ----------------------------
check_deps(){
  local deps=(curl jq find file md5sum stat diff patch python3 sed grep awk tee)
  for d in "${deps[@]}"; do
    command -v "$d" >/dev/null 2>&1 || fatal "Required dependency '$d' not found in PATH"
  done
  # check Ollama
  if ! curl -s "http://$OLLAMA_HOST/api/tags" >/dev/null 2>&1; then
    fatal "Ollama not reachable at $OLLAMA_HOST"
  fi
}

# ----------------------------
# Init memory & scoreboard
# ----------------------------
init_state(){
  [[ -f "$MEMORY_FILE" ]] || echo "{}" > "$MEMORY_FILE"
  [[ -f "$SCOREBOARD_FILE" ]] || jq -n '{}' > "$SCOREBOARD_FILE"
}

load_memory(){ MEM_JSON=$(cat "$MEMORY_FILE"); }
save_memory(){ printf '%s' "$MEM_JSON" > "$MEMORY_FILE"; }

load_scoreboard(){ SCORE_JSON=$(cat "$SCOREBOARD_FILE"); }
save_scoreboard(){ printf '%s' "$SCORE_JSON" > "$SCOREBOARD_FILE"; }

# Ensure models have scoreboard entries
ensure_scoreboard_models(){
  load_scoreboard
  for m in "${MODELS[@]}"; do
    if ! echo "$SCORE_JSON" | jq -e --arg m "$m" '.[$m]' >/dev/null 2>&1; then
      SCORE_JSON=$(jq --arg m "$m" '.[$m] = {runs:0,applied:0,total_bytes:0,avg_latency:0,score:0}' <<< "$SCORE_JSON")
    fi
  done
  save_scoreboard
}

# ----------------------------
# Helper: fetch input (prompt text or URL) -> returns path
# ----------------------------
fetch_input(){
  local input="${1:-}"
  local out="$TMP_DIR/fetched_input.txt"
  mkdir -p "$TMP_DIR"
  if [[ -z "$input" ]]; then
    : > "$out"
  elif [[ "$input" =~ ^https?:// ]]; then
    log "Fetching URL: $input"
    curl -sL "$input" -o "$out"
  else
    printf '%s' "$input" > "$out"
  fi
  echo "$out"
}

# ----------------------------
# Build dependency graph file -> JSON map file => { "relpath": ["dep1","dep2"] }
# ----------------------------
build_dependency_graph_file(){
  local graph_json="$RESULTS_DIR/dependency_graph.json"
  : > "$graph_json"
  local -a files
  mapfile -t files < <(find "$PROJECT_ROOT" -type f -not -path "$BACKUP_DIR/*" -not -path "$RESULTS_DIR/*" -not -name "*.log")
  local tmp_entries="$TMP_DIR/graph_entries.jsonl"
  : > "$tmp_entries"
  for f in "${files[@]}"; do
    local rel; rel=$(realpath --relative-to="$PROJECT_ROOT" "$f")
    local matches
    matches=$(grep -Eo "import[[:space:]].*from[[:space:]]+['\"][^'\"]+['\"]|require\(['\"][^'\"]+['\"]\)|source[[:space:]]+['\"][^'\"]+['\"]" "$f" 2>/dev/null || true)
    local deps=()
    if [[ -n "$matches" ]]; then
      while IFS= read -r line; do
        local path; path=$(echo "$line" | grep -Eo "['\"][^'\"]+['\"]" | sed -E "s/^['\"]|['\"]$//g" | head -1 || true)
        if [[ -n "$path" ]]; then
          if [[ "$path" == ./* || "$path" == ../* || "$path" == /* ]]; then
            local cand; cand=$(realpath -m "$(dirname "$f")/$path" 2>/dev/null || true)
            if [[ -n "$cand" && -f "$cand" ]]; then
              deps+=("$(realpath --relative-to="$PROJECT_ROOT" "$cand")")
            fi
          fi
        fi
      done <<< "$matches"
    fi
    # write JSON entry
    jq -n --arg f "$rel" --argjson d "$(printf '%s\n' "${deps[@]}" | jq -R . | jq -s .)" '{file:$f,deps:$d}' >> "$tmp_entries"
  done
  # combine to map
  jq -s 'reduce .[] as $i ({}; .[$i.file] = $i.deps)' "$tmp_entries" > "$graph_json" 2>/dev/null || echo "{}" > "$graph_json"
  rm -f "$tmp_entries"
  echo "$graph_json"
}

# ----------------------------
# Produce DAG levels (list of arrays) using python
# ----------------------------
produce_dag_levels(){
  local graph_json="$1"
  local levels_file="$RESULTS_DIR/dag_levels.json"
  python3 - <<PY - "$graph_json" "$levels_file"
import sys,json
gfile=sys.argv[1]; ofile=sys.argv[2]
with open(gfile) as f:
    graph=json.load(f)
nodes=set(graph.keys())
for deps in graph.values():
    for d in deps:
        nodes.add(d)
incoming={n:set() for n in nodes}
outgoing={n:set() for n in nodes}
for n,deps in graph.items():
    for d in deps:
        if d in incoming:
            incoming[n].add(d)
            outgoing[d].add(n)
# Kahn levels
levels=[]
while True:
    ready=[n for n in list(incoming.keys()) if len(incoming[n])==0]
    if not ready:
        break
    ready_sorted=sorted(ready)
    levels.append(ready_sorted)
    for r in ready_sorted:
        incoming.pop(r,None)
        for m in list(outgoing.get(r,[])):
            incoming[m].discard(r)
        outgoing.pop(r,None)
if incoming:
    # cycles remain; append them as final level
    remain=sorted(list(incoming.keys()))
    levels.append(remain)
with open(ofile,'w') as f:
    json.dump(levels,f,indent=2)
PY
  echo "$levels_file"
}

# ----------------------------
# CALL OLLAMA streaming (writes output to file) and returns pid
# Uses stream:true where supported and falls back to non-stream call if empty
# ----------------------------
call_ollama_stream_to_file(){
  local model="$1"; local prompt="$2"; local outfile="$3"
  # ensure logfile exists
  mkdir -p "$(dirname "$outfile")"
  : > "$outfile"
  # try streaming
  curl -s -X POST "http://$OLLAMA_HOST/api/generate" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg model "$model" --arg prompt "$prompt" '{model:$model,prompt:$prompt,stream:true}')" \
    | jq -r '.response // empty' >> "$outfile" &
  local pid=$!
  echo "$pid"
}

# Non-stream fallback
call_ollama_sync_to_file(){
  local model="$1"; local prompt="$2"; local outfile="$3"
  curl -s -X POST "http://$OLLAMA_HOST/api/generate" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg model "$model" --arg prompt "$prompt" '{model:$model,prompt:$prompt,stream:false}')" \
    | jq -r '.response // ""' > "$outfile"
}

# Wrapper: try streaming then fallback if produced nothing after wait
run_model_and_wait(){
  local model="$1"; local prompt="$2"; local out="$3"
  local pid
  pid=$(call_ollama_stream_to_file "$model" "$prompt" "$out")
  # wait with timeout (e.g., 300s)
  local timeout=${MODEL_TIMEOUT:-300}
  local waited=0
  while kill -0 "$pid" 2>/dev/null; do
    sleep 1
    waited=$((waited+1))
    if (( waited >= timeout )); then
      # give up on streaming: kill and fallback
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      call_ollama_sync_to_file "$model" "$prompt" "$out"
      return 0
    fi
  done
  # streaming finished; if out empty, fallback sync
  if [[ ! -s "$out" ]]; then
    call_ollama_sync_to_file "$model" "$prompt" "$out"
  fi
  return 0
}

# ----------------------------
# Score a model output with meta-eval using the 'core' model.
# Returns JSON metrics via stdout: {"coherence":N,"improvement":N,"memorylink":N,"latency":N}
# ----------------------------
score_model_output(){
  local model="$1"; local outfile="$2"; local latency="$3"
  local text; text=$(sed 's/\"/\\\"/g' "$outfile")
  # prompt core to evaluate; ask for consistent JSON in response
  local eval_prompt="Evaluate the following model output for quality. Return JSON with keys: coherence (0-100), improvement (0-100), memorylink (0-100). Output only JSON.\n\nOutput:\n$text"
  local eval_resp
  eval_resp=$(curl -s -X POST "http://$OLLAMA_HOST/api/generate" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg model "core" --arg prompt "$eval_prompt" '{model:$model,prompt:$prompt,stream:false}')" \
    | jq -r '.response // ""')
  # try to extract JSON; fallback defaults
  local json
  if echo "$eval_resp" | jq -e . >/dev/null 2>&1; then
    json=$(echo "$eval_resp" | jq -c '.')
  else
    # try to parse numbers heuristically
    local coh=$(echo "$eval_resp" | grep -Eo 'coherence[:= ]+[0-9]+' | head -1 | grep -Eo '[0-9]+' || echo 50)
    local imp=$(echo "$eval_resp" | grep -Eo 'improv|improvement[:= ]+[0-9]+' | head -1 | grep -Eo '[0-9]+' || echo 50)
    local mem=$(echo "$eval_resp" | grep -Eo 'memory[:= ]+[0-9]+' | head -1 | grep -Eo '[0-9]+' || echo 50)
    json=$(jq -n --argjson c "$coh" --argjson i "$imp" --argjson m "$mem" '{coherence:$c,improvement:$i,memorylink:$m}')
  fi
  # add latency
  json=$(jq --argjson lat "$latency" '. + {latency:$lat}' <<< "$json")
  echo "$json"
}

# ----------------------------
# Update scoreboard with metrics (SCORE_JSON variable)
# ----------------------------
update_scoreboard_with_metrics(){
  local model="$1"; local metrics_json="$2"
  load_scoreboard
  local prev; prev=$(jq -r --arg m "$model" '.[$m] // {}' <<< "$SCORE_JSON")
  # compute aggregated statistics (simple running averages)
  SCORE_JSON=$(jq --arg m "$model" --argjson met "$metrics_json" '
    ($met) as $metobj |
    (.[$m] // {runs:0,applied:0,total_bytes:0,avg_latency:0,score:0}) as $cur |
    ($cur | .runs) as $runs |
    ($cur | .avg_latency) as $avglat |
    ($cur | .score) as $sc |
    ($metobj.latency) as $latency |
    ($metobj.coherence) as $coh |
    ($metobj.improvement) as $imp |
    ($metobj.memorylink) as $mem |
    # new averages
    .[$m] = {
      runs: ($cur.runs + 1),
      applied: ($cur.applied // 0),
      total_bytes: ($cur.total_bytes // 0),
      avg_latency: ((($cur.avg_latency // 0) * ($cur.runs) + $latency) / ($cur.runs + 1)),
      score: (($coh + $imp + $mem) / 3) - (0.1 * ($latency/100))
    }
  ' <<< "$SCORE_JSON")
  save_scoreboard
}

# After a file merge is applied, mark models that produced differing output as applied++
mark_models_applied_for_file(){
  local fdir="$1"; local rel="$2"
  local orig="$PROJECT_ROOT/$rel"
  for m in "${MODELS[@]}"; do
    local mout="$fdir/model_${m}.txt"
    if [[ -f "$mout" ]]; then
      if [[ -f "$orig" ]]; then
        if ! diff -u "$orig" "$mout" >/dev/null 2>&1; then
          # increment applied count
          load_scoreboard
          SCORE_JSON=$(jq --arg m "$m" '.[$m].applied = (.[$m].applied // 0) + 1' <<< "$SCORE_JSON")
          save_scoreboard
        fi
      else
        # new file -> consider applied
        load_scoreboard
        SCORE_JSON=$(jq --arg m "$m" '.[$m].applied = (.[$m].applied // 0) + 1' <<< "$SCORE_JSON")
        save_scoreboard
      fi
    fi
  done
}

# ----------------------------
# Autotune model order: sort models by scoreboard.score desc; fallback to configured MODELS
# ----------------------------
autotune_model_order(){
  load_scoreboard
  local count; count=$(echo "$SCORE_JSON" | jq 'length')
  if [[ "$count" -eq 0 ]]; then
    echo "${MODELS[@]}"
    return
  fi
  # select models that are present in SCORE_JSON; sort by score desc
  local ordered
  ordered=$(echo "$SCORE_JSON" | jq -r 'to_entries | sort_by(.value.score) | reverse | .[].key' || true)
  # keep only models present in MODELS, preserve others after
  local result=()
  for m in $ordered; do
    for want in "${MODELS[@]}"; do
      if [[ "$m" == "$want" ]]; then
        result+=("$m")
      fi
    done
  done
  # append any missing models
  for w in "${MODELS[@]}"; do
    if ! printf '%s\n' "${result[@]}" | grep -xq "$w"; then
      result+=("$w")
    fi
  done
  echo "${result[@]}"
}

# ----------------------------
# Safe approval: show diff to user, or apply automatically if AUTO_APPROVE=true, or skip if no tty
# ----------------------------
safe_apply_patch(){
  local difffile="$1"; local orig="$2"; local fdir="$3"
  if [[ ! -s "$difffile" ]]; then
    echo "nochange"
    return 0
  fi
  if [[ "$AUTO_APPROVE" == "true" ]]; then
    if patch -p0 --forward < "$difffile" 2>/dev/null; then
      echo "applied"
    else
      # fallback replace
      mv "$fdir/enhanced_file" "$orig"
      echo "replaced"
    fi
    return 0
  fi
  # interactive if tty
  if [[ -t 0 && -t 1 ]]; then
    echo "------------------------------"
    echo "File: $orig"
    echo "Diff saved at: $difffile"
    echo "Preview first 200 lines of diff? [y/N]"
    read -r ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
      sed -n '1,200p' "$difffile" || true
      echo "-----"
    fi
    echo "Apply patch? [y/N]"
    read -r apply
    if [[ "$apply" =~ ^[Yy]$ ]]; then
      if patch -p0 --forward < "$difffile" 2>/dev/null; then
        echo "applied"
      else
        # fallback replace
        mv "$fdir/enhanced_file" "$orig"
        echo "replaced"
      fi
    else
      echo "skipped"
    fi
  else
    log "No TTY: diff saved to $difffile; skipping apply."
    echo "skipped"
  fi
}

# ----------------------------
# Per-file processing:
#  - run all models concurrently (ordered by autotune)
#  - collect outputs to fdir/model_<model>.txt
#  - meta-evaluate each output (score_model_output)
#  - build final enhanced content (simple merge strategy: choose best-scored output or combine - here we choose highest 'score' output)
#  - produce merge.diff and call safe_apply_patch
#  - update memory & scoreboard
# ----------------------------
process_file(){
  local fullpath="$1"
  local rel; rel=$(realpath --relative-to="$PROJECT_ROOT" "$fullpath")
  local fdir="$RESULTS_DIR/$rel"
  mkdir -p "$fdir"
  : > "$fdir/verbose_log.txt"

  log "Processing file: $rel"

  # metadata
  local ftype fsize fmd5
  ftype=$(file -b "$fullpath" 2>/dev/null || echo unknown)
  fsize=$(stat -c%s "$fullpath" 2>/dev/null || echo 0)
  fmd5=$(md5sum "$fullpath" 2>/dev/null | awk '{print $1}' || echo 0)
  printf "File: %s\nType: %s\nSize: %s\nMD5: %s\n" "$rel" "$ftype" "$fsize" "$fmd5" > "$fdir/basic_analysis.txt"

  # decide model order
  local order; order=($(autotune_model_order))
  logv "Model order: ${order[*]}"

  # prepare prompt for models: include memory summary context if present
  load_memory
  local memsum; memsum=$(jq -r --arg f "$rel" '.[$f].summary // ""' <<< "$MEM_JSON")
  local base_content; base_content=$(cat "$fullpath")
  local prompt_prefix
  if [[ -n "$memsum" && "$memsum" != "null" ]]; then
    prompt_prefix="Previous memory summary:\n$memsum\n\nFile content:\n$base_content"
  else
    prompt_prefix="File content:\n$base_content"
  fi

  # launch all models concurrently, store pids
  declare -A pid_map out_map startts_map
  for m in "${order[@]}"; do
    local mout="$fdir/model_${m}.txt"
    : > "$mout"
    startts_map["$m"]="$(date +%s)"
    # run streaming in background
    # Each run appends to its file; we will wait and then fallback if empty
    call_ollama_stream_to_file "$m" "$prompt_prefix" "$mout" &
    pid_map["$m"]=$!
    out_map["$m"]="$mout"
  done

  # Wait for all models to finish (simple wait loop)
  for m in "${order[@]}"; do
    local pid=${pid_map["$m"]}
    if [[ -n "$pid" ]]; then
      wait "$pid" 2>/dev/null || true
      local endts; endts=$(date +%s)
      local start=${startts_map["$m"]}
      local latency=$((endts - start))
      # if model output file empty, run sync fallback
      local mout=${out_map["$m"]}
      if [[ ! -s "$mout" ]]; then
        call_ollama_sync_to_file "$m" "$prompt_prefix" "$mout"
      fi
      # score
      local metrics; metrics=$(score_model_output "$m" "$mout" "$latency")
      # update scoreboard with metrics
      update_scoreboard_with_metrics "$m" "$metrics"
    fi
  done

  # pick best model output by scoreboard score (choose highest score in SCORE_JSON)
  load_scoreboard
  local best_model; best_model=$(echo "$SCORE_JSON" | jq -r 'to_entries | sort_by(.value.score) | reverse | .[0].key' || echo "")
  # if best_model produced output, use it; otherwise fallback to combined heuristic (take code model, else first)
  local final_out="$fdir/final_enhanced.txt"
  if [[ -n "$best_model" && -f "$fdir/model_${best_model}.txt" && -s "$fdir/model_${best_model}.txt" ]]; then
    cp -p "$fdir/model_${best_model}.txt" "$final_out"
  elif [[ -f "$fdir/model_code.txt" && -s "$fdir/model_code.txt" ]]; then
    cp -p "$fdir/model_code.txt" "$final_out"
  else
    # fallback: choose longest output among models
    local longest=""
    local maxbytes=0
    for m in "${order[@]}"; do
      local p="$fdir/model_${m}.txt"
      if [[ -f "$p" ]]; then
        local b; b=$(wc -c < "$p" 2>/dev/null || echo 0)
        if (( b > maxbytes )); then
          maxbytes=$b; longest="$p"
        fi
      fi
    done
    if [[ -n "$longest" ]]; then cp -p "$longest" "$final_out"; else printf '%s' "$base_content" > "$final_out"; fi
  fi

  # produce diff against original (if exists)
  local orig="$PROJECT_ROOT/$rel"
  if [[ -f "$orig" ]]; then
    cp -p "$orig" "$orig.bak"
    diff -u "$orig" "$final_out" > "$fdir/merge.diff" || true
  else
    diff -u /dev/null "$final_out" > "$fdir/merge.diff" || true
  fi

  # Safe apply patch
  local apply_status; apply_status=$(safe_apply_patch "$fdir/merge.diff" "$orig" "$fdir")
  if [[ "$apply_status" == "applied" || "$apply_status" == "replaced" ]]; then
    # mark models that produced differing outputs as applied++
    mark_models_applied_for_file "$fdir" "$rel"
  fi

  # Update memory (short summary)
  local summary; summary=$(head -n 40 "$final_out" | sed -n '1,40p' || :)
  load_memory
  MEM_JSON=$(jq --arg f "$rel" --arg s "$summary" '.[$f] = { last_update: ('"$(date +%s)"'), summary:$s }' <<< "$MEM_JSON")
  save_memory

  logv "Processed $rel -> apply_status=$apply_status ; results in $fdir"
}

# ----------------------------
# Main orchestration loop:
#  - fetch input
#  - if input non-empty treat as single content file
#  - else build DAG, produce levels, process levels sequentially
# ----------------------------
main(){
  local input="${1:-}"
  check_deps
  init_state
  ensure_scoreboard_models
  generate_tools(){
    mkdir -p "$TOOLS_DIR"
    cat > "$TOOLS_DIR/analyze_file.sh" <<'EOF'
#!/usr/bin/env bash
FILE="$1"
[[ -z "$FILE" || ! -f "$FILE" ]] && echo "Usage: $0 <file>" && exit 1
echo "File: $FILE"
file -b "$FILE"
stat -c '%s bytes' "$FILE"
EOF
    cat > "$TOOLS_DIR/enhance_code.sh" <<'EOF'
#!/usr/bin/env bash
FILE="$1"; OLLAMA="${OLLAMA_HOST:-localhost:11434}"
[[ -z "$FILE" || ! -f "$FILE" ]] && echo "Usage: $0 <file>" && exit 1
CONTENT=$(cat "$FILE")
curl -s -X POST "http://$OLLAMA/api/generate" -H "Content-Type: application/json" \
  -d "$(jq -n --arg model "code" --arg prompt "Enhance this code:\n$CONTENT" '{model:$model,prompt:$prompt,stream:false}')" | jq -r '.response'
EOF
    chmod +x "$TOOLS_DIR"/*.sh
  }
  generate_tools
  backup_files(){
    log "Backing up project files to $BACKUP_DIR"
    find "$PROJECT_ROOT" -type f -not -path "$BACKUP_DIR/*" -not -path "$RESULTS_DIR/*" -not -name "*.log" -exec cp --parents {} "$BACKUP_DIR/" \;
  }
  backup_files

  local fetched; fetched=$(fetch_input "$input")

  # if fetched file has content (prompt or external file), process it as temporary content
  if [[ -s "$fetched" ]]; then
    log "Processing fetched input as temporary content"
    # write to temp path and process as temporary file (no merge into project unless interactive decisions specify)
    local tfile; tfile=$(mktemp "$TMP_DIR/tempfile.XXXXXX")
    cp -p "$fetched" "$tfile"
    process_file "$tfile"
    rm -f "$tfile"
    log "Finished fetched input processing"
    exit 0
  fi

  # Build dependency graph and DAG levels
  local graph_json levels_json
  graph_json=$(build_dependency_graph_file)
  levels_json=$(produce_dag_levels "$graph_json")
  # read levels and process sequentially; nodes in each level in parallel (bounded by MAX_PARALLEL_JOBS)
  local levels_count; levels_count=$(jq 'length' "$levels_json" 2>/dev/null || echo 0)
  if (( levels_count == 0 )); then
    # no graph: fallback to all files
    mapfile -t allfiles < <(find "$PROJECT_ROOT" -type f -not -path "$BACKUP_DIR/*" -not -path "$RESULTS_DIR/*" -not -name "*.log")
    for f in "${allfiles[@]}"; do
      process_file "$f"
    done
  else
    for idx in $(seq 0 $((levels_count-1))); do
      # get array at index idx
      mapfile -t nodes < <(jq -r ".[$idx][]?" "$levels_json" 2>/dev/null || true)
      if (( ${#nodes[@]} == 0 )); then
        continue
      fi
      log "Processing DAG level $((idx+1)) with ${#nodes[@]} node(s)"
      # run nodes in parallel up to MAX_PARALLEL_JOBS
      local pids=()
      for rel in "${nodes[@]}"; do
        local full="$PROJECT_ROOT/$rel"
        if [[ -f "$full" ]]; then
          process_file "$full" &
          pids+=($!)
          # throttle
          while (( $(jobs -r | wc -l) >= MAX_PARALLEL_JOBS )); do sleep 0.25; done
        fi
      done
      # wait for this level to complete
      wait
      log "Completed level $((idx+1))"
    done
  fi

  log "Orchestration complete. Scoreboard at $SCOREBOARD_FILE ; Memory at $MEMORY_FILE ; Results at $RESULTS_DIR"
}

main "$@"

