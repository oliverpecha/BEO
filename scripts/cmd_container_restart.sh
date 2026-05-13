#!/bin/bash

# --- CONFIGURATION ---
DOTS_INIT="..."
PHASE_LIMIT=20
AUTO_EXIT_SEC=30
DICT_FILE="$HOME/openclaw/emoji_dict.txt"

# --- HELPER: RESOLVE EMOJI ---
get_emoji() {
    local name=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    local emoji="📦"
    
    declare -A map
    map["cli"]="⌨️ "; map["dashboard"]="📊"; map["gateway"]="🌐"
    map["preflight"]="🚦"; map["litellm"]="🛫"; map["redis"]="🗄 "

    if [ -f "$DICT_FILE" ]; then
        while IFS='=' read -r key val; do
            map[$(echo "$key" | tr -d ' ' | tr '[:upper:]' '[:lower:]')]=$(echo "$val" | tr -d ' ')
        done < "$DICT_FILE"
    fi

    for key in "${!map[@]}"; do
        if [[ "$name" == *"$key"* ]]; then
            emoji="${map[$key]}"
            break
        fi
    done
    echo "$emoji"
}

# --- 1. CORE RESTART FUNCTION ---
restart_container() {
    local NAME=$1
    local IS_RETRY=${2:-0}
    local T_START=$(date +%s)
    local EMOJI=$(get_emoji "$NAME")
    
    echo -n "🔄 Restarting container: $EMOJI $NAME$DOTS_INIT"
    
    docker restart "$NAME" >/dev/null &
    local RESTART_PID=$!
    
    while kill -0 $RESTART_PID 2>/dev/null; do
        sleep 1
        echo -n "."
    done
    wait $RESTART_PID 
    echo " [Done]"
    echo "---------------------------------------------------"
    
    HAS_HEALTH=$(docker inspect -f '{{if .State.Health}}yes{{else}}no{{end}}' "$NAME" 2>/dev/null)
    if [ "$HAS_HEALTH" == "no" ]; then 
        echo "🏁 It took $(( $(date +%s) - T_START )) total seconds for a healthy restart"
        echo "🟢 $NAME is back online (Healthchecks: N/A)"
        echo ""
        return 0
    fi
    
    local ELAPSED=0
    local DOTS=""
    while true; do 
        if [ "$(docker inspect -f '{{.State.Health.Status}}' "$NAME" 2>/dev/null)" == "healthy" ]; then
            echo ""
            echo "🏁 It took $(( $(date +%s) - T_START )) total seconds for a healthy restart"
            echo "🟢 $NAME is healthy and ready!"
            echo ""
            return 0
        fi

        local REMAINING=$((PHASE_LIMIT - ELAPSED))
        echo -ne "\r⏳ Waiting for health checks (${REMAINING}s remaining)${DOTS_INIT}${DOTS}"
        
        if [ $ELAPSED -ge $PHASE_LIMIT ]; then break; fi
        
        sleep 1
        ((ELAPSED++))
        DOTS="${DOTS}."
    done

    echo ""
    echo "⚠️  It's taking longer than usual $PHASE_LIMIT seconds!"
    echo ""
    beo status
    echo ""
    echo "🖨️  Printing recent logs..."
    echo "---------------------------------------------------"
    docker logs --tail 15 "$NAME"
    echo "---------------------------------------------------"
    
    local LOG_MARKER=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local EXTRA=0
    local DOTS_EXTRA=""
    while true; do 
        if [ "$(docker inspect -f '{{.State.Health.Status}}' "$NAME" 2>/dev/null)" == "healthy" ]; then
            echo ""
            echo "🏁 It took $(( $(date +%s) - T_START )) total seconds for a healthy restart"
            echo "🟢 $NAME is healthy and ready!"
            echo ""
            return 0
        fi

        local REM_EXTRA=$((PHASE_LIMIT - EXTRA))
        echo -ne "\r⏳ Continuing to wait (${REM_EXTRA}s remaining)${DOTS_INIT}${DOTS_EXTRA}"

        if [ $EXTRA -ge $PHASE_LIMIT ]; then break; fi

        sleep 1
        ((EXTRA++))
        DOTS_EXTRA="${DOTS_EXTRA}."
    done

    echo ""
    echo "❌ $NAME failed to become healthy after total $((ELAPSED + EXTRA)) seconds."
    echo "🕵️  Final Crash Logs (Since Warning):"
    echo "---------------------------------------------------"
    docker logs --since "$LOG_MARKER" "$NAME"
    echo "---------------------------------------------------"
    
    if [[ "$NAME" == *"openclaw"* ]]; then
        if [ "$IS_RETRY" -eq 0 ]; then
            echo "🔧 This is an OpenClaw failing container. Attempting 'openclaw doctor --fix'..."
            docker exec -it openclaw-cli openclaw doctor --fix || echo "⚠️ Doctor command failed or CLI container unavailable."
            echo ""
            echo "🔄 Initiating automatic restart loop for $NAME..."
            echo ""
            restart_container "$NAME" 1
            return $?
        fi
    fi

    echo "🛑 Auto-restart aborted due to failure."
    return 1
}

