#!/bin/bash
source ./tl-functions.sh

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

echo "=== Timelapse Processing Pipeline ==="
echo "Stage location: $STAGE"
echo

# Set source 
if [ $# -eq 0 ]; then
    # Step 1: Find and mount SD card
    echo "Step 1: Finding SD card..."
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

# Step 2: Rename and move files from DCIM to TEMP
echo "Step 2: Processing DCIM files..."

./tl-stage.sh "$DCIM_PATH" "$TEMP_PATH"
check_status "Failed to process DCIM files"
echo

#sudo umount "$SD_MOUNT"

# Step 3: Group files into timelapse series
echo "Step 3: Grouping timelapse series..."

./tl-group.sh "$TEMP_PATH" "$TL_PATH"
check_status "Failed to group timelapse series"
echo

# Step 4: Generate videos from timelapse series
echo "Step 4: Generating videos..."
./tl-ffmpeg.sh "$TL_PATH"
check_status "Failed to generate videos"
echo

echo "=== Pipeline Complete ==="
echo "Videos are located in: $TL_PATH"