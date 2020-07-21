" Always source these
source $HOME/.config/nvim/vim-plug/plugins.vim
source $HOME/.config/nvim/general/settings.vim
source $HOME/.config/nvim/general/functions.vim
source $HOME/.config/nvim/general/mappings.vim
source $HOME/.config/nvim/general/mappings-leader.vim
source $HOME/.config/nvim/general/spelling.vim

if exists('g:vscode')
    source $HOME/.config/nvim/vscode/vscode.vim
    source $HOME/.config/nvim/plug-config/targets.vim
else
    source $HOME/.config/nvim/themes/gruvbox.vim
    source $HOME/.config/nvim/themes/airline.vim
    source $HOME/.config/nvim/filetype/filetype.vim

    " Source all plugin configuration files
    for s:fpath in split(globpath('$HOME/.config/nvim/plug-config', '*.vim'), '\n')
        exe 'source' s:fpath
    endfor
endif

