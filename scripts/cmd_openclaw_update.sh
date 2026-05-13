#!/bin/bash
source ~/beo/scripts/util_version_check.sh
COMPOSE_FILE="/root/openclaw/docker-compose.yml"

# How many seconds to wait before auto-exiting the update menu
AUTO_EXIT_SEC=30

echo "🔍 Checking OpenClaw and Upstream Dependencies..."

# --- 1. GATHER LOCAL VERSIONS ---
CUR=$(beo_get_current_version)
VER_LITELLM=$(docker inspect litellm --format '{{.Config.Image}}' 2>/dev/null | awk -F':' '{print $2}')
VER_REDIS=$(docker inspect beo-redis --format '{{.Config.Image}}' 2>/dev/null | awk -F':' '{print $2}')

# --- 2. PYTHON API FETCH & COMPARISON ---
eval $(python3 -c "
import sys, json, urllib.request

oc_cur = sys.argv[1].lstrip('v')
redis_cur = sys.argv[2]

def get_json(url):
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'BEO-CLI'})
        return json.loads(urllib.request.urlopen(req, timeout=3).read().decode())
    except: return None

# LiteLLM Local API Fetch (Port 4000)
llm_loc = 'unknown'
try:
    h = get_json('http://localhost:4000/health/readiness')
    if h: llm_loc = h.get('litellm_version', 'unknown')
    if llm_loc != 'unknown' and not llm_loc.startswith('v'): llm_loc = 'v' + llm_loc
except: pass

# OpenClaw GitHub
oc_lat, oc_exp = '', ''
oc_data = get_json('https://api.github.com/repos/openclaw/openclaw/releases')
if oc_data:
    stables = [r['tag_name'] for r in oc_data if 'beta' not in r['tag_name'] and 'alpha' not in r['tag_name']]
    exps = [r['tag_name'] for r in oc_data if 'beta' in r['tag_name'] or 'alpha' in r['tag_name']]
    if stables: oc_lat = stables[0]
    if exps: oc_exp = exps[0]

# LiteLLM GitHub
llm_lat = 'unknown'
llm_data = get_json('https://api.github.com/repos/berriai/litellm/releases/latest')
if llm_data: llm_lat = llm_data.get('tag_name', 'unknown')

# Redis Hub
redis_lat = 'unknown'
redis_data = get_json('https://hub.docker.com/v2/repositories/redis/redis-stack-server/tags/?page_size=10')
if redis_data:
    tags = [t['name'] for t in redis_data.get('results', []) if t['name'] != 'latest']
    if tags: redis_lat = tags[0]

# Boolean Update Flags (1 = Needs Update, 0 = Up to Date)
oc_needs = '1' if oc_lat and oc_cur != oc_lat.lstrip('v') else '0'
llm_needs = '0'
if llm_lat != 'unknown':
    if llm_loc == 'unknown' or llm_loc.lstrip('v') not in llm_lat:
        llm_needs = '1'
redis_needs = '1' if redis_lat != 'unknown' and redis_cur != redis_lat else '0'

