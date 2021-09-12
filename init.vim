" Always source these
luafile $HOME/.config/nvim/general/settings.lua
source $HOME/.config/nvim/general/functions.vim
luafile $HOME/.config/nvim/general/mappings.lua
luafile $HOME/.config/nvim/general/mappings-leader.lua

if exists('g:vscode')
  source $HOME/.config/nvim/vscode/vscode.vim
else
  source $HOME/.config/nvim/general/colors.vim
  source $HOME/.config/nvim/general/bclose.vim

  " Source Lua files
  luafile $HOME/.config/nvim/lua/source.lua
endif
