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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" &> /dev/null && pwd)"

source "$SCRIPT_DIR/gl-functions.sh"

if [ $# -ne 1 ]; then
    echo "Usage: $0 <TL_folder>"
    exit 1
fi

TL_DIR="$1"
framerate=30

check_install "ffmpeg"

# Check if any TL_* folders exist before looping
if ! ls -d "$TL_DIR"/TL_* >/dev/null 2>&1; then
    echo "No timelapse series folders (TL_*) found in $TL_DIR."
    echo "Done"
    exit 0
fi

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