# --- 2. GET AVAILABLE CONTAINERS ---
mapfile -t CONTAINERS < <(docker ps -a --format '{{.Names}}' | sort -f)
TARGETS=()

# --- 3. INPUT GATHERING WITH MULTI-LINE PROGRESS BAR ---
if [ -z "$1" ]; then
    echo "⚠️  Attention: A container to restart should be provided."
    echo ""
    echo "===================================================="
    echo "📦  CONTAINER LIST"
    echo "----------------------------------------------------"
    for i in "${!CONTAINERS[@]}"; do 
        EMOJI=$(get_emoji "${CONTAINERS[$i]}")
        echo "    $((i+1))) $EMOJI ${CONTAINERS[$i]}"
    done

    if [ ${#CONTAINERS[@]} -gt 1 ]; then
        echo "    x) 🛒 Select ALL above"
    fi
    echo "===================================================="
    echo ""

    if [ ${#CONTAINERS[@]} -gt 1 ]; then
        PROMPT_TEXT="Select numbers (e.g., '1, 3' or 'x' for all): "
    else
        PROMPT_TEXT="Press 1 to restart: "
    fi

    FIRST_PROMPT=1
    while [ ${#TARGETS[@]} -eq 0 ]; do
        if [ "$FIRST_PROMPT" -eq 1 ]; then
            FIRST_PROMPT=0
            TIMEOUT_REACHED=true
            for (( i=$AUTO_EXIT_SEC; i>0; i-- )); do
                FILLED=$(( i * 20 / AUTO_EXIT_SEC ))
                EMPTY=$(( 20 - FILLED ))
                BAR=$(printf "%${FILLED}s" | tr ' ' '?')
                SPACES=$(printf "%${EMPTY}s" | tr ' ' '-')
                
                printf "\r\033[K%s\n" "$PROMPT_TEXT"
                printf "\r\033[K\n"
                printf "\r\033[K(%d seconds remaining to choose, q to cancel) %s%s" "$i" "$BAR" "$SPACES"
                
                printf "\033[2A\r\033[%dC" "${#PROMPT_TEXT}"
                
                if read -t 1 -n 1 FIRST_CHAR; then
                    TIMEOUT_REACHED=false
                    printf "\033[s\n\r\033[K\n\r\033[K\033[u"
                    if [[ "$FIRST_CHAR" != "" ]] && [[ "$FIRST_CHAR" != $'\n' ]]; then
                        read -r REST_OF_INPUT
                        RAW_INPUT="${FIRST_CHAR}${REST_OF_INPUT}"
                    else
                        RAW_INPUT=""
                    fi
                    break
                fi
            done
            
            if [ "$TIMEOUT_REACHED" = true ]; then
                printf "\n\r\033[K\n\r\033[K\033[2A\r\033[K"
                echo "⏳ Auto-exit timeout reached ($AUTO_EXIT_SEC seconds). Restart aborted."
                exit 0
            fi
        else
            echo -ne "\r\033[K"
            read -r -p "$PROMPT_TEXT" RAW_INPUT
        fi

        if [[ "$RAW_INPUT" =~ ^[Qq]$ ]]; then
            echo "Restart aborted."
            exit 0
        fi

        CLEAN_INPUT=$(echo "$RAW_INPUT" | tr ',' ' ')
        read -r -a CHOICES <<< "$CLEAN_INPUT"
        
        for CHOICE in "${CHOICES[@]}"; do
            if [[ "$CHOICE" =~ ^[Xx]$ ]] && [ ${#CONTAINERS[@]} -gt 1 ]; then 
                TARGETS=("${CONTAINERS[@]}")
                break 2
            elif [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -gt 0 ] && [ "$CHOICE" -le "${#CONTAINERS[@]}" ]; then 
                TARGETS+=("${CONTAINERS[$((CHOICE-1))]}")
            fi
        done

        if [ ${#TARGETS[@]} -eq 0 ]; then
            echo -e "\n❌ Invalid selection. Please try again."
        fi
    done
else
    for ARG in "$@"; do
        RESOLVED=$(docker ps -a --format '{{.Names}}' | grep -i "$ARG" | head -n 1)
        [ -n "$RESOLVED" ] && TARGETS+=("$RESOLVED")
    done
fi

echo ""
for container in "${TARGETS[@]}"; do restart_container "$container"; done
