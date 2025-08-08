#!/bin/bash

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
print_message "$BLUE" "================================================"
print_message "$BLUE" "   Thanx Isolated Sandbox - Code Review Tool   "
print_message "$BLUE" "================================================"
echo

# Create necessary directories
mkdir -p submissions extracted

# Prompt for ZIP file path
print_message "$YELLOW" "Enter the path to the submission ZIP file:"
read -r zip_path

# Validate file exists
if [ ! -f "$zip_path" ]; then
    print_message "$RED" "Error: File not found at $zip_path"
    exit 1
fi

# Validate it's a ZIP file
if ! file "$zip_path" | grep -q "Zip archive"; then
    print_message "$RED" "Error: File is not a valid ZIP archive"
    exit 1
fi

# Copy submission to local directory
submission_name=$(basename "$zip_path")
cp "$zip_path" "submissions/$submission_name"

print_message "$GREEN" "✓ File copied to submissions directory"

# Build Docker image if needed
print_message "$YELLOW" "Building/updating Docker environment..."
docker-compose build

# Run virus scan inside Docker
print_message "$YELLOW" "Running virus scan on submission..."
docker-compose run --rm sandbox bash -c "
    # Update virus definitions
    freshclam 2>/dev/null || true
    
    # Run ClamAV scan
    clamscan --infected --remove=no --recursive /sandbox/submissions/$submission_name
"

if [ $? -ne 0 ]; then
    print_message "$RED" "⚠️  WARNING: Virus or malware detected!"
    print_message "$RED" "The submission has been quarantined and will not be extracted."
    
    # Ask if user wants to proceed anyway (for testing purposes)
    print_message "$YELLOW" "Do you want to proceed anyway? (DANGEROUS - type 'yes' to continue):"
    read -r proceed
    if [ "$proceed" != "yes" ]; then
        exit 1
    fi
    print_message "$YELLOW" "Proceeding at your own risk..."
fi

print_message "$GREEN" "✓ Virus scan passed - submission is clean"

# Extract the submission
print_message "$YELLOW" "Extracting submission..."
docker-compose run --rm sandbox bash -c "
    cd /sandbox/extracted
    unzip -q /sandbox/submissions/$submission_name
    echo 'Extraction complete'
    ls -la
"

print_message "$GREEN" "✓ Submission extracted successfully"

# Show extracted contents
print_message "$BLUE" "\nExtracted contents:"
docker-compose run --rm sandbox bash -c "cd /sandbox/extracted && find . -type f -name 'README*' | head -5"

# Ask user what to do next
print_message "$YELLOW" "\nWhat would you like to do?"
echo "1) Open interactive shell in sandbox"
echo "2) Run a specific command"
echo "3) Exit"
read -r choice

case $choice in
    1)
        print_message "$GREEN" "Opening interactive shell in sandbox..."
        print_message "$YELLOW" "Note: You are now in the isolated environment at /sandbox/extracted"
        print_message "$YELLOW" "Type 'exit' to leave the sandbox"
        docker-compose run --rm sandbox bash -c "cd /sandbox/extracted && exec bash"
        ;;
    2)
        print_message "$YELLOW" "Enter the command to run:"
        read -r command
        docker-compose run --rm sandbox bash -c "cd /sandbox/extracted && $command"
        ;;
    3)
        print_message "$GREEN" "Exiting..."
        ;;
    *)
        print_message "$RED" "Invalid choice"
        ;;
esac

print_message "$BLUE" "\n================================================"
print_message "$BLUE" "Session complete. Extracted files remain in ./extracted/"
print_message "$BLUE" "Run 'docker-compose down' to clean up containers"
print_message "$BLUE" "================================================"