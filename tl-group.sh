#!/bin/bash
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
        local series_folder="TL_${count}_D-${delay}_N-${num}"
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

# Get sorted list of jpg files
files=($(find "$TEMP_DIR" -name "*.jpg" -type f -exec basename {} \; | sort))
if [ ${#files[@]} -eq 0 ]; then
    echo "No jpg files found"
    exit 0
fi

prev_file=""
prev_timestamp=0
current_delay=0
series_count=0
series_file_count=0
series_files=()

for file in "${files[@]}"; do
    # Extract datetime from filename: YYYY-MM-DD_HH-MM-SS_NNNNN.jpg
    datetime="${file%_*}"
    
    # Convert to timestamp
    date_part="${datetime%_*}"
    time_part="${datetime#*_}"
    iso_datetime="${date_part} ${time_part//-/:}"
    
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