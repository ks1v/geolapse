#!/usr/bin/env bash

# Function to detect and mount SD card
find_and_mount_sd() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        echo "Detecting SD card on macOS..." >&2
        
        # Find external disk
        sd_disk=$(diskutil list | grep -i "external" | awk '{print $1}' | head -1)
        
        if [ -z "$sd_disk" ]; then
            echo "No SD card detected" >&2
            return 1
        fi
        
        echo "Found SD card: $sd_disk" >&2
        
        # Check if already mounted
        mount_point=$(diskutil info "$sd_disk" | grep "Mount Point" | cut -d: -f2 | xargs)
        
        if [ -z "$mount_point" ]; then
            # Mount the SD card
            diskutil mount "$sd_disk"
            mount_point=$(diskutil info "$sd_disk" | grep "Mount Point" | cut -d: -f2 | xargs)
        fi
        
        echo "SD card mounted at: $mount_point" >&2
        echo "$mount_point"
        
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

find_and_mount_sd