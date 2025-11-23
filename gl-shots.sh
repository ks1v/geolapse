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

# Parsing GPX file
if [[ "$HAS_GPX" == "true" ]]; then
    echo ""
    echo "=== Parse GPX file ==="

    # Local TZ offset
    LOCAL_TZ_STR=$(date +%z)
    LOCAL_TZ_OFFSET=$(( (10#${LOCAL_TZ_STR:0:3}) * 3600 + (10#${LOCAL_TZ_STR:3:2}) * 60 ))
    echo "Local timezone offset: $LOCAL_TZ_STR (${LOCAL_TZ_OFFSET} seconds)" >&2

    # Loading GPS data
    GPX_TS=()
    GPX_LATS=()
    GPX_LONGS=()
    GPX_ELEVS=()
    while IFS='|' read -r lat lon ele time_str; do
        if [[ -n "$time_str" ]]; then
            # GPX time is in UTC (e.g., 2023-01-01T12:00:00Z).
            # We need to convert it to a local timestamp to match the photo's EXIF time.
            if [[ "$OSTYPE" == "darwin"* ]]; then
                utc_ts=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$time_str" "+%s" 2>/dev/null)
            else
                utc_ts=$(date -d "$time_str" "+%s" 2>/dev/null)
            fi
            local_ts=$((utc_ts + LOCAL_TZ_OFFSET))
            GPX_TS+=("$local_ts")
            GPX_LATS+=("$lat")
            GPX_LONGS+=("$lon")
            GPX_ELEVS+=("$ele")
        fi
    done < <(xmlstarlet sel -N "gpx=http://www.topografix.com/GPX/1/1" -t -m "//gpx:trkpt" \
        -v "@lat" -o '|' -v "@lon" -o '|' -v "gpx:ele" -o '|' -v "gpx:time" -n "$GPX_FILE" 2>/dev/null)

    # Checking if GPX was fulli loaded
    cnt_gpx_ts=${#GPX_TS[@]}
    cnt_gpx_lats=${#GPX_LATS[@]}
    cnt_gpx_longs=${#GPX_LONGS[@]}
    cnt_gpx_elevs=${#GPX_ELEVS[@]}

    if [[ "$cnt_gpx_ts" -ne "$cnt_gpx_lats" \
       || "$cnt_gpx_ts" -ne "$cnt_gpx_longs" \
       || "$cnt_gpx_ts" -ne "$cnt_gpx_elevs" ]]; then
        echo "Warning: Mismatch in GPX data arrays. Some data points may be incomplete." >&2
        echo "  Timestamps: $cnt_gpx_ts points" >&2
        echo "  Latitudes:  $cnt_gpx_lats point" >&2
        echo "  Longitudes: $cnt_gpx_longs point" >&2
        echo "  Elevations: $cnt_gpx_elevs point" >&2
        GPX_STATUS="WARNING"
    else 
        echo "GPX track loaded consistenly -- all $cnt_gpx_ts points" >&2
        GPX_STATUS="OK"
    fi

    # Unified way to show first 5 elements
    echo "First 5 timestamps: $(echo "${GPX_TS[@]}" | tr ' ' '\n' | head -5 | tr '\n' ' ')"
    echo "First 5 latitudes:  $(echo "${GPX_LATS[@]}" | tr ' ' '\n' | head -5 | tr '\n' ' ')"

fi


if [[ "$GPX_STATUS" == "OK" ]]; then
    echo ""
    echo "=== Matching photos with GPS locations and updating EXIF ==="
else 
    echo ""
    echo "=== Updating EXIF: timestamps only ==="
fi

echo ""
echo "=== Calculate datetime offset ==="

FIRST_IMG=$(find "$IMG_DIR" -type f '(' -name "*.jpg" ')' | sort | head -1)
if [ -z "$FIRST_IMG" ]; then
    echo "No JPG files found in folder" >&2
    exit 1
fi

echo "First photo: $(basename "$FIRST_IMG")" >&2
exif_datetime=$(exiftool -d "%Y-%m-%d %H:%M:%S" -s3 -DateTimeOriginal "$FIRST_IMG")
echo "   Its EXIF datetime: $exif_datetime" >&2

if [[ "$GPX_STATUS" == "OK" ]]; then
    echo "Does the first image is aligned with GPS track? Y/N" >&2
    read READ_FIRST_IMG_TS_FROM_GPX 
fi

if [[ "$GPX_STATUS" == "OK" && ("$READ_FIRST_IMG_TS_FROM_GPX" == "Y" || "$READ_FIRST_IMG_TS_FROM_GPX" == "y") ]]; then
    if [ -n "$ZSH_VERSION" ]; then
        actual_timestamp=${GPX_TS[1]} 
    else
        actual_timestamp=${GPX_TS[0]} 
    fi
else
    if [[ "$OSTYPE" == "darwin"* ]]; then
        open -a Preview "$FIRST_IMG" 2>/dev/null
    fi

    echo "Enter the actual datetime of this photo (ISO format: YYYY-MM-DD HH:MM):" >&2
    read actual_datetime
    actual_datetime="${actual_datetime}:00"
    echo "Actual datetime: $actual_datetime" >&2
    actual_timestamp=$(iso_to_unix "$actual_datetime")
fi

exif_timestamp=$(iso_to_unix "$exif_datetime")
CAMERA_OFFSET=$((actual_timestamp - exif_timestamp))
echo "Calculated offset: $CAMERA_OFFSET seconds"


echo ""
echo "=== Building updated timestamps ==="
temp_photo_data=()
while IFS='|' read -r filepath exif_dt; do
    if [ -n "$filepath" ] && [ -n "$exif_dt" ]; then
        exif_ts=$(iso_to_unix "$exif_dt")
        actual_ts=$((exif_ts + CAMERA_OFFSET))
        actual_dt=$(unix_to_iso "$actual_ts")
        echo "$(basename "$filepath"): $exif_dt -> $actual_dt" >&2
        temp_photo_data+=("$actual_ts|$filepath")
    fi
done < <(exiftool -d "%Y-%m-%d %H:%M:%S" -p '$directory/$filename|$DateTimeOriginal' "$IMG_DIR"/*.jpg 2>/dev/null)

# Sort the data numerically by timestamp and load into the final array
IMG_DIR_TS=()
while IFS= read -r line; do
    IMG_DIR_TS+=("$line")
done < <(for item in "${temp_photo_data[@]}"; do echo "$item"; done | sort -n)


echo ""
echo "=== Writing new EXIF ==="

# This loop iterates through the photos and the GPX track simultaneously.
GPX_INDEX=1
now_for_exif=$(date "+%Y:%m:%d %H:%M:%S")

for item in "${IMG_DIR_TS[@]}"; do
    IFS='|' read -r actual_ts filepath <<< "$item"

    actual_dt=$(unix_to_iso "$actual_ts")

    # Format datetime for EXIF (YYYY:MM:DD HH:MM:SS)
    exif_format_dt=$(echo "$actual_dt" | sed 's/-/:/g')
    
    local exif_args=(-overwrite_original -q \
        -DateTimeOriginal="$exif_format_dt" \
        -CreateDate="$exif_format_dt" \
        -ModifyDate="$now_for_exif" \
        -OffsetTimeOriginal= \
        -OffsetTime=)

    if [[ "$GPX_STATUS" != "OK" ]]; then
        echo "EXIF for $(basename "$filepath") -> $actual_dt"
    else
        # Advance the GPX index until the GPX time is just past the photo time.
        # This keeps the GPX pointer moving forward, avoiding redundant searches.
        while (( GPX_INDEX < ${#GPX_TS[@]} && ${GPX_TS[GPX_INDEX+1]} < actual_ts )); do
            ((GPX_INDEX++))
        done

        # Now check which of the two surrounding GPX points is closer.
        diff1=$((actual_ts - ${GPX_TS[GPX_INDEX]}))
        [[ $diff1 -lt 0 ]] && diff1=$((-diff1))

        closest_idx=$GPX_INDEX
        if (( GPX_INDEX < ${#GPX_TS[@]} )); then
            diff2=$((actual_ts - ${GPX_TS[GPX_INDEX+1]}))
            [[ $diff2 -lt 0 ]] && diff2=$((-diff2))
            if (( diff2 < diff1 )); then
                closest_idx=$((GPX_INDEX + 1))
            fi
        fi
        
        elevation=${GPX_ELEVS[$closest_idx]}
        latitude=${GPX_LATS[$closest_idx]}
        longitude=${GPX_LONGS[$closest_idx]}
        lat_ref="N" && [[ $latitude == -* ]] && lat_ref="S"
        lon_ref="E" && [[ $longitude == -* ]] && lon_ref="W"
        exif_args+=(-GPSLatitude="$latitude" -GPSLatitudeRef="$lat_ref" \
                    -GPSLongitude="$longitude" -GPSLongitudeRef="$lon_ref" \
                    -GPSAltitude="$elevation")

        echo "EXIF for $(basename "$filepath") -> $actual_dt @ $lat_ref $latitude, $lon_ref $longitude at $elevation m"
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
if [[ "$GPX_STATUS" == "OK" ]]; then
    check_condition='$DateTimeOriginal =~ /^2016/ or not $GPSLatitude or not $GPSLongitude'
else
    check_condition='$DateTimeOriginal =~ /^2016/'
fi
unprocessed_files=$(exiftool -m -n -q -p '$filename | $DateTimeOriginal | $GPSLatitude, $GPSLongitude, $GPSAltitude' \
    -d '%Y-%m-%d %H:%M:%S' -if "$check_condition" "$IMG_DIR")

if [[ -n "$unprocessed_files" ]]; then
    echo "Untreated files found:"
    echo "$unprocessed_files"
else
    echo ""
    echo "ALL GOOD"
fi