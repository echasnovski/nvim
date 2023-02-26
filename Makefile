GROUP_DEPTH ?= 1
NVIM_EXEC ?= nvim

# Download 'mini.nvim' to use its 'mini.test' testing module
deps/mini.nvim:
	@mkdir -p deps
	git clone --depth 1 https://github.com/echasnovski/mini.nvim $@