print(f\"OC_LAT='{oc_lat}'; OC_EXP='{oc_exp}'; OC_NEEDS={oc_needs}; LLM_LAT='{llm_lat}'; LLM_LOC='{llm_loc}'; LLM_NEEDS={llm_needs}; REDIS_LAT='{redis_lat}'; REDIS_NEEDS={redis_needs};\")
" "$CUR" "${VER_REDIS:-unknown}")

# Format the local LiteLLM version string nicely
LLM_CURRENT_STR="${VER_LITELLM:-unknown}"
if [ "$LLM_LOC" != "unknown" ]; then
    LLM_CURRENT_STR="$LLM_CURRENT_STR ($LLM_LOC)"
fi

# --- 3. PRE-FETCH CHANGELOGS ---
OC_LOGS=""
LLM_LOGS=""

# OpenClaw Logs
OC_LOGS=$(python3 -c "
import sys, json, urllib.request
cur_ver = sys.argv[1].lstrip('v')
try:
    req = urllib.request.Request('https://api.github.com/repos/openclaw/openclaw/releases', headers={'User-Agent': 'BEO-CLI'})
    releases = json.loads(urllib.request.urlopen(req, timeout=5).read().decode())
    updates = []
    for r in releases:
        if r['tag_name'].lstrip('v') == cur_ver: break
        updates.append(r)
        if len(updates) >= 4: break
    if updates:
        print('') 
        print(f'    📰  OPENCLAW UPDATES ({len(updates)} recent releases since v{cur_ver})')
        print('    - - - - - - - - - - - - - - - - - - - - - - - - ')
        for r in updates:
            branch = '🧪 [EXP]' if 'beta' in r['tag_name'] or 'alpha' in r['tag_name'] else '📣 [STABLE]'
            print(f'        {branch} {r[\"tag_name\"]}:')
            body = r.get('body', '').split('\n')
            bullets = [line.strip().replace('**', '') for line in body if line.strip().startswith(('-', '*'))][:2]
            for b in bullets: print(f'            {b}')
            if r.get('html_url'): print(f'            🔗 {r[\"html_url\"]}')
            print('')
except: pass
" "$CUR")

# LiteLLM Logs
if [ "$LLM_NEEDS" = "1" ]; then
    LLM_LOGS=$(python3 -c "
import sys, json, urllib.request
llm_loc = sys.argv[1].lstrip('v')
try:
    req = urllib.request.Request('https://api.github.com/repos/berriai/litellm/releases', headers={'User-Agent': 'BEO-CLI'})
    releases = json.loads(urllib.request.urlopen(req, timeout=5).read().decode())
    updates = []
    for r in releases:
        tag = r['tag_name'].lstrip('v')
        if llm_loc != 'unknown' and llm_loc in tag: break
        updates.append(r)
        if len(updates) >= 4: break
    if updates:
        print('') 
        print(f'    📰  LITELLM UPDATES ({len(updates)} recent releases since {llm_loc})')
        print('    - - - - - - - - - - - - - - - - - - - - - - - - ')
        for r in updates:
            print(f'        🛫 {r[\"tag_name\"]}:')
            body = r.get('body', '').split('\n')
            
            ignored = ['verify using', 'cosign', 'docker pull', 'sha256', 'docker run', 'signatures were verified', 'verify docker', 'commit hash', 'cryptographically']
            bullets = []
            for line in body:
                line = line.strip().replace('**', '')
                if line.startswith(('-', '*')):
                    if not any(ig in line.lower() for ig in ignored) and len(line) > 5:
                        bullets.append(line)
            
            for b in bullets[:2]: print(f'            {b}')
            if not bullets: print('            - (Incremental internal updates)')
            
            if r.get('html_url'): print(f'            🔗 {r[\"html_url\"]}')
            print('')
except: pass
" "$LLM_LOC")
fi

# --- 4. UI DISPLAY GRID ---
echo ""
echo "===================================================="
echo "🦞  OPENCLAW"
echo ""
echo "    📦 Current:       v$CUR"
[ -n "$OC_LAT" ] && echo "    🆕 Latest stable: $OC_LAT"
[ -n "$OC_EXP" ] && echo "    🧪 Experimental:  $OC_EXP"
echo ""
if [ "$OC_NEEDS" = "1" ]; then
    echo "    ⚠️   Update available!"
else
    echo "    ✅  OpenClaw is on the latest stable release."
fi

# Inject OpenClaw logs directly
[ -n "$OC_LOGS" ] && echo "$OC_LOGS"

echo "----------------------------------------------------"
echo "🛫  LITELLM"
echo ""
echo "    📦 Current:       $LLM_CURRENT_STR"
echo "    🆕 Latest GitHub: $LLM_LAT"
echo ""
if [ "$LLM_NEEDS" = "1" ]; then
    echo "    ⚠️   Update available!"
else
    echo "    ✅  LiteLLM is on the latest stable release."
fi

# Inject LiteLLM logs directly
[ -n "$LLM_LOGS" ] && echo "$LLM_LOGS"

echo "----------------------------------------------------"
echo "🗄   REDIS"
echo ""
echo "    📦 Current:       ${VER_REDIS:-unknown}"
echo "    🆕 Latest Hub:    $REDIS_LAT"
echo ""
if [ "$REDIS_NEEDS" = "1" ]; then
    echo "    ⚠️   Update available (Manual edit required)"
else
    echo "    ✅  Redis is on the latest version."
fi
echo "===================================================="
echo ""

# --- 5. DYNAMIC MENU BUILDER ---
OPT_COUNT=0
OPT_MAP=()

if [ "$OC_NEEDS" = "1" ]; then 
    OPT_COUNT=$((OPT_COUNT + 1)); OPT_MAP[$OPT_COUNT]="openclaw"
fi
if [ "$LLM_NEEDS" = "1" ]; then 
    OPT_COUNT=$((OPT_COUNT + 1)); OPT_MAP[$OPT_COUNT]="litellm"
fi
if [ "$REDIS_NEEDS" = "1" ]; then
    OPT_COUNT=$((OPT_COUNT + 1)); OPT_MAP[$OPT_COUNT]="redis"
fi

if [ $OPT_COUNT -eq 0 ]; then
    echo "✅ All components are up to date."
    exit 0
fi

echo "🛠️  What would you like to update?"
echo "----------------------------------------------------"

for i in $(seq 1 $OPT_COUNT); do
    if [ "${OPT_MAP[$i]}" = "openclaw" ]; then
        echo "  $i) 🦞 OpenClaw"
    elif [ "${OPT_MAP[$i]}" = "litellm" ]; then
        echo "  $i) 🛫 LiteLLM"
    elif [ "${OPT_MAP[$i]}" = "redis" ]; then
        echo "  $i) 🗄  Redis (View Manual Update Instructions)"
    fi
done

if [ $OPT_COUNT -gt 1 ]; then
    echo "  x) 🛒 Select ALL above"
fi
echo ""

# --- 6. INPUT LOOP WITH MULTI-LINE PROGRESS BAR ---
TARGETS=""
SHOW_REDIS=0
FIRST_PROMPT=1

# Determine the prompt text
if [ $OPT_COUNT -gt 1 ]; then
    PROMPT_TEXT="Select numbers (e.g., '1, 2' or 'x' for all): "
else
    PROMPT_TEXT="Press 1 to select: "
fi

while true; do
    if [ "$FIRST_PROMPT" -eq 1 ]; then
        FIRST_PROMPT=0
        TIMEOUT_REACHED=true
        
        for (( i=$AUTO_EXIT_SEC; i>0; i-- )); do
            # Calculate the `?` and `-` formatting for the bar
            FILLED=$(( i * 20 / AUTO_EXIT_SEC ))
            EMPTY=$(( 20 - FILLED ))
            BAR=$(printf "%${FILLED}s" | tr ' ' '?')
            SPACES=$(printf "%${EMPTY}s" | tr ' ' '-')
            
            # Print Line 1: The Prompt
            printf "\r\033[K%s\n" "$PROMPT_TEXT"
            # Print Line 2: The Spacing
            printf "\r\033[K\n"
            # Print Line 3: The Countdown Bar
            printf "\r\033[K(%d seconds remaining to choose an option, q to cancel) %s%s" "$i" "$BAR" "$SPACES"
            
            # ANSI Trick: Move cursor UP 2 lines back to the Prompt, and RIGHT to the exact end of the text
            printf "\033[2A\r\033[%dC" "${#PROMPT_TEXT}"
            
            # Wait 1 second for the user to touch ANY key
            if read -t 1 -n 1 FIRST_CHAR; then
                TIMEOUT_REACHED=false
                
                # The user typed something! Instantly wipe the countdown lines below the prompt
                printf "\033[s\n\r\033[K\n\r\033[K\033[u"
                
                # If they typed a real letter/number (not just Enter), let them finish typing
                if [[ "$FIRST_CHAR" != "" ]] && [[ "$FIRST_CHAR" != $'\n' ]]; then
                    read -r REST_OF_INPUT
                    RAW_INPUT="${FIRST_CHAR}${REST_OF_INPUT}"
                else
                    RAW_INPUT=""
                fi
                break
            fi
        done
        
        # If the 20 seconds expires
        if [ "$TIMEOUT_REACHED" = true ]; then
            printf "\n\r\033[K\n\r\033[K\033[2A\r\033[K"
            echo "⏳ Auto-exit timeout reached ($AUTO_EXIT_SEC seconds). Update aborted."
            exit 0
        fi
    else
        # If validation failed and the loop repeats, just show standard prompt without countdown
        read -r -p "$PROMPT_TEXT" RAW_INPUT
    fi
    
    # Handle cancellation
    if [[ "$RAW_INPUT" =~ ^[Qq]$ ]]; then
        echo "Update aborted."
        exit 0
    fi
    
    CLEAN_INPUT=$(echo "$RAW_INPUT" | tr ',' ' ')
    
    for choice in $CLEAN_INPUT; do
        if [[ "$choice" =~ ^[Xx]$ ]] && [ $OPT_COUNT -gt 1 ]; then
            [ "$OC_NEEDS" = "1" ] && TARGETS+=" openclaw-gateway openclaw-cli"
            [ "$LLM_NEEDS" = "1" ] && TARGETS+=" litellm"
            [ "$REDIS_NEEDS" = "1" ] && SHOW_REDIS=1
            break 2
        fi
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -le "$OPT_COUNT" ] && [ "$choice" -gt 0 ]; then
            if [ "${OPT_MAP[$choice]}" = "openclaw" ]; then 
                TARGETS+=" openclaw-gateway openclaw-cli"
            elif [ "${OPT_MAP[$choice]}" = "litellm" ]; then 
                TARGETS+=" litellm"
            elif [ "${OPT_MAP[$choice]}" = "redis" ]; then 
                SHOW_REDIS=1
            fi
        fi
    done

    TARGETS=$(echo "$TARGETS" | xargs)

    if [ -n "$TARGETS" ] || [ "$SHOW_REDIS" = "1" ]; then
        break
    else
        echo "❌ Invalid selection. Please try again."
    fi
done

# --- 7. EXECUTE UPDATE & INSTRUCTIONS ---
echo ""

if [ "$SHOW_REDIS" = "1" ]; then
    echo "📘 How the Redis Update Works (And Why It's Manual)"
    echo "----------------------------------------------------------------"
    echo "Unlike OpenClaw and LiteLLM which use 'rolling' tags, your Redis"
    echo "image is strictly pinned to prevent automated database breakages."
    echo ""
    echo "To update Redis from ${VER_REDIS:-unknown} to $REDIS_LAT:"
    echo "  1. Open your compose file: nano ~/openclaw/docker-compose.yml"
    echo "  2. Scroll down to the 'beo-redis' service."
    echo "  3. Change the image line to exactly:"
    echo "     image: redis/redis-stack-server:$REDIS_LAT"
    echo "  4. Save the file (Ctrl+O, Enter, Ctrl+X)."
    echo "  5. Run 'beo update' again, or 'docker compose up -d'."
    echo "----------------------------------------------------------------"
    echo ""
fi

if [ -z "$TARGETS" ]; then
    exit 0
fi

echo "⬇️  Pulling automated updates for: $TARGETS"
docker compose -f "$COMPOSE_FILE" pull $TARGETS

echo ""
echo "🔄 Applying updates and restarting containers..."

if [[ "$TARGETS" == *"openclaw"* ]]; then
    docker compose -f "$COMPOSE_FILE" stop openclaw-gateway openclaw-cli
    docker compose -f "$COMPOSE_FILE" rm -f openclaw-gateway openclaw-cli
fi

docker compose -f "$COMPOSE_FILE" up -d $TARGETS

if [[ "$TARGETS" == *"openclaw"* ]]; then
    echo ""
    echo "⏳ Waiting for gateway to initialize..."
    for i in $(seq 1 30); do
        STATUS=$(docker inspect openclaw-gateway --format "{{.State.Health.Status}}" 2>/dev/null)
        if [ "$STATUS" = "healthy" ]; then break; fi
        sleep 2
    done
fi

echo ""
echo "✅ Update successfully applied!"
echo ""
