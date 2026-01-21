#!/usr/bin/env bash
# scripts/validate-schema.sh
# Validate AST schema against TCL parser output
# Exit 0 if valid, 1 if drift detected

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FIXTURES_DIR="${PROJECT_ROOT}/tests/tcl/fixtures"
PARSER="${PROJECT_ROOT}/tcl/core/parser.tcl"
VALIDATOR="${PROJECT_ROOT}/scripts/run-validator.lua"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

validate_file() {
    local file="$1"
    local json
    local filename

    filename=$(basename "$file")

    # Parse file with TCL parser
    if ! json=$(tclsh "$PARSER" "$file" 2>&1); then
        log_error "Failed to parse: $filename"
        echo "  Parser error: $json"
        return 1
    fi

    # Validate JSON with Lua validator
    if ! echo "$json" | nvim --headless -u NONE \
        --cmd "set runtimepath+=${PROJECT_ROOT}" \
        -c "lua dofile('${VALIDATOR}')" \
        -c "qa" 2>&1; then
        log_error "Validation failed: $filename"
        return 1
    fi

    log_info "Valid: $filename"
    return 0
}

validate_all() {
    local errors=0
    local total=0

    log_info "Starting schema validation..."
    log_info "Fixtures directory: $FIXTURES_DIR"

    # Check if fixtures directory exists
    if [[ ! -d "$FIXTURES_DIR" ]]; then
        log_warn "Fixtures directory not found, creating..."
        mkdir -p "$FIXTURES_DIR"
        # Create a basic fixture file
        cat > "${FIXTURES_DIR}/basic.tcl" << 'EOF'
# Basic fixture for schema validation
set x "hello"
proc test {} {
    puts "Hello, World!"
}
EOF
    fi

    # Validate each TCL file in fixtures
    for file in "$FIXTURES_DIR"/*.tcl; do
        [[ -f "$file" ]] || continue
        ((total++))
        if ! validate_file "$file"; then
            ((errors++))
        fi
    done

    echo ""
    if [[ $total -eq 0 ]]; then
        log_warn "No fixture files found in $FIXTURES_DIR"
        exit 0
    fi

    if [[ $errors -gt 0 ]]; then
        log_error "Schema validation failed: $errors/$total file(s) with drift"
        exit 1
    fi

    log_info "Schema validation passed: $total file(s) validated"
    exit 0
}

# Handle single file validation
if [[ $# -eq 1 ]]; then
    validate_file "$1"
    exit $?
fi

# Default: validate all fixtures
validate_all
