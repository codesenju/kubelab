#!/bin/bash
set -e

show_help() {
  cat <<'EOF'
Usage: getvid.sh <video_url_or_id> [options]

Options:
  -o, --output <name>   Rename final file (keep extension)
  --audio               Download audio only (mp3)
  --trim <seconds>      Keep only the first N seconds
  --30s                 Cut video to 30 seconds
  -q, --quiet           Suppress downloader/ffmpeg output
  --yt-dlp-args "<args>"  Append extra arguments to yt-dlp (split on spaces)
  -h, --help            Show this help

Notes:
  - Supports YouTube URLs/IDs and TikTok links (full share URLs with query params included).
  - In zsh, quote the URL or prefix the command with "noglob" to avoid "no matches found" on links containing ? or *.
  - Add `--` before any yt-dlp arguments that need complex quoting, e.g. `./getvid.sh <url> -- --impersonate chrome122`.
  - Use `yt-dlp --list-impersonate-targets` to pick a supported impersonation target (for example `chrome122` or `firefox123`); the target names, not full user agents, are required.

Examples:
  ./getvid.sh "https://www.tiktok.com/@user/video/12345?is_from_webapp=1"
  noglob ./getvid.sh https://www.tiktok.com/@user/video/12345?is_from_webapp=1
EOF
}

yt_dlp_extra_args=()

# Check if input is provided
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  show_help
  exit 0
fi

if [ -z "$1" ]; then
  show_help
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
    --30s)
      trim=true
      trim_duration=30
      shift
      ;;
    --audio)
      audio_only=true
      shift
      ;;
    -q|--quiet)
      quiet=true
      shift
      ;;
    --yt-dlp-args)
      if [[ -n "$2" ]]; then
        read -r -a parsed <<< "$2"
        yt_dlp_extra_args+=("${parsed[@]}")
        shift 2
      else
        echo "Provide arguments to --yt-dlp-args"
        exit 1
      fi
      ;;
    --)
      shift
      yt_dlp_extra_args+=("$@")
      break
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
elif [[ "$input" =~ ^https?://(www\.)?tiktok\.com/@[^/]+/video/[0-9]+(\?.*)?$ ]]; then
  url="$input"
  platform="tiktok"
elif [[ "$input" =~ ^https?://(vm\.)?tiktok\.com/[^/]+/?(\?.*)?$ ]]; then
  url=$(curl -Ls -o /dev/null -w %{url_effective} "$input")
  platform="tiktok"
else
  echo "Invalid input. Provide a valid YouTube or TikTok URL."
  exit 1
fi

# Download logic
if [ "$platform" = "youtube" ]; then
  yt_cmd=(yt-dlp "${yt_dlp_extra_args[@]}")
  if [ "$audio_only" = true ]; then
    cmd=("${yt_cmd[@]}" -f bestaudio --extract-audio --audio-format mp3 --audio-quality 0 "$url")
    if [ "$quiet" = true ]; then
      "${cmd[@]}" >/dev/null 2>&1
    else
      "${cmd[@]}"
    fi
    cmd=("${yt_cmd[@]}" --get-filename -f bestaudio "$url" -o "%(title)s.%(ext)s")
    if [ "$quiet" = true ]; then
      filename=$("${cmd[@]}" 2>/dev/null)
    else
      filename=$("${cmd[@]}")
    fi
  else
    cmd=("${yt_cmd[@]}" -f "best[ext=mp4]" "$url" -o "%(title)s.%(ext)s")
    if [ "$quiet" = true ]; then
      "${cmd[@]}" >/dev/null 2>&1
    else
      "${cmd[@]}"
    fi
    cmd=("${yt_cmd[@]}" --get-filename -f "best[ext=mp4]" "$url" -o "%(title)s.%(ext)s")
    if [ "$quiet" = true ]; then
      filename=$("${cmd[@]}" 2>/dev/null)
    else
      filename=$("${cmd[@]}")
    fi
  fi
elif [ "$platform" = "tiktok" ]; then
  yt_cmd=(yt-dlp "${yt_dlp_extra_args[@]}")
  cmd=("${yt_cmd[@]}" -f best "$url" -o "%(title)s.%(ext)s")
  if [ "$quiet" = true ]; then
    "${cmd[@]}" >/dev/null 2>&1
  else
    "${cmd[@]}"
  fi
  cmd=("${yt_cmd[@]}" --get-filename -f best "$url" -o "%(title)s.%(ext)s")
  if [ "$quiet" = true ]; then
    filename=$("${cmd[@]}" 2>/dev/null)
  else
    filename=$("${cmd[@]}")
  fi
  if [ "$audio_only" = true ]; then
    mp3name="${filename%.*}.mp3"
    if [ "$quiet" = true ]; then
      ffmpeg -y -i "$filename" -q:a 0 -map a "$mp3name" >/dev/null 2>&1
    else
      ffmpeg -y -i "$filename" -q:a 0 -map a "$mp3name"
    fi
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
  rm -f "$filename"
  mv "$trimmed" "$filename"
  if [ "$quiet" = false ]; then
    echo "Saved as: $filename"
  fi
fi

# Output final filename only in quiet mode
if [ "$quiet" = true ]; then
  echo "$filename"
fi
