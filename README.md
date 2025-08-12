# Thanx Isolated Sandbox

A secure Docker-based environment for reviewing and running untrusted code submissions (take-home challenges, etc.) with comprehensive virus scanning and complete isolation from your host system.

## 🔒 Security Features

- **Multi-Layer Virus Scanning**: ClamAV + YARA rules for comprehensive malware detection
- **Complete Isolation**: All code execution happens inside Docker containers
- **No Host Access**: Submissions cannot access your host filesystem
- **Network Control**: Isolated network environment (configurable)
- **Resource Limits**: Container resource constraints prevent DoS attacks
- **Docker-in-Docker**: Safe support for submissions that use Docker
- **Static Analysis Suite**: Built-in security scanning with multiple tools:
  - **Bandit**: Python security issue detection
  - **Safety**: Python dependency vulnerability scanning
  - **Semgrep**: Multi-language security pattern detection
  - **ShellCheck**: Shell script security analysis
  - **YARA**: Advanced malware pattern matching
- **Audit Logging**: All submissions tracked in audit logs

> **💡 Pro Tip**: For maximum security confidence, consider uploading the ZIP file to [VirusTotal](https://www.virustotal.com) before processing. VirusTotal scans with 70+ antivirus engines and provides comprehensive threat analysis.

## 🛠 Prerequisites

### For Using the Sandbox
- **Docker Desktop** installed and running
- **Unix-like environment** (macOS/Linux)
- **(Optional)** VS Code or Cursor with Docker extension for IDE integration

### For Development/Contributing
- All of the above, plus:
- **shfmt** - Shell script formatter
- **shellcheck** - Shell script linter
- **pre-commit** - Git hook framework
- **make** - Build automation (usually pre-installed)

## 📦 Installation

### Quick Setup (End Users)

1. **Clone and setup:**
   ```bash
   git clone <repo-url>
   cd thanx-isolated-sandbox
   chmod +x scripts/*.sh
   ```

2. **Test the installation:**
   ```bash
   scripts/run-sandbox.sh
   # Use the included example-app.zip to test
   ```
   > **⚠️ Note:** The script will automatically build the Docker environment on first run. The initial build takes a while as it installs multiple language versions and databases. Subsequent runs use Docker's cache and are much faster.

### Development Setup (Contributors)

If you want to contribute to this repository:

1. **Clone and install dev dependencies:**
   ```bash
   git clone <repo-url>
   cd thanx-isolated-sandbox
   make install
   ```

2. **Setup pre-commit hooks:**
   ```bash
   make setup-hooks
   ```

3. **Run formatting and linting:**
   ```bash
   make format  # Format shell scripts
   make lint    # Run shellcheck
   ```

4. **Test your changes:**
   ```bash
   make test    # Run basic functionality tests
   ```

#### Development Requirements
- **shfmt**: Shell script formatter
- **shellcheck**: Shell script linter
- **pre-commit**: Git hook framework

Install on macOS:
```bash
brew install shfmt shellcheck pre-commit
```

Install on Ubuntu/Debian:
```bash
sudo apt-get install shellcheck
# Install shfmt and pre-commit via other methods
```

## 🚀 Usage

### Basic Workflow

1. **Start the sandbox**:
   ```bash
   # Interactive mode (prompts for ZIP file)
   scripts/run-sandbox.sh

   # Single ZIP file (direct processing)
   scripts/run-sandbox.sh submission.zip

   # Multiple ZIP files (merged extraction)
   scripts/run-sandbox.sh frontend.zip backend.zip
   ```

2. **If using interactive mode, provide the submission ZIP file path(s)** when prompted:
   ```
   Enter the path to the submission ZIP file:
   ./example-app.zip

   Do you have a second ZIP file to merge? (e.g., frontend + backend)
   Press Enter to skip, or enter the path to the second ZIP file:
   [Press Enter to continue with single ZIP, or enter path like ./backend.zip]
   ```
   - First ZIP is required, second ZIP is optional
   - Press Enter to skip the second ZIP and continue with just one
   - Both ZIPs will be extracted to the same folder if provided
   - Type 'quit' to exit at any time during first prompt
   - Supports absolute and relative paths

3. **Wait for security scanning** - The system will:
   - Copy the ZIP to an isolated location
   - Run ClamAV virus scanning
   - Optionally run static analysis (Bandit, Semgrep, etc.)
   - Only proceed if scans pass

4. **Choose your working environment**:
   - **VS Code**: Opens locally but executes in Docker
   - **Cursor**: Opens locally but executes in Docker
   - **Vim**: Runs completely inside the container
   - **Terminal only**: Direct bash access in the container
   - **Run specific command**: Execute a single command
   - **Exit**: Leave without opening the environment

### IDE Integration

When selecting VS Code or Cursor:
1. The IDE opens with the extracted files
2. Use the integrated terminal to run commands in the container:
   ```bash
   docker-compose run --rm -w /sandbox/extracted sandbox bash
   ```
3. Or use the Docker extension to attach to the `thanx-sandbox` container

### Working with Different Submission Types

#### Node.js/JavaScript Projects
```bash
# Inside the container
npm install
npm start
# or
yarn install
yarn dev
```

#### Ruby/Rails Projects
```bash
# Inside the container
bundle install
rails db:create db:migrate db:seed
rails server
```

#### Python Projects
```bash
# Inside the container
pip install -r requirements.txt
python app.py
```

#### Projects with Docker
```bash
# Docker-in-Docker is supported
docker-compose up
```

#### Multi-Component Projects (Frontend + Backend)
When processing multiple ZIP files (e.g., separate frontend and backend archives):
```bash
# Process both ZIPs into a single extraction folder
scripts/run-sandbox.sh frontend.zip backend.zip

# The contents of both ZIPs will be merged into extracted/combined_[timestamp]/
# For example:
#   frontend.zip contains: /frontend/src, /frontend/package.json
#   backend.zip contains: /backend/api, /backend/requirements.txt
# Result: extracted/combined_20241212_143022/
#         ├── frontend/
#         │   ├── src/
#         │   └── package.json
#         └── backend/
#             ├── api/
#             └── requirements.txt
```

## 📂 Directory Structure

```
thanx-isolated-sandbox/
├── scripts/                    # Shell scripts
│   ├── run-sandbox.sh         # Main execution script
│   ├── cleanup.sh            # Cleanup utility with progress indicators
│   ├── expose-port.sh        # Dynamic port exposure tool
│   └── security-scan.sh      # Comprehensive security analysis tool
├── config/                     # Configuration files
│   ├── docker-compose.yml    # Container orchestration
│   └── Dockerfile            # Container image definition
├── docs/                      # Documentation (future)
├── docker-compose.yml         # Symlink to config/docker-compose.yml
├── Dockerfile                 # Symlink to config/Dockerfile
├── Makefile                   # Development tasks
├── .pre-commit-config.yaml    # Pre-commit hooks configuration
├── example-app.zip            # Example submission file
├── submissions/               # Quarantined ZIP files (gitignored)
├── extracted/                 # Extracted code (gitignored)
├── audit/                     # Security audit logs (gitignored)
└── README.md                 # This file
```

### Script Organization
- **scripts/**: Contains all shell script implementations
- **config/**: Docker and configuration files
- **Symlinks**: Docker files are symlinked to root for `docker-compose` compatibility

## 🔧 How It Works

### 1. Submission Intake
- ZIP file is copied to `submissions/` directory
- Original file remains untouched
- Path sanitization prevents directory traversal

### 2. Virus Scanning
- ClamAV scans the ZIP before extraction
- Updated virus definitions via `freshclam`
- Blocks extraction if threats detected
- Optional override for testing (use with extreme caution)

### 3. Extraction & Cleanup
- ZIP(s) extracted to `extracted/` directory
- Single ZIP: extracted to `extracted/{base_name}/`
- Multiple ZIPs: merged into `extracted/combined_{timestamp}/`
- Nested paths (e.g., `Users/Me/Desktop/...`) are flattened
- Project files moved to root of extraction directory
- Clean workspace ready for review

### 4. Isolated Execution
- All commands run inside Ubuntu 22.04 container
- Multiple language versions via asdf:
  - Node.js: 22.0.0, 23.6.1, 23.10.0, latest
  - Ruby: 2.7.5, 2.7.7, 3.1.4, 3.2.0, 3.2.2, 3.3.0, latest
  - Python: 3.10.13, 3.11.9, latest
- Pre-installed databases: PostgreSQL, MySQL/MariaDB, Redis, SQLite, Memcached
- Database management via `db` command
- Version switching via `versions` command
- Network access for package installation
- Host filesystem completely protected

### 5. Development Experience
- IDE opens on host for familiar editing
- All execution happens in container
- Terminal commands routed through Docker
- File changes sync via volume mounts
- Extracted files are organized in `extracted/{project-name}/` folders

## 🌐 Port Management

The sandbox exposes common development ports and allows dynamic port exposure:

### Pre-configured Ports:
- **3000** - Rails server, Express apps
- **5173** - Vite development server
- **8080** - Generic web servers

### Exposing Additional Ports:
If your application runs on a different port (e.g., Next.js on 4000, Django on 8000):

```bash
# Option 1: From the main menu
scripts/run-sandbox.sh
# Select "6) Expose additional ports"

# Option 2: Direct command
scripts/expose-port.sh
# Follow prompts to expose container port to host
```

## 🗄️ Database Management

The sandbox includes a comprehensive database management system:

### Available Databases:
- **SQLite3** - Embedded database, no server needed
- **PostgreSQL 14** - Full-featured relational database
- **MySQL/MariaDB** - Popular relational database
- **Redis** - In-memory data structure store
- **Memcached** - Memory caching system

### Database Commands:
```bash
# Inside the container
db start postgres     # Start PostgreSQL
db start mysql        # Start MySQL/MariaDB
db start redis        # Start Redis
db start all          # Start all databases
db stop all           # Stop all databases
db status             # Check database statuses
db create sqlite app.db  # Create SQLite database
```"

## 🔄 Version Management

Switch between multiple language versions using asdf:

```bash
# Inside the container
versions              # Show all available versions

# Set for current directory
asdf set nodejs 20.0.0
asdf set ruby 3.2.2
asdf set python 3.11.9

# Set global default
asdf global nodejs 22.0.0
asdf global ruby 2.7.7
```

## ⚙️ Configuration

### Customizing the Environment

Edit `Dockerfile` to add tools or languages:
```dockerfile

# Add Go support
RUN apt-get update && apt-get install -y golang-go

# Add Rust support
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
```

### Adjusting Security Settings

Edit `docker-compose.yml` for different security levels:
```yaml
# Stricter isolation (no network)
network_mode: "none"

# Remove Docker socket access
# volumes:
#   - /var/run/docker.sock:/var/run/docker.sock
```

## 🔍 Security Analysis

The sandbox includes comprehensive security analysis tools that run automatically (optional) or on-demand:

### Built-in Security Tools:
- **ClamAV**: Virus and malware detection
- **YARA**: Advanced malware pattern matching
- **Bandit**: Python security vulnerability scanner
- **Safety**: Python dependency vulnerability checker
- **Semgrep**: Multi-language security pattern detection
- **ShellCheck**: Shell script security analysis

### Running Security Analysis:

#### During Initial Scan (Automatic):
The main script will prompt to run additional security analysis after virus scanning.

#### Manual Analysis:
```bash
# Comprehensive security report
scripts/security-scan.sh

# Or run specific tools inside container (adjust path to your project)
docker-compose run --rm sandbox bash
bandit -r /sandbox/extracted/example-app          # Python security
safety check -r requirements.txt                  # Python dependencies
semgrep --config=auto /sandbox/extracted/example-app  # General patterns
shellcheck /sandbox/extracted/example-app/*.sh    # Shell scripts
```

#### Analysis Output:
- File type overview and suspicious file detection
- Language-specific security issues
- Dependency vulnerability reports
- Code pattern analysis
- Permission and hidden file checks

## 🧹 Cleanup

### Interactive Cleanup Tool:
```bash
scripts/cleanup.sh
```

Features:
- Interactive menu with animated progress indicators
- Remove extracted files only
- Remove submission ZIPs only
- Clean container logs and temp files
- Full reset with 30-second timeout protection
- Remove old files (>7 days)
- Shows disk usage after cleanup

### Manual cleanup:
```bash
# Remove extracted files
rm -rf extracted/*

# Remove submission ZIPs
rm -rf submissions/*

# Stop containers
docker-compose down

# Full cleanup
docker-compose down --rmi all --volumes
```

## ⚠️ Security Limitations: What This Doesn't Cover

**This tool provides strong isolation but is NOT bulletproof.** Understand these limitations:

### 🚨 Container Escape Risks
- **Kernel vulnerabilities**: Containers share the host kernel - kernel exploits could break out
- **Docker daemon exploits**: If Docker itself has vulnerabilities
- **Privileged operations**: Some operations require elevated permissions
- **Resource exhaustion**: Malicious code could still impact host performance

### 🚨 Volume Mount Risks
- **File system access**: The `extracted/` directory is shared with your host
- **Malware persistence**: Files written to `extracted/` exist on your Mac
- **Symlink attacks**: Malicious symlinks could potentially access host files
- **Path traversal**: Sophisticated ZIP bombs or path traversal attempts

### 🚨 Network-based Attacks
- **Data exfiltration**: Code can make HTTP requests (unless network disabled)
- **Command & control**: Malware could communicate with external servers
- **Port scanning**: Internal network reconnaissance from container
- **DNS poisoning**: Container DNS queries go through host system

### 🚨 Side-channel Attacks
- **Timing attacks**: Measuring execution times across container boundary
- **Resource monitoring**: Observing host CPU/memory usage patterns
- **Covert channels**: Using legitimate features for unauthorized communication

## ⚠️ Important Security Notes

1. **Never disable virus scanning** for real submissions
2. **Don't mount sensitive host directories** into the container
3. **Review extraction directory** before running any commands
4. **Use network isolation** for highly suspicious submissions
5. **Regular updates**: Keep Docker, ClamAV definitions, and this tool updated
6. **Air-gapped systems**: For truly malicious code, use isolated VMs
7. **Backup important data** before analyzing suspicious submissions

## 🐛 Troubleshooting

### Docker not running
```
Cannot connect to the Docker daemon at unix:///...
```
**Solution**: Start Docker Desktop

### Build failures
```
failed to solve: process "/bin/sh -c ..." did not complete
```
**Solution**: Check internet connection, try `docker-compose build --no-cache`

### Permission issues
```
Permission denied
```
**Solution**: Ensure script is executable: `chmod +x run-sandbox.sh`

### VS Code/Cursor command not found
**Solution**: Install command line tools from the IDE:
- VS Code: CMD+Shift+P → "Shell Command: Install 'code' command"
- Cursor: CMD+Shift+P → "Shell Command: Install 'cursor' command"

## 🚀 Quick Start

### First Time Setup
1. **Test with example**: `scripts/run-sandbox.sh` and use `./example-app.zip`
2. **Wait for build**: Initial build takes a while (installs multiple language versions)
3. **Choose terminal**: Select option 4 for terminal access
4. **Test it works**: Inside container, run `ls`, `node -v`, `ruby -v`

### Daily Usage
1. **Get ZIP file(s)** from candidate/submission
2. **Run sandbox**:
   - Interactive: `scripts/run-sandbox.sh` (then enter path)
   - Single ZIP: `scripts/run-sandbox.sh submission.zip`
   - Multiple ZIPs: `scripts/run-sandbox.sh frontend.zip backend.zip`
3. **Choose editor**: VS Code, Cursor, or terminal
4. **Work safely**: All commands run in isolated container
5. **Cleanup**: `scripts/cleanup.sh` when done

## 📝 Example Session

```bash
$ scripts/run-sandbox.sh
================================================
   Thanx Isolated Sandbox - Code Review Tool
================================================

Enter the path to the submission ZIP file:
./example-app.zip
✓ File copied to submissions directory
Building/updating Docker environment...
✓ Build complete
Running virus scan on submission...
✓ Virus scan passed - submission is clean
Extracting submission...
✓ Submission extracted successfully

How would you like to work with the submission?
(Note: Options 1-2 are beta and may not work as expected)
1) Open in VS Code (with Docker extension)
2) Open in Cursor (with Docker extension)
3) Use Vim in terminal
4) Terminal only (no IDE)
5) Run a specific command
6) Expose additional ports (if needed)
7) Exit
> 4

Opening terminal in sandbox...
Note: You are now in the isolated environment
The extracted project is in the current directory
Type 'exit' to leave the sandbox

root@docker:/sandbox/extracted/example-app# ls
README.md  backend/  frontend/  docker-compose.yml

root@docker:/sandbox/extracted/example-app# cd backend && bundle install
...
root@docker:/sandbox/extracted/example-app/backend# rails s
...
```

## 🤝 Contributing

Contributions are welcome! This project uses:
- **Shell script standards**: Follow ShellCheck recommendations
- **Formatting**: Use `shfmt` for consistent formatting
- **Testing**: Test changes with the example app
- **Pre-commit hooks**: Automatic formatting and linting

### Development Workflow

1. **Fork and clone the repository**
2. **Setup development environment:**
   ```bash
   make install
   make setup-hooks
   ```
3. **Make your changes** in the `scripts/` directory
4. **Test your changes:**
   ```bash
   make lint      # Check for issues
   make format    # Auto-format code
   make test      # Run basic tests
   ```
5. **Submit a pull request**

### Areas for Improvement
- Additional language support (Go, Rust, Java)
- Enhanced security features
- Better IDE integrations
- Performance optimizations
- Windows/WSL2 support
- CI/CD pipeline integration

### Code Standards
- Use `shellcheck` for shell script quality
- Use `shfmt -i 4` for consistent formatting
- Add comments for complex logic
- Test with multiple submission types
- Maintain backward compatibility

## 📄 License

MIT License - Use at your own risk. This tool provides isolation but no security solution is perfect.
