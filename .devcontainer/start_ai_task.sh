#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

echo "--- Running post-create script ---"
BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
SANITIZED_BRANCH_NAME=$(echo "$BRANCH_NAME" | sed 's#/#-#g')
TASK_FILE="AI_TASKS/${SANITIZED_BRANCH_NAME}.md"

echo "Checking for task file at path: $TASK_FILE"
if [ -f "$TASK_FILE" ]; then
    echo "Task file found."

    # Extract Job ID to send back to the worker
    JOB_ID=$(grep 'jobId:' "$TASK_FILE" | cut -d ' ' -f 2)

    if [ -n "$JOB_ID" ] && [ -n "$CALLBACK_URL" ]; then
        echo "Signaling 'AI Dev In Progress' status to worker for job: $JOB_ID"
        curl -X POST -H "Content-Type: application/json" \
             -d "{\"jobId\": \"$JOB_ID\", \"targetStatus\": \"AI Dev In Progress\"}" \
             "$CALLBACK_URL/update-status"
    else
        echo "Warning: Could not find Job ID or CALLBACK_URL. Skipping status update."
    fi

    echo "Installing dependencies and running agent..."
    pip install google-generativeai requests
    python .devcontainer/run-agent.py "$BRANCH_NAME"
else
    echo "Task file not found. Skipping agent execution."
fi
echo "--- Post-create script finished ---"
