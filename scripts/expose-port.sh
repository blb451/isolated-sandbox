#!/bin/bash

# Script to expose additional ports from the running sandbox container

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

echo
print_message "$BLUE" "================================================"
print_message "$BLUE" "   Port Exposure Tool for Sandbox Container    "
print_message "$BLUE" "================================================"
echo

# Check if container is running
if ! docker ps | grep -q "thanx-sandbox"; then
    print_message "$RED" "Error: Sandbox container is not running"
    print_message "$YELLOW" "Start it first with: ./run-sandbox.sh"
    exit 1
fi

# Get current port mappings
echo
print_message "$BLUE" "Current port mappings:"
docker port thanx-sandbox | while read line; do
    if [ -n "$line" ]; then
        echo "  $line"
    fi
done

echo
print_message "$YELLOW" "What port would you like to expose from the container?"
print_message "$BLUE" "Examples:"
echo "  - 4000 (for Jekyll, Next.js dev server)"
echo "  - 9000 (for webpack dev server)"
echo "  - 8000 (for Django, Python SimpleHTTPServer)"
echo "  - 3001 (for additional Node.js app)"
echo "  - 6006 (for Storybook)"
echo

read -p "Container port to expose: " container_port

# Validate port number
if ! [[ $container_port =~ ^[0-9]+$ ]] || [ "$container_port" -lt 1 ] || [ "$container_port" -gt 65535 ]; then
    print_message "$RED" "Error: Invalid port number"
    exit 1
fi

# Suggest host port (same as container port by default)
default_host_port=$container_port
echo
print_message "$YELLOW" "What host port should it map to? (default: $default_host_port)"
read -p "Host port (press Enter for $default_host_port): " host_port

if [ -z "$host_port" ]; then
    host_port=$default_host_port
fi

# Validate host port
if ! [[ $host_port =~ ^[0-9]+$ ]] || [ "$host_port" -lt 1 ] || [ "$host_port" -gt 65535 ]; then
    print_message "$RED" "Error: Invalid host port number"
    exit 1
fi

# Check if host port is already in use
if netstat -an | grep -q ":$host_port "; then
    print_message "$RED" "Warning: Port $host_port appears to be in use on the host"
    print_message "$YELLOW" "Do you want to continue anyway? (y/n)"
    read -r confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo
print_message "$YELLOW" "Exposing container port $container_port to host port $host_port..."

# Stop the current container
print_message "$BLUE" "Stopping current container..."
docker-compose down

# Create a temporary docker-compose override
cat >docker-compose.override.yml <<EOF
services:
  sandbox:
    ports:
      - "$host_port:$container_port"
EOF

print_message "$BLUE" "Starting container with new port mapping..."
docker-compose up -d

# Wait a moment for container to start
sleep 2

if docker ps | grep -q "thanx-sandbox"; then
    print_message "$GREEN" "✓ Success! Container is running with new port mapping"
    print_message "$GREEN" "✓ Container port $container_port is now accessible at http://localhost:$host_port"
    echo
    print_message "$BLUE" "Updated port mappings:"
    docker port thanx-sandbox | while read line; do
        if [ -n "$line" ]; then
            echo "  $line"
        fi
    done
    echo
    print_message "$YELLOW" "To connect to the container:"
    print_message "$YELLOW" "  docker-compose exec sandbox bash"
else
    print_message "$RED" "Error: Container failed to start with new port mapping"
    print_message "$YELLOW" "Check for port conflicts and try again"
fi
