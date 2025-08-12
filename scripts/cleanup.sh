#!/bin/bash

# Cleanup script for Thanx Isolated Sandbox

# Enable Docker Compose bake for better performance
export COMPOSE_BAKE=true

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

# Spinner animation function
show_spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    local temp
    while ps -p $pid >/dev/null 2>&1; do
        temp=${spinstr#?}
        printf " [%c] " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
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
    print_message "$YELLOW" "Removing extracted files..."
    # Fix permissions first in case they're messed up
    chmod -R 755 extracted 2>/dev/null
    rm -rf extracted/*
    rm -rf extracted/.* 2>/dev/null
    print_message "$GREEN" "✓ Extracted files removed"
    ;;
2)
    echo
    print_message "$YELLOW" "Removing submission ZIPs..."
    rm -rf submissions/*
    print_message "$GREEN" "✓ Submission files removed"
    ;;
3)
    echo
    print_message "$YELLOW" "Cleaning container artifacts..."
    docker-compose down
    docker system prune -f
    rm -rf audit/*.log
    print_message "$GREEN" "✓ Container artifacts cleaned"
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
    print_message "$YELLOW" "Removing files older than 7 days..."
    find extracted -type f -mtime +7 -delete 2>/dev/null
    find submissions -type f -mtime +7 -delete 2>/dev/null
    find audit -type f -mtime +7 -delete 2>/dev/null
    print_message "$GREEN" "✓ Old files removed"
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
print_message "$BLUE" "Current disk usage:"
du -sh extracted 2>/dev/null | awk '{print "  Extracted: " $1}'
du -sh submissions 2>/dev/null | awk '{print "  Submissions: " $1}'
du -sh audit 2>/dev/null | awk '{print "  Audit logs: " $1}'
docker system df | grep -E "Images|Containers" | awk '{print "  Docker " $1 ": " $2}'

# Exit the script
exit 0
