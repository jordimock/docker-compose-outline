#!/bin/bash
set -e

# Usage:
#   ./restore.bash /path/to/backup-file

BACKUP_FILE="$1"

# Validate backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    echo "Usage: $0 /path/to/backup-file"
    echo "Error: Backup file '$BACKUP_FILE' not found."
    exit 1
fi

# Get absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."

# Determine backup type
FILENAME="$(basename -- "$BACKUP_FILE")"

# Generate unique temp directory
TMP_DIR=$(mktemp -d -t restore-test-XXXXXXXXXXXXXXXX)
TMP_ARCHIVE="${TMP_DIR}/${FILENAME%.gpg}"
echo "Created temporary directory: $TMP_DIR"

# Cleanup function to ensure temp files are removed on exit
cleanup() {
    if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
        echo "Cleaning up temporary directory: $TMP_DIR"
        rm -rf "$TMP_DIR"
    fi
}

# Trap EXIT to run cleanup
trap cleanup EXIT


#
#
# Step 1: Decrypt if necessary
if [[ "$BACKUP_FILE" == *.gpg ]]; then
    echo "Backup file is encrypted. Decryption..."

    if ! gpg --output "$TMP_ARCHIVE" --decrypt "$BACKUP_FILE"; then
        echo "Error: Failed to decrypt backup." >&2
        echo "Possible causes:" >&2
        echo "  - The required private key is missing from your keyring." >&2
        echo "  - You might have entered an incorrect passphrase." >&2
        exit 1
    fi
    ARCHIVE_FILE="$TMP_ARCHIVE"
else
    ARCHIVE_FILE="$BACKUP_FILE"
fi


#
#
# Step 2: Archive extraction
echo "Extraction to temporary directory..."

if tar -xzf "$ARCHIVE_FILE" -C "$TMP_DIR"; then
    echo "Archive extracted successfully"
else
    echo "Error: Failed to extract archive." >&2
    exit 1
fi


#
#
# Step 3: Stopping Docker containers
echo "Stopping Docker containers..."
docker compose --project-directory "$PROJECT_ROOT" down


#
#
# Step 4: Pre-restore backup (optional)
echo "Creating pre-restore backup using backup.bash..."

if ! "${SCRIPT_DIR}/backup.bash"; then
    echo "Warning: Pre-restore backup failed. Continuing with restore..." >&2
fi


#
#
# Step 5: Restoring files from backup archive
echo "Restoring new .env and vol/ from backup archive..."

if [ -f "${TMP_DIR}/.env" ]; then
    mv "${TMP_DIR}/.env" "${PROJECT_ROOT}/.env"
    echo "Restored .env"
else
    echo "Warning: .env not found in backup archive" >&2
fi

if [ -d "${TMP_DIR}/vol" ]; then
    mv "${TMP_DIR}/vol" "${PROJECT_ROOT}/vol"
    echo "Restored vol/"
else
    echo "Warning: vol/ directory not found in backup archive" >&2
fi


#
#
# Step 6: Starting Docker containers
echo "Starting Docker containers..."
docker compose --project-directory "$PROJECT_ROOT" up -d


echo "Restore process completed successfully!"
