#!/bin/bash
ARG=$1
if [ -z "$ARG" ]; then echo "Error: Please provide a container name (e.g., beo restart gateway)"; exit 1; fi
CONTAINER=$(docker ps -a --format '{{.Names}}' | grep -i "$ARG" | head -n 1)
if [ -z "$CONTAINER" ]; then echo "Error: No container found matching '$ARG'."; exit 1; fi
echo "Restarting container '$CONTAINER'..."
docker restart "$CONTAINER" >/dev/null
HAS_HEALTH=$(docker inspect -f '{{if .State.Health}}yes{{else}}no{{end}}' "$CONTAINER")
if [ "$HAS_HEALTH" == "no" ]; then echo "$CONTAINER restarted successfully! (No health status to track)."; exit 0; fi
echo -n "Waiting for $CONTAINER to be healthy"
while [ "$(docker inspect -f '{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null)" != "healthy" ]; do sleep 1; echo -n "."; done
echo -e "\n$CONTAINER is officially healthy and ready!"
