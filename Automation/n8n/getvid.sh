#!/bin/bash
set -e

# Check if input is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <video_url_or_id> [-o|--output <output_name>] [--audio] [--trim <seconds>] [-q|--quiet]"
  exit 1
fi

input="$1"
trim=false
trim_duration=0
audio_only=false
quiet=false
output_name=""

# Parse optional flags
shift
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -o|--output)
      if [[ -n "$2" ]]; then
        output_name="$2"
        shift 2
      else
        echo "Invalid output name. Use: -o|--output <output_name>"
        exit 1
      fi
      ;;
    --trim)
      if [[ "$2" =~ ^[0-9]+$ ]]; then
        trim=true
        trim_duration="$2"
        shift 2
      else
        echo "Invalid trim duration. Use: --trim <seconds>"
        exit 1
      fi
      ;;
    --audio)
      audio_only=true
      shift
      ;;
    -q|--quiet)
      quiet=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Detect platform and normalize URL
if [[ "$input" =~ ^https?://(www\.)?youtube\.com/watch\?v=([^&]+) ]]; then
  video_id="${BASH_REMATCH[2]}"
  url="https://www.youtube.com/watch?v=$video_id"
  platform="youtube"
elif [[ "$input" =~ ^https?://(www\.)?youtube\.com/shorts/([^/?]+) ]]; then
  video_id="${BASH_REMATCH[2]}"
  url="https://www.youtube.com/watch?v=$video_id"
  platform="youtube"
elif [[ "$input" =~ ^[a-zA-Z0-9_-]{11}$ ]]; then
  url="https://www.youtube.com/watch?v=$input"
  platform="youtube"
elif [[ "$input" =~ ^https?://(www\.)?tiktok\.com/@[^/]+/video/[0-9]+ ]]; then
  url="$input"
  platform="tiktok"
elif [[ "$input" =~ ^https?://(vm\.)?tiktok\.com/[^/]+/?$ ]]; then
  url=$(curl -Ls -o /dev/null -w %{url_effective} "$input")
  platform="tiktok"
else
  echo "Invalid input. Provide a valid YouTube or TikTok URL."
  exit 1
fi

# Download logic
if [ "$platform" = "youtube" ]; then
  if [ "$audio_only" = true ]; then
    yt-dlp -f bestaudio --extract-audio --audio-format mp3 --audio-quality 0 "$url"
    filename=$(yt-dlp --get-filename -f bestaudio "$url" -o "%(title)s.%(ext)s")
  else
    yt-dlp -f "best[ext=mp4]" "$url" -o "%(title)s.%(ext)s"
    filename=$(yt-dlp --get-filename -f "best[ext=mp4]" "$url" -o "%(title)s.%(ext)s")
  fi
elif [ "$platform" = "tiktok" ]; then
  yt-dlp -f best "$url" -o "%(title)s.%(ext)s"
  filename=$(yt-dlp --get-filename -f best "$url" -o "%(title)s.%(ext)s")
  if [ "$audio_only" = true ]; then
    mp3name="${filename%.*}.mp3"
    ffmpeg -y -i "$filename" -q:a 0 -map a "$mp3name"
    rm -f "$filename"
    filename="$mp3name"
    if [ "$quiet" = false ]; then
      echo "Saved MP3 as: $filename"
    fi
  fi
fi

# Rename if custom name provided
if [ -n "$output_name" ]; then
  ext="${filename##*.}"
  new_filename="${output_name}.${ext}"
  mv "$filename" "$new_filename"
  filename="$new_filename"
fi

# Optional trim
if [ "$trim" = true ]; then
  if [ "$quiet" = false ]; then
    echo "Trimming to first $trim_duration seconds..."
  fi
  trimmed="trimmed_${filename}"
  if [ "$quiet" = true ]; then
    ffmpeg -y -i "$filename" -t "$trim_duration" -c copy "$trimmed" >/dev/null 2>&1
  else
    ffmpeg -y -i "$filename" -t "$trim_duration" -c copy "$trimmed"
  fi
  filename="$trimmed"
  if [ "$quiet" = false ]; then
    echo "Saved as: $filename"
  fi
fi

# Output final filename only in quiet mode
if [ "$quiet" = true ]; then
  echo "$filename"
fi

