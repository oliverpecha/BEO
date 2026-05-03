#!/usr/bin/env bash
# /root/beo/scripts/payload_cleanup.sh
# ── PAYLOAD REGISTRY OVERVIEW ────────────────────────────────────────────────
# The Payload Registry is maintained by 'proxy.py'. Every outgoing request 
# to the Gemini/OpenAI API is intercepted, timestamped, and saved as a JSON 
# file to disk before being forwarded to LiteLLM. 
#
# Registry Location: /root/.openclaw/payloads/
# Structure: YYYY/MM/DD/[optional_bins]/beo_payload_HH_MM_SS.json
# ─────────────────────────────────────────────────────────────────────────────

set -e

# ── Configuration ─────────────────────────────────────────────────────────────
PAYLOAD_DIR="/root/.openclaw/payloads"
RETENTION_DAYS=30  # Set this according to your storage/audit needs

# ── Helpers ───────────────────────────────────────────────────────────────────
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [Payload Cleanup] $*"
}

# ── Execution ─────────────────────────────────────────────────────────────────

if [[ ! -d "$PAYLOAD_DIR" ]]; then
    log "Error: Directory $PAYLOAD_DIR not found. Check Docker volume mapping."
    exit 1
fi

log "Starting maintenance on payload registry..."

# 1. Purge old files
# find scans recursively, so it is NOT affected if you remove am/pm folders.
# It simply looks for any file (-type f) deeper than the base path.
find "$PAYLOAD_DIR" -type f -mtime +"$RETENTION_DAYS" -delete
log "Files older than $RETENTION_DAYS days have been purged."

# 2. Prune empty directory tree
# This removes empty leaf nodes (like /pm/ or /03/) to keep the host tidy.
find "$PAYLOAD_DIR" -type d -empty -delete
log "Empty registry directories pruned."

log "Cleanup finished successfully."
