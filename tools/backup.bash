#!/bin/bash
set -e

# Define items to backup (relative to PROJECT_ROOT)
TO_BACKUP=(
    ".env"
    "vol"
)

# Usage:
#   ./backup.bash [recipient-fingerprint]
#
# Arguments:
#   [recipient-fingerprint] - (Optional) GPG recipient fingerprint. If provided, the backup archive will be encrypted.
#
# Description:
#   This script performs the following steps:
#     1. Stops Docker containers located in the parent directory of this script.
#     2. Creates a backup archive containing project files and directories.
#     3. Restarts Docker containers.
#     4. Optionally encrypts the archive using the provided GPG recipient fingerprint.
#     5. Backup files are stored in ../backup relative to this script.

GPG_FINGERPRINT="$1"

# Get absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."
BACKUP_DIR="${PROJECT_ROOT}/backup"

# Validate GPG fingerprint if provided
if [ -n "$GPG_FINGERPRINT" ]; then
    gpg --list-keys "$GPG_FINGERPRINT" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: GPG key with fingerprint '$GPG_FINGERPRINT' not found in keyring."
        echo
        echo "Available GPG keys:"
        gpg --list-keys --with-colons | grep '^fpr' | cut -d: -f10
        exit 1
    fi
fi

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Initialize variables after validation
DATE=$(date +"%Y%m%d")
ARCHIVE_NAME="${DATE}.tar.gz"
ENCRYPTED_NAME="${DATE}.${GPG_FINGERPRINT}.gpg"

# Clean old backup files with the same names
echo "Cleaning up old backup files..."
rm -f "${BACKUP_DIR}/${ARCHIVE_NAME}"
rm -f "${BACKUP_DIR}/${ENCRYPTED_NAME}"

# Stop Docker containers
echo "Stopping containers..."
docker compose --project-directory "$PROJECT_ROOT" down

# Create backup archive
echo "Creating archive ${ARCHIVE_NAME}..."
tar -czf "${BACKUP_DIR}/${ARCHIVE_NAME}" -C "$PROJECT_ROOT" "${TO_BACKUP[@]}"

# Restart Docker containers
echo "Starting Docker containers..."
docker compose --project-directory "$PROJECT_ROOT" up -d

# Check if archive was created
if [ ! -f "${BACKUP_DIR}/${ARCHIVE_NAME}" ]; then
    echo "Error: Backup archive was not created." >&2
    exit 1
fi

# Optional encryption
if [ -n "$GPG_FINGERPRINT" ]; then
    echo "Encrypting archive with recipient fingerprint ${GPG_FINGERPRINT}..."
    
    gpg --trust-model always \
        --output "${BACKUP_DIR}/${ENCRYPTED_NAME}" \
        --encrypt \
        --recipient "$GPG_FINGERPRINT" \
        "${BACKUP_DIR}/${ARCHIVE_NAME}"

    if [ $? -eq 0 ]; then
        rm "${BACKUP_DIR}/${ARCHIVE_NAME}"
        echo "Archive successfully encrypted as ${ENCRYPTED_NAME}."
    else
        echo "Error encrypting the archive."
        exit 1
    fi
fi

echo "Backup completed successfully. Backup file located in ${BACKUP_DIR}"
