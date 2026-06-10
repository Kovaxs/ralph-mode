#!/usr/bin/env bash
# Ralph Mode - pi-based autonomous agent loop
# Usage: ./ralph-mode/run.sh --model <model> [max-iterations]
#        MAX_ITERATIONS=10 ./ralph-mode/run.sh --model <model>
#        ./ralph-mode/run.sh --model sonnet 10

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$(pwd)"
PROMPT_FILE="$SCRIPT_DIR/prompt.md"
PRD_FILE="$RUN_DIR/prd.json"
PROGRESS_FILE="$RUN_DIR/progress.txt"
ARCHIVE_DIR="$RUN_DIR/archive"
LAST_BRANCH_FILE="$RUN_DIR/.ralph-last-branch"
MAX_ITERATIONS="${MAX_ITERATIONS:-20}"
MODEL=""
POSITIONAL_MAX_SET=0

usage() {
  echo "Usage: $0 --model <model> [max-iterations]"
  echo "   or: MAX_ITERATIONS=10 $0 --model <model>"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "ERROR: --model requires a value"
        usage
        exit 1
      fi
      MODEL="$2"
      shift 2
      ;;
    --model=*)
      MODEL="${1#--model=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -* )
      echo "ERROR: invalid argument '$1'"
      usage
      exit 1
      ;;
    *)
      if [[ "$1" =~ ^[0-9]+$ && "$POSITIONAL_MAX_SET" -eq 0 ]]; then
        MAX_ITERATIONS="$1"
        POSITIONAL_MAX_SET=1
        shift
      else
        echo "ERROR: invalid argument '$1'"
        usage
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$MODEL" ]]; then
  echo "ERROR: --model is required"
  usage
  exit 1
fi

if [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]] || [[ "$MAX_ITERATIONS" -lt 1 ]]; then
  echo "ERROR: MAX_ITERATIONS must be a positive integer, got '$MAX_ITERATIONS'"
  exit 1
fi

if [[ ! -f "$PRD_FILE" ]]; then
  echo "ERROR: prd.json not found in $RUN_DIR"
  echo "Run plan-mode and /compile-prd first, then run this script from the project root."
  exit 1
fi

if [[ ! -f "$PROMPT_FILE" ]]; then
  echo "ERROR: prompt.md not found at $PROMPT_FILE"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but was not found in PATH"
  exit 1
fi

if ! command -v pi >/dev/null 2>&1; then
  echo "ERROR: pi is required but was not found in PATH"
  exit 1
fi

all_pass() {
  jq -e '[.userStories[] | select(.passes == false)] | length == 0' "$PRD_FILE" >/dev/null
}

remaining_count() {
  jq '[.userStories[] | select(.passes == false)] | length' "$PRD_FILE"
}

# Archive previous run if branch changed, following the official Ralph pattern.
CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
if [[ -f "$LAST_BRANCH_FILE" ]]; then
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")
  if [[ -n "$CURRENT_BRANCH" && -n "$LAST_BRANCH" && "$CURRENT_BRANCH" != "$LAST_BRANCH" ]]; then
    DATE=$(date +%Y-%m-%d)
    FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^ralph/||')
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"

    echo "Archiving previous Ralph run: $LAST_BRANCH"
    mkdir -p "$ARCHIVE_FOLDER"
    [[ -f "$PRD_FILE" ]] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [[ -f "$PROGRESS_FILE" ]] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    echo "Archived to: $ARCHIVE_FOLDER"

    {
      echo "# Ralph Progress Log"
      echo "Started: $(date)"
      echo "---"
    } > "$PROGRESS_FILE"
  fi
fi

if [[ -n "$CURRENT_BRANCH" ]]; then
  echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
fi

if [[ ! -f "$PROGRESS_FILE" ]]; then
  {
    echo "# Ralph Progress Log"
    echo "Started: $(date)"
    echo "---"
  } > "$PROGRESS_FILE"
fi

echo "Starting Ralph Mode - Max iterations: $MAX_ITERATIONS"
echo "Project root: $RUN_DIR"
echo "PRD: $PRD_FILE"
echo "Progress: $PROGRESS_FILE"

if all_pass; then
  echo "All stories already pass. Nothing to do."
  exit 0
fi

PROMPT_CONTENT="$(cat "$PROMPT_FILE")"

for i in $(seq 1 "$MAX_ITERATIONS"); do
  REMAINING=$(remaining_count)
  echo ""
  echo "==============================================================="
  echo "  Ralph Iteration $i of $MAX_ITERATIONS ($REMAINING remaining)"
  echo "==============================================================="

  OUTPUT=$(pi --model "$MODEL" -p "$PROMPT_CONTENT" 2>&1 | tee /dev/stderr) || true

  # Official Ralph-compatible stop signal. Verify prd.json too so a tool
  # echoing the prompt cannot create a false completion.
  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    if all_pass; then
      echo ""
      echo "Ralph completed all tasks!"
      echo "Completed at iteration $i of $MAX_ITERATIONS"
      exit 0
    fi
    echo "Completion signal was seen, but prd.json still has failing stories. Continuing."
  fi

  # Plan-mode MVP requirement: independently verify prd.json after each iteration.
  if all_pass; then
    echo ""
    echo "All stories pass after iteration $i."
    exit 0
  fi

  echo "Iteration $i complete. Continuing..."
  sleep 2
done

REMAINING=$(remaining_count)
echo ""
echo "Ralph reached max iterations ($MAX_ITERATIONS) with $REMAINING stories still failing."
echo "Check $PROGRESS_FILE for status."
exit 1
