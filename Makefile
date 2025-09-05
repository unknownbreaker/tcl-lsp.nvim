# TCL LSP for Neovim - Build Automation
.DEFAULT_GOAL := help
.PHONY: help install test test-unit test-integration test-performance clean lint format check docs release

# Configuration
SHELL := /bin/bash
NVIM ?= nvim
LUA ?= lua
TCLSH ?= tclsh
BUSTED ?= busted

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

install: ## Install dependencies
	@echo "Installing Lua dependencies..."
	luarocks install busted
	luarocks install luacheck
	luarocks install ldoc
	@echo "Installing Node.js dependencies..."
	npm install
	@echo "Installing Python dependencies..."
	pip install -r requirements-dev.txt

test: test-unit test-integration ## Run all tests
	@echo "All tests completed"

test-unit: ## Run unit tests
	@echo "Running Lua unit tests..."
	busted tests/lua --verbose
	@echo "Running Tcl unit tests..."
	tclsh tests/tcl/run_tests.tcl

test-integration: ## Run integration tests
	@echo "Running integration tests..."
	busted tests/integration --verbose

test-performance: ## Run performance benchmarks
	@echo "Running performance tests..."
	busted tests/integration/test_performance.lua --verbose

test-coverage: ## Generate test coverage report
	@echo "Generating coverage report..."
	busted tests/lua --coverage --verbose
	luacov

lint: ## Run linting
	@echo "Linting Lua code..."
	luacheck lua/ tests/
	@echo "Linting Tcl code..."
	tclchecker tcl/

format: ## Format code
	@echo "Formatting Lua code..."
	stylua lua/ tests/lua/
	@echo "Formatting Tcl code..."
	find tcl/ -name "*.tcl" -exec tclFormatter {} \;

check: lint test ## Run checks and tests
	@echo "All checks passed"

docs: ## Generate documentation
	@echo "Generating documentation..."
	ldoc lua/
	@echo "Generating API docs..."
	tclsh scripts/generate_tcl_docs.tcl

clean: ## Clean build artifacts
	@echo "Cleaning build artifacts..."
	rm -rf .luacov
	rm -rf doc/html/
	rm -rf coverage/
	rm -rf node_modules/.cache/

release: check docs ## Prepare release
	@echo "Preparing release..."
	@scripts/prepare_release.sh
