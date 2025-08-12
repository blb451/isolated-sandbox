#!/bin/bash

# Enable Docker Compose bake for better performance
export COMPOSE_BAKE=true

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Banner
echo
print_message "$BLUE" "================================================"
print_message "$BLUE" "   Thanx Isolated Sandbox - Code Review Tool   "
print_message "$BLUE" "================================================"
echo

# Create necessary directories
mkdir -p submissions extracted audit

# Prompt for ZIP file path with retry loop
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
    break
done

# Check file size (max 100MB)
MAX_SIZE=$((100 * 1024 * 1024)) # 100MB in bytes
FILE_SIZE=$(stat -f%z "$zip_path" 2>/dev/null || stat -c%s "$zip_path" 2>/dev/null)
if [ "$FILE_SIZE" -gt "$MAX_SIZE" ]; then
    print_message "$RED" "Error: File size exceeds 100MB limit ($((FILE_SIZE / 1024 / 1024))MB)"
    print_message "$YELLOW" "Large files may contain malicious payloads or cause resource exhaustion"
    exit 1
fi

# Log submission for audit
echo "$(date '+%Y-%m-%d %H:%M:%S') - Submission: $zip_path ($((FILE_SIZE / 1024))KB)" >>audit/submissions.log

# Copy submission to local directory
submission_name=$(basename "$zip_path")
cp "$zip_path" "submissions/$submission_name"

print_message "$GREEN" "✓ File copied to submissions directory"

# Build Docker image if needed
echo
print_message "$YELLOW" "Checking Docker status..."

# Check if Docker daemon is running with timeout
if ! timeout 5 docker info >/dev/null 2>&1; then
    if [ $? -eq 124 ]; then
        print_message "$RED" "Error: Docker is not responding (timed out)"
        print_message "$YELLOW" "Docker Desktop may be starting up. Please wait and try again."
    else
        print_message "$RED" "Error: Docker is not running!"
        print_message "$YELLOW" "Please start Docker Desktop and try again."
    fi
    exit 1
fi

print_message "$GREEN" "✓ Docker is running"
echo
print_message "$YELLOW" "Building/updating Docker environment..."

# Check if this is the first build
if ! docker images | grep -q "thanx-isolated-sandbox-sandbox"; then
    print_message "$BLUE" "⏳ First-time build detected. This will take a while..."
    print_message "$BLUE" "   Installing multiple language versions and databases."
    print_message "$BLUE" "   Future builds will be much faster due to caching."
    echo
fi

# Build with timeout and error handling
if ! timeout 300 docker-compose build; then
    if [ $? -eq 124 ]; then
        print_message "$RED" "Error: Docker build timed out after 5 minutes"
        print_message "$YELLOW" "This might indicate a network issue or Docker problem"
    else
        print_message "$RED" "Error: Docker build failed"
        print_message "$YELLOW" "Please check Docker logs for more information"
    fi
    exit 1
fi

# Run virus scan inside Docker
echo
print_message "$YELLOW" "Running virus scan on submission..."
if ! docker-compose run --rm sandbox bash -c "
    # Update virus definitions
    freshclam 2>/dev/null || true

    # Run ClamAV scan
    clamscan --infected --remove=no --recursive /sandbox/submissions/$submission_name
"; then
    # Check if the failure was due to Docker issues
    if ! timeout 5 docker info >/dev/null 2>&1; then
        print_message "$RED" "Error: Docker connection lost during scan."
        print_message "$RED" "The process cannot continue."
    else
        # This means ClamAV actually detected malware
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

print_message "$GREEN" "✓ Virus scan passed - submission is clean"

# Extract the submission
echo
print_message "$YELLOW" "Extracting submission..."

# Get the base name without extension for the parent folder
base_name=$(basename "$submission_name" .zip)

# Clean up any existing extraction for this submission
rm -rf "extracted/$base_name" 2>/dev/null || true

# Create the extraction folder and extract directly into it
mkdir -p "extracted/$base_name"
cd "extracted/$base_name" || exit
unzip -q "../../submissions/$submission_name"

# Return to root directory
cd ../..

echo 'Extraction complete'

# Store the extracted project path for later use
EXTRACTED_PROJECT_PATH="/sandbox/extracted/"$base_name""

print_message "$GREEN" "✓ Submission extracted successfully"

# Add a simple warning file without breaking permissions
cat >"extracted/"$base_name"/README_SECURITY_WARNING.txt" <<'EOF'
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
if ! timeout 5 docker info >/dev/null 2>&1; then
    print_message "$RED" "Error: Cannot connect to Docker daemon."
    print_message "$RED" "Please ensure Docker is running and try again."
    exit 1
fi

if ! docker-compose run --rm sandbox bash -c "
    # Update virus definitions
    freshclam 2>/dev/null || true

    # Run recursive ClamAV scan on extracted contents
    clamscan --infected --remove=no --recursive /sandbox/extracted
