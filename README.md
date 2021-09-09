# NeoVim setup

This is a setup for Neovim>=0.5.

## Installation

Basically, this should (after installing system dependencies) work just by cloning this repository and fetching its plugin submodules:

```bash
git clone --depth 1 https://github.com/echasnovski/nvim.git

# Download all plugin submodules with latest commit
# `--recursive` ensures that submodules of plugins are also downloaded
git submodule update --init --depth 1 --recursive
```

## Maintenance

### Update all plugins

Get the latest updates from submodules' remotes:

```bash
git submodule update --remote --init --depth 1 --recursive
```

### Add new plugin

Add new plugin as a normal submodule. NOTEs:

- Current naming convention is to strip any "extension-like" substring from end of plugin name (usually it is '.nvim', '.lua', '.vim').
- Plugins should be added to package directory 'pack/plugins' in one of 'start' or 'opt'.

For example, 'nvim-telescope/telescope-fzy-native.nvim' (as it has its submodule) to 'opt' directory:

```bash
# Add submodule. This will load plugin (but not its submodules)
git submodule add --depth 1 https://github.com/nvim-telescope/telescope-fzy-native.nvim pack/plugins/opt/telescope-fzy-native

# Ensure that all submodules of plugin are also downloaded
git submodule update --init --depth 1 --recursive
```

### Delete plugin

Delete plugin as a normal submodule. For example, 'telescope-fzy-native.nvim' from 'pack/plugins/opt' directory:

```bash
submodule_name="pack/plugins/opt/telescope-fzy-native"

# Unregister submodule (this also empties plugin's directory)
git submodule deinit -f $submodule_name

# Remove the working tree of the submodule
git rm --cached $submodule_name

# Remove relevant section from '.gitmodules'
git config -f .gitmodules --remove-section "submodule.$submodule_name"

# Remove submodule's (which should be empty) directory from file system
rm -r $submodule_name

# Remove associated submodule directory in '.git/modules'.
git_dir=`git rev-parse --git-dir`
rm -rf $git_dir/modules/$submodule_name

# Optionally: add and commit changes
git add .
git commit -m "Remove $submodule_name plugin."
```

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
    - Possibly change default version of node which is added to `$PATH` via `nvm alias default <version>`.

- **Nerd fonts** ([information source](https://gist.github.com/matthewjberger/7dd7e079f282f8138a9dc3b045ebefa0)):
    - Download a [Nerd Font](https://www.nerdfonts.com/) (good choice is "UbuntuMono Nerd Font").
    - Unzip and copy to '~/.fonts'.
    - Run the command `fc-cache -fv` to manually rebuild the font cache.

- **Tools for finding stuff**:
    - [ripgrep](https://github.com/BurntSushi/ripgrep#installation)

- **Spelling dictionaries**:
    - Create '~/.nvim/spell' directory.
    - Put there English and Russian dictionaries (download from ftp://ftp.vim.org/pub/vim/runtime/spell/).

- **Clipboard support**. One of 'xsel' (preferred) or 'xclip' (had some minor issues after installing 'vim-exchange').

- **Language Server Protocols**. These should be handled manually for Neovim>=0.5.0. For a list of needed LSP providers look at settings for 'nvim-lspconfig'.

## Notes

- Important dependency is `pynvim` Python package. Path to Python executable for which it is installed should be changed in 'general/settings.vim' as 'g:python3_host_prog' variable.
- Important dependency is `node.js`. Path to it should be changed in 'general/settings.vim' as 'g:node_host_prog' variable. Help for updating its version using `npm`: https://phoenixnap.com/kb/update-node-js-version.
- Output of `:checkhealth` can show that there is a problem with node installation. For some reason, it tries to run `node '[path/to/node] --version'` instead of correct `'[path/to/node]' --version`.
- Two directories ('session' and 'undodir') are placeholders for local use (vim sessions and vim's persistent undo). They both have '.gitignore' files (which instruct to ignore everything in that directory, except '.gitignore' itself to have git recognize them) so that they will be automatically created when pulling this repository.
- For tags to work correctly in R projects, add appropriate '.ctags' file. Currently the source can be found at https://tinyheero.github.io/2017/05/13/r-vim-ctags.html.
- 'Pyright' language server currently by default uses python interpreter that is active when Neovim is opened. However, if using virtual environment, it is a good idea to create 'pyrightconfig.json' file with at least the following content:
    ```
    {
        "include": ["<package_name>"], // Directory of package source
        "venvPath": ".", // Path to folder where virtual environment can be found
        "venv": ".venv" // Folder name of virtual environment
    }
    ```

## Errors

## Tips and tricks

- This setup is configured to use buffers instead of tabs. Remember: buffer ~ file (saved or not), window ~ view of a buffer, tab ~ collection of windows. Normally you would have multiple buffers open in a single window which completely emulates "tab behavior" of "normal editor" (only with current settings of 'vim-airline' which shows buffers in "tabline" in case of a single tab). Splits create separate windows inside single tab. Usually use tabs to work on "different" projects. Useful keybindings:
    - `<Leader>b` has set of commands related to buffers. For example, `<Leader>bd` - close buffer.
    - `:q` - close window.
    - `]b` and `[b` - go to next and previous buffer (current keybinding).
    - `<Leader>fb` - list all present buffers with fuzzy searcher (current keybinding).
- Source for some inspiration: https://stackoverflow.com/questions/726894/what-are-the-dark-corners-of-vim-your-mom-never-told-you-about . Notable examples:
    - Use `:.![command]` to execute command in terminal and put its output into current buffer. For example: `:.!ls -lhR`.
- When testing with 'vim-test', use `-strategy=make` argument to `:Test*` commands in order to populate quickfix list. **Note** that this will not display testing process as it is running and won't open quickfix list by default.
