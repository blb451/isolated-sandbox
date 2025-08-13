#!/bin/bash
# Filter YARA results based on exclusions file

YARA_RESULT="/tmp/yara_result"
EXCLUSIONS_FILE="/sandbox/config/yara-exclusions-for-code-repos.txt"

# Check if files exist
[ ! -f "$YARA_RESULT" ] && exit 0
[ ! -f "$EXCLUSIONS_FILE" ] && exit 0

# Create temp file for filtered results
TEMP_RESULT="/tmp/yara_result.filtered"
cp "$YARA_RESULT" "$TEMP_RESULT"

# Read exclusions and filter each one
grep -v '^#' "$EXCLUSIONS_FILE" 2>/dev/null | grep -v '^$' | while IFS= read -r rule; do
    # Remove lines starting with this rule name
    grep -v "^$rule " "$TEMP_RESULT" >"$TEMP_RESULT.tmp" 2>/dev/null || true
    mv "$TEMP_RESULT.tmp" "$TEMP_RESULT" 2>/dev/null || true
done

# Replace original with filtered results
mv "$TEMP_RESULT" "$YARA_RESULT" 2>/dev/null || true
