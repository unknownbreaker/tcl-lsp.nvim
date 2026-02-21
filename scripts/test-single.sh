#!/bin/sh
# Run a single test file or filter tests by name.
#
# Usage:
#   ./scripts/test-single.sh tests/lua/analyzer/extractor_spec.lua
#   ./scripts/test-single.sh tests/tcl/core/ast/test_json.tcl
#   ./scripts/test-single.sh extractor          # filter by name

set -e

arg="${1:?Usage: $0 <test-file-or-filter>}"

# TCL tests: run directly with tclsh
case "$arg" in
  *.tcl)
    exec tclsh "$arg"
    ;;
esac

# Lua tests: if a full path is given, run that file; otherwise use as filter
case "$arg" in
  tests/*)
    exec nvim --headless -u tests/minimal_init.lua \
      -c "lua require('plenary.test_harness').test_directory('${arg}', {minimal_init='tests/minimal_init.lua'})" \
      -c "qa!"
    ;;
  *)
    exec nvim --headless -u tests/minimal_init.lua \
      -c "lua require('plenary.test_harness').test_directory('tests/lua/', {minimal_init='tests/minimal_init.lua', filter='${arg}'})" \
      -c "qa!"
    ;;
esac
