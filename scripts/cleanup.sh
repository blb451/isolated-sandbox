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
echo "3) Container logs and temp files"
echo "4) Everything (full reset)"
echo "5) Old files (>7 days)"
echo "6) Exit"
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
    (docker-compose down 2>/dev/null && docker system prune -f >/dev/null 2>&1 && rm -rf audit/*.log) &
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
5)
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
6)
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
