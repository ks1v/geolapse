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

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: $0 <photos_folder> [gpx_file]"
    exit 1
fi

IMG_DIR="$1"
GPX_FILE="$2"

# Validate photos folder
if [ ! -d "$IMG_DIR" ]; then
    echo "Error: Photos folder not found"
    exit 1
fi

check_install "exiftool"
check_install "xmlstarlet"

# --- Main Execution ---

echo "=== Rebuilding EXIF data ==="
exiftool -q -q -m -overwrite_original -all= -tagsfromfile @ -all:all --MakerNotes --ComponentsConfiguration -unsafe -icc_profile "$IMG_DIR" 2>/dev/null

echo ""
echo "=== Calculate datetime offset ==="

FIRST_IMG=$(find "$IMG_DIR" -type f '(' -name "*.jpg" ')' | sort | head -1)
if [ -z "$FIRST_IMG" ]; then
    echo "No JPG files found in folder" >&2
    exit 1
fi

echo "First photo: $(basename "$FIRST_IMG")" >&2
if [[ "$OSTYPE" == "darwin"* ]]; then
    open -a Preview "$FIRST_IMG" 2>/dev/null
fi

echo "Enter the actual datetime of this photo (ISO format: YYYY-MM-DD HH:MM):" >&2
read actual_datetime
actual_datetime="${actual_datetime}:00"
exif_datetime=$(exiftool -d "%Y-%m-%d %H:%M:%S" -s3 -DateTimeOriginal "$FIRST_IMG")
echo "EXIF datetime: $exif_datetime" >&2
echo "Actual datetime: $actual_datetime" >&2

if [[ "$OSTYPE" == "darwin"* ]]; then
    exif_timestamp=$(date -j -f "%Y-%m-%d %H:%M:%S" "$exif_datetime" "+%s")
    actual_timestamp=$(date -j -f "%Y-%m-%d %H:%M:%S" "$actual_datetime" "+%s")
else
    exif_timestamp=$(date -d "$exif_datetime" "+%s")
    actual_timestamp=$(date -d "$actual_datetime" "+%s")
fi

CAMERA_OFFSET=$((actual_timestamp - exif_timestamp))
echo "Calculated offset: $CAMERA_OFFSET seconds"

# --- Optional GPX Handling ---
if [[ -z "$GPX_FILE" ]]; then
    echo ""
    echo -n "Enter path to GPX file (or press Enter to skip geotagging): "
    read -r GPX_FILE
fi

HAS_GPX=false
if [[ -n "$GPX_FILE" ]]; then
    if [[ -f "$GPX_FILE" ]]; then
        HAS_GPX=true
    else
        echo "Warning: GPX file not found at '$GPX_FILE'. Skipping geotagging."
    fi
fi

echo ""
echo "=== Building updated timestamps ==="

# This block reads photo data from exiftool, calculates the correct timestamp,
# and populates the IMG_DIR_TS array after sorting it numerically.
temp_photo_data=()
while IFS='|' read -r filepath exif_dt; do
    if [ -n "$filepath" ] && [ -n "$exif_dt" ]; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            exif_ts=$(date -j -f "%Y-%m-%d %H:%M:%S" "$exif_dt" "+%s")
            actual_ts=$((exif_ts + CAMERA_OFFSET))
            actual_dt=$(date -j -r "$actual_ts" "+%Y-%m-%d %H:%M:%S")
        else
            exif_ts=$(date -d "$exif_dt" "+%s")
            actual_ts=$((exif_ts + CAMERA_OFFSET))
            actual_dt=$(date -d "@$actual_ts" "+%Y-%m-%d %H:%M:%S")
        fi
        echo "$(basename "$filepath"): $exif_dt -> $actual_dt" >&2
        temp_photo_data+=("$actual_ts|$filepath")
    fi
