.PHONY: test
test:
	@echo ""
	@echo "TEST WITH BLANK CONFIG "
	nvim --headless --noplugin -u tests/mininit.lua -c "PlenaryBustedDirectory tests/neo-tree/ { minimal_init = 'tests/mininit.lua' }"

	@echo ""
	@echo "TEST WITH follow_current_file = true"
	nvim --headless --noplugin -u tests/init_follow_current_file.lua -c "PlenaryBustedDirectory tests/neo-tree/ { minimal_init = 'tests/init_follow_current_file.lua' }"

.PHONY: format
format:
	stylua --glob '*.lua' --glob '!defaults.lua' .
