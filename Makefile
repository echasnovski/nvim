GROUP_DEPTH ?= 1
NVIM_EXEC ?= nvim

# Download 'mini.nvim' to use its 'mini.test' testing module
deps/mini.nvim:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/echasnovski/mini.nvim $@

test_hipatterns: deps/mini.nvim
	$(NVIM_EXEC) --version | head -n 1 && echo ''
	$(NVIM_EXEC) --headless --noplugin -u ./lua/mini-dev/minimal_init.lua \
		-c "lua require('mini.test').setup()" \
		-c "lua MiniTest.run_file('lua/mini-dev/test_hipatterns.lua', { execute = { reporter = MiniTest.gen_reporter.stdout({ group_depth = $(GROUP_DEPTH) }) } })"
