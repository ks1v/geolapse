# Function to detect and mount SD card
find_and_mount_sd() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        echo "Detecting SD card on macOS..." >&2

        # Find all external disks
        external_disks=$(diskutil list | grep "external" | grep -o '/dev/disk[0-9]*')

        sd_disk=""
        for disk in $external_disks; do
            # Check if this disk is SD/MMC
            if diskutil info "$disk" | grep -q "SD/MMC"; then
                sd_disk="$disk"
                break
            fi
        done

        if [ -z "$sd_disk" ]; then
            echo "No SD card detected" >&2
            return 1
        fi

        echo "Found SD card: $sd_disk" >&2

        # Find the first partition (usually s1)
        sd_partition="${sd_disk}s1"

        # Check if partition exists and get mount point
        if diskutil info "$sd_partition" &>/dev/null; then
            mount_point=$(diskutil info "$sd_partition" | grep "Mount Point" | cut -d: -f2 | xargs)
            
            if [ -z "$mount_point" ]; then
                # Mount the partition
                diskutil mount "$sd_partition"
                mount_point=$(diskutil info "$sd_partition" | grep "Mount Point" | cut -d: -f2 | xargs)
            fi
            
            echo "SD card mounted at: $mount_point" >&2
            echo "$mount_point"
        else
            echo "No valid partition found on $sd_disk" >&2
            return 1
        fi
        
    elif grep -qi microsoft /proc/version 2>/dev/null; then
        # WSL
        echo "Detecting SD card on WSL..." >&2
        
        # Check for existing mounts under /mnt/ (excluding c, wsl, wslg)
        for drive in /mnt/[d-z]; do
            if [ -d "$drive" ] && [ "$(ls -A $drive 2>/dev/null)" ]; then
                echo "Found SD card at: $drive" >&2
                echo "$drive"
                return 0
            fi
        done
        
        # Get drive letter from PowerShell
        drive_letter=$(powershell.exe -Command "Get-Volume | Where-Object {\$_.DriveType -eq 'Removable'} | Select-Object -ExpandProperty DriveLetter" 2>/dev/null | tr -d '\r\n ' | head -1)
        
        if [ -z "$drive_letter" ]; then
            echo "No SD card detected" >&2
            return 1
        fi
        
        echo "Found removable drive: $drive_letter" >&2
        
        # Mount it in WSL
        mount_point="/mnt/$(echo $drive_letter | tr '[:upper:]' '[:lower:]')"
        
        if [ ! -d "$mount_point" ] || [ -z "$(ls -A $mount_point 2>/dev/null)" ]; then
            sudo mkdir -p "$mount_point"
            sudo mount -t drvfs "${drive_letter}:" "$mount_point"
        fi
        
        echo "SD card mounted at: $mount_point" >&2
        echo "$mount_point"
        
    else
        # Native Linux
        echo "Detecting SD card on Linux..." >&2
        
        # Check for already mounted removable media
        mount_point=$(lsblk -nlo MOUNTPOINT,RM,TYPE | awk '$2=="1" && $3=="part" && $1!="" {print $1}' | grep -v "^/$" | head -1)
        
        if [ -n "$mount_point" ]; then
            echo "SD card already mounted at: $mount_point" >&2
            echo "$mount_point"
            return 0
        fi
        
        # Find unmounted SD card
        sd_partition=$(lsblk -nlo NAME,RM,TYPE | awk '$2=="1" && $3=="part" {print "/dev/"$1}' | head -1)
        
        if [ -z "$sd_partition" ]; then
            echo "No SD card detected" >&2
            return 1
        fi
        
        echo "Found SD card partition: $sd_partition" >&2
        
        # Create mount point and mount
        mount_point="/mnt/sdcard"
        sudo mkdir -p "$mount_point"
        sudo mount "$sd_partition" "$mount_point"
        
        echo "SD card mounted at: $mount_point" >&2
        echo "$mount_point"
    fi
}

# Function to check exit status ($?) and exit if non-zero.
# Usage: check_status "Error message"
check_status() {
    local last_status=$?
    local error_message=""

    if [ $# -eq 0 ]; then
        error_message="Unknown error"
    else
        error_message="$1"
    fi

    if [ "$last_status" -ne 0 ]; then
        echo "Error: $error_message (Exit Code $last_status)" >&2
        exit 1
    fi
}

check_install(){
    app_name="$1"

    if command -v "$app_name" >/dev/null 2>&1; then
        echo "$app_name is installed."
        return 0
    fi

    local install_name="$app_name"
    # Handle special case for exiftool on Debian/Ubuntu
    if [[ "$app_name" == "exiftool" && ("$OSTYPE" == "linux-gnu"* || "$OSTYPE" == "linux"*) ]]; then
        install_name="libimage-exiftool-perl"
    fi

    echo "$app_name not found. Attempting installation..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install "$install_name"
        check_status "Failed to install $app_name using brew."
    elif [[ "$OSTYPE" == "linux-gnu"* || "$OSTYPE" == "linux"* ]]; then
        sudo apt update && sudo apt install -y "$install_name"
        check_status "Failed to install $app_name using apt."
    else
        echo Error: "Unsupported OS. Please install $app_name manually."
        exit 1
    fi
}

iso_to_unix() {
    local datetime_str="$1"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        date -j -f "%Y-%m-%d %H:%M:%S" "$datetime_str" "+%s" 2>/dev/null
    else
        date -d "$datetime_str" "+%s" 2>/dev/null
    fi
}

unix_to_iso() {
    local unix_ts="$1"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        date -j -r "$unix_ts" "+%Y-%m-%d %H:%M:%S" 2>/dev/null
    else
        date -d "@$unix_ts" "+%Y-%m-%d %H:%M:%S" 2>/dev/null
    fi
}