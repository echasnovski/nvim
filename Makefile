GROUP_DEPTH ?= 1
NVIM_EXEC ?= nvim

# Download 'mini.nvim' to use its 'mini.test' testing module
deps/mini.nvim:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/nvim-mini/mini.nvim $@

# test_cmdline: deps/mini.nvim
# 	for nvim_exec in $(NVIM_EXEC); do \
# 		printf "\n======\n\n" ; \
# 		$$nvim_exec --version | head -n 1 && echo '' ; \
# 		$$nvim_exec --headless --noplugin -u ./lua/mini-dev/minimal_init.lua \
# 			-c "lua require('mini.test').setup()" \
# 			-c "lua MiniTest.run_file('lua/mini-dev/test_cmdline.lua', { execute = { reporter = MiniTest.gen_reporter.stdout({ group_depth = $(GROUP_DEPTH) }) } })" ; \
# 	done
