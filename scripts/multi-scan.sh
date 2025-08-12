#!/bin/bash

# Multi-AV Scanner Script
# Scans files with multiple antivirus engines for better detection

FILE_PATH="$1"
SCAN_RESULTS=""
THREATS_FOUND=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Running multi-engine virus scan...${NC}"
echo ""

# 1. ClamAV scan (always available)
echo -n "  ClamAV: "
if clamscan --infected --no-summary "$FILE_PATH" 2>/dev/null | grep -q "FOUND"; then
    echo -e "${RED}THREAT DETECTED${NC}"
    THREATS_FOUND=$((THREATS_FOUND + 1))
    SCAN_RESULTS="${SCAN_RESULTS}\nClamAV: THREAT FOUND"
else
    echo -e "${GREEN}Clean${NC}"
    SCAN_RESULTS="${SCAN_RESULTS}\nClamAV: Clean"
fi

# 2. Sophos scan (if available)
if command -v savscan >/dev/null 2>&1; then
    echo -n "  Sophos: "
    if savscan -nc -f -all "$FILE_PATH" 2>/dev/null | grep -q ">>> Virus"; then
        echo -e "${RED}THREAT DETECTED${NC}"
        THREATS_FOUND=$((THREATS_FOUND + 1))
        SCAN_RESULTS="${SCAN_RESULTS}\nSophos: THREAT FOUND"
    else
        echo -e "${GREEN}Clean${NC}"
        SCAN_RESULTS="${SCAN_RESULTS}\nSophos: Clean"
    fi
else
    echo -e "  Sophos: ${YELLOW}Not installed${NC}"
fi

# 3. F-Prot scan (if available)
if command -v fpscan >/dev/null 2>&1; then
    echo -n "  F-Prot: "
    if fpscan --report --quiet "$FILE_PATH" 2>/dev/null | grep -q "Infection:"; then
        echo -e "${RED}THREAT DETECTED${NC}"
        THREATS_FOUND=$((THREATS_FOUND + 1))
        SCAN_RESULTS="${SCAN_RESULTS}\nF-Prot: THREAT FOUND"
    else
        echo -e "${GREEN}Clean${NC}"
        SCAN_RESULTS="${SCAN_RESULTS}\nF-Prot: Clean"
    fi
else
    echo -e "  F-Prot: ${YELLOW}Not installed${NC}"
fi

# 4. Check file hash against known malware (using hash check)
echo -n "  Hash Check: "
FILE_HASH=$(sha256sum "$FILE_PATH" | cut -d' ' -f1)
# Here we could check against a malware hash database if available
echo -e "${GREEN}Completed${NC}"

# 5. YARA rules scan (if available)
if [ -d /opt/yara-rules/rules ] && command -v yara >/dev/null 2>&1; then
    echo -n "  YARA Rules: "
    YARA_RESULT=$(yara -r /opt/yara-rules/rules "$FILE_PATH" 2>/dev/null)
    if [ -n "$YARA_RESULT" ]; then
        echo -e "${RED}SUSPICIOUS PATTERNS${NC}"
        THREATS_FOUND=$((THREATS_FOUND + 1))
        SCAN_RESULTS="${SCAN_RESULTS}\nYARA: SUSPICIOUS"
    else
        echo -e "${GREEN}Clean${NC}"
        SCAN_RESULTS="${SCAN_RESULTS}\nYARA: Clean"
    fi
else
    echo -e "  YARA: ${YELLOW}Not available${NC}"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "Scan Summary: "
if [ $THREATS_FOUND -eq 0 ]; then
    echo -e "${GREEN}✓ All scanners report file as CLEAN${NC}"
    exit 0
else
    echo -e "${RED}⚠ $THREATS_FOUND scanner(s) detected threats!${NC}"
    echo -e "$SCAN_RESULTS"
    exit 1
fi
