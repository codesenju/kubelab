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