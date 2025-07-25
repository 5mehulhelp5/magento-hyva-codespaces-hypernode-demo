#!/bin/bash
set -e

TASK_FILE=$1
MAX_ATTEMPTS=5
ATTEMPT=1

# --- 1. Initialization from JSON file ---
JOB_ID=$(jq -r '.jobId' "$TASK_FILE")
PARENT_BRANCH=$(jq -r '.parentBranch' "$TASK_FILE")
ISSUE_KEY=$(jq -r '.issueKey' "$TASK_FILE")
SUMMARY=$(jq -r '.summary' "$TASK_FILE")
TASK_DESCRIPTION=$(jq -r '.description' "$TASK_FILE")

# --- 2. Setup Logging ---
LOG_FILE="/tmp/agent_log_${JOB_ID}.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "--- Agent Loop Started ---"
echo "Task File: $TASK_FILE"
echo "Log File: $LOG_FILE"

# Signal that development is starting
if [ -n "$JOB_ID" ] && [ -n "$CALLBACK_URL" ]; then
    echo "Signaling 'AI Dev In Progress' for job: $JOB_ID"
    curl -X POST -H "Content-Type: application/json" \
         -d "{\"jobId\": \"$JOB_ID\", \"targetStatus\": \"AI Dev In Progress\"}" \
         "$CALLBACK_URL/update-status"
fi

# Create the feature branch idempotently
NEW_BRANCH_NAME="feature/${ISSUE_KEY}-$(echo "$SUMMARY" | tr '[:upper:]' '[:lower:]' | tr -s ' ' '-' | cut -c 1-40)"
if git show-ref --verify --quiet "refs/heads/$NEW_BRANCH_NAME"; then
    echo "Branch '$NEW_BRANCH_NAME' already exists. Checking it out."
    git checkout "$NEW_BRANCH_NAME"
else
    echo "Branch '$NEW_BRANCH_NAME' does not exist. Creating and checking it out."
    git checkout -b "$NEW_BRANCH_NAME"
fi

LAST_ERROR="No errors yet."
FULL_HISTORY=""

# --- 3. The Main Agent Loop ---
while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    echo "--- Attempt #$ATTEMPT of $MAX_ATTEMPTS ---"
    CURRENT_ATTEMPT_HISTORY=""

    # --- Planning Step ---
    echo "Planning step: Asking Gemini for a plan..."
    PLAN_PROMPT="You are an expert developer agent. Based on this task: '${TASK_DESCRIPTION}'. The last attempt failed with this error: '${LAST_ERROR}'. The full history of the failed attempt is: '${FULL_HISTORY}'. Create a new, corrected, step-by-step plan. The plan must include writing code, writing Playwright or unit tests to validate the code, and running those tests. Your output must ONLY be the plan as a numbered list. Do not use any tool calls."

    PLAN=$(gemini -p "$PLAN_PROMPT")
    echo "Received Plan:"
    echo "$PLAN"
    CURRENT_ATTEMPT_HISTORY+="Plan:\n$PLAN\n\n"

    # --- Execution Step ---
    EXECUTION_SUCCESS=true
    echo "Execution step: Executing the plan..."

    OLD_IFS=$IFS
    IFS=$'\n'
    for STEP in $PLAN; do
        ACTION_PROMPT="You are an expert developer agent. Your task is to convert a step from a plan into a single, directly executable bash command. Do not use tool calls. Do not explain the command. Only output the raw command. For file writing, use the format 'cat > /path/to/file.js <<EOF\ncode here\nEOF'. For tests, generate real Playwright or unit tests. The step is: '${STEP}'"
        ACTION=$(gemini -p "$ACTION_PROMPT")

        echo "Executing Action for step '${STEP}':"
        echo "$ACTION"
        CURRENT_ATTEMPT_HISTORY+="Action for '${STEP}':\n$ACTION\n"

        # Capture stdout and stderr for better error reporting
        ACTION_OUTPUT=$(eval "$ACTION" 2>&1) || {
            echo "Action failed!"
            LAST_ERROR="The command for step '${STEP}' failed with output: $ACTION_OUTPUT"
            CURRENT_ATTEMPT_HISTORY+="Error: $LAST_ERROR\n"
            EXECUTION_SUCCESS=false
            break
        }
        echo "$ACTION_OUTPUT"
        CURRENT_ATTEMPT_HISTORY+="Output:\n$ACTION_OUTPUT\n\n"
    done
    IFS=$OLD_IFS

    if ! $EXECUTION_SUCCESS; then
        FULL_HISTORY="$CURRENT_ATTEMPT_HISTORY"
        ATTEMPT=$((ATTEMPT + 1))
        continue
    fi

    # --- Validation Step ---
    echo "Validation step: Running all tests..."
    VALIDATION_PROMPT="You are an expert developer agent. Generate the final validation command to run all tests for this project. Your output must ONLY be the raw, executable bash command. Do not use tool calls."
    VALIDATION_CMD=$(gemini -p "$VALIDATION_PROMPT")

    echo "Running validation: $VALIDATION_CMD"
    VALIDATION_OUTPUT=$(eval "$VALIDATION_CMD" 2>&1) || {
        LAST_ERROR="The final validation tests failed with output: $VALIDATION_OUTPUT"
        echo "$LAST_ERROR"
        CURRENT_ATTEMPT_HISTORY+="Validation Error: $LAST_ERROR\n"
        FULL_HISTORY="$CURRENT_ATTEMPT_HISTORY"
        ATTEMPT=$((ATTEMPT + 1))
        continue
    }
    echo "$VALIDATION_OUTPUT"
    echo "--- Validation Successful! Task Complete. ---"
    break # Exit the loop
