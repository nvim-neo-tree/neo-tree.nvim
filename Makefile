.PHONY: test
test:
	nvim --headless --noplugin -u tests/mininit.lua -c "lua require('plenary.test_harness').test_directory('tests/neo-tree/', {minimal_init='tests/mininit.lua'})"

.PHONY: test-docker
test-docker:
	docker build -t neo-tree .
	docker run --rm neo-tree make test

.PHONY: format
format:
	stylua --glob '*.lua' --glob '!defaults.lua' .

# Dependencies:

DEPS := ${CURDIR}/.dependencies/pack/vendor/start

$(DEPS):
	mkdir -p "$(DEPS)"

$(DEPS)/nui.nvim: $(DEPS)
	@test -d "$(DEPS)/nui.nvim" || git clone https://github.com/MunifTanjim/nui.nvim "$(DEPS)/nui.nvim"

$(DEPS)/nvim-web-devicons: $(DEPS)
	@test -d "$(DEPS)/nvim-web-devicons" || git clone https://github.com/nvim-tree/nvim-web-devicons "$(DEPS)/nvim-web-devicons"

$(DEPS)/plenary.nvim: $(DEPS)
	@test -d "$(DEPS)/plenary.nvim" || git clone https://github.com/nvim-lua/plenary.nvim "$(DEPS)/plenary.nvim"

$(DEPS)/snacks.nvim: $(DEPS)
	@test -d "$(DEPS)/snacks.nvim" || git clone https://github.com/folke/snacks.nvim "$(DEPS)/snacks.nvim"

setup: $(DEPS)/nui.nvim $(DEPS)/nvim-web-devicons $(DEPS)/plenary.nvim $(DEPS)/snacks.nvim
	@echo "[setup] environment ready"

.PHONY: clean
clean:
	rm -rf "$(DEPS)"

CONFIGURATION = ${CURDIR}/.luarc.json
luals-check: setup
	VIMRUNTIME="`nvim --clean --headless --cmd 'lua io.write(vim.env.VIMRUNTIME)' --cmd 'quit'`" lua-language-server --configpath=$(CONFIGURATION) --check=.

emmylua-check: setup
	VIMRUNTIME="`nvim --clean --headless --cmd 'lua io.write(vim.env.VIMRUNTIME)' --cmd 'quit'`" emmylua_check -c $(CONFIGURATION) -i ".dependencies/**" --  .
