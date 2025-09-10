## How to add blurred border to an image
```bash
# Blur intensity (horizontal:vertical)
export BLUR_INTENSITY="20:10"
# Crop percentage (how much of height to keep)
export CROP_PERCENTAGE="0.85"
# Crop position (percentage from top)
export CROP_POSITION="0.075"
# Output resolution
export OUTPUT_WIDTH="1080"
export OUTPUT_HEIGHT="1920"
# Video quality
export CRF_VALUE="23"

```
```bash
ffmpeg -i input.mp4 -filter_complex "
    [0:v]split=2[blur_source][crop_source];
    [blur_source]scale=${OUTPUT_WIDTH}:${OUTPUT_HEIGHT},boxblur=${BLUR_INTENSITY}[blurred_bg];
    [crop_source]crop=iw:ih*${CROP_PERCENTAGE}:0:ih*${CROP_POSITION},scale=${OUTPUT_WIDTH}:-1[main];
    [blurred_bg][main]overlay=(W-w)/2:(H-h)/2:format=auto
" -c:a copy -c:v libx264 -crf ${CRF_VALUE} output_cropped_blur.mp4
```

# Script
video_blur_border.sh:
```bash
#!/bin/bash

# Default values
BLUR_INTENSITY=${1:-"20:10"}
CROP_PERCENTAGE=${2:-"0.85"}
CROP_POSITION=${3:-"0.075"}
OUTPUT_WIDTH=${4:-"1080"}
OUTPUT_HEIGHT=${5:-"1920"}
CRF_VALUE=${6:-"23"}
INPUT_FILE=${7:-"input.mp4"}
OUTPUT_FILE=${8:-"output_cropped_blur.mp4"}

ffmpeg -i "$INPUT_FILE" -filter_complex "
    [0:v]split=2[blur_source][crop_source];
    [blur_source]scale=${OUTPUT_WIDTH}:${OUTPUT_HEIGHT},boxblur=${BLUR_INTENSITY}[blurred_bg];
    [crop_source]crop=iw:ih*${CROP_PERCENTAGE}:0:ih*${CROP_POSITION},scale=${OUTPUT_WIDTH}:-1[main];
    [blurred_bg][main]overlay=(W-w)/2:(H-h)/2:format=auto
" -c:a copy -c:v libx264 -crf ${CRF_VALUE} "$OUTPUT_FILE"
```
# Make executable
```bash
chmod +x video_blur_border.sh
```

# Usage examples:
```bash
./video_blur_border.sh
./video_blur_border.sh "25:15" "0.80" "0.10" "1080" "1920" "23" "input.mp4" "my_video.mp4"
./video_blur_border.sh "30:15" "0.75" "0.125" "1080" "1920" "22" "video.mp4" "output.mp4"
```