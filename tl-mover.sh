#!/bin/bash

# --- Error and Utility Functions ---

# Function to check exit status ($?) and exit if non-zero.
# Usage: check_status "Error message"
check_status() {
  local last_status=$?
  if [ "$last_status" -ne 0 ]; then
    echo "Error: $1 (Exit Code $last_status)" >&2
    exit 1
  fi
}

# Function to check for exiftool and install it if necessary.
install_exiftool() {
  if command -v exiftool >/dev/null 2>&1; then
    echo "exiftool is installed."
    return 0
  fi

  echo "exiftool not found. Attempting installation..."
  if [[ "$OSTYPE" == "darwin"* ]]; then
    brew install exiftool
    check_status "Failed to install exiftool using brew."
  elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    sudo apt update && sudo apt install -y libimage-exiftool-perl
    check_status "Failed to install exiftool using apt."
  else
    echo "Error: Unsupported OS. Please install exiftool manually." >&2
    exit 1
  fi
}

# --- Main Logic ---

# Check arguments and set variables
if [ $# -ne 2 ]; then
    echo "Usage: $0 <DCIM_folder> <TEMP_folder>" >&2
    exit 1
fi
DCIM_DIR="$1"
TEMP_DIR="$2"

# 1. Setup and Preparation
install_exiftool
echo "Creating temporary directory: $TEMP_DIR"
mkdir -p "$TEMP_DIR"
check_status "Failed to create temporary directory $TEMP_DIR."

total_renamed=0

# 2. Process DCIM Subfolders
# Use a simple glob and process only directories (to be robust)
echo "--- Starting file processing in $DCIM_DIR ---"
for subfolder in "$DCIM_DIR"/*/ ; do
    # Skip if not a directory (handles case where glob matches nothing)
    [ -d "$subfolder" ] || continue
    
    subfolder_name=$(basename "$subfolder")
    
    # Use find to safely count and get files, handling paths with spaces
    mapfile -t jpg_files < <(find "$subfolder" -maxdepth 1 -type f -name "*.JPG")
    file_count="${#jpg_files[@]}"

    if [ "$file_count" -eq 0 ]; then
        echo "$subfolder_name: No .JPG files found. Skipping."
        continue
    fi

    renamed_count=0
    processed_count=0
    
    # Start progress line
    echo -n "$subfolder_name: $file_count files - 0%"

    # 3. Get EXIF data and rename
    # Use array expansion to safely pass files to exiftool
    exiftool -d "%Y-%m-%d_%H-%M-%S" -p '$filename,$DateTimeOriginal' "${jpg_files[@]}" 2>/dev/null | \
    while IFS=',' read -r filename datetime; do
        ((processed_count++))
        
        # Check for valid datetime and ensure it's a JPG (exiftool might list other files)
        if [[ -n "$datetime" && "$filename" =~ \.JPG$ ]]; then
            # Extract the 5-digit numeric part (e.g., 12345 from DSC12345.JPG)
            # This regex is more concise than the string manipulation
            if [[ "$filename" =~ DSC([0-9]{5})\.JPG$ ]]; then
                numeric_part="${BASH_REMATCH[1]}"
                
                # Construct new name and rename
                new_name="${datetime}_${numeric_part}.jpg"
                mv "$subfolder$filename" "$subfolder$new_name"
                # Check for mv error (if file was open or permissions denied)
                check_status "Failed to rename $subfolder$filename"
                
                ((renamed_count++))
            fi
        fi
        
        # Update progress 
        if (( processed_count % 10 == 0 || processed_count == file_count )); then
             current_percent=$(( processed_count * 100 / file_count ))
             # Only update the display if the percentage has changed
             if [ "$current_percent" -ne "$last_percent" ]; then
                echo -ne "\r$subfolder_name: $file_count files - ${current_percent}%"
                last_percent=$current_percent
             fi
        fi
    done
    
    # Final status update for the subfolder
    echo -e "\r$subfolder_name: $file_count files processed, $renamed_count renamed.        "
    ((total_renamed+=renamed_count))
done

# 4. Final Cleanup
echo "--- Finalizing ---"
echo "Moving $total_renamed renamed files to $TEMP_DIR..."

# Move all *renamed* files (which now have a lowercase .jpg extension)
# Add an extra check to prevent error message if no files match
find "$DCIM_DIR" -maxdepth 2 -type f -name "*.jpg" -exec mv {} "$TEMP_DIR/" \; 2>/dev/null

echo "Removing empty subfolders in $DCIM_DIR..."
# The original code's find command is correct for this job
find "$DCIM_DIR" -type d -empty -delete

temp_count=$(find "$TEMP_DIR" -type f -name "*.jpg" | wc -l | tr -d ' ')
echo "Total files successfully moved to TEMP: $temp_count"

echo "Script finished."