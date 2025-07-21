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

if [ -z "$ACTIVE_JOB_ID" ]; then
    echo "ACTIVE_JOB_ID not found. No task to run. Exiting."
    exit 0
fi

if [ -z "$CALLBACK_URL" ] || [ -z "$WORKER_AUTH_TOKEN" ]; then
    echo "CALLBACK_URL or WORKER_AUTH_TOKEN is not set. Cannot fetch task details."
    exit 1
fi

echo "Found ACTIVE_JOB_ID: $ACTIVE_JOB_ID. Fetching task details..."
TASK_FILE="/tmp/task.json"

# Fetch the task details from the worker and save to a local file
curl -s -f -X GET -H "Authorization: Bearer $WORKER_AUTH_TOKEN" \
     "$CALLBACK_URL/get-task?jobId=$ACTIVE_JOB_ID" \
     -o "$TASK_FILE"

if [ ! -s "$TASK_FILE" ]; then
    echo "Failed to download task details or task file is empty."
    exit 1
fi

echo "Task details fetched successfully. Starting agent loop in the background..."
bash .devcontainer/run-agent-loop.sh "$TASK_FILE" &

echo "--- Post-create script finished ---"