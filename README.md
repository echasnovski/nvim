# NeoVim setup

This is a modified version of https://github.com/ChristianChiarulli/nvim. It was set up incrementally by following 'neovim' tag on [his blog](https://www.chrisatmachine.com/neovim).

Basically, this should (after installing system dependencies) work just by cloning this repository into '~/.config/nvim' path and running `:PlugInstall`.

Important system dependencies:

- Neovim python support (preferably to be installed in a separate virtual evnironment dedicated specifically to NeoVim):

    pip install pynvim

- Neovim node support (generally taken from https://phoenixnap.com/kb/update-node-js-version), optional but needed for coc.nvim:

    - Install `nvm`:

        sudo apt install build-essential checkinstall libssl-dev
        curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.35.1/install.sh | bash

    - Close and reopen the terminal. Verify installation with `nvm --version`.

    - Check which version is currently running (`nvm ls`) and which are available (`nvm ls-remote`).

    - Install specific version:

        nvm install [version.number]

    - Switch to installed version with `nvm use [version.number]`.

    - Install `neovim` package:

        npm i neovim

## Notes

- Important dependency is `pynvim` Python package. Path to Python executable for which it is installed should be changed in 'general/settings.vim' as 'g:python3_host_prog' variable.
- Important dependency is `node.js`. Path to it should be changed in 'general/settings.vim' as 'g:node_host_prog' variable. Help for updating its version using `npm`: https://phoenixnap.com/kb/update-node-js-version.
- Output of `:checkhealth` can show that there is a problem with node installation. For some reason, it tries to run `node '[path/to/node] --version'` instead of correct `'[path/to/node]' --version`.

