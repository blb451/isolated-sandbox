#!/bin/bash

# This is a wrapper for pre-commit that automatically stages fixed files
# Install this by running: make setup-hooks

# Run pre-commit hooks
pre-commit run

EXIT_CODE=$?

# If pre-commit made changes (exit code 1), add the changes and continue
if [ $EXIT_CODE -eq 1 ]; then
    # Check if there are actually unstaged changes (meaning pre-commit fixed something)
    if ! git diff --exit-code --quiet; then
        echo ""
        echo "✨ Pre-commit hooks fixed some issues. Auto-staging the changes..."

        # Get list of files that were originally staged
        STAGED_FILES=$(git diff --name-only --cached)

        # Re-add only the files that were originally staged (to avoid adding unrelated changes)
        if [ -n "$STAGED_FILES" ]; then
            echo "$STAGED_FILES" | xargs git add
        fi

        echo "📝 Fixed files have been staged. Running pre-commit again to verify..."
        echo ""

        # Run pre-commit again to verify everything passes now
        pre-commit run
        EXIT_CODE=$?

        if [ $EXIT_CODE -eq 0 ]; then
            echo ""
            echo "✅ All checks passed! Proceeding with commit..."
        fi
    else
        echo ""
        echo "❌ Pre-commit checks failed. Please fix the issues and try again."
    fi
fi

exit $EXIT_CODE
