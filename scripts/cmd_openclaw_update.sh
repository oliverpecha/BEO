#!/bin/bash
source ~/beo/scripts/util_version_check.sh
COMPOSE_FILE="/root/openclaw/docker-compose.yml"

echo "" && echo "🏷️ --- UPDATE CHECK ---"

CUR=$(beo_get_current_version)
TAGS=$(beo_get_tags)
LAT=$(beo_get_stable_version "$TAGS")
EXP=$(beo_get_experimental_version "$TAGS")

if [ -z "$LAT" ]; then
  echo "  ❓ Could not verify latest version from GitHub. Aborting to be safe."
elif [ "$CUR" = "$LAT" ]; then
  echo "  📦 Current:       v$CUR"
  echo "  ✅ You are already running the latest stable version. No upgrade needed."
  [ -n "$EXP" ] && echo "  🧪 Experimental:  v$EXP (not auto-installed)"
else
  echo "  📦 Current:       v$CUR"
  echo "  🆕 Latest stable: v$LAT"
  [ -n "$EXP" ] && echo "  🧪 Experimental:  v$EXP (not auto-installed)"
  echo ""
  echo "⬇️  Pulling latest image..."
  docker compose -f "$COMPOSE_FILE" pull
  echo ""
  echo "🔄 Restarting containers..."
  docker compose -f "$COMPOSE_FILE" stop gateway cli
  docker compose -f "$COMPOSE_FILE" rm -f gateway cli
  docker compose -f "$COMPOSE_FILE" up -d
  echo ""
  echo "⏳ Waiting for gateway to initialize..."
  for i in $(seq 1 30); do
    STATUS=$(docker inspect openclaw-gateway --format "{{.State.Health.Status}}" 2>/dev/null)
    if [ "$STATUS" = "healthy" ]; then break; fi
    sleep 2
  done
  NEWVER=$(beo_get_current_version)
  if [ "$NEWVER" = "$LAT" ]; then
    echo "✅ Upgrade to v$LAT complete!"
  else
    echo "⚠️  Still on v$NEWVER after upgrade — latest stable image may not be published yet."
  fi
fi
echo ""
