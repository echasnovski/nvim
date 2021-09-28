" Always source these
luafile $HOME/.config/nvim/general/settings.lua
luafile $HOME/.config/nvim/general/functions.lua
luafile $HOME/.config/nvim/general/mappings.lua
luafile $HOME/.config/nvim/general/mappings-leader.lua

if exists('g:vscode')
  luafile $HOME/.config/nvim/general/vscode.lua
else
  source $HOME/.config/nvim/general/bclose.vim

  " Source Lua files
  luafile $HOME/.config/nvim/lua/source.lua
endif
