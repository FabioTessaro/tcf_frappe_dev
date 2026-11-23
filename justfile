# Tasks of the development environment repository. `just` lists them.
# Recipe names follow architecture/50-delivery/501-ci.md; the environment's
# lifecycle stays in ./install.sh, ./setup.sh, ./initialize.sh, ./teardown.sh.

set shell := ["bash", "-euo", "pipefail", "-c"]

# List the recipes
default:
    @just --list

# Install the git hooks and their environments (not to be confused with ./setup.sh)
setup:
    pre-commit install
    pre-commit install-hooks

# Format Python (Ruff) and fix whitespace / end of files (rerun `just lint` after)
fmt:
    -pre-commit run ruff-format --all-files
    -pre-commit run trailing-whitespace --all-files
    -pre-commit run end-of-file-fixer --all-files

# Every check of the git hooks, on every file
lint:
    pre-commit run --all-files

# Secret scan of the whole git history
scan:
    gitleaks git --redact --no-banner .

# Architecture guide: rule IDs unique and defined, links valid
check-guide:
    python3 architecture/tools/check_guide.py

# Build the architecture guide as PDF and EPUB (needs Docker: run it on the host)
book:
    architecture/book/build.sh

# What CI runs on every change
ci: lint scan
