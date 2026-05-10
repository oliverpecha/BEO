#!/bin/bash
# Shared version detection utility — sourced by cmd_openclaw_update.sh and cmd_container_status.sh

beo_get_current_version() {
  docker exec openclaw-gateway cat /app/package.json 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('version','unknown'))" 2>/dev/null
}

beo_get_tags() {
  curl -s --connect-timeout 5 https://api.github.com/repos/openclaw/openclaw/tags 2>/dev/null
}

beo_get_stable_version() {
  echo "$1" | python3 -c "
import sys, json
tags = json.load(sys.stdin)
stable = [t['name'].lstrip('v') for t in tags if 'beta' not in t['name'] and 'alpha' not in t['name']]
print(stable[0] if stable else '')
" 2>/dev/null
}

beo_get_experimental_version() {
  echo "$1" | python3 -c "
import sys, json
tags = json.load(sys.stdin)
exp = [t['name'].lstrip('v') for t in tags if 'beta' in t['name'] or 'alpha' in t['name']]
print(exp[0] if exp else '')
" 2>/dev/null
}
