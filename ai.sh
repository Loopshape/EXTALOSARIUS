#!/usr/bin/env bash
# ai_prime.sh – orchestrator mit genesis-hash, rehash und parallelen Agenten

set -euo pipefail
OLLAMA_HOST="${OLLAMA_HOST:-localhost}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
OLLAMA_API="http://${OLLAMA_HOST}:${OLLAMA_PORT}/api/generate"
STREAM=true
KEEP_ALIVE="5m"

declare -A MODELS=(
  ["cube"]="cube"
  ["core"]="core"
  ["loop"]="loop"
  ["wave"]="wave"
  ["line"]="line"
  ["coin"]="coin"
  ["code"]="code"
  ["work"]="work"
)

LOGDIR="${HOME}/.ai_prime_logs"
mkdir -p "$LOGDIR"

call_model() {
  local agent=$1 prompt=$2 model="${MODELS[$agent]}"
  local curl_output
  curl_output=$(jq -nc --arg m "$model" --arg p "$prompt" --arg ka "$KEEP_ALIVE" --argjson st "$STREAM" \
    '{model:$m,prompt:$p,keep_alive:$ka,stream:$st}' |
  curl -s -w "%{http_code}" "$OLLAMA_API" -H "Content-Type: application/json" -d @- || echo "CURL_ERROR")

  local http_code="${curl_output: -3}"
  local response_body="${curl_output:0:$((${#curl_output}-3))}"

  if [[ "$http_code" -ne 200 ]]; then
    echo "Error calling Ollama API for agent $agent (model: $model). HTTP Code: $http_code. Response: $response_body" >&2
    return 1
  else
    echo "$response_body"
  fi
}

orchestrate() {
  local hash=$1 prompt=$2
  for agent in "${!MODELS[@]}"; do
    (
      local msg="GENESIS_HASH:$hash\nPROMPT:$prompt\nROLE:$agent"
      call_model "$agent" "$msg" | while read -r line; do
        echo "[$agent] $line"
        echo "$line" >> "$LOGDIR/$agent.log"
      done
    ) &
  done
  wait
}

orchestrate_for_rewrite() {
  local hash=$1 prompt=$2
  local agent="code" # Designate 'code' agent for rewrite
  local rewrite_output_file="${LOGDIR}/ai_rewrite_${hash}.log" # Unique log file for each rewrite

  # Ensure the log file is empty before starting
  > "$rewrite_output_file"

  echo "DEBUG: Calling model for agent '$agent' with prompt (first 100 chars): ${prompt:0:100}..." >&2

  (
    local msg="GENESIS_HASH:$hash\nPROMPT:$prompt\nROLE:$agent"
    # Call model and pipe output to log file
    call_model "$agent" "$msg" | while read -r line; do
      echo "$line" >> "$rewrite_output_file"
    done
  )
  # Wait for the background process to complete, using its PID if available
  # For simplicity here, we'll just wait a bit, or assume the subshell completes if not in background
  # Since it's not truly backgrounded with '&' anymore, this wait isn't strictly necessary for the subshell itself

  # Read the captured content and return it
  if [ -s "$rewrite_output_file" ]; then # Check if file exists and is not empty
    cat "$rewrite_output_file"
  else
    echo "DEBUG: No content captured for rewrite from agent '$agent'." >&2
    return 1
  fi
}

compute_rehash() {
  local buf=""
  for a in "${!MODELS[@]}"; do
    buf+=$(tail -n1 "$LOGDIR/$a.log" 2>/dev/null)
  done
  echo -n "$buf" | sha256sum | awk '{print $1}'
}

