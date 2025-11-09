# timelapse-toolkit
Scripts for automatic timelapse sorting and assembling 

Written in shell, for both MacOS's zsh and Ubuntu WSL's bash

# Description
* tl-functions.sh -- library of serivce functions 
* tl-mover.sh -- find SD card, rename files and move them to Stage folder
* tl-group.sh -- group timelapse sessions and separate single shots
* tl-ffmpeg.sh -- assemble video files for each timelapse session
* tl-toolkit.sh -- run the whole pipeline

# TODO:
* [x] Test on Ubuntu WSL
* [x] Test on MacOS
* [x] Unique TL folder
* [ ] Streamline logic
* [ ] Wrong camera dates workaround 
* [ ] Find shots with birds in timelapses 
