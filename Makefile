# Root convenience targets. The Go server has its own Makefile under server/.

.PHONY: test-unit test-lua test-go

# Run the Lua plugin tests (plenary, headless). Mirrors the test-lua skill.
test-unit test-lua:
	nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/lua/ { minimal_init = 'tests/minimal_init.lua', sequential = true }"

# Run the Go server tests.
test-go:
	go test -C server ./...
