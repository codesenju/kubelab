FROM n8nio/n8n:1.110.1
USER root
# Install MinIO Client (mc) & video editor script
COPY video_editor.sh .
COPY getvid.sh .
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
        wget -q https://dl.min.io/client/mc/release/linux-amd64/mc -O /usr/local/bin/mc; \
    elif [ "$ARCH" = "aarch64" ]; then \
        wget -q https://dl.min.io/client/mc/release/linux-arm64/mc -O /usr/local/bin/mc; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    chmod +x /usr/local/bin/mc && \
    chmod +x *.sh && \
    chown node:node *.sh && \
    mkdir -p /home/node/output/ && \
    mkdir -p /home/node/input/ && \
    chown -R node:node /home/node/

# Install ffmpeg (includes ffprobe) and yt-dlp on Alpine
RUN apk update && \
    apk add --no-cache ffmpeg curl bash python3 py3-pip && \
    pip3 install --break-system-packages yt-dlp

# Optional: switch back to node user for security
USER node