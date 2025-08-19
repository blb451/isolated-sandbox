#!/bin/bash

# Enable Docker Compose bake for better performance
export COMPOSE_BAKE=true

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Reusable spinner animation for progress indicators
SPINNER_FRAMES=("⣾" "⣽" "⣻" "⢿" "⡿" "⣟" "⣯" "⣷")

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to check Docker connectivity
check_docker() {
    if ! timeout 5 docker info >/dev/null 2>&1; then
        if [ $? -eq 124 ]; then
            print_message "$RED" "Error: Docker is not responding (timed out)"
            print_message "$YELLOW" "Docker Desktop may be starting up. Please wait and try again."
        else
            print_message "$RED" "Error: Docker is not running!"
            print_message "$YELLOW" "Please start Docker Desktop and try again."
        fi
        return 1
    fi
    return 0
}

# Banner
# Get version from VERSION file if it exists
VERSION=$(cat VERSION 2>/dev/null || echo "dev")

echo
print_message "$BLUE" "================================================"
print_message "$BLUE" "   Thanx Isolated Sandbox - Code Review Tool   "
print_message "$BLUE" "   Version: v$VERSION"
print_message "$BLUE" "================================================"
echo

# Create necessary directories
mkdir -p submissions extracted audit

# Handle command-line arguments or prompt for input
if [ $# -eq 0 ]; then
    # No arguments provided, use interactive mode
    zip_paths=()

    # Get first ZIP file
    while true; do
        echo
        print_message "$YELLOW" "Enter the path to the submission ZIP file:"
        read -r zip_path

        # Check if user wants to quit
        if [ -z "$zip_path" ]; then
            print_message "$YELLOW" "No path entered. Press Enter to try again or type 'quit' to exit:"
            read -r response
            if [ "$response" = "quit" ]; then
                print_message "$BLUE" "Exiting..."
                exit 0
            fi
            continue
        fi

        # Expand tilde and environment variables in the path
        zip_path=$(eval echo "$zip_path")

        # Validate file exists
        if [ ! -f "$zip_path" ]; then
            print_message "$RED" "Error: File not found at $zip_path"
            print_message "$YELLOW" "Please check the path and try again (or type 'quit' to exit)"
            continue
        fi

        # Validate it's a ZIP file
        if ! file "$zip_path" | grep -q "Zip archive"; then
            print_message "$RED" "Error: File is not a valid ZIP archive"
            print_message "$YELLOW" "Please provide a valid ZIP file (or type 'quit' to exit)"
            continue
        fi

        # If we get here, file is valid
        zip_paths+=("$zip_path")
        break
    done

    # Ask if user wants to add a second ZIP file (optional)
    echo
    print_message "$YELLOW" "Do you have a second ZIP file to merge? (e.g., frontend + backend)"
    print_message "$YELLOW" "Press Enter to skip, or enter the path to the second ZIP file:"
    read -r second_zip_path

    if [ -n "$second_zip_path" ]; then
        # Expand tilde and environment variables in the second path
        second_zip_path=$(eval echo "$second_zip_path")

        # Validate second file if provided
        if [ ! -f "$second_zip_path" ]; then
            print_message "$RED" "Warning: Second file not found at $second_zip_path"
            print_message "$YELLOW" "Proceeding with single ZIP file only"
        elif ! file "$second_zip_path" | grep -q "Zip archive"; then
            print_message "$RED" "Warning: Second file is not a valid ZIP archive"
            print_message "$YELLOW" "Proceeding with single ZIP file only"
        else
            zip_paths+=("$second_zip_path")
            print_message "$GREEN" "✓ Both ZIP files will be merged into the same extraction folder"
        fi
    fi
elif [ $# -eq 1 ] || [ $# -eq 2 ]; then
    # Command-line arguments provided
    zip_paths=()
    for arg in "$@"; do
        if [ ! -f "$arg" ]; then
            print_message "$RED" "Error: File not found at $arg"
            exit 1
        fi
        if ! file "$arg" | grep -q "Zip archive"; then
            print_message "$RED" "Error: File $arg is not a valid ZIP archive"
            exit 1
        fi
        zip_paths+=("$arg")
    done
    print_message "$GREEN" "✓ Processing ${#zip_paths[@]} ZIP file(s)"
else
    print_message "$RED" "Error: Too many arguments. Maximum 2 ZIP files supported."
    print_message "$YELLOW" "Usage: $0 [zip_file1] [zip_file2]"
    exit 1
fi

# Check file sizes and copy submissions
MAX_SIZE=$((500 * 1024 * 1024)) # 500MB in bytes
submission_names=()

for zip_path in "${zip_paths[@]}"; do
    # Detect OS and use appropriate stat command
    if [[ $OSTYPE == "darwin"* ]] || [[ "$(uname)" == "Darwin" ]]; then
        FILE_SIZE=$(stat -f%z "$zip_path")
    else
        FILE_SIZE=$(stat -c%s "$zip_path")
    fi
    if [ "$FILE_SIZE" -gt "$MAX_SIZE" ]; then
        print_message "$RED" "Error: File $zip_path exceeds 500MB limit ($((FILE_SIZE / 1024 / 1024))MB)"
        print_message "$YELLOW" "Large files may contain malicious payloads or cause resource exhaustion"
        exit 1
    fi

    # Log submission for audit
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Submission: $zip_path ($((FILE_SIZE / 1024))KB)" >>audit/submissions.log

    # Copy submission to local directory
    submission_name=$(basename "$zip_path")
    cp "$zip_path" "submissions/$submission_name"
    submission_names+=("$submission_name")
done

print_message "$GREEN" "✓ ${#submission_names[@]} file(s) copied to submissions directory"

# Build Docker image if needed
echo
print_message "$YELLOW" "Checking Docker status..."

# Check if Docker daemon is running with timeout
if ! check_docker; then
    exit 1
fi

print_message "$GREEN" "✓ Docker is running"
echo

# Build with timeout and error handling
print_message "$YELLOW" "Building/updating Docker environment..."

# Check if this is a first build or if Dockerfile has been modified
IS_FIRST_BUILD=0
if ! docker images | grep -q "thanx-isolated-sandbox-sandbox"; then
    IS_FIRST_BUILD=1
fi

# Check for Dockerfile modifications
DOCKERFILE_CHANGED=0
if [ "$(git diff --name-only config/Dockerfile 2>/dev/null | wc -l)" -gt 0 ] ||
    [ "$(git status --porcelain config/Dockerfile 2>/dev/null | wc -l)" -gt 0 ] ||
    [ "$(git diff --name-only HEAD~1 HEAD config/Dockerfile 2>/dev/null | wc -l)" -gt 0 ]; then
    DOCKERFILE_CHANGED=1
fi

# Determine build timeout and show appropriate message
if [ "$IS_FIRST_BUILD" -eq 1 ]; then
    BUILD_TIMEOUT=1200 # 20 minutes for first build
    print_message "$BLUE" "⏳ First-time build detected. This will take a while..."
    print_message "$BLUE" "   Installing multiple language versions and databases."
    print_message "$BLUE" "   Future builds will be much faster due to caching."
    echo
elif [ "$DOCKERFILE_CHANGED" -eq 1 ]; then
    BUILD_TIMEOUT=1200 # 20 minutes for Dockerfile changes
    print_message "$BLUE" "⏳ Dockerfile changes detected. Rebuilding affected layers..."
    print_message "$BLUE" "   This may take a while depending on what changed."
    print_message "$BLUE" "   Future builds will use cached layers."
    echo
else
    # For regular builds, just use standard timeout without the misleading message
    BUILD_TIMEOUT=300 # 5 minutes for regular cached builds
fi
if ! timeout $BUILD_TIMEOUT docker-compose build; then
    if [ $? -eq 124 ]; then
        print_message "$RED" "Error: Docker build timed out after $((BUILD_TIMEOUT / 60)) minutes"
        print_message "$YELLOW" "This might indicate a network issue or Docker problem"
        if [ $BUILD_TIMEOUT -eq 1200 ]; then
            print_message "$YELLOW" "First-time builds can take 10-15 minutes. Try running again with:"
            print_message "$BLUE" "  docker-compose build"
        fi
    else
        print_message "$RED" "Error: Docker build failed"
        print_message "$YELLOW" "Please check Docker logs for more information"
    fi
    exit 1
fi

# Run virus scan inside Docker for all submissions
echo
print_message "$YELLOW" "Running enhanced virus scan on submission(s)..."
scan_failed=false

for submission_name in "${submission_names[@]}"; do
    print_message "$BLUE" "Scanning $submission_name..."

    # Run multi-engine scan inline with progress indicators
    docker-compose run --rm sandbox bash -c '
        FILE_PATH="/sandbox/submissions/'"$submission_name"'"
        THREATS_FOUND=0
        YARA_SUSPICIOUS=0

        # Define spinner frames inside container
        SPINNER_FRAMES=("⣾" "⣽" "⣻" "⢿" "⡿" "⣟" "⣯" "⣷")

        # Update ClamAV definitions only on first submission
        if [ "'"$submission_name"'" = "'"${submission_names[0]}"'" ]; then
            echo "⏳ Updating virus definitions..."
            freshclam 2>/dev/null || true
            echo
        fi

        echo "🔍 Running multi-engine virus scan..."
        echo ""

        # 1. ClamAV scan with spinner
        echo -n "  [1/3] ClamAV: Scanning"
        (clamscan --infected --no-summary "$FILE_PATH" > /tmp/clam_result 2>&1) &
        SCAN_PID=$!

        # Show spinner while scanning
        while kill -0 $SCAN_PID 2>/dev/null; do
            for s in "${SPINNER_FRAMES[@]}"; do
                echo -ne "\r  [1/3] ClamAV: Scanning $s"
                sleep 0.1
            done
        done
        wait $SCAN_PID

        if grep -q "FOUND" /tmp/clam_result 2>/dev/null; then
            echo -e "\r  [1/3] ClamAV: ❌ THREAT DETECTED    "
            THREATS_FOUND=$((THREATS_FOUND + 1))
        else
            echo -e "\r  [1/3] ClamAV: ✅ Clean              "
        fi
        rm -f /tmp/clam_result

        # 2. Rootkit Hunter scan (quick mode for archives) with progress
        echo -n "  [2/3] RKHunter: Extracting"
        TEMP_DIR=$(mktemp -d)
        unzip -q "$FILE_PATH" -d "$TEMP_DIR" 2>/dev/null || true

        echo -ne "\r  [2/3] RKHunter: Scanning  "
        (rkhunter --check --skip-keypress --quiet --no-mail-on-warning --disable all --enable hidden_files --enable hidden_dirs --enable suspicious_files --pkgmgr NONE --rwo "$TEMP_DIR" > /tmp/rk_result 2>&1) &
        SCAN_PID=$!

        # Show spinner while scanning
        while kill -0 $SCAN_PID 2>/dev/null; do
            for s in "${SPINNER_FRAMES[@]}"; do
                echo -ne "\r  [2/3] RKHunter: Scanning $s"
                sleep 0.1
            done
        done
        wait $SCAN_PID

        if grep -q "Warning" /tmp/rk_result 2>/dev/null; then
            echo -e "\r  [2/3] RKHunter: ⚠️  Suspicious patterns found    "
            THREATS_FOUND=$((THREATS_FOUND + 1))
        else
            echo -e "\r  [2/3] RKHunter: ✅ Clean                        "
        fi
        rm -rf "$TEMP_DIR"
        rm -f /tmp/rk_result

        # 3. YARA rules scan (if available) with progress
        if [ -d /opt/yara-rules/rules ] && command -v yara >/dev/null 2>&1; then
            echo -n "  [3/3] YARA Rules: Scanning"
            # Find and compile only .yar files, avoiding directories and other files
            (find /opt/yara-rules/rules -name "*.yar" -type f 2>/dev/null | head -20 | xargs -I {} yara {} "$FILE_PATH" 2>/tmp/yara_warnings > /tmp/yara_result) &
            SCAN_PID=$!

            # Show spinner while scanning
            while kill -0 $SCAN_PID 2>/dev/null; do
                for s in "${SPINNER_FRAMES[@]}"; do
                    echo -ne "\r  [3/3] YARA Rules: Scanning $s"
                    sleep 0.1
                done
            done
            wait $SCAN_PID

            # Apply exclusions if config file exists
            if [ -f /sandbox/config/yara-exclusions-for-code-repos.txt ] && [ -f /sandbox/scripts/filter_yara.sh ]; then
                /sandbox/scripts/filter_yara.sh 2>/dev/null || true
            fi

            # Filter out warnings and get only actual detections
            YARA_RESULT=$(cat /tmp/yara_result 2>/dev/null | grep -v "^warning:" | grep -v "^$")
            YARA_WARNINGS=$(cat /tmp/yara_warnings 2>/dev/null | grep "^warning:" | wc -l)

            if [ -n "$YARA_RESULT" ]; then
                echo -e "\r  [3/3] YARA Rules: ⚠️  SUSPICIOUS PATTERNS    "
                YARA_SUSPICIOUS=1

                # Save full results to audit folder
                SUBMISSION_BASE=$(basename "$FILE_PATH" .zip)
                mkdir -p /sandbox/audit
                echo "YARA Scan Results for $SUBMISSION_BASE" > "/sandbox/audit/${SUBMISSION_BASE}_yara_scan.txt"
                echo "=====================================" >> "/sandbox/audit/${SUBMISSION_BASE}_yara_scan.txt"
                echo "" >> "/sandbox/audit/${SUBMISSION_BASE}_yara_scan.txt"
                echo "Detections:" >> "/sandbox/audit/${SUBMISSION_BASE}_yara_scan.txt"
                echo "$YARA_RESULT" >> "/sandbox/audit/${SUBMISSION_BASE}_yara_scan.txt"
                echo "" >> "/sandbox/audit/${SUBMISSION_BASE}_yara_scan.txt"
                echo "Warnings: $YARA_WARNINGS rule inefficiencies detected" >> "/sandbox/audit/${SUBMISSION_BASE}_yara_scan.txt"

                # Show detection details to user
                echo ""
                echo "  YARA Detection Details:"
                echo "  ────────────────────────"
                echo "$YARA_RESULT" | head -10
                if [ $(echo "$YARA_RESULT" | wc -l) -gt 10 ]; then
                    echo "    ... (more detections in audit file)"
                fi
                echo "  Full results saved to: audit/${SUBMISSION_BASE}_yara_scan.txt"
            else
                echo -e "\r  [3/3] YARA Rules: ✅ Clean                  "
            fi
            rm -f /tmp/yara_result /tmp/yara_warnings
        else
            echo "  [3/3] YARA: ⏭️  Skipped (rules not loaded)"
        fi

        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo -n "📊 Scan Summary: "
        if [ $THREATS_FOUND -eq 0 ] && [ $YARA_SUSPICIOUS -eq 0 ]; then
            echo "✅ All scanners report file as CLEAN"
            exit 0
        elif [ $THREATS_FOUND -gt 0 ]; then
            echo "⚠️  $THREATS_FOUND scanner(s) detected potential threats!"
            exit 1
        else
            # Only YARA found something
            echo "⚠️  Suspicious patterns detected, may require additional investigation"
            exit 2
        fi
    '
    scan_exit_code=$?
    if [ $scan_exit_code -ne 0 ]; then
        scan_failed=true
        break
    fi

    # Add extra spacing between multiple submissions
    if [ ${#submission_names[@]} -gt 1 ] && [ "$submission_name" != "${submission_names[-1]}" ]; then
        echo
    fi
done

if [ "$scan_failed" = true ]; then
    # Check if the failure was due to Docker issues
    if ! check_docker; then
        print_message "$RED" "Error: Docker connection lost during scan."
        print_message "$RED" "The process cannot continue."
    elif [ "$scan_exit_code" -eq 2 ]; then
        # YARA-only detection (exit code 2)
        print_message "$YELLOW" "⚠️  Suspicious patterns detected, may require additional investigation."
        print_message "$YELLOW" "The submission contains code patterns that warrant review."
    else
        # ClamAV or RKHunter detected actual malware (exit code 1)
        print_message "$RED" "⚠️  WARNING: Virus or malware detected!"
        print_message "$RED" "The submission has been quarantined and will not be extracted."
    fi

    # Ask if user wants to proceed anyway (for testing purposes)
    echo
    print_message "$YELLOW" "Do you want to proceed anyway? (DANGEROUS - type 'yes' to continue):"
    read -r proceed
    if [ "$proceed" != "yes" ]; then
        exit 1
    fi
    echo
    print_message "$YELLOW" "Proceeding at your own risk..."
fi

print_message "$GREEN" "✓ Multi-engine virus scan passed - submission is clean"

# Extract the submission(s)
echo
print_message "$YELLOW" "Extracting submission(s)..."

# Determine base name for extraction folder
if [ ${#submission_names[@]} -eq 1 ]; then
    # Single zip - use its base name
    base_name=$(basename "${submission_names[0]}" .zip)
else
    # Multiple zips - create a combined name or use timestamp
    base_name="combined_$(date +%Y%m%d_%H%M%S)"
fi

# Clean up any existing extraction and create fresh folder
rm -rf "extracted/$base_name" 2>/dev/null || true
mkdir -p "extracted/$base_name"

# Extract all zip files into the same folder
for submission_name in "${submission_names[@]}"; do
    print_message "$BLUE" "  Extracting $submission_name..."
    cd "extracted/$base_name" || exit
    unzip -q -o "../../submissions/$submission_name"
    cd ../..
done

echo 'Extraction complete'

# Store the extracted project path for later use
EXTRACTED_PROJECT_PATH="/sandbox/extracted/$base_name"
HOST_EXTRACTED_PATH="$(pwd)/extracted/$base_name"

# Check for Docker Compose files and warn about Docker-in-Docker limitations
compose_files_found=false
while IFS= read -r compose_file; do
    compose_files_found=true
    relative_path="${compose_file#extracted/$base_name/}"
done < <(find "extracted/$base_name" \( -name "docker-compose.yml" -o -name "docker-compose.yaml" -o -name "compose.yml" -o -name "compose.yaml" \) 2>/dev/null)

if [ "$compose_files_found" = true ]; then
    print_message "$YELLOW" "⚠️  Docker Compose files detected in the submission"
    print_message "$BLUE" "  Note: Docker-in-Docker has limitations with volume mounts."
    print_message "$BLUE" "  The Docker socket is mounted, but volume paths from inside"
    print_message "$BLUE" "  the container may not be accessible to the host Docker daemon."
    print_message "$BLUE" "  If you encounter mount errors, try running the app directly"
    print_message "$BLUE" "  without Docker (e.g., bundle install && rails server)."
fi

print_message "$GREEN" "✓ Submission extracted successfully"

# Add a simple warning file without breaking permissions
cat >"extracted/$base_name/README_SECURITY_WARNING.txt" <<EOF
⚠️  SECURITY WARNING ⚠️

This directory contains UNTRUSTED code from a submission.

DO NOT run any commands directly in this directory!

Instead, ALWAYS use the Docker container:
  docker-compose run --rm sandbox bash

Then inside the container:
  cd /sandbox/extracted
  yarn install  # or bundle install, npm install, etc.

The files here are for EDITING ONLY in your IDE.
ALL execution must happen in Docker.

To work with this project:
  docker-compose run --rm -w "$EXTRACTED_PROJECT_PATH" sandbox bash
EOF

# Run recursive virus scan on extracted contents
echo
print_message "$YELLOW" "Running deep virus scan on extracted files..."

# First check if Docker is running
if ! check_docker; then
    exit 1
fi

echo -n "  ⏳ Starting deep scan"
if ! docker-compose run --rm sandbox bash -c '
    # Define spinner frames inside container
    SPINNER_FRAMES=("⣾" "⣽" "⣻" "⢿" "⡿" "⣟" "⣯" "⣷")

    # Run recursive ClamAV scan on extracted contents with progress
    echo -e "\r  🔍 Deep scanning extracted files..."

    # Define directories to exclude from deep scanning
    EXCLUDE_DIRS="node_modules vendor .git venv .venv target dist build .pytest_cache __pycache__ .tox __MACOSX bootsnap .next tmp/cache .ruby-lsp"

    # Build find command with exclusions
    FIND_CMD="find /sandbox/extracted/'"$base_name"' -type f"
    for dir in $EXCLUDE_DIRS; do
        FIND_CMD="$FIND_CMD -not -path \"*$dir*\""
    done

    # Count files first for progress indication (excluding dependency directories)
    FILE_COUNT=$(eval "$FIND_CMD" | wc -l)
    echo "  📁 Found $FILE_COUNT project files to scan (excluding dependencies)"

    # Check for dependency manifests and suggest audit commands
    MANIFESTS_FOUND=""
    if [ -n "$(find /sandbox/extracted/'"$base_name"' -name "package.json" -type f 2>/dev/null)" ]; then
        MANIFESTS_FOUND="$MANIFESTS_FOUND npm"
    fi
    if [ -n "$(find /sandbox/extracted/'"$base_name"' -name "Gemfile" -type f 2>/dev/null)" ]; then
        MANIFESTS_FOUND="$MANIFESTS_FOUND ruby"
    fi
    if [ -n "$(find /sandbox/extracted/'"$base_name"' -name "requirements.txt" -type f 2>/dev/null)" ]; then
        MANIFESTS_FOUND="$MANIFESTS_FOUND python"
    fi

    if [ -n "$MANIFESTS_FOUND" ]; then
        echo "  💡 Tip: To audit dependencies after installing them in Docker:"
        if [[ "$MANIFESTS_FOUND" == *"npm"* ]]; then
            echo "     npm audit (after npm install)"
        fi
        if [[ "$MANIFESTS_FOUND" == *"ruby"* ]]; then
            echo "     bundle-audit check (after bundle install)"
        fi
        if [[ "$MANIFESTS_FOUND" == *"python"* ]]; then
            echo "     safety check -r requirements.txt (after pip install)"
        fi
    fi

    # Run scan with verbose output for progress (excluding dependency directories)

    # Build clamscan exclude options
    CLAM_EXCLUDES=""
    for dir in $EXCLUDE_DIRS; do
        CLAM_EXCLUDES="$CLAM_EXCLUDES --exclude-dir=$dir"
    done

    (clamscan --infected --remove=no --recursive $CLAM_EXCLUDES /sandbox/extracted/'"$base_name"' > /tmp/deep_scan 2>&1) &
    SCAN_PID=$!

    # Show progress with spinner
    while kill -0 $SCAN_PID 2>/dev/null; do
        for s in "${SPINNER_FRAMES[@]}"; do
            echo -ne "\r  ⚡ Scanning files $s "
            sleep 0.1
        done
    done
    wait $SCAN_PID
    SCAN_EXIT=$?

    # Check results
    if [ $SCAN_EXIT -eq 0 ]; then
        echo -e "\r  ✅ Deep scan complete - no threats found        "
        exit 0
    else
        if grep -q "FOUND" /tmp/deep_scan 2>/dev/null; then
            echo -e "\r  ❌ Deep scan found infected files!             "
            grep "FOUND" /tmp/deep_scan | head -5
        fi
        exit 1
    fi
'; then
    # Check if the failure was due to Docker issues
    if ! check_docker; then
        print_message "$RED" "Error: Docker connection lost during scan."
        print_message "$RED" "The process cannot continue."
    else
        # This means ClamAV actually detected malware
        print_message "$RED" "⚠️  WARNING: Virus or malware detected in extracted files!"
        print_message "$RED" "The submission contains dangerous code and should not be executed."
    fi

    # Ask if user wants to proceed anyway (for testing purposes)
    echo
    print_message "$YELLOW" "Do you want to proceed anyway? (DANGEROUS - type 'yes' to continue):"
    read -r proceed
    if [ "$proceed" != "yes" ]; then
        rm -rf extracted/*
        exit 1
    fi
    echo
    print_message "$YELLOW" "Proceeding at your own risk..."
fi

print_message "$GREEN" "✓ Deep scan complete - extracted files are clean"

# Optional: Run additional security analysis
echo
print_message "$YELLOW" "Run additional security analysis? (y/n, default: y):"
read -r run_analysis
if [[ -z $run_analysis || $run_analysis =~ ^[Yy]$ || $run_analysis == "yes" ]]; then
    echo
    print_message "$YELLOW" "Running security analysis tools..."

    # Create a timestamp for the report files
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    REPORT_DIR="audit/security_reports/${base_name}_${TIMESTAMP}"
    mkdir -p "$REPORT_DIR"

    docker-compose run --rm sandbox bash -c "
        cd $EXTRACTED_PROJECT_PATH

        # Define spinner frames inside container
        SPINNER_FRAMES=('⣾' '⣽' '⣻' '⢿' '⡿' '⣟' '⣯' '⣷')

        # Create temp directory for reports
        TEMP_DIR=/tmp/security_analysis_$$
        mkdir -p \$TEMP_DIR

        echo '🔍 Running security analysis...'
        echo

        # Python security analysis
        if find . -name '*.py' -type f | head -1 > /dev/null 2>&1; then
            echo -n '  Analyzing Python code with Bandit'
            (bandit -r . -f txt > \$TEMP_DIR/bandit.txt 2>&1) &
            SCAN_PID=\$!

            # Show spinner while analyzing
            while kill -0 \$SCAN_PID 2>/dev/null; do
                for s in \"\${SPINNER_FRAMES[@]}\"; do
                    echo -ne \"\\r  Analyzing Python code with Bandit \$s\"
                    sleep 0.1
                done
            done
            wait \$SCAN_PID

            BANDIT_LINES=\$(wc -l < \$TEMP_DIR/bandit.txt)
            if [ \$BANDIT_LINES -gt 50 ]; then
                echo -e \"\\r  Analyzing Python code with Bandit... ✓ (found \$BANDIT_LINES lines - saved to report)\"
                head -20 \$TEMP_DIR/bandit.txt
                echo
                echo \"    ... output truncated. Full report saved to: audit/security_reports/\"
            else
                echo -e \"\\r  Analyzing Python code with Bandit... ✓                      \"
                cat \$TEMP_DIR/bandit.txt
            fi
            echo

            if [ -f requirements.txt ]; then
                echo -n '  Checking Python dependencies with Safety'
                (safety check -r requirements.txt > \$TEMP_DIR/safety.txt 2>&1) &
                SCAN_PID=\$!

                # Show spinner while checking
                while kill -0 \$SCAN_PID 2>/dev/null; do
                    for s in \"\${SPINNER_FRAMES[@]}\"; do
                        echo -ne \"\\r  Checking Python dependencies with Safety \$s\"
                        sleep 0.1
                    done
                done
                wait \$SCAN_PID

                SAFETY_LINES=\$(wc -l < \$TEMP_DIR/safety.txt)
                if [ \$SAFETY_LINES -gt 30 ]; then
                    echo -e \"\\r  Checking Python dependencies with Safety... ✓ (found \$SAFETY_LINES lines - saved)\"
                    head -10 \$TEMP_DIR/safety.txt
                    echo \"    ... output truncated. Full report saved to: audit/security_reports/\"
                else
                    echo -e \"\\r  Checking Python dependencies with Safety... ✓                      \"
                    cat \$TEMP_DIR/safety.txt
                fi
            else
                echo '  No requirements.txt found - skipping dependency check'
            fi
            echo
        fi

        # Shell script security (excluding __MACOSX metadata)
        if find . -name '*.sh' -type f -not -path '*/__MACOSX/*' | head -1 > /dev/null 2>&1; then
            echo -n '  Analyzing shell scripts with ShellCheck'
            (find . -name '*.sh' -type f -not -path '*/__MACOSX/*' -exec shellcheck {} \; > \$TEMP_DIR/shellcheck.txt 2>&1) &
            SCAN_PID=\$!

            # Show spinner while analyzing
            while kill -0 \$SCAN_PID 2>/dev/null; do
                for s in \"\${SPINNER_FRAMES[@]}\"; do
                    echo -ne \"\\r  Analyzing shell scripts with ShellCheck \$s\"
                    sleep 0.1
                done
            done
            wait \$SCAN_PID

            SHELL_LINES=\$(wc -l < \$TEMP_DIR/shellcheck.txt)
            if [ \$SHELL_LINES -gt 50 ]; then
                echo -e \"\\r  Analyzing shell scripts with ShellCheck... ✓ (found \$SHELL_LINES lines - saved)\"
                head -20 \$TEMP_DIR/shellcheck.txt
                echo \"    ... output truncated. Full report saved to: audit/security_reports/\"
            else
                echo -e \"\\r  Analyzing shell scripts with ShellCheck... ✓                      \"
                cat \$TEMP_DIR/shellcheck.txt
            fi
            echo
        fi

        # Malicious code detection with Semgrep
        # Uses custom rules to detect only code that could harm the host machine
        # (command execution, backdoors, ransomware, etc.) - not general security issues
        echo -n '  Scanning for malicious code patterns'
        (PYTHONWARNINGS="ignore::UserWarning" semgrep --config=/sandbox/config/semgrep-malicious-only.yml --quiet . > \$TEMP_DIR/semgrep.txt 2>&1) &
        SCAN_PID=\$!

        # Show spinner while scanning
        while kill -0 \$SCAN_PID 2>/dev/null; do
            for s in \"\${SPINNER_FRAMES[@]}\"; do
                echo -ne \"\\r  Running Semgrep security patterns \$s\"
                sleep 0.1
            done
        done
        wait \$SCAN_PID

        SEMGREP_LINES=\$(wc -l < \$TEMP_DIR/semgrep.txt)
        if [ \$SEMGREP_LINES -gt 50 ]; then
            echo -e \"\\r  Scanning for malicious code patterns... ✓ (found \$SEMGREP_LINES lines - saved)      \"
            head -20 \$TEMP_DIR/semgrep.txt
            echo \"    ... output truncated. Full report saved to: audit/security_reports/\"
        else
            echo -e \"\\r  Scanning for malicious code patterns... ✓                      \"
            cat \$TEMP_DIR/semgrep.txt
        fi
        echo

        # YARA malware detection
        if [ -d /opt/yara-rules/rules ]; then
            echo -n '  Scanning for malware patterns with YARA'
            (find . -type f \( -name '*.exe' -o -name '*.dll' -o -name '*.jar' -o -name '*.zip' -o -name '*.tar*' \) | while read file; do
                find /opt/yara-rules/rules -name "*.yar" -type f 2>/dev/null | head -20 | xargs -I {} yara {} "\$file" 2>/dev/null
            done > \$TEMP_DIR/yara.txt 2>&1) &
            SCAN_PID=\$!

            # Show spinner while scanning
            while kill -0 \$SCAN_PID 2>/dev/null; do
                for s in \"\${SPINNER_FRAMES[@]}\"; do
                    echo -ne \"\\r  Scanning for malware patterns with YARA \$s\"
                    sleep 0.1
                done
            done
            wait \$SCAN_PID

            # Check if yara.txt has actual detections (not just errors)
            if grep -q "error:" \$TEMP_DIR/yara.txt 2>/dev/null; then
                # YARA had errors
                echo -e \"\\r  Scanning for malware patterns with YARA... ❌ Scan failed (rule parsing error)\"
            elif [ -s \$TEMP_DIR/yara.txt ]; then
                echo -e \"\\r  Scanning for malware patterns with YARA... ⚠️  SUSPICIOUS FILES DETECTED\"
                grep -v "error:" \$TEMP_DIR/yara.txt
            else
                echo -e \"\\r  Scanning for malware patterns with YARA... ✓ No malware patterns detected\"
            fi
        else
            echo '  YARA rules not available - skipping malware pattern scan'
        fi
        echo

        # Copy reports to host
        cp \$TEMP_DIR/* /sandbox/audit/security_reports/${base_name}_${TIMESTAMP}/ 2>/dev/null || true

        # Summary
        echo '═══════════════════════════════════════════════════════════'
        echo '📊 Security Analysis Summary:'
        echo
        [ -f \$TEMP_DIR/bandit.txt ] && echo \"  • Python (Bandit): \$(grep -c 'Issue:' \$TEMP_DIR/bandit.txt 2>/dev/null || echo '0') issues found\"
        [ -f \$TEMP_DIR/safety.txt ] && echo \"  • Dependencies (Safety): \$(grep -c 'vulnerability' \$TEMP_DIR/safety.txt 2>/dev/null || echo '0') vulnerabilities\"
        [ -f \$TEMP_DIR/shellcheck.txt ] && echo \"  • Shell Scripts: \$(grep -c 'SC[0-9]' \$TEMP_DIR/shellcheck.txt 2>/dev/null || echo '0') warnings\"
        [ -f \$TEMP_DIR/semgrep.txt ] && echo \"  • Malicious Patterns: \$(grep -c '❯❱' \$TEMP_DIR/semgrep.txt 2>/dev/null || echo '0') findings\"
        if [ -f \$TEMP_DIR/yara.txt ]; then
            if grep -q "error:" \$TEMP_DIR/yara.txt 2>/dev/null; then
                echo \"  • Malware Patterns: SCAN FAILED\"
            elif [ -s \$TEMP_DIR/yara.txt ]; then
                echo \"  • Malware Patterns: DETECTED - CHECK REPORT\"
            else
                echo \"  • Malware Patterns: 0 findings\"
            fi
        fi
        echo
        echo \"📁 Full reports saved to: audit/security_reports/${base_name}_${TIMESTAMP}/\"
        echo '═══════════════════════════════════════════════════════════'

        # Clean up
        rm -rf \$TEMP_DIR
    " || print_message "$YELLOW" "Some security tools may have encountered issues (this is normal)"

    # Check if reports were created
    if [ -d "$REPORT_DIR" ] && [ "$(ls -A $REPORT_DIR 2>/dev/null)" ]; then
        echo
        print_message "$GREEN" "✓ Security reports saved to: $REPORT_DIR"
    fi
fi

# Show extracted contents
echo
print_message "$BLUE" "Extracted contents:"
find "extracted/$base_name" -maxdepth 2 -type f | head -10

# Ask user what to do next
while true; do
    echo
    print_message "$BLUE" "⚠️  Remember: Edit in your IDE/editor, but run ALL commands in Docker:"
    print_message "$YELLOW" "  docker-compose run --rm -w "$EXTRACTED_PROJECT_PATH" sandbox bash"
    echo
    print_message "$YELLOW" "How would you like to work with the submission?"
    print_message "$YELLOW" "(Note: Editor functionality is beta and may not work as expected)"
    echo "1) Open in VS Code (with Docker extension)"
    echo "2) Open in Cursor (with Docker extension)"
    echo "3) Use Vim in terminal"
    echo "4) Terminal only (no IDE)"
    echo "5) Run a specific command"
    echo "6) Expose additional ports (if needed)"
    echo "7) Exit"
    read -r choice

    case $choice in
    1)
        echo
        print_message "$YELLOW" "Opening VS Code with the extracted submission..."

        # Create VS Code workspace configuration
        mkdir -p "extracted/$base_name/.vscode" 2>/dev/null

        # Get absolute path to the sandbox directory (parent of scripts)
        SANDBOX_DIR="$(cd "$(dirname "$0")/.." && pwd)"

        # Create settings to configure integrated terminal with proper Docker command
        cat >"extracted/$base_name/.vscode/settings.json" <<EOF
{
    "terminal.integrated.defaultProfile.osx": "Docker Sandbox",
    "terminal.integrated.defaultProfile.linux": "Docker Sandbox",
    "terminal.integrated.profiles.osx": {
        "Docker Sandbox": {
            "path": "/bin/bash",
            "args": ["-c", "$SANDBOX_DIR/scripts/launch-sandbox.sh '$EXTRACTED_PROJECT_PATH'"]
        }
    },
    "terminal.integrated.profiles.linux": {
        "Docker Sandbox": {
            "path": "/bin/bash",
            "args": ["-c", "$SANDBOX_DIR/scripts/launch-sandbox.sh '$EXTRACTED_PROJECT_PATH'"]
        }
    },
    "terminal.integrated.automationProfile.osx": {
        "path": "/bin/bash",
        "args": ["-c", "$SANDBOX_DIR/scripts/launch-sandbox.sh '$EXTRACTED_PROJECT_PATH'"]
    }
}
EOF

        # Open VS Code and trigger the terminal task
        if code "./extracted/$base_name" --new-window 2>/dev/null; then
            sleep 2
            # Use AppleScript to open integrated terminal in VS Code
            osascript -e 'tell application "Visual Studio Code" to activate' 2>/dev/null
            osascript -e 'tell application "System Events" to keystroke "`" using {control down}' 2>/dev/null

            print_message "$GREEN" "✓ VS Code opened with Docker terminal"
            print_message "$YELLOW" "The integrated terminal is connected to the Docker container"
            print_message "$YELLOW" "You're working in the isolated environment at $EXTRACTED_PROJECT_PATH"
        else
            print_message "$RED" "VS Code not found. Make sure 'code' command is in PATH"
            print_message "$YELLOW" "Install from VS Code: Shell Command: Install 'code' command in PATH"

            # Fallback: open terminal separately
            echo
            print_message "$YELLOW" "Opening terminal in sandbox..."
            docker-compose run --rm -w "$EXTRACTED_PROJECT_PATH" sandbox bash
        fi
        ;;
    2)
        echo
        print_message "$YELLOW" "Opening Cursor with the extracted submission..."

        # Create Cursor workspace configuration
        mkdir -p "extracted/$base_name/.vscode" 2>/dev/null # Cursor also uses .vscode

        # Get absolute path to the sandbox directory (parent of scripts)
        SANDBOX_DIR="$(cd "$(dirname "$0")/.." && pwd)"

        # Create settings to configure integrated terminal with proper Docker command
        cat >"extracted/$base_name/.vscode/settings.json" <<EOF
{
    "terminal.integrated.defaultProfile.osx": "Docker Sandbox",
    "terminal.integrated.defaultProfile.linux": "Docker Sandbox",
    "terminal.integrated.profiles.osx": {
        "Docker Sandbox": {
            "path": "/bin/bash",
            "args": ["-c", "$SANDBOX_DIR/scripts/launch-sandbox.sh '$EXTRACTED_PROJECT_PATH'"]
        }
    },
    "terminal.integrated.profiles.linux": {
        "Docker Sandbox": {
            "path": "/bin/bash",
            "args": ["-c", "$SANDBOX_DIR/scripts/launch-sandbox.sh '$EXTRACTED_PROJECT_PATH'"]
        }
    },
    "terminal.integrated.automationProfile.osx": {
        "path": "/bin/bash",
        "args": ["-c", "$SANDBOX_DIR/scripts/launch-sandbox.sh '$EXTRACTED_PROJECT_PATH'"]
    }
}
EOF

        # Open Cursor and trigger the terminal task
        if cursor "./extracted/$base_name" --new-window 2>/dev/null; then
            sleep 2
            # Use AppleScript to open integrated terminal in Cursor
            osascript -e 'tell application "Cursor" to activate' 2>/dev/null
            osascript -e 'tell application "System Events" to keystroke "`" using {control down}' 2>/dev/null

            print_message "$GREEN" "✓ Cursor opened with Docker terminal"
            print_message "$YELLOW" "The integrated terminal is connected to the Docker container"
            print_message "$YELLOW" "You're working in the isolated environment at $EXTRACTED_PROJECT_PATH"
        else
            print_message "$RED" "Cursor not found. Make sure 'cursor' command is in PATH"
            print_message "$YELLOW" "Install from Cursor: Shell Command: Install 'cursor' command in PATH"

            # Fallback: open terminal separately
            echo
            print_message "$YELLOW" "Opening terminal in sandbox..."
            docker-compose run --rm -w "$EXTRACTED_PROJECT_PATH" sandbox bash
        fi
        ;;
    3)
        echo
        print_message "$GREEN" "Opening Vim in the sandbox..."
        print_message "$YELLOW" "Note: You are now in the isolated environment with Vim"
        print_message "$YELLOW" "Type ':q' to exit Vim, then 'exit' to leave the sandbox"
        docker-compose run --rm -w "$EXTRACTED_PROJECT_PATH" sandbox bash -c "apt-get update && apt-get install -y vim 2>/dev/null; vim ."
        ;;
    4)
        echo
        print_message "$GREEN" "Opening terminal in sandbox..."
        print_message "$YELLOW" "Note: You are now in the isolated environment"
        print_message "$YELLOW" "The extracted project is in the current directory"
        print_message "$YELLOW" "Type 'exit' to leave the sandbox"
        "$(dirname "$0")/launch-sandbox.sh" "$EXTRACTED_PROJECT_PATH"
        ;;
    5)
        echo
        print_message "$YELLOW" "Enter the command to run:"
        read -r command
        docker-compose run --rm sandbox bash -c "cd $EXTRACTED_PROJECT_PATH && $command"
        ;;
    6)
        print_message "$BLUE" "Opening port exposure tool..."
        "$(dirname "$0")/expose-port.sh"
        ;;
    7)
        print_message "$GREEN" "Exiting..."
        break
        ;;
    *)
        print_message "$RED" "Invalid choice. Please select a valid option (1-7)."
        continue
        ;;
    esac

    # If we successfully ran a command, break the loop
    break
done

print_message "$BLUE" "\n================================================"
print_message "$BLUE" "Session complete. Extracted files remain in ./extracted/"
print_message "$BLUE" "Run 'docker-compose down' to clean up containers"
print_message "$BLUE" "================================================"
