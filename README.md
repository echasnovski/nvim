# NeoVim setup

This is a modified version of https://github.com/ChristianChiarulli/nvim. It was set up incrementally by following 'neovim' tag on [his blog](https://www.chrisatmachine.com/neovim).

Basically, this should (after installing system dependencies) work just by cloning this repository into '~/.config/nvim' path and running `:PlugInstall`.

# System dependencies

Important system dependencies:

- (Optional but highly advisable) Separate python3 evnironment (called 'neovim') with necessary packages:
    - Install `pyenv`. Source for installation:  https://linux-notes.org/ustanovka-pyenv-v-unix-linux/. **Note**: it probably can be `conda` or any other environment management tool (with some tweaks to configuration files afterwards).
    - Install recent version of Python.
    - Create 'neovim' environment with `pyenv virtualenv [options] neovim`.
    - Activate 'neovim' environment with `pyenv activate neovim`.
    - Install NeoVim python support:

    ```bash
        python -m pip install pynvim
    ```
    - Install 'Black' formatting engine. **Note** if done differently, don't forget to change path to it in "python.formatting.blackPath" variable in 'coc-settings.json':

    ```bash
        python -m pip install pynvim
    ```

- Neovim node support (generally taken from https://phoenixnap.com/kb/update-node-js-version), optional but needed for coc.nvim:

    - Install `nvm`:

    ```bash
        sudo apt install build-essential checkinstall libssl-dev
        curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.35.1/install.sh | bash
    ```

    - Close and reopen the terminal. Verify installation with `nvm --version`.

    - Check which version is currently running (`nvm ls`) and which are available (`nvm ls-remote`).

    - Install specific version:

    ```bash
        nvm install [version.number]
    ```

    - Switch to installed version with `nvm use [version.number]`.

    - Install `neovim` package:

    ```bash
        npm i neovim
    ```

    - Possibly change `node_host_prog` variable in 'general/settings.vim' with correct path.

## Notes

- Important dependency is `pynvim` Python package. Path to Python executable for which it is installed should be changed in 'general/settings.vim' as 'g:python3_host_prog' variable.
- Important dependency is `node.js`. Path to it should be changed in 'general/settings.vim' as 'g:node_host_prog' variable. Help for updating its version using `npm`: https://phoenixnap.com/kb/update-node-js-version.
- Output of `:checkhealth` can show that there is a problem with node installation. For some reason, it tries to run `node '[path/to/node] --version'` instead of correct `'[path/to/node]' --version`.

