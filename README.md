# NeoVim setup

This is a setup for Neovim>=0.8. Current structure (might be a bit outdated):

```
after/                  # Everything that will be sourced last (`:h after-directory`)
│ ftplugin/             # Configurations for filetypes
└ queries/              # Queries for treesitter
lua/                    # Lua code used in configuration
├ ec/                   # Custom 'plugin namespace'
│ │ configs/            # Configurations for plugins
│ │ functions.lua       # Custom functions
│ │ mappings-leader.lua # Mappings for `<Leader>` key
│ │ mappings.lua        # Mappings
│ │ packadd.lua         # Code for initializing plugins
│ │ settings.lua        # General settings
│ └ vscode.lua          # VS Code related configuration
└ mini-dev/             # Development code for 'mini.nvim'
misc/                   # Everything not directly related to Neovim startup
│ dict/                 # Dictionary files
│ mini_vimscript/       # Vimscript (re)implementation of some 'mini' modules
│ scripts/              # Scripts for miscellaneous usage
│ sessions/             # Placeholder for local use of Neovim sessions (content ignored)
│ snippets/             # Snippets for snippets engine
└ undodir/              # Placeholder for local use of persistent undo (content ignored)
pack/                   # Directory for plugins/submodules managed with native package manager
└ plugins/              # Name of the plugin bundle
  └ opt/                # Use all plugin as optional (requires manual `packadd`)
spell/                  # Files for spelling
```

NOTE: Currently this configuration defers sourcing of most time consuming commands (mostly plugins). This is done by using `vim.schedule(f)` which defers execution of `f` until Vim is loaded. This doesn't affect general usability: it decreases time before showing fully functional start screen (or asked file) from \~240ms to \~105ms (on a not so quick i3-6100) to \~65ms (on Ryzen 5600u).

## Installation

Basically, this should (after installing system dependencies) work just by cloning this repository and fetching its plugin submodules:

```bash
git clone --filter=blob:none https://github.com/echasnovski/nvim.git

# Download all plugin submodules with latest commit
# `--recursive` ensures that submodules of plugins are also downloaded
git submodule update --init --filter=blob:none --recursive
```

## Maintenance

### Update all plugins

Get the latest updates from submodules' remotes:

```bash
git submodule update --remote --init --filter=blob:none --recursive
```

### Add new plugin

1. Download new plugin as a normal submodule. NOTEs:

    - Current naming convention is to strip any "extension-like" substring from end of plugin name (usually it is '.nvim', '.lua', '.vim').
    - Plugins should be added to package directory 'pack/plugins' in one of 'start' or 'opt'. Prefer 'opt' in order to be able to lazy load.

    For example, 'nvim-telescope/telescope-fzy-native.nvim' (as it has its submodule) to 'opt' directory:

    ```bash
    # Add submodule which will track branch `main` (replace manually with what you want; usually 'main' or 'master').
    # This will download plugin (but not its submodules).
    git submodule add --name telescope-fzy-native -b main https://github.com/nvim-telescope/telescope-fzy-native.nvim pack/plugins/opt/telescope-fzy-native

    # Ensure that all submodules of plugin are also downloaded
    git submodule update --init --filter=blob:none --recursive
    ```
1. Ensure that plugin is loaded (added to `runtimepath` and all needed files are executed) alongside its custom configuration (goes into 'lua/ec/configs'):
    - If plugin is added to 'start', nothing is needed to be done.
    - If plugin is added to 'opt', add `packadd()` or `packadd_defer()` call in 'packadd.lua'.

### Delete plugin

Delete plugin as a normal submodule. For example, 'telescope-fzy-native.nvim' from 'pack/plugins/opt' directory:

```bash
submodule_name="telescope-fzy-native"
submodule_path="pack/plugins/opt/$submodule_name"

# Unregister submodule (this also empties plugin's directory)
git submodule deinit -f $submodule_path

# Remove the working tree of the submodule
git rm --cached $submodule_path

# Remove relevant section from '.gitmodules'
git config -f .gitmodules --remove-section "submodule.$submodule_name"

# Remove submodule's (which should be empty) directory from file system
rm -r $submodule_path

# Remove associated submodule directory in '.git/modules'.
git_dir=`git rev-parse --git-dir`
rm -rf $git_dir/modules/$submodule_path

# Optionally: add and commit changes
git add .
git commit -m "Remove $submodule_path plugin."
```

## System dependencies

Important system dependencies:

- **Nerd fonts** ([information source](https://gist.github.com/matthewjberger/7dd7e079f282f8138a9dc3b045ebefa0)):
    - Download a [Nerd Font](https://www.nerdfonts.com/) (good choice is "UbuntuMono Nerd Font").
    - Unzip and copy to '~/.local/share/fonts'.
    - Run the command `fc-cache -fv` to manually rebuild the font cache.

- **Tools for finding stuff**:
    - [ripgrep](https://github.com/BurntSushi/ripgrep#installation)

- **Spelling dictionaries**:
    - Create '~/.nvim/spell' directory.
    - Put there English and Russian dictionaries (download from ftp://ftp.vim.org/pub/vim/runtime/spell/).

- **Clipboard support**. One of 'xsel' (preferred) or 'xclip'.

- **Language Servers**. These should be handled manually. For a list of needed LSP providers look at settings for 'nvim-lspconfig'.

- **Pre-commit hooks** (not strictly necessary but "good to have"). This repository uses pre-commit hooks to verify integrity of code. Preferred way of setting this up:
    - Install `pre-commit`. Preferred way is to use [pipx](https://github.com/pypa/pipx) with `pipx install pre-commit`. There also [other options](https://pre-commit.com/#install).
    - From the root of this repository run `pre-commit install`. This enables pre-commit checks. Now they will be run before any commit. In case they did something, you need to `git add` those changes before commiting will become allowed.

## Notes

- 'Pyright' language server currently by default uses python interpreter that is active when Neovim is opened. However, if using virtual environment, it is a good idea to create 'pyrightconfig.json' file with at least the following content:
    ```
    {
        "include": ["<package_name>"], // Directory of package source
        "venvPath": ".", // Path to folder where virtual environment can be found
        "venv": ".venv" // Folder name of virtual environment
    }
    ```

## Tips and tricks

- When testing with 'vim-test', use `-strategy=make` argument to `:Test*` commands in order to populate quickfix list. **Note** that this will not display testing process as it is running and won't open quickfix list by default.
