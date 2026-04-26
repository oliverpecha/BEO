#!/bin/bash
set -uo pipefail

CONFIG=/app/config.yaml
FALLBACK=/tmp/litellm_nocache.yaml

echo "🚀 Starting LiteLLM with config: $CONFIG"
litellm --config "$CONFIG" --port 4000 &
LITELLM_PID=$!
wait "$LITELLM_PID"
EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ]; then
  echo "LiteLLM exited normally"
  exit 0
fi

echo "⚠️ LiteLLM failed with exit code $EXIT_CODE — retrying with cache disabled"
sed 's/cache: true/cache: false/' "$CONFIG" > "$FALLBACK"
echo "📋 Fallback config written to $FALLBACK"
exec litellm --config "$FALLBACK" --port 4000
