#!/bin/bash
# Setup script for tcl-lsp.nvim development environment
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

# Check if running in the correct environment
print_status "Checking environment..."
if [ ! -d "/home/claude" ]; then
    print_error "Not running in expected Claude environment"
    exit 1
fi
print_success "Environment check passed"

# Install TCL
print_status "Installing TCL (tclsh)..."
if command -v tclsh &> /dev/null; then
    print_success "TCL already installed: $(tclsh << 'EOF'
puts [info patchlevel]
EOF
)"
else
    apt-get update -qq 2>&1 | grep -v "Failed to fetch" || true
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

# Install Lua if needed (for running tests)
print_status "Checking Lua installation..."
if command -v lua &> /dev/null; then
    print_success "Lua already installed: $(lua -v 2>&1 | head -n1)"
else
    print_status "Installing Lua..."
    apt-get install -y lua5.4 liblua5.4-dev > /dev/null 2>&1
    print_success "Lua installed: $(lua -v 2>&1 | head -n1)"
fi

# Install LuaRocks if needed (for Lua package management)
print_status "Checking LuaRocks installation..."
if command -v luarocks &> /dev/null; then
    print_success "LuaRocks already installed: $(luarocks --version | head -n1)"
else
    print_status "Installing LuaRocks..."
    apt-get install -y luarocks > /dev/null 2>&1
    print_success "LuaRocks installed: $(luarocks --version | head -n1)"
fi

# Set up working directory
print_status "Setting up working directory..."
WORK_DIR="/home/claude/tcl-lsp-dev"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
print_success "Working directory created: $WORK_DIR"

# Create common project structure
print_status "Creating project structure..."
mkdir -p lua/tcl-lsp
mkdir -p tcl/core/ast
mkdir -p tests/lua
mkdir -p tests/tcl
mkdir -p tests/integration
mkdir -p tests/spec
print_success "Project structure created"

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
echo -e "Working Dir:      $WORK_DIR"
echo -e "Current Dir:      $(pwd)"
echo ""

print_success "Environment setup complete!"
echo ""
echo "You can now:"
echo "  1. Copy TCL files from project knowledge to $WORK_DIR"
echo "  2. Run TCL scripts: tclsh your_script.tcl"
echo "  3. Run Lua tests: lua tests/lua/your_test.lua"
echo "  4. Install Lua packages: luarocks install <package>"
echo ""
