#!/bin/bash
# FroggyDocs Installation Script
# Supports Linux, macOS, and Windows (via Git Bash)

set -e

INSTALL_DIR="${HOME}/.froggy-docs"
BIN_DIR="${HOME}/.local/bin"
REPO_URL="https://github.com/yourusername/froggy-docs/releases"
VERSION="1.0.0"

echo "🐸 FroggyDocs Installer v${VERSION}"
echo "=================================="

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Linux*)     echo "linux" ;;
        Darwin*)   echo "macos" ;;
        MINGW*|MSYS*) echo "windows" ;;
        *)         echo "unknown" ;;
    esac
}

# Get binary name
get_binary_name() {
    local os=$(detect_os)
    case "$os" in
        windows) echo "froggy-docs.exe" ;;
        *)      echo "froggy-docs" ;;
    esac
}

# Create directories
setup_dirs() {
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$BIN_DIR"
}

# Download and install binary
install_binary() {
    local os=$(detect_os)
    local arch
    local binary_name
    local download_url

    case "$os" in
        linux)
            arch="x86_64-linux-gnu"
            ;;
        mocos)
            arch="x86_64-macos"
            ;;
        windows)
            arch="x86_64-windows.zip"
            ;;
        *)
            echo "❌ Unsupported OS"
            exit 1
            ;;
    esac

    binary_name=$(get_binary_name)
    download_url="${REPO_URL}/download/v${VERSION}/froggy-docs-${arch}"

    echo "📥 Downloading for $os..."

    curl -L "$download_url" -o "${INSTALL_DIR}/${binary_name}"
    chmod +x "${INSTALL_DIR}/${binary_name}"

    echo "✅ Installed to ${INSTALL_DIR}/${binary_name}"
}

# Add to PATH
add_to_path() {
    echo ""
    echo "📝 Adding to PATH..."
    echo ""
    echo "Add this line to your ~/.bashrc or ~/.zshrc:"
    echo "   export PATH=\"\$PATH:${BIN_DIR}\""
    echo ""
    echo "Then run: source ~/.bashrc"
}

# Main
main() {
    setup_dirs
    
    if [ -f "${INSTALL_DIR}/froggy-docs" ] || [ -f "${INSTALL_DIR}/froggy-docs.exe" ]; then
        echo "✅ FroggyDocs already installed"
        echo "   Location: ${INSTALL_DIR}"
        echo ""
        echo "To update: rm -rf ${INSTALL_DIR} && $(basename $0)"
    else
        install_binary
        add_to_path
    fi

    echo ""
    echo "🎉 Installation complete!"
    echo ""
    echo "Usage:"
    echo "  froggy-docs serve              Start documentation server"
    echo "  froggy-docs serve -p 3000     Custom port"
    echo "  froggy-docs serve -h 0.0.0.0  Make accessible on network"
    echo "  froggy-docs watch            Watch for changes"
}

main "$@"