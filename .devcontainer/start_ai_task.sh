#!/bin/bash
set -e 

LOCK_FILE="/tmp/agent.lock"
if [ -f "$LOCK_FILE" ]; then
    echo "Agent lock file found. Another agent process may be running. Exiting post-create script."
    exit 0
fi

echo "--- Running post-create script ---"

if [ -z "$CALLBACK_URL" ] || [ -z "$WORKER_AUTH_TOKEN" ]; then
    echo "CALLBACK_URL or WORKER_AUTH_TOKEN is not set. Cannot claim a task."
    exit 1
fi

echo "Attempting to claim a task from the queue..."
TASK_FILE="/tmp/task.json"

# Use curl to claim a task from the worker and save it to a local file
# The --fail flag will cause curl to exit with an error if the HTTP request fails (e.g., 404 Not Found)
if curl -s -f -X POST -H "Authorization: Bearer $WORKER_AUTH_TOKEN" \
     "$CALLBACK_URL/claim-task" \
     -o "$TASK_FILE"; then

    if [ ! -s "$TASK_FILE" ]; then
        echo "Claimed task file is empty. No task to run."
        exit 0
    fi

    echo "Task claimed successfully. Starting agent loop in the background..."
    touch "$LOCK_FILE" # Create the lock file before starting the agent
    bash .devcontainer/run-agent-loop.sh "$TASK_FILE" &
else
    echo "Failed to claim a task from the queue. The queue might be empty. Exiting."
    exit 0
fi

echo "--- Post-create script finished ---"
