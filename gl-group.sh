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

if [ $# -ne 2 ]; then
    echo "Usage: $0 <TEMP_folder> <TL_folder>"
    exit 1
fi
TEMP_DIR="$1"
TL_DIR="$2"

# Create TL and MISC folders
mkdir -p "$TL_DIR"
mkdir -p "$TL_DIR/MISC"

# Function to move series files
move_series() {
    local count=$1
    local delay=$2
    local num=$3
    shift 3
    local files=("$@")
    
    if [ $num -gt 10 ]; then
        local rnd="$(LC_ALL=C tr -dc 'a-zA-Z' < /dev/urandom | head -c 3)"
        local series_folder="TL_${count}_D-${delay}_N-${num}_${rnd}"
        local series_path="$TL_DIR/$series_folder"
        mkdir -p "$series_path"
        for f in "${files[@]}"; do
            mv "$TEMP_DIR/$f" "$series_path/"
        done
        echo " -> $series_folder"
    else
        for f in "${files[@]}"; do
            mv "$TEMP_DIR/$f" "$TL_DIR/MISC/"
        done
        echo " -> MISC"
    fi
}

prev_file=""
prev_timestamp=0
current_delay=0
series_count=0
series_file_count=0
series_files=()
file_data=()

# Read file paths and EXIF timestamps in one go, then sort by timestamp.
# This is more reliable than parsing filenames.
while IFS='|' read -r timestamp file; do
    file_data+=("$timestamp|$file")
done < <(exiftool -d "%s" -p '$DateTimeOriginal|$filename' "$TEMP_DIR"/*.jpg 2>/dev/null | sort -n)

if [ ${#file_data[@]} -eq 0 ]; then
    echo "No jpg files with EXIF data found"
    exit 0
fi

for item in "${file_data[@]}"; do
    IFS='|' read -r timestamp file <<< "$item"

    if [[ "$OSTYPE" == "darwin"* ]]; then
        timestamp=$(date -j -f "%Y-%m-%d %H:%M:%S" "$iso_datetime" "+%s")
    else
        timestamp=$(date -d "$iso_datetime" "+%s")
    fi
    
    if [ -z "$prev_file" ]; then
        # First file
        prev_file="$file"
        prev_timestamp=$timestamp
        series_count=1
        series_file_count=1
        series_files=("$file")
        continue
    fi
    
    # Calculate delay
    delay=$((timestamp - prev_timestamp))
    delay_diff=$((delay - current_delay))
    
    if [ $series_file_count -eq 1 ]; then
        # Starting new series
        current_delay=$delay
        echo -n "$series_count -- $prev_file -- D=${current_delay} -- N="
        series_file_count=2
        series_files=("$prev_file" "$file")
    elif [ ${delay_diff#-} -le 1 ]; then
        # Continue current series
        ((series_file_count++))
        series_files+=("$file")
    else
        # Series ended - move files
        echo -n "${series_file_count}"
        move_series $series_count $current_delay $series_file_count "${series_files[@]}"
        
        # Current file starts potential new series
        current_delay=$delay
        ((series_count++))
        series_file_count=1
        series_files=("$file")
    fi
    
    prev_file="$file"
    prev_timestamp=$timestamp
done

# Process last series
if [ $series_file_count -gt 0 ]; then
    echo -n "${series_file_count}"
    move_series $series_count $current_delay $series_file_count "${series_files[@]}"
fi