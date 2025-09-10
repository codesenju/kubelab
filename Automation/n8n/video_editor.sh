#!/bin/bash

# Default values
INPUT_FILE="input.mp4"
WATERMARK_FILE="escape925.png"
OUTPUT_FILE="output_with_watermark.mp4"
BLUR_INTENSITY="20:10"
OUTPUT_WIDTH="1080"
OUTPUT_HEIGHT="1920"
CROP_PERCENTAGE="0.85"
CROP_POSITION="0.075"
WATERMARK_OPACITY="0.9"
WATERMARK_SCALE="0.3"
BOTTOM_SPACING="150"
CRF_VALUE="23"

# Help function
show_help() {
    cat << EOF
Video Processor Script - Adds blurred borders and watermark to videos

Usage: $0 [OPTIONS]

Options:
  -i, --input FILE          Input video file (default: $INPUT_FILE)
  -w, --watermark FILE      Watermark image file (default: $WATERMARK_FILE)
  -o, --output FILE         Output video file (default: $OUTPUT_FILE)
  
  --blur INTENSITY          Blur intensity 'horizontal:vertical' (default: $BLUR_INTENSITY)
  --width WIDTH             Output width (default: $OUTPUT_WIDTH)
  --height HEIGHT           Output height (default: $OUTPUT_HEIGHT)
  
  --crop-percent DECIMAL    Crop percentage (0.0-1.0) (default: $CROP_PERCENTAGE)
  --crop-position DECIMAL   Crop position from top (0.0-1.0) (default: $CROP_POSITION)
  
  --wm-opacity DECIMAL      Watermark opacity (0.0-1.0) (default: $WATERMARK_OPACITY)
  --wm-scale DECIMAL        Watermark scale factor (default: $WATERMARK_SCALE)
  --wm-spacing PIXELS       Watermark spacing from bottom (default: $BOTTOM_SPACING)
  
  --crf VALUE               Video quality CRF value (default: $CRF_VALUE)
  -h, --help                Show this help message

Examples:
  $0
  $0 -i myvideo.mp4 -o result.mp4 --wm-scale 0.4 --wm-spacing 100
  $0 --blur "25:15" --crop-percent 0.8 --wm-opacity 0.8
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--input)
            INPUT_FILE="$2"
            shift 2
            ;;
        -w|--watermark)
            WATERMARK_FILE="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --blur)
            BLUR_INTENSITY="$2"
            shift 2
            ;;
        --width)
            OUTPUT_WIDTH="$2"
            shift 2
            ;;
        --height)
            OUTPUT_HEIGHT="$2"
            shift 2
            ;;
        --crop-percent)
            CROP_PERCENTAGE="$2"
            shift 2
            ;;
        --crop-position)
            CROP_POSITION="$2"
            shift 2
            ;;
        --wm-opacity)
            WATERMARK_OPACITY="$2"
            shift 2
            ;;
        --wm-scale)
            WATERMARK_SCALE="$2"
            shift 2
            ;;
        --wm-spacing)
            BOTTOM_SPACING="$2"
            shift 2
            ;;
        --crf)
            CRF_VALUE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Check if input file exists
if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Error: Input file '$INPUT_FILE' not found!"
    exit 1
fi

# Check if watermark file exists
if [[ ! -f "$WATERMARK_FILE" ]]; then
    echo "Error: Watermark file '$WATERMARK_FILE' not found!"
    exit 1
fi

# Show current configuration
echo "=== Video Processing Configuration ==="
echo "Input: $INPUT_FILE"
echo "Watermark: $WATERMARK_FILE"
echo "Output: $OUTPUT_FILE"
echo "Resolution: ${OUTPUT_WIDTH}x${OUTPUT_HEIGHT}"
echo "Blur: $BLUR_INTENSITY"
echo "Crop: ${CROP_PERCENTAGE} (keep), position: ${CROP_POSITION}"
echo "Watermark: scale ${WATERMARK_SCALE}, opacity ${WATERMARK_OPACITY}, spacing ${BOTTOM_SPACING}px"
echo "Quality: CRF $CRF_VALUE"
echo "======================================"

# Run FFmpeg command
ffmpeg -i "$INPUT_FILE" -i "$WATERMARK_FILE" -filter_complex "
    [0:v]split=2[blur_source][crop_source];
    [blur_source]scale=${OUTPUT_WIDTH}:${OUTPUT_HEIGHT},boxblur=${BLUR_INTENSITY}[blurred_bg];
    [crop_source]crop=iw:ih*${CROP_PERCENTAGE}:0:ih*${CROP_POSITION},scale=${OUTPUT_WIDTH}:-1[main];
    [blurred_bg][main]overlay=(W-w)/2:(H-h)/2[base];
    [1:v]scale=iw*${WATERMARK_SCALE}:-1,format=rgba,colorchannelmixer=aa=${WATERMARK_OPACITY}[watermark];
    [base][watermark]overlay=(W-w)/2:H-h-${BOTTOM_SPACING}
" -c:a copy -c:v libx264 -crf "$CRF_VALUE" "$OUTPUT_FILE"

# Check if successful
if [[ $? -eq 0 ]]; then
    echo "✅ Success! Output file: $OUTPUT_FILE"
else
    echo "❌ Processing failed!"
    exit 1
fi