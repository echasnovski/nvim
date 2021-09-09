" Always source these
source $HOME/.config/nvim/general/settings.vim
source $HOME/.config/nvim/general/functions.vim
source $HOME/.config/nvim/general/mappings.vim
luafile $HOME/.config/nvim/general/mappings-leader.lua

if exists('g:vscode')
  source $HOME/.config/nvim/vscode/vscode.vim
else
  source $HOME/.config/nvim/general/colors.vim
  source $HOME/.config/nvim/general/bclose.vim
  source $HOME/.config/nvim/general/spelling.vim

  " Source Lua files
  luafile $HOME/.config/nvim/lua/source.lua
endif
