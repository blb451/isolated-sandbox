#!/bin/bash

# Cleanup script for Thanx Isolated Sandbox

# Enable Docker Compose bake for better performance
export COMPOSE_BAKE=true

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Reusable spinner animation for progress indicators (same as run-sandbox.sh)
SPINNER_FRAMES=("⣾" "⣽" "⣻" "⢿" "⡿" "⣟" "⣯" "⣷")

print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Spinner animation function using consistent frames
show_spinner() {
    local pid=$1
    local delay=0.1
    while ps -p $pid >/dev/null 2>&1; do
        for frame in "${SPINNER_FRAMES[@]}"; do
            printf " %s " "$frame"
            sleep $delay
            printf "\b\b\b"
            # Check if process is still running
            if ! ps -p $pid >/dev/null 2>&1; then
                break
            fi
        done
    done
    printf "   \b\b\b"
}

# Progress indicator with steps
run_with_progress() {
    local message=$1
    shift
    echo -ne "${YELLOW}  ${message}${NC}"

    # Run command with timeout
    timeout 30 "$@" &>/dev/null &
    local pid=$!

    show_spinner $pid
    wait $pid
    local result=$?

    if [ $result -eq 124 ]; then
        echo -e "\r${RED}  ✗ ${message} (timeout)${NC}"
    elif [ $result -eq 0 ]; then
        echo -e "\r${GREEN}  ✓ ${message}${NC}"
    else
        echo -e "\r${RED}  ✗ ${message}${NC}"
    fi
    return $result
}

echo
print_message "$BLUE" "================================================"
print_message "$BLUE" "   Sandbox Cleanup Tool                        "
print_message "$BLUE" "================================================"
echo

echo
print_message "$YELLOW" "What would you like to clean?"
echo "1) Extracted files only"
echo "2) Submission ZIPs only"
echo "3) Logs and temp files"
echo "4) Docker artifacts (keeps current build)"
echo "5) Everything (full reset)"
echo "6) Old files (>7 days)"
echo "7) Exit"
read -r choice

