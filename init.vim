" Always source these
source $HOME/.config/nvim/vim-plug/plugins.vim
source $HOME/.config/nvim/general/settings.vim
source $HOME/.config/nvim/general/functions.vim
source $HOME/.config/nvim/general/mappings.vim
source $HOME/.config/nvim/general/mappings-leader.vim

if exists('g:vscode')
  source $HOME/.config/nvim/vscode/vscode.vim
  source $HOME/.config/nvim/plug-config/targets.vim
  source $HOME/.config/nvim/plug-config/sideways.vim
else
  source $HOME/.config/nvim/general/colors.vim
  source $HOME/.config/nvim/general/bclose.vim
  source $HOME/.config/nvim/general/spelling.vim

  if has("nvim-0.5.0")
    for s:fpath in split(globpath('$HOME/.config/nvim/lua', '*.lua'), '\n')
        exe 'luafile' s:fpath
    endfor
  endif

  " Source all plugin configuration files
  for s:fpath in split(globpath('$HOME/.config/nvim/plug-config', '*.vim'), '\n')
      exe 'source' s:fpath
  endfor
endif
