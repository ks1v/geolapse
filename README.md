# geolapse
Scripts for automatic timelapse assembling and embedding GPS data for non-timelapse shots

Written in shell, for both MacOS's zsh and Ubuntu WSL's bash

# Description
* gl-functions.sh -- library of serivce functions 
* gl-stage.sh -- find SD card, rename files and move them to Stage folder
* gl-group.sh -- group timelapse sessions and separate single shots
* gl-build.sh -- assemble video files for each timelapse session
* gl-shots.sh -- fixes EXIF for non-timelapse shots and writing GPS coordinates 
* geolapse.sh -- run the whole pipeline

# TODO:
* [ ] Test on Ubuntu WSL
* [x] Test on MacOS
* [x] Unique TL folder
* [x] Reassemble logic for GPX data
* [x] Add elevation data
* [x] Why GPS don't show on Samgung? (LatRef and LonRef are neccessery fields)
* [x] Skip manual timestamp input if GPS track is aligned with the first image 
* [ ] TL: Detect motion in the beg and end and remove such frames
* [ ] TL: Add resolution to built TL videos
* [ ] Detect interesting shots among TL frames:
    * [ ] TL: build a filestamped copies for manual identification
    * [ ] TL: Motion analysis for possible intruders like birds or so (save a percentile by motion)