case $choice in
1)
    echo
    echo -n "  Removing extracted files"
    # Fix permissions first in case they're messed up
    (chmod -R 755 extracted 2>/dev/null && rm -rf extracted/* && rm -rf extracted/.* 2>/dev/null) &
    PID=$!

    # Show spinner while removing
    while ps -p $PID >/dev/null 2>&1; do
        for frame in "${SPINNER_FRAMES[@]}"; do
            printf "\r  Removing extracted files %s" "$frame"
            sleep 0.1
        done
    done
    wait $PID

    echo -e "\r  ✓ Extracted files removed                    "
    ;;
2)
    echo
    print_message "$YELLOW" "Removing submission ZIPs..."
    rm -rf submissions/*
    print_message "$GREEN" "✓ Submission files removed"
    ;;
3)
    echo
    echo -n "  Cleaning container artifacts"

    # Run cleanup operations in background
    (docker-compose down 2>/dev/null && docker system prune -f >/dev/null 2>&1 && rm -rf audit/*) &
    PID=$!

    # Show spinner while cleaning
    while ps -p $PID >/dev/null 2>&1; do
        for frame in "${SPINNER_FRAMES[@]}"; do
            printf "\r  Cleaning container artifacts %s" "$frame"
            sleep 0.1
        done
    done
    wait $PID

    echo -e "\r  ✓ Container artifacts cleaned                 "
    ;;
4)
    echo
    echo -n "  Analyzing Docker build cache and images"

    # Get info about Docker images and build cache
    CURRENT_IMAGE=$(docker images thanx-isolated-sandbox-sandbox:latest -q 2>/dev/null)
    OLD_IMAGES=$(docker images thanx-isolated-sandbox-sandbox --filter "before=thanx-isolated-sandbox-sandbox:latest" -q 2>/dev/null | grep -v "$CURRENT_IMAGE" || true)
    DANGLING=$(docker images -f "dangling=true" -q 2>/dev/null)

    # Get build cache information more accurately
    BUILD_CACHE_BEFORE=$(docker system df 2>/dev/null | grep "Build Cache" | awk '{print $3}' || echo "0B")
    # Count all build cache entries, not just ones with our name
    BUILD_CACHE_COUNT=$(docker builder du 2>/dev/null | wc -l || echo 0)

    echo -e "\r  Docker System Cleanup                        "
    echo

    # Count stopped containers
    STOPPED_CONTAINERS=$(docker ps -a -q --filter "status=exited" | wc -l | tr -d ' ')
    # Count unused volumes
    UNUSED_VOLUMES=$(docker volume ls -q -f dangling=true | wc -l | tr -d ' ')

    # Always show what we found
    print_message "$YELLOW" "  Found the following to clean:"

    # Show what can be cleaned
    [ -n "$OLD_IMAGES" ] && echo "    • Old sandbox images: $(echo "$OLD_IMAGES" | wc -l | tr -d ' ')"
    [ -n "$DANGLING" ] && echo "    • Dangling images: $(echo "$DANGLING" | wc -l | tr -d ' ')"
    [ "$STOPPED_CONTAINERS" -gt 0 ] && echo "    • Stopped containers: $STOPPED_CONTAINERS"
    [ "$UNUSED_VOLUMES" -gt 0 ] && echo "    • Unused volumes: $UNUSED_VOLUMES"
    [ "$BUILD_CACHE_COUNT" -gt 1 ] && echo "    • Build cache entries: $BUILD_CACHE_COUNT ($BUILD_CACHE_BEFORE)"

    if [ -z "$OLD_IMAGES" ] && [ -z "$DANGLING" ] && [ "$BUILD_CACHE_COUNT" -le 1 ] && [ "$STOPPED_CONTAINERS" -eq 0 ] && [ "$UNUSED_VOLUMES" -eq 0 ]; then
        print_message "$GREEN" "  ✓ Nothing to clean"
        print_message "$BLUE" "  Current build and container preserved"
    else
        print_message "$GREEN" "  Will preserve: Current build & most recent container"
        echo
        print_message "$YELLOW" "  Proceed with cleanup? (y/n):"
        read -r confirm

        if [[ $confirm =~ ^[Yy]$ ]]; then
            echo -n "  Cleaning Docker system"

            # Clean up in background with spinner
            (
                # Remove old sandbox images (but keep current)
                if [ -n "$OLD_IMAGES" ]; then
                    echo "$OLD_IMAGES" | xargs docker rmi -f >/dev/null 2>&1 || true
                fi

                # Remove unused volumes (not attached to any container)
                docker volume prune -f >/dev/null 2>&1

                # Remove old stopped containers (but keep the most recent sandbox container)
                # Get the most recent sandbox container ID
                RECENT_CONTAINER=$(docker ps -a --filter "ancestor=thanx-isolated-sandbox-sandbox:latest" --format "{{.ID}}" | head -1)
                # Remove all stopped containers except the most recent sandbox one
                docker ps -a -q --filter "status=exited" | while read container; do
                    if [ "$container" != "$RECENT_CONTAINER" ]; then
                        docker rm "$container" >/dev/null 2>&1 || true
                    fi
                done

                # Remove dangling images (layers not tagged and not used by any container)
                docker image prune -f >/dev/null 2>&1

                # Remove unused networks (not used by any container)
                docker network prune -f >/dev/null 2>&1

                # Remove unused build cache (keeps cache used by existing images)
                # This preserves cache for the current thanx-isolated-sandbox-sandbox:latest
                docker builder prune -f >/dev/null 2>&1

                # Also clean up any unused buildx cache
                docker buildx prune -f >/dev/null 2>&1 || true
            ) &
            PID=$!

            # Show spinner while cleaning
            while ps -p $PID >/dev/null 2>&1; do
                for frame in "${SPINNER_FRAMES[@]}"; do
                    printf "\r  Cleaning Docker system %s" "$frame"
                    sleep 0.1
                done
            done
            wait $PID

            echo -e "\r  ✓ Docker system cleaned                                     "

            # Show space reclaimed
            BUILD_CACHE_AFTER=$(docker system df 2>/dev/null | grep "Build Cache" | awk '{print $3}' || echo "0B")
            print_message "$GREEN" "  Build cache before: $BUILD_CACHE_BEFORE"
            print_message "$GREEN" "  Build cache after: $BUILD_CACHE_AFTER"
            print_message "$BLUE" "  Run 'docker system df' to see full details"
            echo
            print_message "$YELLOW" "  Note: Docker Desktop's Build History shows metadata only."
            print_message "$YELLOW" "        These records don't consume significant disk space."
        else
            print_message "$BLUE" "  Cleanup cancelled"
        fi
    fi
    ;;
5)
    print_message "$RED" "⚠️  This will remove all data and reset the sandbox!"
    echo
    print_message "$YELLOW" "Are you sure? (type 'yes' to confirm):"
    read -r confirm
    if [ "$confirm" = "yes" ]; then
        echo
        print_message "$YELLOW" "Performing full cleanup..."
        echo

        # Check if docker-compose exists and containers are running
        if command -v docker-compose &>/dev/null; then
            if docker info &>/dev/null; then
                # Check if any containers exist first
                if docker-compose ps -q 2>/dev/null | grep -q .; then
                    run_with_progress "Stopping containers..." docker-compose down --rmi local --volumes
                else
                    echo -e "${YELLOW}  No containers to stop${NC}"
                fi
            else
                echo -e "${YELLOW}  Docker daemon not running, skipping container cleanup${NC}"
            fi
        else
            echo -e "${YELLOW}  Docker Compose not found, skipping container cleanup${NC}"
        fi

        # Remove all files with progress
        if [ -d "extracted" ]; then
            run_with_progress "Removing extracted files..." bash -c "rm -rf extracted/* extracted/.* 2>/dev/null"
        else
            echo -e "${YELLOW}  No extracted directory found${NC}"
        fi
        if [ -d "submissions" ]; then
            run_with_progress "Removing submissions..." rm -rf submissions/*
        else
            echo -e "${YELLOW}  No submissions directory found${NC}"
        fi
        if [ -d "audit" ]; then
            run_with_progress "Removing audit logs..." rm -rf audit/*
        else
            echo -e "${YELLOW}  No audit directory found${NC}"
        fi

        # Remove override files with progress
        run_with_progress "Removing override files..." bash -c "rm -f docker-compose.override.yml scan-deep.sh"

        # Prune Docker system with progress
        if command -v docker &>/dev/null; then
            if docker info &>/dev/null; then
                run_with_progress "Pruning Docker system..." docker system prune -af
            else
                echo -e "${YELLOW}  Docker daemon not running, skipping Docker cleanup${NC}"
            fi
        else
            echo -e "${YELLOW}  Docker not found, skipping Docker cleanup${NC}"
        fi

        echo
        print_message "$GREEN" "✓ Full cleanup complete"
        echo
        print_message "$YELLOW" "Run 'docker-compose build' to rebuild the environment"
    else
        print_message "$BLUE" "Cleanup cancelled"
    fi
    ;;
6)
    echo
    echo -n "  Scanning for old files"

    # Count old files first
    OLD_COUNT=$(find extracted submissions audit -type f -mtime +7 2>/dev/null | wc -l)

    if [ "$OLD_COUNT" -gt 0 ]; then
        echo -e "\r  Found $OLD_COUNT old files (>7 days)          "
        echo -n "  Removing old files"

        # Remove old files in background
        (find extracted -type f -mtime +7 -delete 2>/dev/null &&
            find submissions -type f -mtime +7 -delete 2>/dev/null &&
            find audit -type f -mtime +7 -delete 2>/dev/null) &
        PID=$!

        # Show spinner while removing
        while ps -p $PID >/dev/null 2>&1; do
            for frame in "${SPINNER_FRAMES[@]}"; do
                printf "\r  Removing old files %s" "$frame"
                sleep 0.1
            done
        done
        wait $PID

        echo -e "\r  ✓ Removed $OLD_COUNT old files                "
    else
        echo -e "\r  ✓ No old files found (>7 days)               "
    fi
    ;;
7)
    print_message "$GREEN" "Exiting..."
    ;;
*)
    print_message "$RED" "Invalid choice"
    ;;
esac

# Show disk usage
echo
echo -n "  Calculating disk usage"

# Run disk usage calculations in background
(
    echo "EXTRACTED=$(du -sh extracted 2>/dev/null | awk '{print $1}')" >/tmp/disk_usage.txt
    echo "SUBMISSIONS=$(du -sh submissions 2>/dev/null | awk '{print $1}')" >>/tmp/disk_usage.txt
    echo "AUDIT=$(du -sh audit 2>/dev/null | awk '{print $1}')" >>/tmp/disk_usage.txt
    docker system df 2>/dev/null | grep -E "Images|Containers" | awk '{print "DOCKER_" $1 "=\"" $2 "\""}' >>/tmp/disk_usage.txt
) &
PID=$!

# Show spinner while calculating
while ps -p $PID >/dev/null 2>&1; do
    for frame in "${SPINNER_FRAMES[@]}"; do
        printf "\r  Calculating disk usage %s" "$frame"
        sleep 0.1
    done
done
wait $PID

# Read results
source /tmp/disk_usage.txt 2>/dev/null || true
rm -f /tmp/disk_usage.txt

echo -e "\r${BLUE}Current disk usage:${NC}                     "
[ -n "$EXTRACTED" ] && echo "  Extracted: $EXTRACTED"
[ -n "$SUBMISSIONS" ] && echo "  Submissions: $SUBMISSIONS"
[ -n "$AUDIT" ] && echo "  Audit logs: $AUDIT"
[ -n "$DOCKER_Images" ] && echo "  Docker Images: $DOCKER_Images"
[ -n "$DOCKER_Containers" ] && echo "  Docker Containers: $DOCKER_Containers"

# Exit the script
exit 0
