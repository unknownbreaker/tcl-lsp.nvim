# Makefile
# TCL LSP for Neovim - Build Automation
.DEFAULT_GOAL := help
.PHONY: help install test test-unit test-integration test-performance clean lint format check docs release validate-schema pre-commit

# Configuration
SHELL := /bin/bash
NVIM ?= nvim
LUA ?= lua
TCLSH ?= tclsh
BUSTED ?= busted
NAGELFAR ?= nagelfar
TEST_FORMATTER := ./scripts/format_test_output.py

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

test-unit: ## Run unit tests with formatted output
	@echo "Running Lua unit tests with plenary..."
	@$(NVIM) --headless --noplugin -u tests/minimal_init.lua \
		-c "lua require('plenary.test_harness').test_directory('tests/lua/', {minimal_init = 'tests/minimal_init.lua'})" \
		-c "qa!" 2>&1 | $(TEST_FORMATTER)
	@echo ""
	@echo "Running Tcl unit tests..."
	@$(TCLSH) tests/tcl/core/ast/run_all_tests.tcl 2>&1 | $(TEST_FORMATTER)

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
	@$(NVIM) --headless --noplugin -u tests/minimal_init.lua \
		-c "lua require('plenary.test_harness').test_directory('tests/integration/', {minimal_init = 'tests/minimal_init.lua'})" \
		-c "qa!" 2>&1 | $(TEST_FORMATTER)

test-performance: ## Run performance benchmarks
	@echo "Running performance tests..."
	@$(NVIM) --headless --noplugin -u tests/minimal_init.lua \
		-c "lua require('plenary.test_harness').test_directory('tests/integration/', {minimal_init = 'tests/minimal_init.lua', filter = 'performance'})" \
		-c "qa!" 2>&1 | $(TEST_FORMATTER)

test-coverage: ## Generate test coverage report (placeholder - Neovim tests don't support coverage yet)
	@echo "Coverage reporting for Neovim plugins requires special setup."
	@echo "Run 'make test' to run all tests without coverage."

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
	luacheck lua/ tests/ || [ $$? -eq 1 ]

lint-tcl: ## Lint TCL code with nagelfar
	@echo "Linting Tcl code with Nagelfar..."
	@find tcl/ tests/tcl/ -name "*.tcl" -print0 2>/dev/null | while IFS= read -r -d '' file; do \
		echo ""; \
		printf "\033[1;36mChecking: %s\033[0m\n" "$$file"; \
		$(NAGELFAR) -H "$$file" 2>&1 | awk -v RED='\033[1;31m' -v YELLOW='\033[1;33m' -v CYAN='\033[0;36m' -v NC='\033[0m' '{ \
			if (match($$0, /^Checking file /)) { \
				next; \
			} else if (match($$0, /: E /)) { \
				print RED $$0 NC; \
			} else if (match($$0, /: W /)) { \
				print YELLOW $$0 NC; \
			} else if (match($$0, /: N /)) { \
				print CYAN $$0 NC; \
			} else { \
				print $$0; \
			} \
			fflush(); \
		}'; \
	done
	@echo ""
	@printf "\033[1;32m✓ TCL linting complete\033[0m\n"

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

format-lua: ## Format Lua code
	@echo "Formatting Lua code..."
	stylua lua/ tests/lua/

format-tcl: ## Format TCL code
	@echo "Formatting Tcl code..."
	find tcl/ -name "*.tcl" -exec tclFormatter {} \;

format: format-lua format-tcl format-js ## Run all formatting
	@echo "All formatting completed"

check: lint test ## Run all checks (lint + test)

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

validate-schema: ## Validate AST schema against TCL parser output
	@echo "Validating AST schema..."
	@./scripts/validate-schema.sh

pre-commit: lint validate-schema test-unit ## Run pre-commit checks
	@echo "Pre-commit checks completed"
