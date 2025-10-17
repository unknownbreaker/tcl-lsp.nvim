# TCL LSP for Neovim - Build Automation
.DEFAULT_GOAL := help
.PHONY: help install test test-unit test-integration test-performance clean lint format check docs release

# Configuration
SHELL := /bin/bash
NVIM ?= nvim
LUA ?= lua
TCLSH ?= tclsh
BUSTED ?= busted
NAGELFAR ?= nagelfar

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

test: test-unit test-integration test-performance test-coverage ## Run all tests
	@echo "All tests completed"

test-e2e:
	@echo: "Running E2E tests..."
	npm run test:e2e

test-unit: ## Run unit tests
	@echo "Running Lua unit tests with plenary..."
	nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "lua require('plenary.test_harness').test_directory('tests/lua/', {minimal_init = 'tests/minimal_init.lua'})" \
		-c "qa!"
	@echo "Running Tcl unit tests..."
	tclsh tests/tcl/run_tests.tcl

test-unit-lsp-server: ## Run LSP server specific tests
	@echo "Running LSP server unit tests..."
	$(NVIM) --headless --noplugin -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/lua/ {minimal_init = 'tests/minimal_init.lua'}" \
		-c "qa!"

test-unit-lsp-server-file: ## Run specific server test file
	@echo "Running server_spec.lua only..."
	$(NVIM) --headless --noplugin -u tests/minimal_init.lua \
		-c "lua require('plenary.test_harness').test_directory('tests/lua/', {minimal_init = 'tests/minimal_init.lua', filter = 'server'})" \
		-c "qa!"

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

lint: lint-lua lint-tcl lint-js ## Run all linting
	@echo "All linting completed"

lint-js: ## Lint JavaScript test files (if any exist)
	@count=$$(find tests -name '*.js' 2>/dev/null | wc -l); \
	if [ $$count -gt 0 ]; then \
		echo "Linting $$count JavaScript file(s)..."; \
		npm run lint; \
	else \
		echo "No JavaScript files found, skipping JS linting..."; \
	fi

lint-js-fix: ## Fix JavaScript linting issues (if any exist)
	@count=$$(find tests -name '*.js' 2>/dev/null | wc -l); \
	if [ $$count -gt 0 ]; then \
		echo "Fixing JavaScript linting issues in $$count file(s)..."; \
		npm run lint:fix; \
	else \
		echo "No JavaScript files found, skipping JS linting fixes..."; \
	fi

lint-lua: ## Run linting
	@echo "Linting Lua code..."
	luacheck lua/ tests/

lint-tcl: ## Run linting
	@echo "Linting Tcl code with Nagelfar..."
	find tcl/ -name "*.tcl" -exec $(NAGELFAR) -H {} \;

format-js: ## Format JavaScript test files (if any exist)
	@count=$$(find tests -name '*.js' 2>/dev/null | wc -l); \
	if [ $$count -gt 0 ]; then \
		echo "Formatting $$count JavaScript file(s)..."; \
		npm run format; \
	else \
		echo "No JavaScript files found, skipping JS formatting..."; \
	fi

format-js-check: ## Check JavaScript formatting (if any exist)
	@count=$$(find tests -name '*.js' 2>/dev/null | wc -l); \
	if [ $$count -gt 0 ]; then \
		echo "Checking formatting of $$count JavaScript file(s)..."; \
		npm run format:check; \
	else \
		echo "No JavaScript files found, skipping JS format checking..."; \
	fi

format-lua: ## Format code
	@echo "Formatting Lua code..."
	stylua lua/ tests/lua/

format-tcl: ## Format code
	@echo "Formatting Tcl code..."
	find tcl/ -name "*.tcl" -exec tclFormatter {} \;

format: format-lua format-tcl format-js ## Run all formatting
	@echo "All formatting completed"

check: lint test ## Run checks and tests
	@echo "All checks passed"

clean: ## Clean build artifacts
	@echo "Cleaning build artifacts..."
	rm -rf .luacov
	rm -rf doc/html/
	rm -rf coverage/
	rm -rf node_modules/.cache/

docs: ## Generate documentation
	@echo "Generating documentation..."
	ldoc lua/
	@echo "Generating API docs..."
	tclsh scripts/generate_tcl_docs.tcl

release: check docs ## Prepare release
	@echo "Preparing release..."
	@scripts/prepare_release.sh
