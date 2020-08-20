# NeoVim setup

This is a modified version of https://github.com/ChristianChiarulli/nvim. It was set up incrementally by following 'neovim' tag on [his blog](https://www.chrisatmachine.com/neovim).

Basically, this should (after installing system dependencies) work just by cloning this repository into '~/.config/nvim' path and running `:PlugInstall`.

## System dependencies

Important system dependencies:

- (Optional but highly advisable) **Separate python3 evnironment** (called 'neovim') **with necessary packages** (variable `g:python3_host_prog` should point to Python interpreter of this environment):
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
        python -m pip install black
    ```
    - When working with 'nvim-ipy' plugin, you might need to install 'jupyter' into this environment. See 'Notes' section.

- **Neovim node support** (generally taken from https://phoenixnap.com/kb/update-node-js-version), optional but needed for coc.nvim:

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

    - Possibly change `node_host_prog` (in 'general/settings.vim') and `coc_node_path` (in 'plugins/coc.nvim') variables with correct path.

- **Nerd fonts** ([information source](https://gist.github.com/matthewjberger/7dd7e079f282f8138a9dc3b045ebefa0)):
    - Download a [Nerd Font](https://www.nerdfonts.com/) (good choice is "UbuntuMono Nerd Font").
    - Unzip and copy to '~/.fonts'.
    - Run the command `fc-cache -fv` to manually rebuild the font cache.

- **Tools for finding stuff**:
    - [fzf](https://github.com/junegunn/fzf#installation)
    - [ripgrep](https://github.com/BurntSushi/ripgrep#installation)

- **Spelling dictionaries**:
    - Create '~/.nvim/spell' directory.
    - Put there English and Russian dictionaries (download from ftp://ftp.vim.org/pub/vim/runtime/spell/).

- **Clipboard support**. One of 'xsel' (preferred) or 'xclip' (had some minor issues after installing 'vim-exchange').

- **ranger**.
    - There are three ways of installing it that worked for me in different situations:
        - _First_ seems to be the most robust (`. ranger` works in command line and 'rnvimr' picks files inside Neovim):
            - Install (if not already installed) [pipx](https://github.com/pipxproject/pipx).
            - Install 'ranger-fm' package with 'pipx' by runngin `pipx install ranger-fm`. This already should be enough to be used in command line.
            - To work in Neovim with 'rnvimr', package 'pynvim' should be installed in the same environment in which 'ranger' (or rather 'ranger-fm') is installed. It should be located at '~/.local/pipx/venvs/ranger-fm/'. Go into that directory. It should have python executables (probably both `python` and `python3`). Use them to install 'pynvim' package by running: `./python3 -m pip install pynvim`. This should enable 'rnvimr' to pick files inside Neovim.
        - _Second_ is to run `python -m pip install ranger-fm pynvim`, as instructed in ['rnvimr' plugin README](https://github.com/kevinhwang91/rnvimr#dependence). Make sure to use appropriate Pythonv version.
        - _Third_ is to install from source ([original instructions](https://vitux.com/how-to-install-ranger-terminal-file-manager-on-linux/)):
            - Clone 'ranger' to appropriate place (something like dedicated 'Install' directory:

            ```bash
                git clone https://github.com/hut/ranger.git
            ```

            - Install it with `make install` (executed from 'ranger' directory).
    - It is also handy to use Ranger devicons by installing [this plugin](https://github.com/alexanderjeurissen/ranger_devicons) and setting `default_linemode devicons` in `rc.conf`:

    ```bash
        git clone https://github.com/alexanderjeurissen/ranger_devicons ~/.config/ranger/plugins/ranger_devicons
    ```

## Notes

- Important dependency is `pynvim` Python package. Path to Python executable for which it is installed should be changed in 'general/settings.vim' as 'g:python3_host_prog' variable.
- Important dependency is `node.js`. Path to it should be changed in 'general/settings.vim' as 'g:node_host_prog' variable. Help for updating its version using `npm`: https://phoenixnap.com/kb/update-node-js-version.
- Output of `:checkhealth` can show that there is a problem with node installation. For some reason, it tries to run `node '[path/to/node] --version'` instead of correct `'[path/to/node]' --version`.
- If encounter 'E117: Unknown function: IPyConnect' error while using 'nvim-ipy' plugin (which shows when 'nvim-ipy' has just been installed), run `:UpdateRemotePlugins` and restart NeoVim. **Note** that in order to run `:UpdateRemotePlugins`, NeoVim uses Python interpreter set in `g:python3_host_prog`. That Python interpreter needs to have **both** 'pynvim' and 'jupyter' installed. There are two possible solutions:
    - Install 'jupyter' to 'neovim' virtual environment set up in 'System dependencies' section (possibly, the easiest one).
    - Temporarily have `g:python3_host_prog` point to interpreter in separate environment with installed 'pynvim' and 'jupyter'.
- If when using 'nvim-ipy', you see "AttributeError: 'IPythonPlugin' object has no attribute 'km'" error, it might mean that no connection with `:IPython` was done.  In present setup, it means you forgot to type `<Leader>ik` after `<Leader>iq`.
- If you want 'coc-python' to always use python from $PATH (the one returned by `which python` when NeoVim is opened), you can use this hack ([original source](https://www.reddit.com/r/neovim/comments/dyl6xw/need_help_setting_up_cocnvim_for_python_with/f81to9e/)):
    - Create _executable_ file (for example, 'pythonshim' inside this top 'nvim' directory) with the following code:

    ```bash
    #!/bin/bash

    python "$@"
    ```
    - Put full path to this file as "python.pythonPath" settings in 'coc-settings.json'.

    **Note** that otherwise you should either choose manually Python interpreter (via `CocCommand python.setInterpreter`) or have '.nvim/coc-settings.json' file in project root with relevant option "python.pythonPath".
- Two directories ('session' and 'undodir') are placeholders for local use (vim sessions and vim's persistent undo). They both have '.gitignore' files (which instruct to ignore everything in that directory, except '.gitignore' itself to have git recognize them) so that they will be automatically created when pulling this repository.

## Errors

- `E117: Unknown function: IPyConnect`: run `:UpdateRemotePlugins` to properly use 'nvim-ipy' plugin (see 'Notes').
- `AttributeError: 'IPythonPlugin' object has no attribute 'km'`: connect to IPython console (see 'Notes').
- `[coc.nvim] Jedi error: Cannot call write after a stream was destroyed`: current Python interpreter used by 'coc.nvim' doesn't have 'jedi' installed. Make sure you use proper Python interpreter (set with `:CocCommand` and proper 'python.setInterpreter' value) where it is installed.

## Tips and tricks

- This setup is configured to use buffers instead of tabs. Remember: buffer ~ file (saved or not), window ~ view of a buffer, tab ~ collection of windows. Normally you would have multiple buffers open in a single window which completely emulates "tab behavior" of "normal editor" (only with current settings of 'vim-airline' which shows buffers in "tabline" in case of a single tab). Splits create separate windows inside single tab. Usually use tabs to work on "different" projects. Useful keybindings:
    - `:bd` - close buffer.
    - `:q` - close window.
    - `<TAB>` and `<SHIFT-TAB>` - go to next previous buffer (current keybinding).
    - `<Leader>b` - list all present buffers with fzf (current keybinding).
- Source for some inspiration: https://stackoverflow.com/questions/726894/what-are-the-dark-corners-of-vim-your-mom-never-told-you-about . Notable examples:
    - Use `:.![command]` to execute command in terminal and put its output into current buffer. For example: `:.!ls -lhR`.
- In NERDTree use 'm' keybinding to open a menu with actions you can do with current file tree.
- When testing with 'vim-test', use `-strategy=make` argument to `:Test*` commands in order to populate quickfix list. **Note** that this will not display testing process as it is running and won't open quickfix list by default.
