test:
	nvim --version | head -n 1
	nvim --headless --noplugin -u ./scripts/minimal_init.vim -c "lua require('mini-dev.test').run()"