main() {
  local hash
  hash=$(date +%s%N | sha256sum | awk '{print $1}')
  local prompt_from_file=""
  local prompt_from_url=""
  local script_to_rewrite=""
  local full_prompt_context="" # Renamed from full_prompt to avoid confusion
  local cli_extracted_prompts="" # New variable for CLI extracted prompts

  # Argument parsing
  while getopts "f:u:r:" opt; do
    case "$opt" in
      f) 
        if [ -f "$OPTARG" ]; then
          prompt_from_file=$(cat "$OPTARG") || { echo "Error reading file: $OPTARG" >&2; exit 1; }
        else
          echo "File not found: $OPTARG" >&2; exit 1
        fi
        ;;
      u) 
        prompt_from_url=$(curl -s "$OPTARG")
        if [ $? -ne 0 ]; then
          echo "Error fetching content from URL: $OPTARG" >&2
          exit 1
        fi
        ;;
      r)
        script_to_rewrite="$OPTARG"
        if [ ! -f "$script_to_rewrite" ]; then
          echo "Script to rewrite not found: $script_to_rewrite" >&2; exit 1
        fi
        ;;
      \?) echo "Invalid option -$OPTARG" >&2; exit 1 ;;
    esac
  done
  shift $((OPTIND-1))

  # Process remaining positional arguments for hyphen-encapsulated strings
  for arg in "$@"; do
    if [[ "$arg" =~ ^-(.+)-$ ]]; then
      local extracted_string="${BASH_REMATCH[1]}"
      if [[ -n "$extracted_string" ]]; then
        if [[ -n "$cli_extracted_prompts" ]]; then
          cli_extracted_prompts+="\n"
        fi
        cli_extracted_prompts+="--- CLI Argument Start ---\n$extracted_string\n--- CLI Argument End ---"
      fi
    fi
  done

  # If content from file or url is provided, use it as part of the full prompt
  if [[ -n "$prompt_from_file" ]]; then
    full_prompt_context+="--- File Content Start ---\n$prompt_from_file\n--- File Content End ---\n\n"
  fi
  if [[ -n "$prompt_from_url" ]]; then
    full_prompt_context+="--- URL Content Start ---\n$prompt_from_url\n--- URL Content End ---\n\n"
  fi
  # Add CLI extracted prompts to the full prompt context
  if [[ -n "$cli_extracted_prompts" ]]; then
    full_prompt_context+="\n$cli_extracted_prompts\n\n"
  fi

  if [[ -n "$script_to_rewrite" ]]; then
    # Rewrite Mode
    echo "Entering rewrite mode for: $script_to_rewrite"
    local original_script_content=$(cat "$script_to_rewrite")
    local rewrite_prompt="${full_prompt_context}--- Script to Refine Start ---\n${original_script_content}\n--- Script to Refine End ---\n\nInstruction: Refine the provided script, ensuring syntax correctness, best practices, and improved clarity. Provide only the refined script content. Do not include any conversational text or explanations outside of the code. If the script is already perfect, return it as is."

    echo "Sending rewrite prompt to AI..."
    local refined_script
    if ! refined_script=$(orchestrate_for_rewrite "$hash" "$rewrite_prompt"); then
      echo "Failed to get AI refinement. Exiting rewrite mode." >&2
      exit 1
    fi
    
    if [[ -n "$refined_script" ]]; then
      echo "AI refinement complete. Overwriting $script_to_rewrite with refined content."
      echo "$refined_script" > "$script_to_rewrite"
      echo "File $script_to_rewrite successfully rewritten."
    else
      echo "AI did not return any refined content. File not modified." >&2
      exit 1
    fi
  elif [[ -n "$full_prompt_context" ]]; then
    # Non-interactive mode with collected prompts
    echo "Processing prompt from CLI arguments, file or URL..."
    orchestrate "$hash" "$full_prompt_context"
    hash=$(compute_rehash)
    echo "REHASH: $hash"
  else
    # Interactive Mode (only if no prompts from other sources)
    while true; do
      echo -n "Prompt: "
      local user_input_prompt
      read -r user_input_prompt
      [[ "$user_input_prompt" == quit ]] && break

      local final_ai_prompt="--- User Input Start ---\n$user_input_prompt\n--- User Input End ---"

      orchestrate "$hash" "$final_ai_prompt"
      hash=$(compute_rehash)
      echo "REHASH: $hash"
    done
  fi
}

main
