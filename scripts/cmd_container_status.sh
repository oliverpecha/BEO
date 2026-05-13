#!/bin/bash
source ~/beo/scripts/util_version_check.sh

DICT_FILE="$HOME/openclaw/emoji_dict.txt"

# Centralized formatting and emoji logic
format_table() {
  awk -F'|' -v dict_file="$DICT_FILE" '
  BEGIN {
    OFS="|"
    # Default baseline dictionary
    map["cli"] = "⌨️ "; map["dashboard"] = "📊"; map["gateway"] = "🌐"
    map["preflight"] = "🚦"; map["litellm"] = "🛫"; map["redis"] = "🗄 "

    while ((getline line < dict_file) > 0) {
      if (line ~ /=/) {
        split(line, kv, "=")
        gsub(/^[ \t]+|[ \t]+$/, "", kv[1]); gsub(/^[ \t]+|[ \t]+$/, "", kv[2])
        map[tolower(kv[1])] = kv[2]
      }
    }
  }
  {
    if (NR == 1) { print tolower($0); next }

    # --- EMOJI INJECTION ---
    lower_name = tolower($1); emoji = "📦"
    for (key in map) { if (index(lower_name, key) > 0) { emoji = map[key]; break } }
    $1 = emoji " " $1

    # --- PORT CLEANUP ---
    if ($3 ~ /->/) {
        # Extracts clean port mapping (e.g. 18789-18790:18789-18790)
        match($3, /[0-9-]+->[0-9-]+/, m)
        $3 = m[0]; gsub(/->/, ":", $3)
    } else {
        # Cleans up plain ports (e.g. 6379/tcp -> 6379)
        gsub(/\/.*/, "", $3)
    }
    if ($3 == "") $3 = "-"

    print $0
  }' | column -t -s '|'
}

echo "" && echo "🍡 --- MOCHI CONTAINER STATUS ---"
echo ""
(
  echo "SERVICE|STATUS|PORTS"
  docker ps --format "{{.Names}}|{{.Status}}|{{.Ports}}" | sort -f
) | format_table

echo "" && echo "🚀 --- VPS RESOURCE LOAD ---"
echo ""
free -h | grep Mem && uptime

echo "" && echo "🏷️ --- VERSION CHECK ---"
echo ""

CUR=$(beo_get_current_version)
TAGS=$(beo_get_tags)
LAT=$(beo_get_stable_version "$TAGS")
EXP=$(beo_get_experimental_version "$TAGS")

# Extract the running image tags directly from Docker inspect
VER_LITELLM=$(docker inspect litellm --format '{{.Config.Image}}' 2>/dev/null | awk -F':' '{print $2}')
VER_REDIS=$(docker inspect beo-redis --format '{{.Config.Image}}' 2>/dev/null | awk -F':' '{print $2}')

# --- OpenClaw Block ---
echo "🦞 OpenClaw..."
if [ -z "$LAT" ]; then
  echo "   📦 Current: v$CUR"
  echo "   ❓ Could not verify latest version."
else
  echo "   📦 Current:       v$CUR"
  echo "   🆕 Latest Stable: v$LAT"
  [ -n "$EXP" ] && echo "   🧪 Experimental release: v$EXP"
  if [ "$CUR" != "$LAT" ]; then
    echo "   ⚠️  Stable update available! Run 'beo update'"
  else
    echo "   ✅ OpenClaw is on the latest stable release."
  fi
fi

echo ""

