#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

echo "--- Running post-create script ---"

# Install Node.js, npm, and gemini-cli
sudo apt-get update && sudo apt-get install -y nodejs npm
npm install -g @google/gemini-cli

# Install Python dependencies
pip install requests

# Find the task file to kick off the agent
TASK_FILE=$(find AI_TASKS -name "*.md" -print -quit)

if [ -f "$TASK_FILE" ]; then
    echo "Task file found: $TASK_FILE. Starting agent loop..."
    # Launch the agent in the background so the container finishes starting
    bash .devcontainer/run-agent-loop.sh "$TASK_FILE" &
else
    echo "No task file found in AI_TASKS/. Skipping agent execution."
fi

echo "--- Post-create script finished ---"
