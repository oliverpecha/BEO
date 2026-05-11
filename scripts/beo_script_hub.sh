#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# BEO Unified CLI Hub
# 
# FILE CONVENTION: [trigger]_[domain]_[action].[ext]
# ─────────────────────────────────────────────────────────────────────────────

# Bulletproof path resolution (resolves symlinks safely)
DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
COMMAND=$1
ARG=$2

case "$COMMAND" in
    status)
        "$DIR/cmd_container_status.sh"
        ;;
    update)
        "$DIR/cmd_openclaw_update.sh"
        ;;
    restart)
        "$DIR/cmd_container_restart.sh" "${@:2}"
        ;;
    stats)
        python3 "$DIR/cmd_payload_stats.py" stats
        ;;
    inspect)
        if [ -z "$ARG" ]; then
            echo "Usage: beo inspect <YYYY_MM_DD_@HH_MM_SS>"
        else
            python3 "$DIR/cmd_payload_stats.py" cat "$ARG"
        fi
        ;;
    tail)
        LOG_DIR=~/.openclaw/payloads/$(date +%Y/%m/%d/%p | tr '[:upper:]' '[:lower:]')
        if [ -d "$LOG_DIR" ]; then 
            ls -t "$LOG_DIR"/* | head -n 3 | xargs tail -n +1
        else 
            echo "No logs yet for this AM/PM cycle."
        fi
        ;;
    prune-payloads)
        "$DIR/cron_payload_cleanup.sh"
        ;;
    sync-keys)
        bash "$DIR/util_litellm_rebuild.sh"
        ;;
    diagnose-cache)
        bash "$DIR/cron_cache_health.sh"
        ;;
    diagnose-keys)
        bash "$DIR/cron_key_watchdog.sh"
        ;;
    *)
        echo "🍡 BEO Management Suite"
        echo "Usage: beo [command] [args]"
        echo ""
        echo "--- Core Operations ---"
        echo "  status            Show Docker container health and VPS RAM usage"
        echo "  update            Check GitHub and pull the latest OpenClaw image"
        echo "  restart [name]    Restart a specific container and wait until it is healthy"
        echo ""
        echo "--- Auditing & Analytics ---"
        echo "  stats             Show 7-day API cost-saving metrics (Cache Hit %)"
        echo "  inspect [id]      Output the exact JSON of a specific past conversation"
        echo "  tail              Show the 3 most recent conversation logs instantly"
        echo ""
        echo "--- Maintenance & Diagnostics ---"
        echo "  prune-payloads    Delete payload logs older than 30 days to free up disk space"
        echo "  sync-keys         Read .env and rebuild the LiteLLM load-balancing config"
        echo "  diagnose-cache    Analyze yesterday's logs to ensure cache hit rate is > 0%"
        echo "  diagnose-keys     Ping LiteLLM to check if any Gemini/OpenAI keys are banned"
        echo ""
        ;;
esac
