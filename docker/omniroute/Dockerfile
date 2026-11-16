# OmniRoute with the hard-coded Kiro client versions bumped.
# Upstream sends stale Kiro client identifiers, which Kiro now rejects with
# "400: This version of Kiro is no longer supported". Drop this image once
# upstream ships a fix and go back to diegosouzapw/omniroute.
# Upgrade procedure: docs/omniroute.md
#
# Two places are patched in the compiled Next.js bundle:
#  1. Model-listing path (services/kiroModels.ts): KIRO_IDE_VERSION="0.10.32"
#  2. Chat/streaming path (config/providerHeaderProfiles.ts):
#     User-Agent / X-Amz-User-Agent "…kiro-ide/1.0.0" (no KiroIDE-<version> token)
#     Note: the documented KIRO_USER_AGENT env var is not read by the code.
#
# Chunk file names change between releases, so files are located by content.
# Every step fails the build if its expected string is missing, so an upstream
# refactor can never produce a silently unpatched image.
ARG OMNIROUTE_VERSION=3.8.53
FROM diegosouzapw/omniroute:${OMNIROUTE_VERSION}

ARG KIRO_IDE_VERSION=1.4.178
ARG OLD_KIRO_IDE_VERSION=0.10.32
# Stable pseudo machine id (sha256 hex), same shape the real IDE sends.
ARG KIRO_MACHINE_ID=8f3c2a6d1e9b4f70a5c3d2e1f0b9a8c7d6e5f4a3b2c1d0e9f8a7b6c5d4e3f2a1

USER root
RUN set -eu; \
    cd /app/.build/next; \
    # 1. model-listing path: server bundles that build "KiroIDE-" headers and
    #    still carry the old version literal.
    files=$(grep -rIl "KiroIDE-" server | xargs grep -l "\"${OLD_KIRO_IDE_VERSION}\"" || true); \
    test -n "$files" || { echo "patch 1: \"${OLD_KIRO_IDE_VERSION}\" not found" >&2; exit 1; }; \
    for f in $files; do \
      sed -i "s/\"${OLD_KIRO_IDE_VERSION}\"/\"${KIRO_IDE_VERSION}\"/g" "$f"; \
    done; \
    # 2. chat/streaming path
    ua="aws-sdk-js/1.0.0 ua/2.1 os/linux lang/js md/nodejs#22.21.1 api/codewhispererstreaming#1.0.0 m/E KiroIDE-${KIRO_IDE_VERSION}-${KIRO_MACHINE_ID}"; \
    amz="aws-sdk-js/1.0.0 KiroIDE-${KIRO_IDE_VERSION}-${KIRO_MACHINE_ID}"; \
    files=$(grep -rIl "kiro-ide/1.0.0" . || true); \
    test -n "$files" || { echo "patch 2: kiro-ide/1.0.0 not found" >&2; exit 1; }; \
    for f in $files; do \
      sed -i -e "s|AWS-SDK-JS/3.0.0 kiro-ide/1.0.0|${ua}|g" \
             -e "s|aws-sdk-js/3.0.0 kiro-ide/1.0.0|${amz}|g" "$f"; \
    done; \
    # verify
    ! grep -rIq "kiro-ide/1.0.0" . || { echo "verify: kiro-ide/1.0.0 still present" >&2; exit 1; }; \
    grep -rIq "KiroIDE-${KIRO_IDE_VERSION}-${KIRO_MACHINE_ID}" server || { echo "verify: new UA missing" >&2; exit 1; }; \
    ! grep -rIl "KiroIDE-" server | xargs grep -q "\"${OLD_KIRO_IDE_VERSION}\"" || { echo "verify: old version still present" >&2; exit 1; }
USER node
