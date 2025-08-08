# Thanx Isolated Sandbox

A secure environment for reviewing and running take-home challenge submissions with virus scanning and Docker isolation.

## Features

- **Virus Scanning**: Automatic ClamAV scanning before extraction
- **Docker Isolation**: Code runs in an isolated container environment
- **Multi-language Support**: Pre-installed Node.js, Ruby, Python environments
- **Docker-in-Docker**: Support for submissions that use Docker themselves
- **Interactive Shell**: Option to explore submissions interactively

## Prerequisites

- Docker and Docker Compose installed
- Unix-like environment (macOS/Linux)

## Usage

1. Run the sandbox script:
   ```bash
   ./run-sandbox.sh
   ```

2. When prompted, provide the full path to the submission ZIP file

3. The script will:
   - Copy the file to the sandbox
   - Run a virus scan
   - Extract the contents if safe
   - Offer options to interact with the code

## Security Features

- ClamAV virus scanning before extraction
- Isolated Docker container execution
- Network isolation options
- No direct host system access

## Directory Structure

- `submissions/` - Original ZIP files (gitignored)
- `extracted/` - Extracted submission contents (gitignored)
- `Dockerfile` - Container configuration
- `docker-compose.yml` - Service orchestration
- `run-sandbox.sh` - Main execution script

## Cleanup

To remove containers and clean up:
```bash
docker-compose down
rm -rf submissions/* extracted/*
```

## Notes

- The sandbox uses host networking to allow submissions to run servers
- Docker socket is mounted for Docker-in-Docker support
- All submission files remain isolated within the container