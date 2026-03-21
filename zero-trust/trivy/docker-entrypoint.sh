#!/bin/sh
set -eu

VEX_REPOSITORY_URL="${VEX_REPOSITORY_URL:-https://raw.githubusercontent.com/aquasecurity/vexhub/main/vex-repository.json}"
VEX_ARCHIVE_URL="${VEX_ARCHIVE_URL:-https://github.com/aquasecurity/vexhub/archive/refs/heads/main.zip}"
TARGET_DIR="/srv/.well-known"
TARGET_FILE="${TARGET_DIR}/vex-repository.json"
ARCHIVE_FILE="/srv/main.zip"
ARCHIVE_PATH="/main.zip"

mkdir -p "${TARGET_DIR}"

PORT="${PORT:-8080}"
PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-http://localhost:${PORT}}"
PUBLIC_BASE_URL="${PUBLIC_BASE_URL%/}"

TMP_MANIFEST="/tmp/vex-repository.json"

echo "Downloading vex manifest from: ${VEX_REPOSITORY_URL}"
wget -qO "${TMP_MANIFEST}" "${VEX_REPOSITORY_URL}"

echo "Downloading vex archive from: ${VEX_ARCHIVE_URL}"
wget -qO "${ARCHIVE_FILE}" "${VEX_ARCHIVE_URL}"

MANIFEST_LOCATION_URL="${PUBLIC_BASE_URL}${ARCHIVE_PATH}"
export TMP_MANIFEST TARGET_FILE MANIFEST_LOCATION_URL

python3 - <<'PY'
import json
import os

source = os.environ["TMP_MANIFEST"]
target = os.environ["TARGET_FILE"]
location_url = os.environ["MANIFEST_LOCATION_URL"]

with open(source, "r", encoding="utf-8") as fh:
    data = json.load(fh)

versions = data.get("versions") or []
if versions and isinstance(versions[0], dict):
    locations = versions[0].get("locations")
    if isinstance(locations, list) and locations and isinstance(locations[0], dict):
        locations[0]["url"] = location_url

with open(target, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PY

echo "Serving manifest at ${PUBLIC_BASE_URL}/.well-known/vex-repository.json"
echo "Serving archive at ${PUBLIC_BASE_URL}${ARCHIVE_PATH}"
exec python3 -m http.server "${PORT}" --directory /srv
