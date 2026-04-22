.PHONY: test test-file lint format clean

NVIM ?= nvim

# Run all tests via mini.test
test:
	$(NVIM) --headless --noplugin \
		-u tests/minimal_init.lua \
		-c "lua MiniTest.run()" \
		-c "qa!"

# Run a single test file: make test-file FILE=tests/test_review_state.lua
test-file:
	$(NVIM) --headless --noplugin \
		-u tests/minimal_init.lua \
		-c "lua MiniTest.run_file('$(FILE)')" \
		-c "qa!"

# Lint with luacheck (if installed)
lint:
	luacheck lua/ tests/

# Format with stylua (if installed)
format:
	stylua lua/ tests/

# Check formatting without writing
format-check:
	stylua --check lua/ tests/

clean:
	rm -rf .tests/
