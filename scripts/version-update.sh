#!/bin/bash

# Version update script for Thanx Isolated Sandbox
# Usage: ./scripts/version-update.sh [major|minor|patch]

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

# Check if VERSION file exists
if [ ! -f "VERSION" ]; then
    print_message "$RED" "Error: VERSION file not found"
    exit 1
fi

# Get the update type
UPDATE_TYPE=${1:-patch}

# Validate update type
if [[ ! $UPDATE_TYPE =~ ^(major|minor|patch)$ ]]; then
    print_message "$RED" "Error: Invalid update type '$UPDATE_TYPE'"
    print_message "$YELLOW" "Usage: $0 [major|minor|patch]"
    exit 1
fi

# Read current version
CURRENT_VERSION=$(cat VERSION)

# Parse version components
IFS='.' read -r MAJOR MINOR PATCH <<<"$CURRENT_VERSION"

# Validate version format
if [ -z "$MAJOR" ] || [ -z "$MINOR" ] || [ -z "$PATCH" ]; then
    print_message "$RED" "Error: Invalid version format in VERSION file"
    print_message "$YELLOW" "Expected format: X.Y.Z (e.g., 0.1.22)"
    exit 1
fi

# Calculate new version
case $UPDATE_TYPE in
major)
    NEW_MAJOR=$((MAJOR + 1))
    NEW_MINOR=0
    NEW_PATCH=0
    ;;
minor)
    NEW_MAJOR=$MAJOR
    NEW_MINOR=$((MINOR + 1))
    NEW_PATCH=0
    ;;
patch)
    NEW_MAJOR=$MAJOR
    NEW_MINOR=$MINOR
    NEW_PATCH=$((PATCH + 1))
    ;;
esac

NEW_VERSION="$NEW_MAJOR.$NEW_MINOR.$NEW_PATCH"

# Update VERSION file
echo "$NEW_VERSION" >VERSION

# Display version change
echo
print_message "$BLUE" "================================================"
print_message "$BLUE" "   Version Update"
print_message "$BLUE" "================================================"
echo
print_message "$YELLOW" "Previous version: v$CURRENT_VERSION"
print_message "$GREEN" "New version:      v$NEW_VERSION"
echo
print_message "$BLUE" "Update type:      $UPDATE_TYPE"
echo

# Check if we're in a git repository
if [ -d .git ]; then
    print_message "$YELLOW" "Next steps:"
    echo "  1. Review your changes"
    echo "  2. Commit: git add VERSION && git commit -m \"Bump version to v$NEW_VERSION\""
    echo "  3. Tag:    git tag -a v$NEW_VERSION -m \"Release v$NEW_VERSION\""
    echo "  4. Push:   git push && git push --tags"
    echo

    # Ask if user wants to commit and tag
    print_message "$YELLOW" "Would you like to commit and tag this version now? (y/n):"
    read -r response

    if [[ $response =~ ^[Yy]$ ]]; then
        # Stage VERSION file
        git add VERSION

        # Commit
        git commit -m "Bump version to v$NEW_VERSION"

        # Create annotated tag
        git tag -a "v$NEW_VERSION" -m "Release v$NEW_VERSION"

        print_message "$GREEN" "✓ Version committed and tagged as v$NEW_VERSION"
        print_message "$YELLOW" "Don't forget to push: git push && git push --tags"
    else
        print_message "$BLUE" "VERSION file updated. Remember to commit when ready."
    fi
else
    print_message "$GREEN" "✓ VERSION file updated to v$NEW_VERSION"
fi
