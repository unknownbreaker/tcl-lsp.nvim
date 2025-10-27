#!/bin/bash
# environment_setup.sh - Setup script for tcl-lsp.nvim development environment
# Run this at the start of each chat session to prepare the environment

set -e  # Exit on error

echo "=========================================="
echo "TCL LSP Development Environment Setup"
echo "=========================================="
echo ""

# Color output helpers
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Check if running in the correct environment
print_status "Checking environment..."
if [ ! -d "/home/claude" ]; then
    print_error "Not running in expected Claude environment"
    exit 1
fi
print_success "Environment check passed"

# Update package lists
print_status "Updating package lists..."
apt-get update -qq 2>&1 | grep -v "Failed to fetch" || true
print_success "Package lists updated"

# Install TCL
print_status "Installing TCL (tclsh)..."
if command -v tclsh &> /dev/null; then
    print_success "TCL already installed: $(tclsh << 'EOF'
puts [info patchlevel]
EOF
)"
else
    apt-get install -y tcl > /dev/null 2>&1
    print_success "TCL installed: $(tclsh << 'EOF'
puts [info patchlevel]
EOF
)"
fi

# Verify TCL installation
print_status "Verifying TCL installation..."
if tclsh << 'EOF' > /dev/null 2>&1
puts "TCL test successful"
EOF
then
    print_success "TCL verification passed"
else
    print_error "TCL verification failed"
    exit 1
fi

# Install Lua if needed
print_status "Checking Lua installation..."
if command -v lua &> /dev/null; then
    print_success "Lua already installed: $(lua -v 2>&1 | head -n1)"
else
    print_status "Installing Lua..."
    apt-get install -y lua5.4 liblua5.4-dev > /dev/null 2>&1
    print_success "Lua installed: $(lua -v 2>&1 | head -n1)"
fi

# Install LuaRocks if needed
print_status "Checking LuaRocks installation..."
if command -v luarocks &> /dev/null; then
    print_success "LuaRocks already installed: $(luarocks --version | head -n1)"
else
    print_status "Installing LuaRocks..."
    apt-get install -y luarocks > /dev/null 2>&1
    print_success "LuaRocks installed: $(luarocks --version | head -n1)"
fi

# Install Neovim
print_status "Installing Neovim..."
if command -v nvim &> /dev/null; then
    NVIM_VERSION=$(nvim --version | head -n1)
    print_success "Neovim already installed: $NVIM_VERSION"
else
    print_status "Downloading and installing Neovim..."

    # Install dependencies for Neovim
    apt-get install -y wget curl git build-essential > /dev/null 2>&1

    # Download latest stable Neovim AppImage
    cd /tmp
    wget -q https://github.com/neovim/neovim/releases/download/stable/nvim.appimage
    chmod +x nvim.appimage

    # Extract AppImage (AppImages don't run well in containers)
    ./nvim.appimage --appimage-extract > /dev/null 2>&1

    # Move to /usr/local/bin
    mv squashfs-root /usr/local/nvim
    ln -sf /usr/local/nvim/usr/bin/nvim /usr/local/bin/nvim

    # Cleanup
    rm nvim.appimage

    if command -v nvim &> /dev/null; then
        NVIM_VERSION=$(nvim --version | head -n1)
        print_success "Neovim installed: $NVIM_VERSION"
    else
        print_error "Neovim installation failed"
        exit 1
    fi
fi

# Verify Neovim installation
print_status "Verifying Neovim installation..."
if nvim --version > /dev/null 2>&1; then
    print_success "Neovim verification passed"
else
    print_error "Neovim verification failed"
    exit 1
fi

# Install Git if needed (for Plenary and testing)
print_status "Checking Git installation..."
if command -v git &> /dev/null; then
    print_success "Git already installed: $(git --version)"
else
    print_status "Installing Git..."
    apt-get install -y git > /dev/null 2>&1
    print_success "Git installed: $(git --version)"
fi

# Set up working directory
print_status "Setting up working directory..."
WORK_DIR="/home/claude/tcl-lsp-dev"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
print_success "Working directory created: $WORK_DIR"

# Create project structure
print_status "Creating project structure..."
mkdir -p lua/tcl-lsp/parser
mkdir -p tcl/core/ast/parsers
mkdir -p tests/lua/parser
mkdir -p tests/spec
mkdir -p .github/workflows
print_success "Project structure created"

# Install Plenary.nvim for testing (if not already installed)
print_status "Setting up Plenary.nvim for testing..."
PLENARY_DIR="$HOME/.local/share/nvim/site/pack/vendor/start/plenary.nvim"
if [ -d "$PLENARY_DIR" ]; then
    print_success "Plenary.nvim already installed"
else
    print_status "Cloning Plenary.nvim..."
    mkdir -p "$HOME/.local/share/nvim/site/pack/vendor/start"
    git clone --quiet https://github.com/nvim-lua/plenary.nvim "$PLENARY_DIR" 2>&1 | grep -v "Cloning" || true
    print_success "Plenary.nvim installed"
fi

# Display environment summary
echo ""
echo "=========================================="
echo "Environment Summary"
echo "=========================================="
echo -e "TCL Version:      $(tclsh << 'EOF'
puts [info patchlevel]
EOF
)"
echo -e "Lua Version:      $(lua -v 2>&1 | head -n1 | cut -d' ' -f1-2)"
echo -e "LuaRocks Version: $(luarocks --version 2>&1 | head -n1 | cut -d' ' -f1-2)"
echo -e "Neovim Version:   $(nvim --version 2>&1 | head -n1)"
echo -e "Git Version:      $(git --version)"
echo -e "Working Dir:      $WORK_DIR"
echo -e "Plenary Path:     $PLENARY_DIR"
echo ""

print_success "Environment setup complete!"
echo ""
echo "You can now:"
echo "  1. Test TCL parser: tclsh tcl/core/parser.tcl <file>"
echo "  2. Run Lua code: lua script.lua"
echo "  3. Run Neovim tests: nvim --headless -u minimal_init.lua -c 'lua ...' -c 'qa!'"
echo "  4. Use Plenary for testing: require('plenary.busted')"
echo ""
