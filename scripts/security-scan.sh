#!/bin/bash

# Standalone security analysis script for extracted submissions

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

echo
print_message "$BLUE" "================================================"
print_message "$BLUE" "   Security Analysis Tool                      "
print_message "$BLUE" "================================================"
echo

# Check if extracted directory exists and has content
if [ ! -d "extracted" ] || [ -z "$(ls -A extracted 2>/dev/null)" ]; then
    print_message "$RED" "Error: No extracted submission found"
    print_message "$YELLOW" "Run ./run-sandbox.sh first to extract a submission"
    exit 1
fi

# Check if container is available
if ! docker-compose config >/dev/null 2>&1; then
    print_message "$RED" "Error: Docker Compose configuration not found"
    exit 1
fi

print_message "$YELLOW" "Running comprehensive security analysis on extracted submission..."
echo

docker-compose run --rm sandbox bash -c "
    cd /sandbox/extracted/*

    echo '========================================'
    echo '       SECURITY ANALYSIS REPORT        '
    echo '========================================'
    echo

    # File overview
    echo '--- Submission Overview ---'
    echo \"Total files: \$(find . -type f | wc -l)\"
    echo \"File types:\"
    find . -type f | sed 's/.*\.//' | sort | uniq -c | sort -nr | head -10
    echo

    # Look for suspicious files
    echo '--- Suspicious Files Check ---'
    suspicious_files=\$(find . -type f \( -name '*.exe' -o -name '*.dll' -o -name '*.bat' -o -name '*.cmd' -o -name '*.scr' -o -name '*.pif' \) 2>/dev/null)
    if [ -n \"\$suspicious_files\" ]; then
        echo \"⚠️  Found potentially suspicious files:\"
        echo \"\$suspicious_files\"
    else
        echo \"✓ No obviously suspicious file types found\"
    fi
    echo

    # Python security analysis
    python_files=\$(find . -name '*.py' -type f | head -1)
    if [ -n \"\$python_files\" ]; then
        echo '--- Python Security Analysis ---'
        echo \"Found Python files, running Bandit...\"
        bandit -r . -f txt 2>/dev/null | head -50 || echo 'Bandit analysis completed'
        echo

        echo \"Checking Python dependencies...\"
        if [ -f requirements.txt ]; then
            echo \"Found requirements.txt, checking with Safety...\"
            safety check -r requirements.txt 2>/dev/null || echo 'Safety check completed'
        elif [ -f Pipfile ]; then
            echo \"Found Pipfile, checking with Safety...\"
            safety check 2>/dev/null || echo 'Safety check completed'
        elif [ -f pyproject.toml ]; then
            echo \"Found pyproject.toml (Poetry/PEP 518 project)\"
        else
            echo \"No Python dependency files found\"
        fi
        echo
    fi

    # JavaScript/Node.js analysis
    js_files=\$(find . -name '*.js' -o -name '*.ts' -o -name '*.jsx' -o -name '*.tsx' | head -1)
    if [ -n \"\$js_files\" ]; then
        echo '--- JavaScript/TypeScript Analysis ---'
        echo \"Found JS/TS files\"
        if [ -f package.json ]; then
            echo \"Found package.json:\"
            if command -v jq >/dev/null 2>&1; then
                jq '.dependencies // {}, .devDependencies // {}' package.json 2>/dev/null | head -20
            else
                grep -A 20 -E '\"dependencies\"|\"devDependencies\"' package.json | head -20
            fi
        fi
        echo
    fi

    # Ruby analysis
    ruby_files=\$(find . -name '*.rb' | head -1)
    if [ -n \"\$ruby_files\" ]; then
        echo '--- Ruby Analysis ---'
        echo \"Found Ruby files\"
        if [ -f Gemfile ]; then
            echo \"Found Gemfile:\"
            head -30 Gemfile
        fi
        echo
    fi

    # Shell script analysis
    shell_files=\$(find . -name '*.sh' -o -name '*.bash' -o -name '*.zsh' | head -1)
    if [ -n \"\$shell_files\" ]; then
        echo '--- Shell Script Security (ShellCheck) ---'
        find . -name '*.sh' -type f -exec echo \"Analyzing: {}\" \; -exec shellcheck {} \; 2>/dev/null
        echo
    fi

    # General security patterns with Semgrep
    echo '--- Code Security Patterns (Semgrep) ---'
    echo \"Running Semgrep security rules...\"
    semgrep --config=auto --quiet --json . 2>/dev/null | head -100 || echo 'Semgrep completed'
    echo

    # YARA malware detection
    echo '--- Advanced Malware Detection (YARA) ---'
    if [ -d /opt/yara-rules/rules ]; then
        echo \"Running YARA rules against binary/archive files...\"
        find . -type f \( -name '*.exe' -o -name '*.dll' -o -name '*.jar' -o -name '*.zip' -o -name '*.tar*' -o -name '*.gz' \) -exec echo \"Scanning: {}\" \; -exec yara -r /opt/yara-rules/rules {} \; 2>/dev/null || echo 'YARA scan completed'
    else
        echo \"YARA rules not available\"
    fi
    echo

    # File permissions analysis
    echo '--- File Permissions Analysis ---'
    echo \"Executable files:\"
    find . -type f -perm -111 | head -20
    echo

    # Hidden files check
    echo '--- Hidden Files Check ---'
    hidden_files=\$(find . -name '.*' -type f | grep -v '.git' | head -10)
    if [ -n \"\$hidden_files\" ]; then
        echo \"Found hidden files:\"
        echo \"\$hidden_files\"
    else
        echo \"No concerning hidden files found\"
    fi
    echo

    echo '========================================'
    echo '       ANALYSIS COMPLETE               '
    echo '========================================'
    echo \"📊 Review the above results for potential security concerns\"
    echo \"🔍 Manual code review is still recommended\"
    echo \"⚠️  This analysis doesn't replace human judgment\"
"

echo
print_message "$GREEN" "Security analysis complete!"
print_message "$YELLOW" "Results are advisory only - manual review is still essential"
