#!/bin/bash

# Script to launch sandbox with automatic port detection

SANDBOX_DIR="$(cd "$(dirname "$0")/.." && pwd)"
EXTRACTED_PATH="${1:-/sandbox/extracted/example-app}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to check if port is available
is_port_available() {
    ! lsof -i :$1 >/dev/null 2>&1
}

# Function to find next available port starting from a base port
find_available_port() {
    local base_port=$1
    local max_tries=20
    for ((i = 0; i < max_tries; i++)); do
        local port=$((base_port + i))
        if is_port_available "$port"; then
            echo "$port"
            return 0
        fi
    done
    return 1
}

# Build port arguments dynamically
PORT_ARGS=""

# Define standard ports and their purposes
declare -a STANDARD_PORTS=("3000" "5173" "8080" "5000" "8000")
declare -a PORT_NAMES=("Rails/Node" "Vite" "Generic" "Flask" "Django")

echo ""
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}   Port Mapping Configuration${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""

for i in "${!STANDARD_PORTS[@]}"; do
    CONTAINER_PORT="${STANDARD_PORTS[$i]}"
    NAME="${PORT_NAMES[$i]}"

    if is_port_available "$CONTAINER_PORT"; then
        # Port is available, use direct mapping
        PORT_ARGS="$PORT_ARGS -p $CONTAINER_PORT:$CONTAINER_PORT"
        echo -e "  ${GREEN}✓${NC} localhost:${GREEN}$CONTAINER_PORT${NC} → container:$CONTAINER_PORT ($NAME)"
    else
        # Port is busy, find an alternative
        ALT_PORT=$(find_available_port $((CONTAINER_PORT + 1)))
        if [ -n "$ALT_PORT" ]; then
            PORT_ARGS="$PORT_ARGS -p $ALT_PORT:$CONTAINER_PORT"
            echo -e "  ${YELLOW}⚠️${NC}  localhost:${YELLOW}$ALT_PORT${NC} → container:$CONTAINER_PORT ($NAME) ${RED}[port $CONTAINER_PORT busy]${NC}"
        else
            # Use dynamic port allocation as last resort
            PORT_ARGS="$PORT_ARGS -p $CONTAINER_PORT"
            echo -e "  ${YELLOW}⚠️${NC}  Dynamic port for container:$CONTAINER_PORT ($NAME) - Docker will assign"
        fi
    fi
done

echo ""
if [[ $PORT_ARGS == *"-p"* ]]; then
    echo -e "${BLUE}Note: Access your app at http://localhost:[port] shown above${NC}"
fi
echo -e "${CYAN}================================================${NC}"

# Launch the container with port mappings
cd "$SANDBOX_DIR"
echo ""
echo -e "${GREEN}Launching sandbox container...${NC}"
exec docker-compose run --rm $PORT_ARGS -w "$EXTRACTED_PATH" sandbox bash
