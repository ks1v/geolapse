#!/bin/sh
#
# Polyglot Shell Launcher:
# This block detects if we are running in bash on macOS and, if so,
# re-executes the script with zsh to get access to better features.
# On Linux, it will continue with bash. On zsh, it does nothing.
if [ -n "$BASH_VERSION" ] && [ "$(uname)" = "Darwin" ]; then
    # We are in bash on macOS, switch to zsh
    exec zsh "$0" "$@"
fi
# --- End Launcher ---

# Determine the absolute path of the directory where the script is located
# This is a robust way to get the script's directory, even with symlinks.
# It does not change the working directory of the script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" &> /dev/null && pwd)"

source "$SCRIPT_DIR/gl-functions.sh"

# Configuration
if [[ "$OSTYPE" == "darwin"* ]]; then
    STAGE="$HOME/Stage"
elif grep -qi microsoft /proc/version 2>/dev/null; then
    STAGE="/mnt/c/Users/micro/Stage"
else
    STAGE="$HOME/Stage"
fi

TL_PATH="$STAGE/TL"
TEMP_PATH="$TL_PATH/TEMP"

echo "Stage location: $STAGE"
echo

if [ $# -eq 0 ]; then
    echo "Step 1: Finding and mounting SD card"
    SD_MOUNT=$(find_and_mount_sd)
    check_status "Failed to find or mount SD card"

    echo "SD card found at: $SD_MOUNT"
    DCIM_PATH="$SD_MOUNT/DCIM"
else
    DCIM_PATH="$1"
fi

[ -d "$DCIM_PATH" ]
check_status "DCIM folder not found"
echo "Source set: $DCIM_PATH"

echo "Step 2: Rename and move files from DCIM to TEMP"
"$SCRIPT_DIR/gl-stage.sh" "$DCIM_PATH" "$TEMP_PATH"
check_status "Failed to process DCIM files"
echo

#sudo umount "$SD_MOUNT"

echo "Step 3: Grouping timelapse series"
"$SCRIPT_DIR/gl-group.sh" "$TEMP_PATH" "$TL_PATH"
check_status "Failed to group timelapse series"
echo

echo "Step 4: Generating videos from timelapse series"
"$SCRIPT_DIR/gl-build.sh" "$TL_PATH"
check_status "Failed to generate videos"
echo "Videos are located in: $TL_PATH"
echo

echo "Step 5: Renaming non-timelapse shots and fixing it's EXIF data"
"$SCRIPT_DIR/gl-shots.sh" "$TL_PATH/MISC/"
check_status "Failed to rename non-timelapse shots"
echo

echo "END"
