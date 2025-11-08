#!/usr/bin/env bash
source ./tl-functions.sh

# Configuration
if [[ "$OSTYPE" == "darwin"* ]]; then
    STAGE="~/Stage"
elif grep -qi microsoft /proc/version 2>/dev/null; then
    STAGE="/mnt/c/Users/micro/Stage"
else
    STAGE="~/Stage"
fi

TEMP_PATH="$STAGE/TEMP"
TL_PATH="$STAGE/TL"


echo "=== Timelapse Processing Pipeline ==="
echo "Stage location: $STAGE"
echo

# Step 1: Find and mount SD card
echo "Step 1: Finding SD card..."
SD_MOUNT=$(find_and_mount_sd)
check_error "Failed to find or mount SD card"

echo "SD card found at: $SD_MOUNT"
echo

# Step 2: Rename and move files from DCIM to TEMP
echo "Step 2: Processing DCIM files..."

DCIM_PATH="$SD_MOUNT/DCIM"
[ -d "$DCIM_PATH" ]
check_error "DCIM folder not found on SD card"

./tl-mover.sh "$DCIM_PATH" "$TEMP_PATH"
check_error "Failed to process DCIM files"
echo

sudo umount "$SD_MOUNT"

# Step 3: Group files into timelapse series
echo "Step 3: Grouping timelapse series..."

./tl-group.sh "$TEMP_PATH" "$TL_PATH"
check_error "Failed to group timelapse series"
echo

# Step 4: Generate videos from timelapse series
echo "Step 4: Generating videos..."
./tl-ffmpeg.sh "$TL_PATH"
check_error "Failed to generate videos"
echo

echo "=== Pipeline Complete ==="
echo "Videos are located in: $TL_PATH"