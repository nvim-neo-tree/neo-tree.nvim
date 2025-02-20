.PHONY: test
test:
	nvim --headless --noplugin -u tests/mininit.lua -c "lua require('plenary.test_harness').test_directory('tests/neo-tree/', {minimal_init='tests/mininit.lua',sequential=true})"

.PHONY: test-docker
test-docker:
	docker build -t neo-tree .
	docker run --rm neo-tree make test

.PHONY: format
format:
	stylua --glob '*.lua' --glob '!defaults.lua' .

llscheck:
	llscheck --configpath .github/workflows/.luarc.json .

# Dependencies:

PLUGINS_DIR := ./.dependencies/site/pack/vendor/start

$(PLUGINS_DIR):
	mkdir -p "$(PLUGINS_DIR)"

.PHONY: nui.nvim nvim-web-devicons plenary.nvim setup
nui.nvim:
	git clone https://github.com/MunifTanjim/nui.nvim "$(PLUGINS_DIR)/nui.nvim"

nvim-web-devicons:
	git clone https://github.com/nvim-tree/nvim-web-devicons "$(PLUGINS_DIR)/nvim-web-devicons"

plenary.nvim:
	git clone https://github.com/nvim-lua/plenary.nvim "$(PLUGINS_DIR)/plenary.nvim"

setup: | $(PLUGINS_DIR) nui.nvim nvim-web-devicons plenary.nvim
	@echo "[test] environment ready"

.PHONY: clean
clean:
	rm -rf "$(PLUGINS_DIR)"
