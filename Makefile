.PHONY: test deps

# Install test dependencies (busted + dkjson JSON library).
deps:
	luarocks install busted
	luarocks install dkjson

# Run the unit test suite.
test:
	busted test/unit/ --helper test/helper.lua
