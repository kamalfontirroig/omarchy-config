# Gemini Agent's Approach to Project Interaction

This document outlines the methodology and principles employed by the Gemini AI agent when interacting with and modifying the 'remarchy' project. It serves as a meta-documentation, explaining *how* the agent approaches tasks rather than *what* the project itself does (which is covered in `README.md`).

## Core Principles

1.  **Contextual Understanding:** Before any modification, the agent prioritizes a deep understanding of the existing codebase. This involves:
    *   **Reading Existing Code:** Analyzing relevant scripts, functions, and configuration files.
    *   **Adhering to Conventions:** Mimicking existing coding style, naming conventions, and architectural patterns.
    *   **Dependency Awareness:** Identifying and respecting established libraries, frameworks, and external tools.

2.  **Iterative Development & Planning:** Complex tasks are broken down into smaller, manageable sub-tasks. A clear plan is formulated, often involving:
    *   **Step-by-Step Execution:** Addressing one aspect of the problem at a time.
    *   **Intermediate Verification:** Testing and confirming changes at each stage.
    *   **Refinement:** Adapting the plan based on new information or unexpected outcomes.

3.  **Tool-Driven Execution:** The agent leverages a suite of specialized tools for precise and efficient interaction with the filesystem and shell:
    *   `read_file`: For understanding file contents.
    *   `write_file`: For creating new files or overwriting existing ones.
    *   `replace`: For making targeted modifications to file content.
    *   `run_shell_command`: For executing shell commands (e.g., `git`, `ls`, `pacman`).
    *   `glob`, `search_file_content`: For codebase exploration and targeted searches.

4.  **User Collaboration & Feedback:** The agent actively seeks and incorporates user feedback. When an issue is identified (e.g., a bug in implementation), the agent re-evaluates its approach, debugs, and iterates until the problem is resolved to the user's satisfaction.

5.  **Safety and Idempotence:** Changes are executed carefully, with an emphasis on understanding potential impacts. The agent strives to make changes that are robust and, where appropriate, idempotent (producing the same result regardless of how many times they are applied). **Crucially, the agent will never push code to a remote repository without explicit instruction from the user.**

## Workflow Example (High-Level)

1.  **Request Interpretation:** Analyze the user's request, identifying the core problem or desired feature.
2.  **Initial Investigation:** Use tools like `read_file` or `search_file_content` to gather relevant information from the codebase.
3.  **Strategic Planning:** Formulate a detailed plan, often broken into sub-tasks, to address the request.
4.  **Implementation Phase:** Execute the plan using `replace`, `write_file`, and `run_shell_command` to modify code, create files, or run system commands.
5.  **Verification & Testing:** Run tests, check outputs, and confirm that the changes behave as expected. This often involves running the modified script with various arguments.
6.  **Debugging & Refinement:** If issues arise, analyze error messages, re-evaluate the implementation, and apply corrective actions.
7.  **Documentation:** Update relevant documentation (e.g., `README.md`) to reflect new features or changes in usage.

## Specific Strategies Employed in This Project

During the development of features for 'remarchy.sh', the following specific strategies were applied:

*   **Argument Parsing Refactoring:** When an initial attempt at adding the `-q` (qualifier) option led to incorrect parsing, the agent re-evaluated the entire argument parsing mechanism. It moved from an interleaved parsing/action model to a two-pass approach (parse all arguments, then execute action), ensuring all options were correctly processed before any commands were run.
*   **Dynamic Log File Naming Debugging:** The issue of multiple log files being generated per execution was identified. The agent traced this to the `LOG_FILE` variable being re-evaluated on every `log` call. The solution involved initializing `LOG_FILE` once, *after* all arguments (including the qualifier) had been parsed, ensuring a single, correctly named log file per script execution.
*   **Dependency Management Integration:** The agent identified external dependencies (`jq`, `git`, `rsync`) and systematically integrated their installation into the `init_script` via `dependencies.txt`, centralizing setup.
*   **Proactive Error Handling:** The `log` function was enhanced to detect common "command not found" errors and provide actionable advice (running `--init`), improving user experience.
*   **Documentation Synchronization:** All functional changes were accompanied by updates to `README.md`, ensuring the project's documentation remained accurate and reflected the latest usage instructions and features.

## Limitations and Considerations

While the agent strives for autonomous and robust development, human oversight remains invaluable for:

