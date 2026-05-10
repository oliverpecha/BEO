#!/bin/bash
source ~/beo/scripts/util_version_check.sh

echo "" && echo "🍡 --- MOCHI CONTAINER STATUS ---"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo "" && echo "🚀 --- VPS RESOURCE LOAD ---"
free -h | grep Mem && uptime
echo "" && echo "🏷️ --- VERSION CHECK ---"

CUR=$(beo_get_current_version)
TAGS=$(beo_get_tags)
LAT=$(beo_get_stable_version "$TAGS")
EXP=$(beo_get_experimental_version "$TAGS")

if [ -z "$LAT" ]; then
  echo "  Current: v$CUR"
  echo "  ❓ Could not verify latest version."
else
  echo "  Current:       v$CUR"
  echo "  Latest stable: v$LAT"
  [ -n "$EXP" ] && echo "  Experimental:  v$EXP (not auto-installed)"
  if [ "$CUR" != "$LAT" ]; then
    echo "" && echo "  ⚠️  Stable update available! Run 'beo update'"
  else
    echo "  ✅ You are up to date."
  fi
fi
echo ""
