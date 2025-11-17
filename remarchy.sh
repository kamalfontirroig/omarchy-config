#!/usr/bin/env bash

set -euo pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT_DIR="$SCRIPT_DIR/backup"
PRE_RESTORE_BACKUP_ROOT_DIR="$SCRIPT_DIR/pre_restore_backup"
CONFIG_DIR="$HOME/.config"
OMARCHY_SHARE_DIR="$HOME/.local/share/omarchy"
LOG_DIR="$SCRIPT_DIR/logs"


# --- Prerequisite Check ---
if ! command -v jq &> /dev/null; then
  echo "ERROR: 'jq' is not installed. Please install it to continue." >&2
  exit 1
fi

# Create logs directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Initialize LOG_FILE after QUALIFIER is parsed
LOG_FILE="$LOG_DIR/remarchy-$(date +%Y%m%d-%H%M%S)${QUALIFIER:+"-$QUALIFIER"}.log"

# --- Logging ---
log() {
  local level="$1"
  local component="$2"
  local message="$3"
  local status_code="${4:-}" # Optional: status code of the command
  local output="${5:-}"      # Optional: output of the command
  local details_json="${6:-{}}" # Optional: additional details as a JSON string

  local log_entry
  log_entry=$(jq -n \
    --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg level "$level" \
    --arg component "$component" \
    --arg message "$message" \
    --arg status_code "$status_code" \
    --arg output "$output" \
    --argjson details_json "$details_json" \
    '{timestamp: $timestamp, level: $level, component: $component, message: $message} +
     if ($status_code | length > 0) then {details: ($details_json + {status_code: ($status_code | tonumber)})} else {details: $details_json} end +
     if ($output | length > 0) then .details.output = $output else . end')

  # Check for "command not found" errors and recommend --init
  if [[ "$level" == "error" && -n "$status_code" && "$status_code" -ne 0 ]]; then
    if echo "$output" | grep -q -E "command not found|not found|No such file or directory"; then
      log_entry=$(echo "$log_entry" | jq --arg recommendation "Consider running 'remarchy.sh --init' to install missing dependencies." '.details.recommendation = $recommendation')
      echo "ERROR: $message. Consider running 'remarchy.sh --init' to install missing dependencies." >&2
    else
      echo "ERROR: $message" >&2
    fi
  else
    echo "$message"
  fi

  echo "$log_entry" >> "$LOG_FILE"
}

# --- Help ---
show_help() {
  echo "Usage: $0 [OPTION]"
  echo ""
  echo "Options:"
  echo "  -i, --init           Adds the script as an alias named remarchy"
  echo "  -r, --restore-config Restores backed-up files and folders from the 'backup' directory to their original locations"
  echo "  -b, --backup-config  Backs up specified files and folders to the 'backup' directory"
  echo "  -p, --push           Pushes the current backup to the remote repository if there are differences"
  echo "  -q, --qualifier      Adds a name qualifier to the log file name and commit message for backups"
  echo "  -h, --help           Shows this help message"
  echo "  --revert-restore     Reverts the last restore operation using files in pre_restore_backup"
}

# --- Functions ---

get_rsync_exclude_args() {
  local exclude_args=""
  local skip_file="$SCRIPT_DIR/skip_folders.txt"
  if [ -f "$skip_file" ]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      # Skip empty lines and comments
      if [[ -z "$line" || "$line" =~ ^# ]]; then
        continue
      fi
      exclude_args+=" --exclude=$line"
    done < "$skip_file"
  else
    log "warning" "rsync_exclude" "skip_folders.txt not found. No exclusions will be applied to rsync."
  fi
  echo "$exclude_args"
}

init_script() {
  log "info" "init" "Registering the script as alias 'remarchy' and installing dependencies..."

  log "info" "init" "Installing dependencies from dependencies.txt..."
  if [ -f "$SCRIPT_DIR/dependencies.txt" ]; then
    while IFS= read -r package || [[ -n "$package" ]]; do
      if [ -n "$package" ]; then # Ensure package name is not empty
        log "info" "init" "Attempting to install dependency: $package"
        local install_output=""
        local install_status=0
        if ! install_output=$(sudo pacman -S --noconfirm "$package" 2>&1); then
          install_status=$?
          log "error" "init" "Failed to install dependency: $package. Please install it manually." "$install_status" "$install_output"
          exit 1
        else
          log "info" "init" "Successfully installed dependency: $package" 0 "$install_output"
        fi
      fi
    done < "$SCRIPT_DIR/dependencies.txt"
    log "info" "init" "All dependencies from dependencies.txt installed."
  else
    log "warning" "init" "dependencies.txt not found. Skipping dependency installation."
  fi

  local shell_config
  if [ -f "$HOME/.bashrc" ]; then
    shell_config="$HOME/.bashrc"
  elif [ -f "$HOME/.zshrc" ]; then
    shell_config="$HOME/.zshrc"
  else
    log "error" "init" "Could not find .bashrc or .zshrc. Could not add alias."
    exit 1
  fi

  local alias_line="alias remarchy='$SCRIPT_DIR/$(basename "$0")'"
  if grep -q "alias remarchy=" "$shell_config"; then
    log "info" "init" "Alias 'remarchy' already exists, updating path..."
    # The sed command replaces the line that contains 'alias remarchy=' with the new alias line.
    # This command is not compatible with macOS.
    sed -i "s|alias remarchy=.*|$alias_line|" "$shell_config"
    log "info" "init" "Alias remarchy updated in $shell_config."
  else
    log "info" "init" "Adding alias 'remarchy'..."
    echo "$alias_line" >> "$shell_config"
    log "info" "init" "Alias remarchy added to "$shell_config"."
  fi
}

restore_config() {
  log "info" "restore_config" "Restoring files and folders listed in backup_list.txt..."
  mkdir -p "$PRE_RESTORE_BACKUP_ROOT_DIR"

  local backup_list_file="$SCRIPT_DIR/backup_list.txt"

  if [ ! -f "$backup_list_file" ]; then
    log "error" "restore_config" "backup_list.txt not found. Cannot perform restore."
    exit 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip empty lines and comments
    if [[ -z "$line" || "$line" =~ ^# ]]; then
      continue
    fi

    local original_source_path
    # Expand ~ to HOME directory
    if [[ "$line" == "~/"* ]]; then
      original_source_path="$HOME/${line:2}"
    else
      original_source_path="$line"
    fi

    # Remove trailing slash for consistent behavior with rsync
    original_source_path="${original_source_path%/}"

    local backup_source_path
    local relative_to_home="${original_source_path#$HOME/}"

    if [[ "$original_source_path" == "$HOME"* ]]; then
      # Path was from user's home directory, stored with ~/ prefix
      backup_source_path="$BACKUP_ROOT_DIR/~/$relative_to_home"
    else
      # Path was an absolute path (e.g., /etc/fstab)
      backup_source_path="$BACKUP_ROOT_DIR$original_source_path"
    fi

    if [ ! -e "$backup_source_path" ]; then
      log "warning" "restore_config" "Backed-up path '$backup_source_path' does not exist. Skipping restoration for '$original_source_path'."
      continue
    fi

    # Ensure parent directory for original_source_path exists
    mkdir -p "$(dirname "$original_source_path")"

    # Backup existing item before restoring
    if [ -e "$original_source_path" ]; then
      local pre_restore_dest_path
      if [[ "$original_source_path" == "$HOME"* ]]; then
        pre_restore_dest_path="$PRE_RESTORE_BACKUP_ROOT_DIR/~/$relative_to_home"
      else
        pre_restore_dest_path="$PRE_RESTORE_BACKUP_ROOT_DIR$original_source_path"
      fi

      log "info" "restore_config" "Backing up existing '$original_source_path' to '$pre_restore_dest_path'..."
      mkdir -p "$(dirname "$pre_restore_dest_path")"
      if [ -d "$original_source_path" ]; then
        # If original_source_path is a directory, copy its contents
        if ! rsync -av --progress "${original_source_path}/" "${pre_restore_dest_path}/"; then
          log "error" "restore_config" "Failed to back up existing directory '$original_source_path'"
          exit 1
        fi
      else
        # If original_source_path is a file, copy the file
        if ! rsync -av --progress "$original_source_path" "${pre_restore_dest_path}"; then
          log "error" "restore_config" "Failed to back up existing file '$original_source_path'"
          exit 1
        fi
      fi
    fi

    # Restore from backup
    log "info" "restore_config" "Restoring '$backup_source_path' to '$original_source_path'..."
    if [ -d "$backup_source_path" ]; then
      if ! rsync -av --progress "${backup_source_path}/" "${original_source_path}/"; then
        log "error" "restore_config" "Failed to restore directory '$backup_source_path'"
        exit 1
      fi
    else
      if ! rsync -av --progress "$backup_source_path" "$original_source_path"; then
        log "error" "restore_config" "Failed to restore file '$backup_source_path'"
        exit 1
      fi
    fi
  done < "$backup_list_file"

  log "info" "restore_config" "Files restored and existing files backed up in $PRE_RESTORE_BACKUP_ROOT_DIR."

  if command -v hyprctl &> /dev/null; then
    log "info" "restore_config" "Reloading Hyprland configuration..."
    if ! hyprctl reload; then
      log "warning" "restore_config" "Failed to reload Hyprland configuration. It might not be running."
    fi
  else
    log "info" "restore_config" "hyprctl not found, skipping Hyprland reload."
  fi
}

revert_restore() {
  log "info" "revert_restore" "Attempting to revert last restore operation from $PRE_RESTORE_BACKUP_ROOT_DIR..."

  if [ ! -d "$PRE_RESTORE_BACKUP_ROOT_DIR" ] || [ -z "$(ls -A "$PRE_RESTORE_BACKUP_ROOT_DIR")" ]; then
    log "warning" "revert_restore" "No previous restore backup found in $PRE_RESTORE_BACKUP_ROOT_DIR. Nothing to revert."
    return 0
  fi

  # Find all backed-up items in PRE_RESTORE_BACKUP_ROOT_DIR
  find "$PRE_RESTORE_BACKUP_ROOT_DIR" -mindepth 1 -print0 | while IFS= read -r -d $'\0' pre_restore_path; do
    local relative_path="${pre_restore_path#$PRE_RESTORE_BACKUP_ROOT_DIR/}"
    local original_path=""

    # Determine original path based on how it was backed up (mirroring restore_config logic)
    if [[ "$relative_path" == "~" ]]; then
      original_path="$HOME"
    elif [[ "$relative_path" == "~/"* ]]; then
      original_path="$HOME/${relative_path#~/}"
    else
      original_path="/$relative_path"
    fi

    # Ensure parent directory for original_path exists
    mkdir -p "$(dirname "$original_path")"

    log "info" "revert_restore" "Restoring '$pre_restore_path' to '$original_path'..."
    if [ -d "$pre_restore_path" ]; then
      if ! rsync -av --progress "${pre_restore_path}/" "${original_path}/"; then
        log "error" "revert_restore" "Failed to restore directory '$pre_restore_path'"
        exit 1
      fi
    else
      if ! rsync -av --progress "$pre_restore_path" "$original_path"; then
        log "error" "revert_restore" "Failed to restore file '$pre_restore_path'"
        exit 1
      fi
    fi
  done

  log "info" "revert_restore" "Successfully reverted last restore operation. Cleaning up $PRE_RESTORE_BACKUP_ROOT_DIR..."
  rm -rf "$PRE_RESTORE_BACKUP_ROOT_DIR"/*
  log "info" "revert_restore" "$PRE_RESTORE_BACKUP_ROOT_DIR cleaned up."
}

backup_config() {
  local no_push_flag="$1"
  local perform_git_operations=true
  if [ "$no_push_flag" = true ]; then
    perform_git_operations=false
  fi

  log "debug" "backup_config" "no_push_flag value: $no_push_flag"
  log "info" "backup_config" "Backing up files and folders listed in backup_list.txt..."
  cd "$SCRIPT_DIR"

  # Ensure destination directories exist and are empty
  mkdir -p "$BACKUP_ROOT_DIR"
  log "info" "backup_config" "Emptying backup directory: $BACKUP_ROOT_DIR"
  rm -rf "$BACKUP_ROOT_DIR"/*


    local current_branch=""


    if [ "$perform_git_operations" = true ]; then


      current_branch=$(git rev-parse --abbrev-ref HEAD)


      if [ -z "$current_branch" ]; then


        log "error" "backup_config" "Could not determine current git branch."


        exit 1


      fi


      log "info" "backup_config" "Current branch detected: $current_branch"


  


      # Removed "Staging and committing any pending changes before pull..."


      # This avoids creating an "auto-commit" that might interfere with rebase.


  


      # No git pull before push, but will fetch and rebase before push.


      log "info" "backup_config" "Preparing to push changes without force-push."


    else


      log "info" "backup_config" "Skipping git operations due to --no-push flag."


    fi


  


    local rsync_exclude_args=$(get_rsync_exclude_args)


    local backup_list_file="$SCRIPT_DIR/backup_list.txt"


  


    if [ ! -f "$backup_list_file" ]; then


      log "error" "backup_config" "backup_list.txt not found. Cannot perform backup."


      exit 1


    fi


  


    while IFS= read -r line || [[ -n "$line" ]]; do


      # Skip empty lines and comments


      if [[ -z "$line" || "$line" =~ ^# ]]; then


        continue


      fi


  


      local source_path


      # Expand ~ to HOME directory


      if [[ "$line" == "~/"* ]]; then


        source_path="$HOME/${line:2}"


      else


        source_path="$line"


      fi


  


      # Remove trailing slash for consistent behavior with rsync


      source_path="${source_path%/}"


  


      if [ ! -e "$source_path" ]; then


        log "warning" "backup_config" "Source path '$source_path' does not exist. Skipping."


        continue


      fi


  


                        local relative_path="${source_path#$HOME/}"


  


                        if [[ "$source_path" == "$HOME"* ]]; then


  


                          # If the source is in the home directory, preserve its relative path from home


  


                          # e.g., ~/.config/nvim -> backup/~/.config/nvim


  


                          local dest_dir_for_home="$BACKUP_ROOT_DIR/~"


  


                          local dest_path_full="$dest_dir_for_home/$relative_path"


  


                  


  


                          if [ -d "$source_path" ]; then


  


                            mkdir -p "$dest_path_full" # Ensure destination directory exists


  


                            if ! rsync -av --progress $rsync_exclude_args "${source_path}/" "$dest_path_full/" 2>&1; then


  


                              log "error" "backup_config" "rsync failed for '$source_path'"


  


                              exit 1


  


                            fi


  


                          else


  


                            mkdir -p "$(dirname "$dest_path_full")" # Ensure destination directory exists


  


                            if ! rsync -av --progress $rsync_exclude_args "$source_path" "$dest_path_full" 2>&1; then


  


                              log "error" "backup_config" "rsync failed for '$source_path'"


  


                              exit 1


  


                            fi


  


                          fi


      else


        # If the source is outside the home directory (e.g., /etc/fstab),


        # backup to a path reflecting its absolute path from root


        # e.g., /etc/fstab -> backup/etc/fstab


        local dest_path="${BACKUP_ROOT_DIR}${source_path}"


        mkdir -p "$(dirname "$dest_path")"


        if [ -d "$source_path" ]; then


          if ! rsync -av --progress $rsync_exclude_args "${source_path}/" "$dest_path/" 2>&1; then


            log "error" "backup_config" "rsync failed for '$source_path'"


            exit 1


          fi


        else


          if ! rsync -av --progress $rsync_exclude_args "$source_path" "$dest_path" 2>&1; then


            log "error" "backup_config" "rsync failed for '$source_path'"


            exit 1


          fi


        fi


      fi


      log "info" "backup_config" "Successfully backed up '$source_path' to '$BACKUP_ROOT_DIR'."


    done < "$backup_list_file"

  if [ "$perform_git_operations" = true ]; then
    log "info" "backup_config" "Committing changes..."
    git add backup/
    if git diff --cached --quiet; then # If there are NO staged changes
      log "info" "backup_config" "No changes detected after rsync. Skipping commit and push."
    else # If there ARE staged changes
      git commit -m "Configuration backup $(date '+%Y-%m-%d %H:%M:%S')${QUALIFIER:+" - $QUALIFIER"}"
      log "info" "backup_config" "Pushing to git..."

      local push_output=""
      local push_status=0
      if ! push_output=$(git push origin "$current_branch" 2>&1); then
        push_status=$?
        log "error" "backup_config" "git push failed for branch $current_branch" "$push_status" "$push_output"
        exit 1
      else
        log "info" "backup_config" "git push successful for branch $current_branch" 0 "$push_output"
      fi
      log "info" "backup_config" "Backup completed and pushed to the repository."
    fi
  else
    log "info" "backup_config" "Skipping final commit and push due to --no-push flag."
  fi
}

push_backup() {
  log "info" "push_backup" "Checking for differences and pushing to remote if necessary..."
  cd "$SCRIPT_DIR"

  # Fetch the latest from remote to compare
  if ! git fetch origin main; then
    log "error" "push_backup" "Failed to fetch from origin."
    exit 1
  fi

  # Check if local main is ahead of origin/main
  if [[ "$(git rev-list HEAD --count --not origin/main)" -gt 0 ]]; then
    log "info" "push_backup" "Local branch is ahead of remote. Pushing changes..."
    local push_output
    if ! push_output=$(git push origin main 2>&1); then
      log "error" "push_backup" "Failed to push changes to origin." 1 "$push_output"
      exit 1
    fi
    if echo "$push_output" | grep -q "Everything up-to-date"; then
      log "info" "push_backup" "No new changes to push to remote (already up-to-date)."
    else
      log "info" "push_backup" "Successfully pushed changes to remote." 0 "$push_output"
    fi
  else
    log "info" "push_backup" "No local changes to push to remote."
  fi
}

restore_apps() {
  log "info" "restore_apps" "Installing necessary applications..."

  log "info" "restore_apps" "Updating system..."
  if ! sudo pacman -Syu --noconfirm; then
    log "error" "restore_apps" "pacman -Syu failed"
    exit 1
  fi

  if ! command -v yay &> /dev/null; then
    log "info" "restore_apps" "Installing yay..."
    if ! sudo pacman -S --noconfirm git; then
      log "error" "restore_apps" "Failed to install git"
      exit 1
    fi
    ( # Start subshell
      cd "$SCRIPT_DIR" || exit 1 # Ensure we are in SCRIPT_DIR
      rm -rf yay # Clean up previous attempts
      if ! git clone https://aur.archlinux.org/yay.git; then
        log "error" "restore_apps" "Failed to clone yay repo"
        exit 1
      fi
      cd yay || exit 1
      if ! makepkg -si --noconfirm; then
        log "error" "restore_apps" "Failed to install yay"
        exit 1
      fi
      rm -rf "$SCRIPT_DIR/yay" # Clean up after successful installation
    ) # End subshell
  fi

  while read -r app; do
    log "info" "restore_apps" "Attempting to install $app..."
    local install_output=""
    local install_status=1 # Default to failure

    # Check if package exists in official repos
    local pacman_check_output
    if pacman_check_output=$(pacman -Si "$app" 2>&1); then
      log "info" "restore_apps" "Package '$app' found in pacman repositories." 0 "$pacman_check_output"
      # Install with pacman
      install_output=$(sudo pacman -S --noconfirm "$app" 2>&1)
      install_status=$?
      if [ "$install_status" -eq 0 ]; then
        log "info" "restore_apps" "Successfully installed $app with pacman" "$install_status" "$install_output"
      else
        log "error" "restore_apps" "Failed to install $app with pacman" "$install_status" "$install_output"
      fi
    else
      log "info" "restore_apps" "Package '$app' not found in pacman repositories, trying yay." 1 "$pacman_check_output"
      # Install with yay
      install_output=$(yay -S --noconfirm "$app" 2>&1)
      install_status=$?
      if [ "$install_status" -eq 0 ]; then
        # Check yay output for "package not found" or similar messages
        if echo "$install_output" | grep -q -E "package not found|failed to query|could not find all required packages|No AUR package found"; then
          log "error" "restore_apps" "Failed to install $app with yay: Package not found or other error" "$install_status" "$install_output"
        else
          log "info" "restore_apps" "Successfully installed $app with yay" "$install_status" "$install_output"
        fi # Added missing fi
      else
        log "error" "restore_apps" "Failed to install $app with yay" "$install_status" "$install_output"
      fi
    fi
  done < "$SCRIPT_DIR/apps_list.txt"

  log "info" "restore_apps" "Applications installed."
}

# --- Main ---
NO_PUSH_FLAG=false
ACTION=""
QUALIFIER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--init)
      ACTION="init"
      shift
      ;;
    -r|--restore-config)
      ACTION="restore_config"
      shift
      ;;
    -b|--backup-config)
      ACTION="backup_config"
      shift
      ;;
    -a|--restore-apps)
      ACTION="restore_apps"
      shift
      ;;
    -n|--no-push)
      NO_PUSH_FLAG=true
      shift
      ;;
    -p|--push)
      ACTION="push_backup"
      shift
      ;;
    -q|--qualifier)
      if [[ -z "$2" || "$2" == -* ]]; then
        log "error" "main" "Qualifier cannot be empty or start with '-'. Please provide a value."
        show_help
        exit 1
      fi
      QUALIFIER="$2"
      shift 2
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    --revert-restore)
      ACTION="revert_restore"
      shift
      ;;
    *)
      log "error" "main" "Invalid option: $1"
      show_help
      exit 1
      ;;
  esac
done

# Now execute the action based on parsed options
if [ -z "$ACTION" ]; then
  show_help
  exit 0
fi

# Initialize LOG_FILE after QUALIFIER is parsed
LOG_FILE="$LOG_DIR/remarchy-$(date +%Y%m%d-%H%M%S)${QUALIFIER:+"-$QUALIFIER"}.log"

case "$ACTION" in
  "init")
    init_script
    ;;
  "restore_config")
    restore_config
    ;;
  "backup_config")
    backup_config "$NO_PUSH_FLAG"
    ;;
  "restore_apps")
    restore_apps
    ;;
  "push_backup")
    push_backup
    ;;
  "revert_restore")
    revert_restore
    ;;
esac
