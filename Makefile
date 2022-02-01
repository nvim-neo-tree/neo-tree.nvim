.PHONY: test
test:
	nvim --headless --noplugin -u tests/mininit.lua -c "PlenaryBustedDirectory tests/neo-tree/ { minimal_init = 'tests/mininit.lua' }"

.PHONY: format
format:
	stylua ./lua ./tests
