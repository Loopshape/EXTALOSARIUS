#!/usr/bin/env bash
FILE="$1"; OLLAMA="${OLLAMA_HOST:-localhost:11434}"
[[ -z "$FILE" || ! -f "$FILE" ]] && echo "Usage: $0 <file>" && exit 1
CONTENT=$(cat "$FILE")
curl -s -X POST "http://$OLLAMA/api/generate" -H "Content-Type: application/json" \
  -d "$(jq -n --arg model "code" --arg prompt "Enhance this code:\n$CONTENT" '{model:$model,prompt:$prompt,stream:false}')" | jq -r '.response'
