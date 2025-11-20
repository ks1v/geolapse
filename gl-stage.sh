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

source ./gl-functions.sh

# Check arguments and set variables
if [ $# -ne 2 ]; then
    echo "Usage: $0 <DCIM_folder> <TEMP_folder>" >&2
    exit 1
fi
DCIM_DIR="$1"
TEMP_DIR="$2"


# 1. Setup and Preparation
check_install_exiftool
echo "Creating temporary directory: $TEMP_DIR"
mkdir -p "$TEMP_DIR"
check_status "Failed to create temporary directory $TEMP_DIR."


read -p "Manual date in YYYYMMDD format (default: today): " input_date
manual_date="${input_date:-$(date "+%Y%m%d")}"

total_renamed=0

# 2. Process DCIM Subfolders
# Use a simple glob and process only directories (to be robust)
echo "--- Renaming in-place $DCIM_DIR ---"
for subfolder in "$DCIM_DIR"/*/ ; do
    # Skip if not a directory (handles case where glob matches nothing)
    [ -d "$subfolder" ] || continue
    
    subfolder_name=$(basename "$subfolder")
    
    # Use find to safely count and get files, handling paths with spaces
    file_count=$(find "$subfolder" -maxdepth 1 -type f -name "*.JPG" | wc -l | tr -d ' ')

    if [ "$file_count" -eq 0 ]; then
        echo "$subfolder_name: No .JPG files found. Skipping."
        continue
    fi

    renamed_count=0
    processed_count=0
    
    # Start progress line
    echo -n "$subfolder_name: $file_count files - 0%"

    # 3. Get EXIF data and rename
    while IFS=',' read -r filename datetime; do
        ((processed_count++))
        
        if [[ -n "$datetime" && "$filename" == *.JPG ]]; then
            temp="${filename#DSC}"
            numeric_part="${temp%.JPG}"
            
            if [[ ${#numeric_part} -eq 5 && "$numeric_part" =~ ^[0-9]+$ ]]; then
                new_name="${manual_date}_${datetime}_${numeric_part}.jpg"
                mv "$subfolder$filename" "$subfolder$new_name"
                ((renamed_count++))
            fi
        fi
        
        # Update progress 
        if [ "$file_count" -gt 0 ] && (( processed_count % 10 == 0 || processed_count == file_count )); then
            current_percent=$(( processed_count * 100 / file_count ))
            echo -ne "\r$subfolder_name: $file_count files - ${current_percent}%"
        fi
    done < <(exiftool -d "%H%M%S" -p '$filename,$DateTimeOriginal' "$subfolder"*.JPG 2>/dev/null)
    #done < <(exiftool -d "%Y%m%d_%H%M%S" -p '$filename,$DateTimeOriginal' "$subfolder"*.JPG 2>/dev/null)
    
    # Final status update for the subfolder
    echo -e "\r$subfolder_name: $file_count files processed, $renamed_count renamed.        "
    ((total_renamed+=renamed_count))
done

# 4. Final Cleanup
echo "--- Staging ---"
echo "Moving $total_renamed renamed files to $TEMP_DIR..."

# Move all *renamed* files (which now have a lowercase .jpg extension)
#find "$DCIM_DIR" -maxdepth 2 -type f -name "*.jpg" -exec mv {} "$TEMP_DIR/" \; 2>/dev/null
total=$(find "$DCIM_DIR" -maxdepth 2 -type f -name "*.jpg" | wc -l)
count=0
find "$DCIM_DIR" -maxdepth 2 -type f -name "*.jpg" | while read -r file; do
    mv "$file" "$TEMP_DIR/" 2>/dev/null
    count=$((count + 1))
    pct=$((count * 100 / total))
    bar=$(printf '#%.0s' $(seq 1 $((pct / 2))))
    printf "Progress: [%-50s] %d%% (%d/%d)\r" "$bar" "$pct" "$count" "$total"
done
echo -e "\nCompleted!"


echo "Removing empty subfolders in $DCIM_DIR..."
# The original code's find command is correct for this job
find "$DCIM_DIR" -type d -empty -delete

temp_count=$(find "$TEMP_DIR" -type f -name "*.jpg" | wc -l | tr -d ' ')
echo "Total files successfully moved to TEMP: $temp_count"