#!/bin/bash
source ./tl-functions.sh

if [ $# -ne 1 ]; then
    echo "Usage: $0 <TL_folder>"
    exit 1
fi

TL_DIR="$1"
framerate=30

check_install_ffmpeg

# Process each TL subfolder
for subfolder in "$TL_DIR"/TL_*; do
    [ -d "$subfolder" ] || continue
    
    subfolder_name=$(basename "$subfolder")
    
    # Extract delay from folder name (TL_X_D-Y_N-Z)
    delay=$(echo "$subfolder_name" | sed 's/.*D-\([0-9]*\).*/\1/')
    series_num=$(echo "$subfolder_name" | sed 's/TL_\([0-9]*\).*/\1/')
    
    # Calculate speed up factor (delay * framerate)
    speedup=$((delay * framerate))
    
    output_video="$TL_DIR/TL_${series_num}_D-${delay}_${speedup}x.mp4"
    
    echo "Processing $subfolder_name..."
    
    # Create file list for ffmpeg with absolute paths
    file_list="$subfolder/filelist.txt"
    find "$(cd "$subfolder" && pwd)" -name "*.jpg" | sort | sed "s/^/file '/" | sed "s/$/'/" > "$file_list"
    
    ffmpeg -y -f concat -safe 0 -r "$framerate" -i "$file_list" \
        -c:v libx264 -b:v 50M -tune film -pix_fmt yuv420p \
        -loglevel error -stats \
        "$output_video"
    
    rm "$file_list"
    
    if [ $? -eq 0 ]; then
        echo "Created: TL_${series_num}_D-${delay}_${speedup}x.mp4"
    else
        echo "Failed to create video for $subfolder_name"
    fi
done

echo "Done"
