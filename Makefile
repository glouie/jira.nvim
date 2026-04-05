.PHONY: test test-integration test-all deps

# Install test dependencies (busted + dkjson JSON library).
deps:
	luarocks install busted
	luarocks install dkjson

# Run the busted unit test suite (no Neovim required).
test:
	busted test/unit/ --helper test/helper.lua

# Run the headless Neovim integration smoke test.
# Requires nvim to be on PATH.
test-integration:
	nvim --headless -u test/minimal_init.lua -l test/integration/smoke.lua

# Run both test layers.
test-all: test test-integration
