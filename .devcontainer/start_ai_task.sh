#!/bin/bash
set -e 

LOCK_FILE="/tmp/agent.lock"
if [ -f "$LOCK_FILE" ]; then
    echo "Agent lock file found. Another agent process may be running. Exiting post-create script."
    exit 0
fi
touch "$LOCK_FILE"
# Ensure lock file is removed when the script exits
trap 'rm -f "$LOCK_FILE"' EXIT

echo "--- Running post-create script ---"

if [ -z "$CALLBACK_URL" ] || [ -z "$WORKER_AUTH_TOKEN" ]; then
    echo "CALLBACK_URL or WORKER_AUTH_TOKEN is not set. Cannot claim a task."
    exit 1
fi

echo "Attempting to claim a task from the queue..."
TASK_FILE="/tmp/task.json"

# Use curl to claim a task from the worker's queue
HTTP_STATUS=$(curl -s -w "%{http_code}" -X POST \
     -H "Authorization: Bearer $WORKER_AUTH_TOKEN" \
     "$CALLBACK_URL/claim-task" \
     -o "$TASK_FILE")

if [ "$HTTP_STATUS" -ne 200 ]; then
    echo "Failed to claim a task. Worker responded with status $HTTP_STATUS. No tasks in queue or an error occurred."
    cat "$TASK_FILE" # Print response body for debugging
    exit 0
fi

if [ ! -s "$TASK_FILE" ]; then
    echo "Claimed task but the received file is empty."
    exit 1
fi

echo "Task claimed successfully. Starting agent loop in the background..."
bash .devcontainer/run-agent-loop.sh "$TASK_FILE" &

echo "--- Post-create script finished ---"