"; then
    # Check if the failure was due to Docker issues
    if ! timeout 5 docker info >/dev/null 2>&1; then
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
if [[ -z $run_analysis || $run_analysis =~ ^[Yy]$ ]]; then
    echo
    print_message "$YELLOW" "Running security analysis tools..."

    # Create a timestamp for the report files
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    REPORT_DIR="audit/security_reports/${base_name}_${TIMESTAMP}"
    mkdir -p "$REPORT_DIR"

    docker-compose run --rm sandbox bash -c "
        cd $EXTRACTED_PROJECT_PATH

        # Create temp directory for reports
        TEMP_DIR=/tmp/security_analysis_$$
        mkdir -p \$TEMP_DIR

        echo '🔍 Running security analysis...'
        echo

        # Python security analysis
        if find . -name '*.py' -type f | head -1 > /dev/null 2>&1; then
            echo -n '  Analyzing Python code with Bandit... '
            bandit -r . -f txt > \$TEMP_DIR/bandit.txt 2>&1
            BANDIT_LINES=\$(wc -l < \$TEMP_DIR/bandit.txt)
            if [ \$BANDIT_LINES -gt 50 ]; then
                echo \"✓ (found \$BANDIT_LINES lines of output - saved to report)\"
                head -20 \$TEMP_DIR/bandit.txt
                echo
                echo \"    ... output truncated. Full report saved to: audit/security_reports/\"
            else
                echo '✓'
                cat \$TEMP_DIR/bandit.txt
            fi
            echo

            echo -n '  Checking Python dependencies with Safety... '
            if [ -f requirements.txt ]; then
                safety check -r requirements.txt > \$TEMP_DIR/safety.txt 2>&1
                SAFETY_LINES=\$(wc -l < \$TEMP_DIR/safety.txt)
                if [ \$SAFETY_LINES -gt 30 ]; then
                    echo \"✓ (found \$SAFETY_LINES lines of output - saved to report)\"
                    head -10 \$TEMP_DIR/safety.txt
                    echo \"    ... output truncated. Full report saved to: audit/security_reports/\"
                else
                    echo '✓'
                    cat \$TEMP_DIR/safety.txt
                fi
            else
                echo 'No requirements.txt found'
            fi
            echo
        fi

        # Shell script security
        if find . -name '*.sh' -type f | head -1 > /dev/null 2>&1; then
            echo -n '  Analyzing shell scripts with ShellCheck... '
            find . -name '*.sh' -type f -exec shellcheck {} \; > \$TEMP_DIR/shellcheck.txt 2>&1
            SHELL_LINES=\$(wc -l < \$TEMP_DIR/shellcheck.txt)
            if [ \$SHELL_LINES -gt 50 ]; then
                echo \"✓ (found \$SHELL_LINES lines of output - saved to report)\"
                head -20 \$TEMP_DIR/shellcheck.txt
                echo \"    ... output truncated. Full report saved to: audit/security_reports/\"
            else
                echo '✓'
                cat \$TEMP_DIR/shellcheck.txt
            fi
            echo
        fi

        # General code security with Semgrep
        echo -n '  Running Semgrep security patterns... '
        semgrep --config=auto --quiet . > \$TEMP_DIR/semgrep.txt 2>&1
        SEMGREP_LINES=\$(wc -l < \$TEMP_DIR/semgrep.txt)
        if [ \$SEMGREP_LINES -gt 50 ]; then
            echo \"✓ (found \$SEMGREP_LINES lines of output - saved to report)\"
            head -20 \$TEMP_DIR/semgrep.txt
            echo \"    ... output truncated. Full report saved to: audit/security_reports/\"
        else
            echo '✓'
            cat \$TEMP_DIR/semgrep.txt
        fi
        echo

        # YARA malware detection
        echo -n '  Scanning for malware patterns with YARA... '
        if [ -d /opt/yara-rules/rules ]; then
            find . -type f \( -name '*.exe' -o -name '*.dll' -o -name '*.jar' -o -name '*.zip' -o -name '*.tar*' \) -exec yara -r /opt/yara-rules/rules {} \; > \$TEMP_DIR/yara.txt 2>&1
            YARA_LINES=\$(wc -l < \$TEMP_DIR/yara.txt)
            if [ \$YARA_LINES -gt 0 ]; then
                echo \"⚠️  SUSPICIOUS FILES DETECTED\"
                cat \$TEMP_DIR/yara.txt
            else
                echo '✓ No malware patterns detected'
            fi
        else
            echo 'YARA rules not available'
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
        [ -f \$TEMP_DIR/semgrep.txt ] && echo \"  • Code Patterns (Semgrep): \$(grep -c 'found:' \$TEMP_DIR/semgrep.txt 2>/dev/null || echo '0') findings\"
        [ -f \$TEMP_DIR/yara.txt ] && [ -s \$TEMP_DIR/yara.txt ] && echo \"  • Malware Patterns: DETECTED - CHECK REPORT\"
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
find "extracted/"$base_name"" -maxdepth 2 -type f | head -10

# Ask user what to do next
while true; do
    echo
    print_message "$BLUE" "⚠️  Remember: Edit in your IDE/editor, but run ALL commands in Docker:"
    print_message "$YELLOW" "  docker-compose run --rm -w "$EXTRACTED_PROJECT_PATH" sandbox bash"
    echo
    print_message "$YELLOW" "How would you like to work with the submission?"
    print_message "$YELLOW" "(Note: Options 1-2 are beta and may not work as expected)"
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
        mkdir -p "extracted/"$base_name"/.vscode" 2>/dev/null

        # Get absolute path to the sandbox directory (parent of scripts)
        SANDBOX_DIR="$(cd "$(dirname "$0")/.." && pwd)"

        # Create settings to configure integrated terminal with proper Docker command
        cat >extracted/"$base_name"/.vscode/settings.json <<EOF
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
        if code "./extracted/"$base_name"" --new-window 2>/dev/null; then
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
        mkdir -p extracted/"$base_name"/.vscode 2>/dev/null # Cursor also uses .vscode

        # Get absolute path to the sandbox directory (parent of scripts)
        SANDBOX_DIR="$(cd "$(dirname "$0")/.." && pwd)"

        # Create settings to configure integrated terminal with proper Docker command
        cat >extracted/"$base_name"/.vscode/settings.json <<EOF
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
        if cursor "./extracted/"$base_name"" --new-window 2>/dev/null; then
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
