# Neovim setup

This is a setup for Neovim>=0.8. Current structure (might be a bit outdated):

```
after/                # Everything that will be sourced last (`:h after-directory`)
│ ftplugin/           # Configurations for filetypes
│ queries/            # Queries for treesitter
└ snippets/           # Local snippets (override installed collection)
colors/               # Personal color schemes
lua/                  # Lua code used in configuration
└ mini-dev/           # Development code for 'mini.nvim'
misc/                 # Everything not directly related to Neovim startup
│ dict/               # Dictionary files
│ mini_vimscript/     # Vimscript (re)implementation of some 'mini' modules
└ scripts/            # Scripts for miscellaneous usage
plugin/               # Modularized config files sourced during startup
│ 10_options.lua      # Built-in options/settings
│ 11_mappings.lua     # Personal mappings
│ 12_functions.lua    # Personal functions
│ 13_vscode.lua       # VSCode related configuration
│ 20_mini.lua         # Configuration of 'mini.nvim'
└ 21_plugins.lua      # Configuration of other plugins
snippets/             # Global snippets
spell/                # Spelling files
```

NOTEs:
- Code is modularized with parts put into 'plugin/' directory which is sourced automatically during Neovim startup. Files have numeric prefix to ensure that they are loaded in particular order (matters as some files depend on previous ones; like some plugin setup can depend on set options, etc.).

  Currently general approach is to use 'lua/', but it has some downsides:
    - All modules inside of it are shared across installed plugins. This might lead to naming conflicts. It can be avoided by creating "personalized" directory module (like 'lua/ec/'), but with `plugin/` it is not necessary.
    - Using `require()` to source those modules is not easily reloadable, as `require()` caches its outputs (stored inside `package.loaded` table).
      Having config in 'plugin' doesn't solve this directly, but files are more suited to be called with `:source`.

## Installation

Basically, this should (after installing system dependencies) work just by cloning this repository and waiting until all plugins/dependencies are installed (when there is no visible progress):

```bash
git clone --filter=blob:none https://github.com/echasnovski/nvim.git
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
    - Put there English,Russian dictionaries (download from ftp://ftp.vim.org/pub/vim/runtime/spell/).

- **Clipboard support**. One of 'xsel' (preferred) or 'xclip'.

- **Language Servers**. These should be handled manually. For a list of needed LSP providers look at settings for 'nvim-lspconfig'.

- **Pre-commit hooks** (not strictly necessary but "good to have"). This repository uses pre-commit hooks to verify integrity of code. Preferred way of setting this up:
    - Install `pre-commit`. Preferred way is to use [pipx](https://github.com/pypa/pipx) with `pipx install pre-commit`. There also [other options](https://pre-commit.com/#install).
    - From the root of this repository run `pre-commit install`. This enables pre-commit checks. Now they will be run before any commit. In case they did something, you need to `git add` those changes before commiting will become allowed.

## Plugin management

Plugin management is done with 'mini.deps'. See `:h mini.deps`. In short:

- To add plugin, add call to `add()` with plugin source. Restart Neovim.
- To update plugins, run `:DepsUpdate`, review changes, `:write`. Don't forget to `:DepsSnapSave` and commit `mini-deps-snap`. See `:h DepsUpdate` and `:h DepsSnapSave`.
- To delete plugin, remove its `add()` line from config, restart Neovim, run `:DepsClean`.

NOTEs:
- Loading of most non-essential to startup plugins is deferred until after it with `later()` from 'mini.deps'. This mostly doesn't affect general usability: it decreases time before showing fully functional start screen (or asked file) from \~240ms to \~105ms (on a not so quick i3-6100) to \~65ms (on Ryzen 5600u).

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
