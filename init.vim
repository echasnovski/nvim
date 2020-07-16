" Always source these
source $HOME/.config/nvim/vim-plug/plugins.vim
source $HOME/.config/nvim/general/settings.vim
source $HOME/.config/nvim/general/mappings.vim
source $HOME/.config/nvim/general/spelling.vim
source $HOME/.config/nvim/plug-config/targets.vim

if exists('g:vscode')
    source $HOME/.config/nvim/vscode/vscode.vim
else
    source $HOME/.config/nvim/themes/gruvbox.vim
    source $HOME/.config/nvim/filetype/filetype.vim

    source $HOME/.config/nvim/plug-config/coc.vim
    source $HOME/.config/nvim/plug-config/nerdtree.vim
    source $HOME/.config/nvim/plug-config/semshi.vim
    source $HOME/.config/nvim/plug-config/nvim-ipy.vim
endif

