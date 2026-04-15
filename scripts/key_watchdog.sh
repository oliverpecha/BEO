#!/usr/bin/env bash
# ~/beo/scripts/key_watchdog.sh
# Monitors LiteLLM model health — fires once on failure, reminds hourly, notifies on recovery
# Cron (every 5 min):
#   */5 * * * * bash /root/beo/scripts/key_watchdog.sh >> /var/log/beo_watchdog.log 2>&1

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
ENV_FILE=~/openclaw/.env
LITELLM_URL="http://localhost:4000"
LOCK_DIR="/tmp/beo_watchdog"
REMIND_INTERVAL_MIN=60
CRON_INTERVAL_MIN=5

# ── Bootstrap — surgical env extraction, no source ───────────────────────────
get_env() { grep -E "^${1}=" "$ENV_FILE" | head -1 | cut -d= -f2-; }
TELEGRAM_BOT_TOKEN=$(get_env TELEGRAM_BOT_TOKEN)
TELEGRAM_CHAT_ID=$(get_env TELEGRAM_CHAT_ID)
LITELLM_MASTER_KEY=$(get_env LITELLM_MASTER_KEY)

mkdir -p "$LOCK_DIR"

# ── Helpers ───────────────────────────────────────────────────────────────────
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [BEO watchdog] $*"; }

tg() {
  local msg="$1"
  curl -s --max-time 10 \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${msg}" \
    --data-urlencode "parse_mode=HTML" \
    > /dev/null || log "WARNING: Telegram send failed"
}

safe_id() { echo "$1" | tr -cs 'a-zA-Z0-9_-' '_'; }

duration_fmt() {
  local m=$1
  if [[ $m -lt 60 ]]; then echo "${m}m"; else echo "$((m/60))h $((m%60))m"; fi
}

within_remind_window() {
  local mins=$1
  [[ $(( mins % REMIND_INTERVAL_MIN )) -lt $CRON_INTERVAL_MIN ]]
}

NOW=$(date +%s)

# ── Query LiteLLM ─────────────────────────────────────────────────────────────
HEALTH_RAW=$(curl -s --max-time 10 \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  "${LITELLM_URL}/health/readiness" 2>/dev/null || true)

# ── Handle LiteLLM itself being down ─────────────────────────────────────────
if [[ -z "$HEALTH_RAW" ]]; then
  log "ERROR: LiteLLM unreachable at ${LITELLM_URL}"
  LOCK="$LOCK_DIR/svc_litellm_down"
  if [[ ! -f "$LOCK" ]]; then
    echo "$NOW" > "$LOCK"
    tg "🔴 <b>BEO ALERT</b>: beo-litellm is unreachable
Time: $(date '+%H:%M %Z')
Action: <code>docker ps</code> and <code>docker logs beo-litellm --tail 20</code>"
    log "ALERT sent: beo-litellm unreachable"
  else
    SINCE=$(cat "$LOCK")
    MINS=$(( (NOW - SINCE) / 60 ))
    if within_remind_window "$MINS"; then
      tg "⚠️ <b>BEO REMINDER</b>: beo-litellm still unreachable
Duration: <b>$(duration_fmt "$MINS")</b>"
      log "REMINDER: beo-litellm unreachable for ${MINS}m"
    else
      log "ONGOING: beo-litellm unreachable for ${MINS}m (no reminder due)"
    fi
  fi
  exit 1
fi

# LiteLLM is up — clear its down-lock if present
LOCK="$LOCK_DIR/svc_litellm_down"
if [[ -f "$LOCK" ]]; then
  SINCE=$(cat "$LOCK"); MINS=$(( (NOW - SINCE) / 60 ))
  rm -f "$LOCK"
  tg "✅ <b>BEO RECOVERY</b>: beo-litellm is back online
Downtime: <b>$(duration_fmt "$MINS")</b>"
  log "RECOVERY: beo-litellm back after ${MINS}m"
fi

# ── Parse health response ─────────────────────────────────────────────────────
parse_models() {
  local key="$1"
  echo "$HEALTH_RAW" | python3 -c "
import sys, json
h = json.load(sys.stdin)
models = h.get('${key}', [])
for m in models:
    mid = m.get('model_id') or m.get('model', 'unknown')
    err = str(m.get('error') or m.get('exception_type', ''))[:140]
    print(f'{mid}|||{err}')
" 2>/dev/null || true
}

UNHEALTHY=$(parse_models "unhealthy_models")
HEALTHY=$(parse_models "healthy_models")

# ── Process unhealthy models ──────────────────────────────────────────────────
while IFS='|||' read -r mid err; do
  [[ -z "$mid" ]] && continue
  LOCK="$LOCK_DIR/model_$(safe_id "$mid")"
  if [[ ! -f "$LOCK" ]]; then
    echo "$NOW" > "$LOCK"
    tg "🔴 <b>BEO ALERT</b>: Model degraded
Model: <code>${mid}</code>
Error: <code>${err}</code>
Time: $(date '+%H:%M %Z')
Router: key pulled for 5-min cooldown cycles
Fix: update .env → run <code>bash ~/beo/generate_litellm_config.sh</code>"
    log "ALERT: $mid degraded — $err"
  else
    SINCE=$(cat "$LOCK"); MINS=$(( (NOW - SINCE) / 60 ))
    if within_remind_window "$MINS"; then
      tg "⚠️ <b>BEO REMINDER</b>: Model still degraded
Model: <code>${mid}</code>
Duration: <b>$(duration_fmt "$MINS")</b>
Error: <code>${err}</code>"
      log "REMINDER: $mid degraded for ${MINS}m"
    else
      log "ONGOING: $mid degraded for ${MINS}m (no reminder due)"
    fi
  fi
done <<< "${UNHEALTHY:-}"

# ── Process recoveries ────────────────────────────────────────────────────────
while IFS='|||' read -r mid _; do
  [[ -z "$mid" ]] && continue
  LOCK="$LOCK_DIR/model_$(safe_id "$mid")"
  if [[ -f "$LOCK" ]]; then
    SINCE=$(cat "$LOCK"); MINS=$(( (NOW - SINCE) / 60 ))
    rm -f "$LOCK"
    tg "✅ <b>BEO RECOVERY</b>: Model restored
Model: <code>${mid}</code>
Downtime: <b>$(duration_fmt "$MINS")</b>"
    log "RECOVERY: $mid back after ${MINS}m"
  fi
done <<< "${HEALTHY:-}"

# ── Summary ───────────────────────────────────────────────────────────────────
ACTIVE=$(find "$LOCK_DIR" -name 'model_*' 2>/dev/null | wc -l || echo 0)
log "Done — ${ACTIVE} model(s) currently degraded"
exit 0