done

# --- Finalization ---
if [ $ATTEMPT -gt $MAX_ATTEMPTS ]; then
    echo "--- Agent failed to complete the task after $MAX_ATTEMPTS attempts. ---"
    FAILURE_MESSAGE="Agent failed after $MAX_ATTEMPTS attempts. See log file in Codespace at ${LOG_FILE} for details. Last error: $LAST_ERROR"
    curl -X POST -H "Content-Type: application/json" \
         -d "{\"jobId\": \"$JOB_ID\", \"status\": \"failure\", \"message\": \"$FAILURE_MESSAGE\"}" \
         "$CALLBACK_URL/complete"
    exit 1
fi

echo "Finalizing: Pushing changes, creating PR, and signaling completion..."
git push origin "$NEW_BRANCH_NAME"

# Create Pull Request using curl and jq
PR_RESPONSE=$(curl -s -w "\\n%{http_code}" -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$GITHUB_REPOSITORY/pulls" \
  -d "{\"title\":\"feat($ISSUE_KEY): $SUMMARY\",\"body\":\"This PR addresses Jira ticket $ISSUE_KEY.\",\"head\":\"$NEW_BRANCH_NAME\",\"base\":\"$PARENT_BRANCH\"}")

PR_BODY=$(echo "$PR_RESPONSE" | sed '$d')
PR_STATUS=$(echo "$PR_RESPONSE" | tail -n1)

PR_URL=""
if [ "$PR_STATUS" -eq 201 ]; then
    PR_URL=$(echo "$PR_BODY" | jq -r .html_url)
    echo "Successfully created PR: $PR_URL"
else
    echo "Error creating PR. Status: $PR_STATUS, Body: $PR_BODY"
fi

COMPLETION_MESSAGE="Successfully pushed changes for ${ISSUE_KEY}. Log file available in Codespace at ${LOG_FILE}."
if [ -n "$PR_URL" ]; then
    COMPLETION_MESSAGE+="\nPull Request created: ${PR_URL}"
fi

curl -X POST -H "Content-Type: application/json" \
     -d "{\"jobId\": \"$JOB_ID\", \"status\": \"success\", \"message\": \"$COMPLETION_MESSAGE\"}" \
     "$CALLBACK_URL/complete"

echo "--- Agent Finished ---"