*   **Architectural Decisions:** Complex system-wide architectural changes often benefit from human strategic input.
*   **Subjective Design Choices:** User interface design, aesthetic preferences, or highly subjective code style decisions.
*   **Novel Problem Domains:** Tasks requiring understanding of entirely new or highly specialized domains not covered by its training data.

This `GEMINI.md` aims to provide transparency into the agent's operational methodology, fostering a more effective collaboration between the user and the AI.

# remarchy.sh Feature Specifications

This document details the expected behavior and requirements for each feature of the `remarchy.sh` script.

## 1. `init` (`-i, --init`)

**Description:** Adds the script as an alias named `remarchy` and installs dependencies.

**Detailed Specifications:**
*   **Alias Creation:**
    *   Should add `alias remarchy='/path/to/remarchy.sh'` to the user's shell configuration file (`.bashrc` or `.zshrc`).
    *   If the alias already exists, it should update the path if necessary.
    *   Should handle cases where neither `.bashrc` nor `.zshrc` are found.
*   **Dependency Installation:**
    *   Reads `dependencies.txt` from the script's directory.
    *   Installs each package listed in `dependencies.txt` using `sudo pacman -S --noconfirm`.
    *   If it fails to find the package with pacman, it will use yay.
    *   Should handle cases where `dependencies.txt` is not found (log a warning).
    *   Should log detailed output (stdout/stderr) of `pacman` commands, especially on failure.
    *   Should be robust against missing newline characters at the end of `dependencies.txt`.
*   **Logging:**
    *   All actions should be logged to a file in the `logs/` directory.
    *   Log file name should include a timestamp and an optional qualifier.
    *   Log entries should be in JSON format, including timestamp, level, component, message, status code, and command output.
*   **Error Handling:**
    *   Exit with a non-zero status code on critical failures (e.g., `jq` not installed, shell config not found, dependency installation failure).
    *   Provide actionable recommendations for common errors (e.g., "command not found" for dependencies).

## 2. `restore-config` (`-r, --restore-config`)

**Description:** Restores backed-up files and folders from the `backup` directory to their original locations.

**Detailed Specifications:**
*   **Backup Existing Configs:**
    *   Before restoring, existing configurations that would be overwritten should be backed up to a temporary location (e.g., `SCRIPT_DIR/pre_restore_backup/`).
    *   The backup process should handle both files and directories, preserving their original relative paths.
*   **Restore New Configs:**
    *   Uses `rsync` to copy configurations from `SCRIPT_DIR/backup/` to their original locations (e.g., `~/.config/`, `~/.local/share/omarchy/`).
    *   `rsync` should create destination directories idempotently if they don't exist.
*   **Hyprland Reload:**
    *   If `hyprctl` is available, it should attempt to reload the Hyprland configuration.
    *   Log a warning if `hyprctl` fails or is not found.
*   **Logging:**
    *   All actions should be logged, including `rsync` output on success/failure.
*   **Error Handling:**
    *   Exit on `rsync` failures.

## 3. `backup-config` (`-b, --backup-config`)

**Description:** Backs up specified files and folders from the system to the repository, not limited to just configuration files.

**Detailed Specifications:**

*   **`backup_list.txt`:** This file lists the specific files and folders to be backed up. Each line should contain an absolute path or a path relative to the user's home directory (`~`). Folders listed will be backed up recursively. Lines starting with `#` are treated as comments.
*   **Rsync Operations:**
    *   Reads `backup_list.txt` to determine which files and folders to back up.
    *   For each entry in `backup_list.txt`:
        *   The file or folder is copied from its source location to the `SCRIPT_DIR/backup/` directory.
        *   The original relative file structure of the backed-up item is preserved within the `SCRIPT_DIR/backup/` directory. For example, if `~/.config/nvim/init.lua` is backed up, it will be stored as `SCRIPT_DIR/backup/~/.config/nvim/init.lua`.
    *   Excludes files and folders specified in `skip_folders.txt` from the backup.
    *   `rsync` should create destination directories idempotently if they don't exist.
    *   Log detailed `rsync` output on success/failure.
*   **Git Operations (Conditional):**
    *   If `--no-push` flag is *not* set:
        *   Do not fetch, pull or rebase the current branch. We assume we are at par with remote.
        *   Never force push.
        *   Stage changes within the `SCRIPT_DIR/backup/` directory.
        *   Commit changes with a descriptive message including a timestamp and optional qualifier.
        *   Push changes to `origin/<current_branch>`.
    *   If `--no-push` flag *is* set:
        *   **No git add, commit, pull, fetch, rebase, or push operations should be performed.**
        *   Log messages indicating that git operations are skipped.
