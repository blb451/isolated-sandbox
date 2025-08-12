# Makefile for Thanx Isolated Sandbox development

.PHONY: help install lint format test clean setup-hooks

# Default target
help:
	@echo "Available targets:"
	@echo "  install     - Install development dependencies"
	@echo "  setup-hooks - Install pre-commit hooks"
	@echo "  lint        - Run linters on shell scripts and Docker files"
	@echo "  format      - Format shell scripts"
	@echo "  test        - Run basic functionality tests"
	@echo "  clean       - Clean up generated files"

# Install development dependencies
install:
	@echo "Installing development dependencies..."
	@if command -v brew >/dev/null 2>&1; then \
		brew install shellcheck shfmt pre-commit; \
	else \
		echo "Please install shellcheck, shfmt, and pre-commit manually"; \
		echo "  - shellcheck: https://github.com/koalaman/shellcheck"; \
		echo "  - shfmt: https://github.com/mvdan/sh"; \
		echo "  - pre-commit: https://pre-commit.com"; \
	fi

# Setup pre-commit hooks with auto-staging
setup-hooks:
	@echo "Installing pre-commit hooks with auto-staging..."
	pre-commit install
	@echo "Configuring auto-staging for fixed files..."
	@chmod +x scripts/auto-stage-hook.sh
	@echo '#!/bin/bash' > .git/hooks/pre-commit
	@echo '# Auto-generated hook that stages fixes from pre-commit' >> .git/hooks/pre-commit
	@echo 'exec scripts/auto-stage-hook.sh' >> .git/hooks/pre-commit
	@chmod +x .git/hooks/pre-commit
	@echo "Running hooks on all files..."
	pre-commit run --all-files || echo "Some files were formatted - review changes"
	@echo "✅ Pre-commit hooks installed with auto-staging enabled!"

# Lint shell scripts and Docker files (non-fixable checks)
lint:
	@echo "Linting shell scripts..."
	shellcheck scripts/*.sh
	@echo "Validating Docker Compose YAML..."
	docker-compose config >/dev/null
	@echo "Linting complete! Use 'make format' to auto-fix formatting issues."

# Format shell scripts (write changes)
format:
	@echo "Formatting shell scripts..."
	shfmt -w -s -i 4 scripts/*.sh

# Basic functionality tests
test:
	@echo "Testing Docker build..."
	docker-compose build --dry-run >/dev/null
	@echo "Testing script permissions..."
	@for script in scripts/*.sh; do \
		if [ ! -x "$$script" ]; then \
			echo "Warning: $$script is not executable"; \
		fi \
	done
	@echo "All tests passed!"

# Clean up
clean:
	@echo "Cleaning up..."
	rm -rf extracted/* submissions/* audit/* 2>/dev/null || true
	docker-compose down --volumes 2>/dev/null || true
	@echo "Cleanup complete!"
