.PHONY: test
test:
	nvim --headless --noplugin -u tests/mininit.lua -c "PlenaryBustedDirectory tests/plenary/ {minimal_init = 'tests/mininit.lua'}"
