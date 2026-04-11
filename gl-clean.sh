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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" &> /dev/null && pwd)"
source "$SCRIPT_DIR/gl-functions.sh"

# Suppress any inherited shell xtrace (set -x) from the calling environment
{ set +x; } 2>/dev/null

# zsh uses 1-based array indexing by default; force 0-based (bash-compatible)
[[ -n "$ZSH_VERSION" ]] && setopt KSH_ARRAYS

if [ $# -ne 1 ]; then
    echo "Usage: $0 <STAGE_folder>"
    exit 1
fi

STAGE_DIR="$1"

CHECK_FRAMES=10
THRESHOLD_MULTIPLIER=1.15
MIN_SERIES_FRAMES=50
BAR_WIDTH=30

check_install "compare"

# Check if any TL_* folders exist
if ! ls -d "$STAGE_DIR"/TL_* >/dev/null 2>&1; then
    echo "No timelapse series folders (TL_*) found in $STAGE_DIR."
    echo "Done"
    exit 0
fi

clean_series() {
    # Silence any active shell xtrace (set -x / setopt XTRACE) for this function —
    # variable assignment tracing would otherwise leak diff values to the terminal.
    { set +x; } 2>/dev/null
    [[ -n "$ZSH_VERSION" ]] && { setopt noXTRACE; } 2>/dev/null

    local series_dir="$1"
    local series_name
    series_name=$(basename "$series_dir")

    # Collect sorted jpg files
    local files=()
    while IFS= read -r f; do
        files+=("$f")
    done < <(find "$series_dir" -maxdepth 1 -name "*.jpg" | sort)

    local count=${#files[@]}

    if [ "$count" -lt "$MIN_SERIES_FRAMES" ]; then
        echo "  Skipping $series_name: only $count frames (min $MIN_SERIES_FRAMES)"
        return
    fi

    echo "  Analyzing $series_name ($count frames)..."

    # Compute RMSE for first CHECK_FRAMES consecutive pairs
    local diffs=()
    local filenames=()

    for ((i = 0; i < CHECK_FRAMES - 1; i++)); do
        local img1="${files[$i]}"
        local img2="${files[$i + 1]}"
        # Append directly into the array — array += ops are not traced by zsh
        # xtrace even when scalar $() assignments would be. No intermediate
        # scalar variable means no value leaks to the terminal.
        # compare exits 1 when images differ (normal), 2 on actual error.
        # Output format: "1234.5 (0.0188)" — awk extracts the normalised value.
        diffs+=( "$(compare -metric RMSE "$img1" "$img2" null: 2>&1 | awk '{
            gsub(/[()]/, "")
            print (NF >= 2) ? $2 : $1
        }')" ) || true
        filenames+=("$(basename "$img1")")
    done

    # Find global max diff for bar chart normalization
    local max_diff
    max_diff=$(printf '%s\n' "${diffs[@]}" | awk 'BEGIN{m=0} {if($1+0>m) m=$1+0} END{print m}')

    # Stable baseline: mean of the latter half of diffs
    local half_start=$(( (CHECK_FRAMES - 1) / 2 ))
    local stable_mean
    stable_mean=$(printf '%s\n' "${diffs[@]}" | awk -v start="$half_start" \
        'NR > start {sum += $1+0; count++} END {if (count > 0) print sum/count; else print 0}')

    local threshold
    threshold=$(awk "BEGIN{print $stable_mean * $THRESHOLD_MULTIPLIER}")

    # Determine leading frames to delete (stop at first diff at or below threshold)
    local frames_to_delete=0
    for ((i = 0; i < ${#diffs[@]}; i++)); do
        local is_above
        is_above=$(awk "BEGIN{print (${diffs[$i]} + 0 > $threshold + 0) ? 1 : 0}")
        if [ "$is_above" -eq 1 ]; then
            frames_to_delete=$((i + 1))
        else
            break
        fi
    done

    # Print visual diff table
    printf "  %-20s  %-8s  %s\n" "File" "RMSE" "Diff (max-normalized)"
    printf "  %-20s  %-8s  %s\n" "----" "----" "--------------------"
    for ((i = 0; i < ${#diffs[@]}; i++)); do
        local fname="${filenames[$i]}"
        local dval="${diffs[$i]}"

        # Build bar: filled blocks proportional to dval/max_diff
        local filled=0
        if [ "$(awk "BEGIN{print ($max_diff > 0) ? 1 : 0}")" -eq 1 ]; then
            filled=$(awk "BEGIN{printf \"%d\", int(($dval / $max_diff) * $BAR_WIDTH + 0.5)}")
        fi
        [ "$filled" -gt "$BAR_WIDTH" ] && filled=$BAR_WIDTH
        local empty=$(( BAR_WIDTH - filled ))
        local bar=""
        for ((j = 0; j < filled; j++));  do bar+="█"; done
        for ((j = 0; j < empty; j++));   do bar+="░"; done

        local marker=""
        [ "$i" -lt "$frames_to_delete" ] && marker="  [DELETE]"

        printf "  %-20s  %8.4f  %s%s\n" "$fname" "$dval" "$bar" "$marker"
    done

    printf "  Stable mean: %8.4f  Threshold: %8.4f\n" "$stable_mean" "$threshold"
    echo

    # Delete leading shifted frames
    if [ "$frames_to_delete" -gt 0 ]; then
        echo "  Deleting $frames_to_delete shifted frame(s) from $series_name..."
        for ((i = 0; i < frames_to_delete; i++)); do
            rm "${files[$i]}"
            echo "    Removed: $(basename "${files[$i]}")"
        done
    else
        echo "  No shifted frames detected in $series_name"
    fi
    echo
}

echo "=== Cleaning shifted frames from timelapse series ==="
echo

for series_dir in "$STAGE_DIR"/TL_*/; do
    [ -d "$series_dir" ] || continue
    clean_series "$series_dir"
done

echo "Done"
