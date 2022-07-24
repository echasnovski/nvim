-- Enable syntax highlighing if it wasn't already (as it is time consuming)
-- It should be before treesitter is initialized because otherwise there can be
-- weird issues:
-- - When using highlight group like `cterm=underline gui=underline`, it
--   sometimes changes foreground color defined in default syntax and not in
--   treesitter.
if vim.fn.exists('syntax_on') ~= 1 then vim.cmd([[syntax enable]]) end

require('nvim-treesitter.configs').setup({
  ensure_installed = {
    'bash',
    'c',
    'cpp',
    'css',
    'html',
    'javascript',
    'json',
    'julia',
    'lua',
    'markdown',
    'python',
    'r',
    'regex',
    'rst',
    'toml',
    'tsx',
    'yaml',
  },
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
        ['ac'] = '@class.outer',
        ['ic'] = '@class.inner',
        ['aF'] = '@function.outer',
        ['iF'] = '@function.inner',
        -- Used in R
        ['io'] = '@pipe',
      },
    },
    move = {
      enable = true,
      goto_next_start = {
        [']m'] = '@function.outer',
        [']]'] = '@class.outer',
      },
      goto_previous_start = {
        ['[m'] = '@function.outer',
        ['[['] = '@class.outer',
      },
    },
  },
  indent = { enable = false },
  playground = {
    enable = true,
    disable = {},
    updatetime = 25, -- Debounced time for highlighting nodes in the playground from source code
    persist_queries = false, -- Whether the query persists across vim sessions
  },
  -- incremental_selection = {
  --   enable = true,
  --   keymaps = {
  --     init_selection = 'gnn',
  --     node_incremental = 'grn',
  --     scope_incremental = 'grc',
  --     node_decremental = 'grm',
  --   },
  -- },
})

-- Implement custom fold expression for markdown files. Should be defined after
-- `nvim-treesitter` initialization to avoid issues from lazy loading.
--
-- Designed to work with https://github.com/MDeiml/tree-sitter-markdown
-- General ideas:
-- - Requires 'folds.scm' query.
-- - Creates folds on headings (with fold level equal to heading level) and
--   code blocks.
-- - Code is basically a modification of 'nvim-treesitter/fold.lua'.
local query = require('nvim-treesitter.query')
local parsers = require('nvim-treesitter.parsers')
local ts_utils = require('nvim-treesitter.ts_utils')

local folds_levels = ts_utils.memoize_by_buf_tick(function(bufnr)
  local parser = parsers.get_parser(bufnr)

  if not (parser and query.has_folds('markdown')) then return {} end

  local levels = {}

  -- NOTE: don't use `_recursive` variant to fold only based on markdown itself
  local matches = query.get_capture_matches(bufnr, '@fold', 'folds')
  for _, m in pairs(matches) do
    local node = m.node
    local s_row, _, e_row, _ = node:range()
    local node_is_heading = node:type() == 'atx_heading' or node:type() == 'setext_heading'
    local node_is_code = node:type() == 'fenced_code_block'

    -- Process heading. Start fold at start line of heading with fold level
    -- equal to header level.
    if node_is_heading then
      for child in node:iter_children() do
        local _, _, level = string.find(child:type(), 'h([0-9]+)')
        if level ~= nil then
          levels[s_row] = ('>%s'):format(level)
          break
        end
      end
    end

    -- Process code block. Add fold level at start line and subtract at end.
    if node_is_code then
      levels[s_row] = 'a1'
      levels[e_row - 1] = 's1'
    end
  end

  return levels
end)

EC.markdown_foldexpr = function()
  local levels = folds_levels(vim.api.nvim_get_current_buf()) or {}

  return levels[vim.v.lnum - 1] or '='
end
