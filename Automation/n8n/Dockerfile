FROM n8nio/n8n:1.110.1
USER root
# Install MinIO Client (mc) & video editor script
COPY video_editor.sh .
RUN wget -q https://dl.min.io/client/mc/release/linux-amd64/mc -O /usr/local/bin/mc \
    && chmod +x /usr/local/bin/mc \
    && chmod +x ./video_editor.sh

# Install ffmpeg (includes ffprobe) on Alpine
RUN apk update && \
    apk add --no-cache ffmpeg curl

# Optional: switch back to node user for security
USER node