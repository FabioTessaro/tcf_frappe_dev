#!/bin/bash
# bootstrap/setup-vscode.sh

# Capture the first parameter. Default to "update" if none is provided.
MODE=${1:-update}

echo "Fetching the latest VS Code Server commit from Microsoft..."
# Query the VS Code API and parse the latest commit ID using Python
LATEST_COMMIT=$(curl -s https://update.code.visualstudio.com/api/commits/stable/server-linux-x64 | python3 -c "import sys, json; print(json.load(sys.stdin)[0])")

if [ -z "$LATEST_COMMIT" ]; then
    echo "Error: Could not fetch the latest VS Code commit ID."
    exit 1
fi

VSCODE_BASE_DIR="$HOME/.vscode-server"
VSCODE_BIN_DIR="$VSCODE_BASE_DIR/bin"
TARGET_DIR="$VSCODE_BIN_DIR/$LATEST_COMMIT"

# Logic for --install vs update
if [ "$MODE" == "--install" ]; then
    echo "Performing fresh installation..."
    # Completely wipe the VS Code server directory for a clean slate
    rm -rf "$VSCODE_BASE_DIR"
else
    echo "Updating VS Code Server..."
fi

# Ensure the target directory exists
mkdir -p "$TARGET_DIR"

# Check if the exact commit is already installed
if [ -f "$TARGET_DIR/server.sh" ]; then
    echo "VS Code Server for commit $LATEST_COMMIT is already installed and ready."
else
    echo "Downloading VS Code Server (Commit: $LATEST_COMMIT)..."
    curl -sSL "https://update.code.visualstudio.com/commit:$LATEST_COMMIT/server-linux-x64/stable" -o /tmp/vscode-server.tar.gz
    
    echo "Extracting server files..."
    tar -zxf /tmp/vscode-server.tar.gz -C "$TARGET_DIR" --strip-components 1
    rm /tmp/vscode-server.tar.gz
fi

# Clean up older versions to prevent the container from bloating over time
echo "Cleaning up old VS Code Server versions..."
cd "$VSCODE_BIN_DIR" && ls -1 | grep -v "$LATEST_COMMIT" | xargs -r rm -rf

echo "Done! VS Code Server setup is complete."