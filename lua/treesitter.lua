require'nvim-treesitter.configs'.setup {
  ensure_installed = { "json", "python", "lua", "bash", "html", "julia", "css", "regex", "rst", "yaml", "toml"},
  highlight = { enable = true },
  textobjects = {
    -- Not having textobjects for arguments (`parameter.inner` and
    -- `parameter.outer`) because it currently doesn't always work intuitively.
    -- For example, in Python's list `[1, 2, 3]` elements are not recognized as
    -- arguments. 'Sideways.vim' plugin handles this better.
    enable = true,
    select = {
      enable = true,
      keymaps = {
        ["ac"] = "@class.outer",
        ["ic"] = "@class.inner",
        ["af"] = "@function.outer",
        ["if"] = "@function.inner",
        ["aF"] = "@call.outer",
        ["iF"] = "@call.inner",
        -- Used in R
        ["io"] = "@pipe",
      },
    },
    move = {
      enable = true,
      goto_next_start = {
        ["]m"] = "@function.outer",
        ["]]"] = "@class.outer",
      },
      goto_previous_start = {
        ["[m"] = "@function.outer",
        ["[["] = "@class.outer",
      },
    }
  },
  indent = { enable = false },
  playground = {
    enable = true,
    disable = {},
    updatetime = 25, -- Debounced time for highlighting nodes in the playground from source code
    persist_queries = false -- Whether the query persists across vim sessions
  },
  -- incremental_selection = {
  --   enable = true,
  --   keymaps = {
  --     init_selection = "gnn",
  --     node_incremental = "grn",
  --     scope_incremental = "grc",
  --     node_decremental = "grm",
  --   },
  -- },
}

-- Setup R parser
-- To install it:
-- - Install tree-sitter-cli:
--   https://tree-sitter.github.io/tree-sitter/creating-parsers#installation
-- - Run `:TSInstallFromGrammar r`
local parser_config = require "nvim-treesitter.parsers".get_parser_configs()
parser_config.r = {
  install_info = {
    url = "https://github.com/r-lib/tree-sitter-r", -- local path or git repo
    files = { "src/parser.c" }
  },
  filetype = "r", -- if filetype does not agrees with parser name
  used_by = { "rmd" } -- additional filetypes that use this parser
}
