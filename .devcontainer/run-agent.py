# .devcontainer/run-agent.py
import os
import sys
import subprocess
import json
import re
import google.generativeai as genai
import requests
from pathlib import Path

def run_command(command, check=True):
    """Runs a shell command and returns its output."""
    print(f"Executing: {' '.join(command)}")
    result = subprocess.run(command, capture_output=True, text=True, shell=False)
    if check and result.returncode != 0:
        print(f"Error executing command: {' '.join(command)}")
        print(result.stdout)
        print(result.stderr)
        raise Exception(f"Command failed with exit code {result.returncode}")
    print(result.stdout)
    return result

def signal_completion(job_id, status, message):
    """Sends a completion signal back to the Cloudflare Worker."""
    callback_url = os.environ.get("CALLBACK_URL")
    if not callback_url:
        print("Warning: CALLBACK_URL not set. Skipping completion signal.")
        return

    print(f"Sending completion signal for job {job_id} to {callback_url}...")
    try:
        requests.post(f"{callback_url}/complete", json={
            "jobId": job_id,
            "status": status,
            "message": message
        })
        print("Completion signal sent successfully.")
    except Exception as e:
        print(f"Error sending completion signal: {e}")

def create_pull_request(issue_key, summary, current_branch, parent_branch):
    """Creates a pull request on GitHub."""
    token = os.environ.get("GITHUB_TOKEN")
    if not token:
        print("Warning: GITHUB_TOKEN not found. Cannot create pull request.")
        return None

    remote_url = run_command(["git", "remote", "get-url", "origin"]).stdout.strip()
    match = re.search(r'github\.com[/:](.+?/.+?)(?:\.git)?$', remote_url)
    if not match:
        raise Exception("Could not parse repository owner/name from remote URL.")
    repo_path = match.group(1)

    api_url = f"https://api.github.com/repos/{repo_path}/pulls"
    headers = {'Authorization': f'token {token}', 'Accept': 'application/vnd.github.v3+json'}
    data = {'title': f'feat({issue_key}): {summary}', 'body': f'This PR addresses Jira ticket {issue_key}.', 'head': current_branch, 'base': parent_branch}

    response = requests.post(api_url, headers=headers, json=data)
    if response.status_code == 201:
        pr_data = response.json()
        print(f"Successfully created pull request: {pr_data['html_url']}")
        return pr_data['html_url']
    else:
        raise Exception(f"Failed to create pull request: {response.text}")

def main():
    """Main function to drive the AI development process."""
    job_id = None
    # The original branch name is passed as an argument
    original_branch_name = sys.argv[1]
    # Sanitize the branch name for file system operations
    sanitized_branch_name = original_branch_name.replace('/', '-')
    task_file_path = Path(f"AI_TASKS/{sanitized_branch_name}.md")

    try:
        api_key = os.environ.get("GEMINI_API_KEY")
        genai.configure(api_key=api_key)

        # 1. Read the dynamically located task file
        print(f"Reading task file: {task_file_path}")
        content = task_file_path.read_text()

        header, task_description = content.split('---\n', 1)
        header_lines = header.splitlines()
        job_id = header_lines[0].replace('jobId:', '').strip()
        parent_branch = header_lines[1].replace('parentBranch:', '').strip()

        issue_key = task_description.splitlines()[0].split(':')[0].strip('# ')
        summary = task_description.splitlines()[0].split(':', 1)[1].strip()

        # 2. Craft prompt (remains the same)
        prompt = f"""
        You are an expert Magento 2 developer working in a GitHub Codespace.
        Your task is to implement the following requirement described in Jira ticket {issue_key}.

        **Task Description:**
        ---
        {task_description}
        ---

        **Instructions:**
        1.  Analyze the request and determine the necessary code changes.
        2.  Identify the files that need to be created or modified.
        3.  If the task involves business logic, you MUST write a corresponding PHPUnit test.
        4.  If the task is a simple dependency update (e.g., 'run composer install'), your validation command should check for success (e.g., `bin/magento setup:di:compile`).
        5.  Your final output MUST be a single, valid JSON object. Do not include any other text or markdown formatting outside of the JSON.

        **JSON Output Structure:**
        {{
          "explanation": "A brief, one-sentence explanation of your plan.",
          "files": [
            {{
              "path": "path/to/your/file.php",
              "content": "The full content of the file."
            }}
          ],
          "validation_commands": [
            ["command", "arg1", "arg2"],
            ["vendor/bin/phpunit", "path/to/your/Test.php"]
          ],
          "commit_message": "feat({issue_key}): A concise and descriptive commit message"
        }}
        """

       # 3. Call Gemini API
        model = genai.GenerativeModel('gemini-1.5-flash-latest')
        response = model.generate_content(prompt)
        cleaned_response = response.text.strip().lstrip('```json').rstrip('```')
        ai_plan = json.loads(cleaned_response)

        # 4. Update the task file with the AI's plan for debugging
        print("Updating task file with AI's plan...")
        plan_explanation = ai_plan.get("explanation", "No explanation provided.")
        with task_file_path.open('a') as f:
            f.write(f"\n\n---\n\n**AI Plan of Action:**\n{plan_explanation}\n")

        run_command(["git", "add", str(task_file_path)])
        run_command(["git", "commit", "-m", f"docs: Log AI plan for {issue_key}"])

        # 5. Write files
        for file_to_write in ai_plan.get("files", []):
            file_path = Path(file_to_write["path"])
            file_path.parent.mkdir(parents=True, exist_ok=True)
            file_path.write_text(file_to_write["content"])
            run_command(["git", "add", str(file_path)])

        # 6. Run validation
        for command in ai_plan.get("validation_commands", []):
            if isinstance(command, list) and len(command) > 0:
                run_command(command)

        # 7. Commit and push feature changes
        commit_message = ai_plan.get("commit_message", f"feat({issue_key}): Complete task via AI agent")
        status_result = run_command(["git", "status", "--porcelain"], check=False)
        if status_result.stdout:
            run_command(["git", "commit", "-m", commit_message])
        else:
            print("No changes to commit.")

        run_command(["git", "push", "origin", original_branch_name])

        # 8. Create Pull Request
        pr_url = create_pull_request(issue_key, summary, original_branch_name, parent_branch)

        # 9. Archive the task file and push the change
        print("Archiving task file...")
        completed_dir = Path("AI_TASKS/completed")
        completed_dir.mkdir(exist_ok=True)
        completed_file_path = completed_dir / f"{sanitized_branch_name}.md"

        # Use 'git mv' to properly move the file within the repository
        run_command(["git", "mv", str(task_file_path), str(completed_file_path)])

        run_command(["git", "commit", "-m", f"chore: Archive task file for {issue_key}"])
        run_command(["git", "push", "origin", original_branch_name])

        # 10. Signal success
        completion_message = f"Successfully pushed changes for {issue_key}."
        if pr_url:
            completion_message += f"\nPull Request created: {pr_url}"
        signal_completion(job_id, "success", completion_message)

    except Exception as e:
        print(f"An error occurred: {e}")
        if job_id:
            signal_completion(job_id, "failure", f"An error occurred during execution: {e}")
        exit(1)

if __name__ == "__main__":
    main()