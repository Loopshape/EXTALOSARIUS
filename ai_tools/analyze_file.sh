#!/usr/bin/env bash
FILE="$1"
[[ -z "$FILE" || ! -f "$FILE" ]] && echo "Usage: $0 <file>" && exit 1
echo "File: $FILE"
file -b "$FILE"
stat -c '%s bytes' "$FILE"