*   **Logging:**
    *   All actions should be logged, including git command output on success/failure.
*   **Error Handling:**
    *   Exit on `rsync` failures.
    *   Exit on `git fetch`, `git rebase`, or `git push` failures (when git operations are enabled).

## 4. `restore-apps` (`-a, --restore-apps`)

**Description:** Installs the necessary applications without restoring configurations.

**Detailed Specifications:**

*   **System Update:**
    *   Performs `sudo pacman -Syu --noconfirm` to update the system.
*   **YAY Installation (if not found):**
    *   Checks if `yay` is installed.
    *   If not, it should install `git` (if not present), clone the `yay` AUR repository, build, and install `yay`.
    *   Cleans up the cloned `yay` repository after installation.
*   **Application Installation:**
    *   Reads `apps_list.txt` from the script's directory.
    *   For each app:
        *   First attempts to install using `sudo pacman -S --noconfirm`.
        *   If `pacman` fails (e.g., package not found), it then attempts to install using `yay -S --noconfirm`.
        *   Should log detailed output of `pacman` and `yay` commands.
*   **Logging:**
    *   All actions should be logged.
*   **Error Handling:**
    *   Exit on critical failures (e.g., `pacman -Syu` failure, `yay` installation failure, app installation failure).

## 5. `push` (`-p, --push`)

**Description:** Pushes the current configuration backup in the `backup` folder to the remote repository if there are differences.

**Detailed Specifications:**
*   **Git Operations:**
    *   Dynamically determine the current Git branch.
    *   Performs `git fetch origin <current_branch>` to get the latest remote changes.
    *   Checks if the local branch is ahead of the remote branch.
    *   If local is ahead, it performs `git rebase origin/<current_branch>` (to ensure linear history) and then `git push origin <current_branch>`.
    *   If local is not ahead, it logs that there are no changes to push.
*   **Logging:**
    *   All actions should be logged, including git command output.
*   **Error Handling:**
    *   Exit on `git fetch`, `git rebase`, or `git push` failures.

## 6. `no-push` (`-n, --no-push`)

**Description:** Performs a backup without pushing changes to the remote repository. (This is a flag for `backup-config`).

**Detailed Specifications:**
*   **Behavior:**
    *   When used with `backup-config`, it should prevent *all* git operations (`add`, `commit`, `pull`, `fetch`, `rebase`, `push`) within the `backup_config` function.
    *   The `rsync` operations for backing up configurations to the `backup` folder should still proceed.
*   **Logging:**
    *   Log messages indicating that git operations are skipped.

## 7. `qualifier` (`-q, --qualifier`)

**Description:** Adds a name qualifier to the log file name and commit message for backups.

**Detailed Specifications:**
*   **Log File Naming:**
    *   The qualifier string should be appended to the log file name (e.g., `remarchy-YYYYMMDD-HHMMSS-QUALIFIER.log`).
*   **Commit Message:**
    *   For `backup-config`, the qualifier should be included in the commit message (e.g., "Backup YYYY-MM-DD HH:MM:SS - QUALIFIER").
*   **Validation:**
    *   The qualifier should not be empty or start with a hyphen (`-`).
    *   If invalid, log an error and show help.

## 8. `help` (`-h, --help`)

**Description:** Shows this help message.

**Detailed Specifications:**
*   **Output:**
    *   Prints the `show_help` message to standard output.
*   **Exit:**
    *   Exits with a zero status code after displaying help.

## 9. `revert-restore` (`--revert-restore`)

**Description:** Reverts the last restore operation using the files in the `pre_restore_backup` directory.

**Detailed Specifications:**
*   **Revert Mechanism:**
    *   Reads the `pre_restore_backup` directory.
    *   For each file/folder in `pre_restore_backup`, it restores it to its original location on the system.
    *   Handles both files and directories, preserving their original relative paths.
*   **Error Handling:**
    *   Logs a warning if `pre_restore_backup` is empty or does not exist.
    *   Exits with a non-zero status code on `rsync` failures during the revert process.
*   **Cleanup:**
    *   Cleans up (empties) the `pre_restore_backup` directory after a successful revert operation.
*   **Logging:**
    *   All actions should be logged, including `rsync` output on success/failure.