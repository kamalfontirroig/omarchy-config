# OMARCHY Backup and Restore Tools

## Introduction
This project aims to provide a robust set of tools for backing up and restoring configurations and applications related to the OMARCHY ecosystem. The goal is to ensure data integrity, facilitate disaster recovery, and streamline the management of OMARCHY installations for users.

## Features
- **Backup:** Tools to securely backup specified files and folders from the system, as defined in `backup_list.txt`, to the `backup` directory within this repository. Changes are then committed and pushed to a Git remote.
- **Restore:** Functionality to restore backed-up files and folders from the `backup` directory within this repository to their original locations. Existing files at these locations are automatically backed up to the `pre_restore_backup` directory before restoration. Includes Hyprland configuration reload if `hyprctl` is available.
- **Revert Restore:** Ability to undo the last restore operation by using the files backed up in the `pre_restore_backup` directory.
- **Applications Restore:** Ability to install multiple applications from a curated list defined in `apps_list.txt`. The script intelligently handles both official Arch Linux packages (via `pacman`) and AUR packages (via `yay`), including automatic installation of `yay` if it's not present. Each installation attempt is logged with detailed success/failure messages, including command output and exit codes, and improved detection for non-existent AUR packages.
- **Structured Logging:** All operations are logged to a dynamically named file (e.g., `logs/remarchy-YYYYMMDD-HHMMSS.log`) in a structured JSON format, making it easy for automated agents to parse and debug.

## Getting Started

### Prerequisites
- An Arch Linux-based system.
- Internet connection for package downloads.

### Dependencies
The script relies on several external tools. These are listed in `dependencies.txt` and are automatically installed when you run `./remarchy.sh --init`. The primary dependencies include `jq` (for structured logging), `git` (for version control operations), and `rsync` (for file synchronization).

### Installation
1.  Clone this repository:
    ```bash
    git clone <your-repository-url>
    cd <your-repository-name>
    ```
2.  Initialize the script and install its dependencies. This step *must* be run at least once:
    ```bash
    ./remarchy.sh --init
    # Then, restart your shell or source your shell config file (e.g., source ~/.bashrc)
    ```

### Configuration
- **`backup_list.txt`:** This file lists the specific files and folders to be backed up. Each line should contain an absolute path or a path relative to the user's home directory (`~`). Folders listed will be backed up recursively. Lines starting with `#` are treated as comments.
- **`backup/` directory:** This directory stores all your backed-up files and folders, maintaining their original relative paths.
- **`pre_restore_backup/` directory:** During a restore operation, existing files that would be overwritten are moved here before new ones are restored.
- **`apps_list.txt`:** This file contains a list of applications to be installed by the `--restore-apps` option, one application name per line.
- **`skip_folders.txt`:** This file contains a list of folders and files (one per line) that should be excluded from the backup process when using `--backup-config`. This is useful for preventing sensitive data (e.g., browser caches, cookies, temporary files) or large, unnecessary directories from being committed to the repository. Each entry should be a path relative to `~/.config/` or `~/.local/share/omarchy/`. Lines starting with `#` are treated as comments.
- Ensure your Git repository is properly configured for pushing and pulling (e.g., `git remote add origin <your-remote-url>`).

## Usage

### Backing Up Files and Folders
This will backup the files and folders specified in `backup_list.txt` to the `backup/` directory within this repository and commit/push the changes to your Git remote.
```bash
./remarchy.sh --backup-config
```

### Restoring Files and Folders
This will restore files and folders from the `backup/` directory to their original locations. Existing files that would be overwritten will first be moved to a newly created `pre_restore_backup/` directory within the repository.
```bash
./remarchy.sh --restore-config
```

### Restoring OMARCHY Applications
This will install applications listed in `apps_list.txt`. It will first update your system, then install `yay` if it's missing, and finally install each application using `pacman` or `yay` as appropriate.
```bash
./remarchy.sh --restore-apps
```

### Showing Help
```bash
./remarchy.sh --help
```

### Reverting a Restore
This will revert the last restore operation by restoring files from the `pre_restore_backup/` directory to their original locations.
```bash
./remarchy.sh --revert-restore
```

## Logging
The script logs all operations to a dynamically named file within the `logs/` directory (e.g., `logs/remarchy-YYYYMMDD-HHMMSS.log`) in a structured JSON format. This allows for easy parsing and analysis by automated agents. Each log entry contains a timestamp, log level, component, message, and optional details such as status codes and command output.

Example log entry:
```json
{
  "timestamp": "2025-11-16T10:00:05.456Z",
  "level": "error",
  "component": "restore_apps",
  "message": "Failed to install package 'mongodb-bin'.",
  "details": {
    "package": "mongodb-bin",
    "exit_code": 1,
    "stderr": "error: target not found: mongodb-bin"
  }
}
```

Example log entry:
```json
{
  "timestamp": "2025-11-16T10:00:05.456Z",
  "level": "error",
  "component": "restore_apps",
  "message": "Failed to install package 'mongodb-bin'.",
  "details": {
    "package": "mongodb-bin",
    "exit_code": 1,
    "stderr": "error: target not found: mongodb-bin"
  }
}
```

## Project Structure
```
.
├── remarchy.sh             # The main backup and restore script
├── apps_list.txt           # List of applications to be installed
├── README.md               # This README file
├── logs/                   # Directory for structured log files generated by the script
├── backup/                 # Contains all backed-up files and folders
└── pre_restore_backup/   # Stores old files moved during restoration
```

## Contributing
[Guidelines for contributing to the project.]

## License
[License information.]

## Contact
[Contact information or support channels.]