done < <(exiftool -d "%Y-%m-%d %H:%M:%S" -p '$directory/$filename|$DateTimeOriginal' "$IMG_DIR"/*.jpg 2>/dev/null)

# Sort the data numerically by timestamp and load into the final array
IMG_DIR_TS=()
while IFS= read -r line; do
    IMG_DIR_TS+=("$line")
done < <(for item in "${temp_photo_data[@]}"; do echo "$item"; done | sort -n)

if [[ "$HAS_GPX" == "true" ]]; then
    echo ""
    echo "=== Step 3: Parse GPX file ==="
    # This block parses the GPX file and populates the GPX_* arrays.
    local_offset_str=$(date +%z)
    offset_seconds=$(( (10#${local_offset_str:0:3}) * 3600 + (10#${local_offset_str:3:2}) * 60 ))
    echo "Local timezone offset: $local_offset_str (${offset_seconds} seconds)" >&2

    GPX_TS=()
    GPX_LATS=()
    GPX_LONGS=()
    while IFS='|' read -r lat lon time_str; do
        if [[ -n "$time_str" ]]; then
            if [[ "$OSTYPE" == "darwin"* ]]; then
                utc_ts=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$time_str" "+%s" 2>/dev/null)
            else
                utc_ts=$(date -d "$time_str" "+%s" 2>/dev/null)
            fi
            local_ts=$((utc_ts + offset_seconds))
            GPX_TS+=("$local_ts")
            GPX_LATS+=("$lat")
            GPX_LONGS+=("$lon")
        fi
    done < <(xmlstarlet sel -N "gpx=http://www.topografix.com/GPX/1/1" -t -m "//gpx:trkpt" \
        -v "@lat" -o '|' -v "@lon" -o '|' -v "gpx:time" -n "$GPX_FILE" 2>/dev/null)

    echo "Loaded ${#GPX_TS[@]} GPS trackpoints"

    # Unified way to show first 5 elements
    echo "First 5 timestamps: $(echo "${GPX_TS[@]}" | tr ' ' '\n' | head -5 | tr '\n' ' ')"
    echo "First 5 latitudes:  $(echo "${GPX_LATS[@]}" | tr ' ' '\n' | head -5 | tr '\n' ' ')"
    echo ""
    echo "=== Matching photos with GPS locations and updating EXIF ==="
else 
    echo ""
    echo "=== Updating EXIF: timestamps only ==="
fi


# This loop iterates through the photos and the GPX track simultaneously.
GPX_INDEX=1
now_for_exif=$(date "+%Y:%m:%d %H:%M:%S")

for item in "${IMG_DIR_TS[@]}"; do
    IFS='|' read -r actual_ts filepath <<< "$item"

    # Convert actual timestamp back to human-readable datetime for logging.
    if [[ "$OSTYPE" == "darwin"* ]]; then
        actual_dt=$(date -j -r "$actual_ts" "+%Y-%m-%d %H:%M:%S")
    else
        actual_dt=$(date -d "@$actual_ts" "+%Y-%m-%d %H:%M:%S")
    fi

    # Format datetime for EXIF (YYYY:MM:DD HH:MM:SS)
    exif_format_dt=$(echo "$actual_dt" | sed 's/-/:/g')
    
    local exif_args=(-overwrite_original -q \
        -DateTimeOriginal="$exif_format_dt" \
        -CreateDate="$exif_format_dt" \
        -ModifyDate="$now_for_exif" \
        -OffsetTimeOriginal= \
        -OffsetTime=)

    if [[ "$HAS_GPX" == "true" ]]; then
        # Advance the GPX index until the GPX time is just past the photo time.
        # This keeps the GPX pointer moving forward, avoiding redundant searches.
        while (( GPX_INDEX < ${#GPX_TS[@]} && GPX_TS[GPX_INDEX+1] < actual_ts )); do
            ((GPX_INDEX++))
        done

        # Now check which of the two surrounding GPX points is closer.
        diff1=$((actual_ts - GPX_TS[GPX_INDEX]))
        [[ $diff1 -lt 0 ]] && diff1=$((-diff1))

        closest_idx=$GPX_INDEX
        if (( GPX_INDEX < ${#GPX_TS[@]} )); then
            diff2=$((actual_ts - GPX_TS[GPX_INDEX+1]))
            [[ $diff2 -lt 0 ]] && diff2=$((-diff2))
            if (( diff2 < diff1 )); then
                closest_idx=$((GPX_INDEX + 1))
            fi
        fi

        latitude=${GPX_LATS[$closest_idx]}
        longitude=${GPX_LONGS[$closest_idx]}
        exif_args+=(-GPSLatitude="$latitude" -GPSLongitude="$longitude")
        echo "EXIF for $(basename "$filepath") -> $actual_dt @ $latitude, $longitude"
    else
        echo "EXIF for $(basename "$filepath") -> $actual_dt"
    fi
    
    # Update EXIF: datetime and GPS coordinates
    exiftool "${exif_args[@]}" "$filepath" 2>/dev/null
done

echo ""
echo "=== Renaming files ==="
# Rename files based on actual datetime
# Iterate through the sorted photo data to ensure consistent renaming order.
for item in "${IMG_DIR_TS[@]}"; do
    IFS='|' read -r actual_ts filepath <<< "$item"
    
    # Generate new filename: YYYYMMDD_HHMMSS.jpg
    if [[ "$OSTYPE" == "darwin"* ]]; then
        new_name=$(date -j -r "$actual_ts" "+%Y%m%d_%H%M%S.jpg")
    else
        new_name=$(date -d "@$actual_ts" "+%Y%m%d_%H%M%S.jpg")
    fi
    new_path="$(dirname "$filepath")/$new_name"
    
    # Rename if different
    if [ "$filepath" != "$new_path" ]; then
        mv "$filepath" "$new_path"
        echo "Renamed: $(basename "$filepath") -> $new_name"
    fi
done

echo ""
echo "=== Complete ==="

echo ""
echo "=== Checking for unprocessed images ==="

check_condition=""
if [[ "$HAS_GPX" == "true" ]]; then
    check_condition='$DateTimeOriginal =~ /^2016/ or not $GPSLatitude'
else
    check_condition='$DateTimeOriginal =~ /^2016/'
fi
unprocessed_files=$(exiftool -m -n -q -p '$filename | $DateTimeOriginal | $GPSLatitude, $GPSLongitude' -d '%Y-%m-%d %H:%M:%S' -if "$check_condition" "$IMG_DIR")

if [[ -n "$unprocessed_files" ]]; then
    echo "Untreated files found:"
    echo "$unprocessed_files"
else
    echo ""
    echo "ALL GOOD"
fi