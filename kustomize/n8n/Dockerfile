FROM n8nio/n8n:1.110.1

# Install ffmpeg (includes ffprobe) on Alpine
USER root
RUN apk update && \
    apk add --no-cache ffmpeg

# Optional: switch back to node user for security
USER node