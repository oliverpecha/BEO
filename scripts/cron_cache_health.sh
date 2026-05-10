#!/bin/bash
# Checks if the cache optimization broke yesterday. Designed for daily Cron.

ENV_FILE="/root/openclaw/.env"

# 1. Bypass check if optimization is disabled in .env
if ! grep -iq "^BEO_OPTIMIZE_PAYLOAD=true" "$ENV_FILE"; then
    echo "Optimization is disabled in .env. Skipping cache health check."
    exit 0
fi

# 2. Look at yesterday's ledger
DATE=$(date -d "yesterday" +"%Y_%m_%d")
LEDGER="/root/.openclaw/payloads/${DATE}_ledger.csv"

if [ ! -f "$LEDGER" ]; then
    echo "No requests found for yesterday."
    exit 0
fi

# 3. Sum prompt tokens, cached tokens, and total requests
PROMPT_SUM=$(awk -F, 'NR>1 {sum+=$4} END {print sum}' "$LEDGER")
CACHE_SUM=$(awk -F, 'NR>1 {sum+=$5} END {print sum}' "$LEDGER")
REQS=$(awk -F, 'NR>1 {count++} END {print count}' "$LEDGER")

# 4. Ignore if we haven't had enough requests to establish a baseline
if [ -z "$REQS" ] || [ "$REQS" -lt 5 ]; then
    echo "Not enough requests ($REQS) to establish a baseline. Skipping."
    exit 0
fi

# 5. Alert if hit rate is absolutely zero
if [ "$CACHE_SUM" -eq 0 ] && [ "$PROMPT_SUM" -gt 0 ]; then
    MSG="⚠️ BEO CACHE WARNING: 0% Cache Hit Rate yesterday across $REQS requests. Did the OpenClaw payload boundary change?"
    echo "$MSG"
    
    # Send a Telegram alert (Uncomment and replace YOUR_BOT_TOKEN and YOUR_CHAT_ID)
    # curl -s -X POST "https://api.telegram.org/botYOUR_BOT_TOKEN/sendMessage" -d chat_id="YOUR_CHAT_ID" -d text="$MSG" > /dev/null
    
    exit 1
fi

echo "Cache Health OK. (Hit rate > 0%)"
