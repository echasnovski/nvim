" Minimal initialization file for running automatic documentation of Lua
" modules with output being Vim's help files.
" Recommended shell command to run is (should be run inside directory
" containing 'scripts/gendocs.lua' file):
" ```bash
" nvim --headless --noplugin \
" -u ~/.config/nvim/misc/scripts/docgen_init.vim \
" -c 'luafile ./scripts/gendocs.lua' -c 'qa'
" ```
"
" Here file `./scripts/gendocs.lua` is file containing Lua code for actually
" doing documentation generation. Example:
" https://github.com/nvim-telescope/telescope.nvim/blob/master/scripts/gendocs.lua
" Its main functionality currently comes from 'docgen' Lua subplugin of
" 'tjdevries/tree-sitter-lua' plugin. Currently it should be postprocessed
" after its installation (build dedicated tree-sitter parser and expose it to
" Neovim). General instructions:
" https://github.com/nvim-telescope/telescope.nvim/blob/master/CONTRIBUTING.md#generate-on-your-local-machine
set rtp+=.
set rtp+=~/.config/nvim/pack/plugins/opt/plenary/
set rtp+=~/.config/nvim/pack/plugins/opt/tree-sitter-lua/

runtime! plugin/plenary.vim
