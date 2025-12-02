#!/bin/bash

# deepseek.sh - Advanced AI-powered file analysis and enhancement system
# Uses Ollama models: cube, core, loop, wave, coin, code

set -euo pipefail

# Configuration
OLLAMA_HOST="${OLLAMA_HOST:-localhost:11434}"
BACKUP_DIR="./backup_$(date +%Y%m%d_%H%M%S)"
LOG_FILE="./deepseek_analysis.log"
MODELS=("cube" "core" "loop" "wave" "line" "coin" "code" "work")

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${CYAN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    echo -e "${RED}Error: $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

# Check dependencies
check_dependencies() {
    local deps=("curl" "jq" "find" "file" "md5sum")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            error_exit "Required dependency '$dep' not found"
        fi
    done

    # Check if Ollama is accessible
    if ! curl -s "http://$OLLAMA_HOST/api/tags" &> /dev/null; then
        error_exit "Ollama not accessible at $OLLAMA_HOST. Please ensure it's running."
    fi
}

# Backup original files
backup_files() {
    log "Creating backup in $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    find . -maxdepth 1 -type f -not -name "deepseek.sh" -not -name "*.log" -not -path "./$BACKUP_DIR" -exec cp {} "$BACKUP_DIR/" \;
}

# Analyze file type and content
analyze_file() {
    local file="$1"
    local file_type
    local file_size
    local file_md5

    file_type=$(file -b "$file")
    file_size=$(stat -c%s "$file")
    file_md5=$(md5sum "$file" | cut -d' ' -f1)

    echo "File: $file"
    echo "Type: $file_type"
    echo "Size: $file_size bytes"
    echo "MD5: $file_md5"
    echo "---"
}

# Call Ollama model with prompt
call_ollama() {
    local model="$1"
    local prompt="$2"
    local context="${3:-}"

    local request_json
    if [[ -n "$context" ]]; then
        request_json=$(jq -n --arg model "$model" --arg prompt "$prompt" --arg context "$context" \
            '{model: $model, prompt: $prompt, context: $context, stream: false}')
    else
        request_json=$(jq -n --arg model "$model" --arg prompt "$prompt" \
            '{model: $model, prompt: $prompt, stream: false}')
    fi

    local response
    response=$(curl -s -X POST "http://$OLLAMA_HOST/api/generate" \
        -H "Content-Type: application/json" \
        -d "$request_json")

    if echo "$response" | jq -e '.error' &> /dev/null; then
        error_exit "Ollama API error: $(echo "$response" | jq -r '.error')"
    fi

    echo "$response" | jq -r '.response'
}

# Enhanced file analysis using AI models
ai_analyze_file() {
    local file="$1"
    local content
    content=$(cat "$file")

    log "Analyzing $file with AI models..."

    # Use different models for different aspects
    local analysis=""

    # Cube model - structural analysis
    analysis+="=== Structural Analysis (cube model) ===\n"
    analysis+=$(call_ollama "cube" "Analyze the structure and organization of this file. Focus on code structure, patterns, and architecture:\n\n$content")
    analysis+="\n\n"

    # Core model - core functionality analysis
    analysis+="=== Core Functionality (core model) ===\n"
    analysis+=$(call_ollama "core" "Analyze the core functionality and main purpose of this file. Identify key functions and operations:\n\n$content")
    analysis+="\n\n"

    # Loop model - iterative patterns and loops
    analysis+="=== Iterative Patterns (loop model) ===\n"
    analysis+=$(call_ollama "loop" "Identify iterative patterns, loops, and repetitive structures. Suggest optimizations:\n\n$content")
    analysis+="\n\n"

    # Wave model - flow and rhythm analysis
    analysis+="=== Flow Analysis (wave model) ===\n"
    analysis+=$(call_ollama "wave" "Analyze the flow, rhythm, and pacing of the code. Check for smooth execution flow:\n\n$content")
    analysis+="\n\n"

    # Coin model - value and efficiency analysis
    analysis+="=== Efficiency Analysis (coin model) ===\n"
    analysis+=$(call_ollama "coin" "Analyze the efficiency, performance, and resource usage. Suggest improvements:\n\n$content")
    analysis+="\n\n"

    # Code model - code quality and enhancements
    analysis+="=== Code Quality (code model) ===\n"
    analysis+=$(call_ollama "code" "Provide comprehensive code quality analysis and enhancement suggestions:\n\n$content")

    echo -e "$analysis"
}

# Generate enhancement recommendations
generate_enhancements() {
    local file="$1"
    local content
    content=$(cat "$file")

    log "Generating enhancement recommendations for $file..."

    local enhancements=""
    enhancements+="=== ENHANCEMENT RECOMMENDATIONS FOR $file ===\n\n"

    # Get enhancement suggestions from code model
    enhancements+=$(call_ollama "code" "Based on the following code, provide specific, actionable enhancement recommendations. Focus on:\n1. Performance improvements\n2. Code
readability\n3. Best practices\n4. Error handling\n5. Security considerations\n\nCode:\n$content")

    echo -e "$enhancements"
}

# Create enhanced version of file
create_enhanced_version() {
    local file="$1"
    local content
    content=$(cat "$file")

    log "Creating enhanced version of $file..."

    # Use multiple models to enhance the file
    local enhanced_content=""

    # First pass - structural enhancements with cube model
    enhanced_content=$(call_ollama "cube" "Rewrite and enhance the following code with improved structure and organization. Maintain functionality while improving
architecture:\n\n$content")

    # Second pass - code quality enhancements with code model
    enhanced_content=$(call_ollama "code" "Further enhance this code with best practices, improved readability, and optimizations:\n\n$enhanced_content")

    # Third pass - efficiency improvements with coin model
    enhanced_content=$(call_ollama "coin" "Optimize this code for performance and efficiency while maintaining readability:\n\n$enhanced_content")

    echo "$enhanced_content"
}

# Create specialized tools based on analysis
create_tools() {
    local analysis_dir="./ai_analysis_tools"
    mkdir -p "$analysis_dir"

    log "Creating specialized analysis tools in $analysis_dir..."

    # Create file analysis tool
    cat > "$analysis_dir/analyze_file.sh" << 'EOF'
#!/bin/bash
# AI-powered file analysis tool

FILE="${1:-}"
if [[ -z "$FILE" || ! -f "$FILE" ]]; then
    echo "Usage: $0 <file>"
    exit 1
fi

echo "=== AI File Analysis ==="
echo "File: $FILE"
echo "Size: $(stat -c%s "$FILE") bytes"
echo "Type: $(file -b "$FILE")"
echo "---"

# Basic content analysis
echo "First 10 lines:"
head -10 "$FILE"
echo "---"

echo "Last 5 lines:"
tail -5 "$FILE"
EOF

    # Create code enhancement tool
    cat > "$analysis_dir/enhance_code.sh" << 'EOF'
#!/bin/bash
# Code enhancement suggestion tool

FILE="${1:-}"
if [[ -z "$FILE" || ! -f "$FILE" ]]; then
    echo "Usage: $0 <file>"
    exit 1
fi

CONTENT=$(cat "$FILE")
OLLAMA_HOST="${OLLAMA_HOST:-localhost:11434}"

echo "=== Code Enhancement Suggestions ==="
echo "Analyzing $FILE..."

# Use curl to call Ollama for enhancements
enhancements=$(curl -s -X POST "http://$OLLAMA_HOST/api/generate" \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"code\", \"prompt\": \"Suggest specific code enhancements for:\\n\\n$CONTENT\", \"stream\": false}" | jq -r '.response')

echo "$enhancements"
EOF

    # Create batch processing tool
    cat > "$analysis_dir/batch_analyze.sh" << 'EOF'
#!/bin/bash
# Batch file analysis tool

DIR="${1:-.}"
PATTERN="${2:-*}"
OLLAMA_HOST="${OLLAMA_HOST:-localhost:11434}"

echo "=== Batch Analysis of $DIR ==="
find "$DIR" -name "$PATTERN" -type f | while read file; do
    echo "Analyzing: $file"
    echo "---"
    head -3 "$file"
    echo "..."
    echo "---"
done
EOF

    chmod +x "$analysis_dir"/*.sh

    log "Tools created in $analysis_dir/"
}

# Main orchestration function
orchestrate_analysis() {
    log "Starting AI-powered file analysis and enhancement"
    log "Using Ollama models: ${MODELS[*]}"

    # Check dependencies first
    check_dependencies

    # Create backup
    backup_files

    # Find all files in current directory
    local files
    mapfile -t files < <(find . -maxdepth 1 -type f -not -name "deepseek.sh" -not -name "*.log" -not -path "./$BACKUP_DIR")

    if [[ ${#files[@]} -eq 0 ]]; then
        log "No files found to analyze"
        return 0
    fi

    log "Found ${#files[@]} files to analyze"

    # Create analysis directory
    local analysis_dir="./ai_analysis_results"
    mkdir -p "$analysis_dir"

    # Analyze each file
    for file in "${files[@]}"; do
        local filename
        filename=$(basename "$file")

        log "Processing $filename..."

        # Basic analysis
        analyze_file "$file" > "$analysis_dir/${filename}.basic_analysis.txt"

        # AI analysis
        ai_analyze_file "$file" > "$analysis_dir/${filename}.ai_analysis.txt"

        # Generate enhancements
        generate_enhancements "$file" > "$analysis_dir/${filename}.enhancements.txt"

        # Create enhanced version
        create_enhanced_version "$file" > "$analysis_dir/${filename}.enhanced"

        log "Completed analysis for $filename"
    done

    # Create specialized tools
    create_tools

    # Generate summary report
    generate_summary_report "$analysis_dir" "${#files[@]}"

    log "Analysis complete! Results saved in $analysis_dir/"
    log "Backup created in $BACKUP_DIR"
    log "Check $LOG_FILE for detailed logs"
}

# Generate summary report
generate_summary_report() {
    local analysis_dir="$1"
    local file_count="$2"

    local summary_file="$analysis_dir/SUMMARY_REPORT.md"

    cat > "$summary_file" << EOF
# DeepSeek AI Analysis Summary Report

## Overview
- **Analysis Date**: $(date)
- **Files Analyzed**: $file_count
- **Ollama Host**: $OLLAMA_HOST
- **Models Used**: ${MODELS[*]}

## Analysis Structure
Each file was analyzed through multiple AI models:

1. **cube**: Structural and architectural analysis
2. **core**: Core functionality identification
3. **loop**: Iterative pattern analysis
4. **wave**: Execution flow analysis
5. **coin**: Efficiency and performance analysis
6. **code**: Comprehensive code quality analysis

## Generated Files per Original File
- \`.basic_analysis.txt\`: Basic file metadata and statistics
- \`.ai_analysis.txt\`: Comprehensive AI analysis from all models
- \`.enhancements.txt\`: Specific enhancement recommendations
- \`.enhanced\`: AI-rewritten enhanced version

## Tools Created
- \`analyze_file.sh\`: Individual file analysis tool
- \`enhance_code.sh\`: Code enhancement suggestion tool
- \`batch_analyze.sh\`: Batch processing tool

## Next Steps
1. Review the AI analysis reports
2. Compare original files with enhanced versions
3. Implement suggested enhancements
4. Use the created tools for ongoing analysis

## Models Used Description
- **cube**: Analyzes code structure and organization patterns
- **core**: Focuses on core functionality and purpose
- **loop**: Identifies and optimizes iterative patterns
- **wave**: Analyzes code flow and execution rhythm
- **coin**: Evaluates efficiency and resource usage
- **code**: Provides comprehensive code quality analysis

EOF

    log "Summary report generated: $summary_file"
}

# Display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

DeepSeek AI-Powered File Analysis and Enhancement System

OPTIONS:
    -h, --help      Show this help message
    -v, --version   Show version information
    --backup-only   Only create backup without analysis
    --analysis-only Only run analysis without backup
    --tools-only    Only create analysis tools

EXAMPLES:
    $0              # Full analysis with backup
    $0 --backup-only # Only backup files
    $0 --analysis-only # Analyze without backup

ENVIRONMENT VARIABLES:
    OLLAMA_HOST     Set Ollama host (default: localhost:11434)

EOF
}

# Main function
main() {
    local action="full"

    case "${1:-}" in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--version)
            echo "DeepSeek AI Analyzer v1.0.0"
            exit 0
            ;;
        --backup-only)
            action="backup"
            ;;
        --analysis-only)
            action="analysis"
            ;;
        --tools-only)
            action="tools"
            ;;
        "")
            action="full"
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac

    case "$action" in
        backup)
            backup_files
            log "Backup completed successfully"
            ;;
        analysis)
            check_dependencies
            orchestrate_analysis
            ;;
        tools)
            create_tools
            ;;
        full)
            orchestrate_analysis
            ;;
    esac
}

# Run main function with all arguments
main "$@"
