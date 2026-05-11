#!/bin/bash

# --- 1. CORE RESTART FUNCTION ---
restart_container() {
    local NAME=$1
    echo "🔄 Restarting container '$NAME'..."
    docker restart "$NAME" >/dev/null
    
    HAS_HEALTH=$(docker inspect -f '{{if .State.Health}}yes{{else}}no{{end}}' "$NAME" 2>/dev/null)
    if [ "$HAS_HEALTH" == "no" ]; then 
        echo "  ✅ $NAME restarted successfully! (No health status to track)."
        return 0
    fi
    
    echo -n "  ⏳ Waiting for $NAME to be healthy"
    while [ "$(docker inspect -f '{{.State.Health.Status}}' "$NAME" 2>/dev/null)" != "healthy" ]; do 
        sleep 1; echo -n "."
    done
    echo -e "\n  ✅ $NAME is officially healthy and ready!"
}

# --- 2. GET AVAILABLE CONTAINERS (ALPHABETICALLY) ---
mapfile -t CONTAINERS < <(docker ps -a --format '{{.Names}}' | sort -f)
TARGETS=()

# --- 3. INPUT GATHERING ---
# If no arguments were passed from the Hub, launch the menu
if [ -z "$1" ]; then
    echo "⚠️  Attention: A container to restart should be provided."
    echo ""
    echo "See list below:"
    echo "0) Restart ALL containers"
    
    for i in "${!CONTAINERS[@]}"; do
        echo "$((i+1))) ${CONTAINERS[$i]}"
    done
    
    echo ""
    # Keep looping until at least one valid container is selected
    while [ ${#TARGETS[@]} -eq 0 ]; do
        read -r -p "Select numbers (e.g., '1, 3', '0' for all): " RAW_INPUT
        
        # Replace any commas with spaces to standardize the input format
        CLEAN_INPUT=$(echo "$RAW_INPUT" | tr ',' ' ')
        read -r -a CHOICES <<< "$CLEAN_INPUT"
        
        for CHOICE in "${CHOICES[@]}"; do
            if [[ "$CHOICE" == "0" ]]; then
                TARGETS=("${CONTAINERS[@]}")
                break # 0 acts as a master override, grab all and stop parsing
            elif [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -gt 0 ] && [ "$CHOICE" -le "${#CONTAINERS[@]}" ]; then
                TARGETS+=("${CONTAINERS[$((CHOICE-1))]}")
            else
                echo "❌ Invalid selection: '$CHOICE'. Skipping."
            fi
        done
        
        # If the input was entirely invalid, prompt again
        if [ ${#TARGETS[@]} -eq 0 ]; then
            echo "⚠️  No valid containers selected. Please try again."
        fi
    done
else
    # If the user passed arguments directly (e.g., 'beo restart gateway cli')
    for ARG in "$@"; do
        RESOLVED=$(docker ps -a --format '{{.Names}}' | grep -i "$ARG" | head -n 1)
        if [ -n "$RESOLVED" ]; then
            TARGETS+=("$RESOLVED")
        else
            echo "❌ Error: No container found matching '$ARG'."
        fi
    done
    
    if [ ${#TARGETS[@]} -eq 0 ]; then
        echo "❌ No valid containers selected. Exiting."
        exit 1
    fi
fi

# --- 4. EXECUTION ---
# Remove duplicates (in case they typed '1, 1' or '0, 1')
mapfile -t UNIQUE_TARGETS < <(printf "%s\n" "${TARGETS[@]}" | sort -u)

echo ""
for container in "${UNIQUE_TARGETS[@]}"; do
    restart_container "$container"
done
