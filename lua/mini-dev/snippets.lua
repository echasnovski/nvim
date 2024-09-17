-- TODO:
--
-- Code:
-- - A system to load and manage custom snippets:
--     -  Decide whether to allow "scope" when reading snippets.
--
-- - A system to match snippet based on prefix:
--
-- - A system to expand, navigate, and edit snippet:
--
-- Docs:
--
-- Tests:
--

--- *mini.snippets* Manage and expand snippets
--- *MiniSnippets*
---
--- MIT License Copyright (c) 2024 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Snippet is a template for a frequently used text. Typical workflow is to type
--- snippet's (configurable) prefix and expand it into a snippet session.
---
--- The template usually contains both pre-defined text and places (called
--- "tabstops") for user to interactively add text during snippet session.
---
--- This module supports (only) snippet format defined in LSP specification.
--- See |MiniSnippets-specification|.
---
--- Features:
--- - Manage snippet collection with a flexible system of built-in loaders.
---   See |MiniSnippets.gen_loader|.
---
--- - Match which snippet to expand based on the currently typed text.
---
--- - Expand, navigate, and edit snippet in a configurable manner.
---
--- See |MiniSnippets-examples| for common configuration examples.
---
--- Notes:
--- - It does not load any snippets by default. Add to `config.snippets` to
---   have snippets to choose from.
--- - It does not come with a built-in snippet collection. It is expected from
---   users to add their own snippets, manually or with a dedicated plugin(s).
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.snippets').setup({})` (replace `{}`
--- with your `config` table). It will create global Lua table `MiniSnippets` which
--- you can use for scripting or manually (with `:lua MiniSnippets.*`).
---
--- See |MiniSnippets.config| for `config` structure and default values.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.minisnippets_config` which should have same structure as
--- `Minisnippets.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons ~
---
--- - 'L3MON4D3/LuaSnip':
---     - ...
---
--- - Built-in |vim.snippet| (on Neovim>=0.10):
---     - Both contain expand functionality based on LSP snippet format.
---     - Does not contain any functionality to load or match snippets (by design),
---       while this module does.
---
--- - 'rafamadriz/friendly-snippets':
---     - A snippet collection plugin without functionality to manage them.
---       This module is designed to be compatible 'friendly-snippets'.
---
--- # Highlight groups ~
---
--- * `MiniSnippetsCurrent` - current tabstop.
--- * `MiniSnippetsPlaceholder` - placeholder of not yet visited tabstop.
--- * `MiniSnippetsVisited` - text of visited tabstop.
---
--- To change any highlight group, modify it directly with |:highlight|.
---
--- # Disabling ~
---
--- To disable core functionality, set `vim.g.minisnippets_disable` (globally) or
--- `vim.b.minisnippets_disable` (for a buffer) to `true`. Considering high number
--- of different scenarios and customization intentions, writing exact rules
--- for disabling module's functionality is left to user. See
--- |mini.nvim-disabling-recipes| for common recipes.

--- # Snippet format specification ~
---@tag MiniSnippets-specification

--- # Common configuration examples ~
---@tag MiniSnippets-examples

---@alias __minisnippets_cache_opt <cache> `(boolean)` - whether to use cached output. Default: `true`.

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local

-- Module definition ==========================================================
-- TODO: make local before release
MiniSnippets = {}
H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniSnippets.config|.
---
---@usage >lua
---   require('mini.snippets').setup({}) -- replace {} with your config table
---                                      -- needs `highlighters` field present
--- <
MiniSnippets.setup = function(config)
  -- Export module
  _G.MiniSnippets = MiniSnippets

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands()

  -- Create default highlighting
  H.create_default_hl()
end

--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # Loaded snippets ~
---
--- # Mappings ~
MiniSnippets.config = {
  snippets = {},
  match = {},
  mappings = {
    expand = '<C-l>',
    jump_next = '<C-l>',
    jump_prev = '<C-h>',
  },
  expand = {},
}
--minidoc_afterlines_end

--- Generate snippet loader
---
--- Designed to be compatible with 'rafamadriz/friendly-snippets'.
MiniSnippets.gen_loader = {}

---@param opts table|nil Options. Possible values:
---   - <ft_patterns> `(table)` - map from filetype to runtime patterns used to
---     find snippet files. If non-empty filetype is absent, the default one is
---     constructed: searches for "json" and "lua" files named as filetype or have
---     ancestor directory named as filetype.
---     Example for "lua" filetype: `{ 'lua.{json,lua}', 'lua/**.{json,lua}' }`.
---   - __minisnippets_cache_opt
MiniSnippets.gen_loader.from_filetype = function(opts)
  opts = vim.tbl_extend('force', { ft_patterns = {}, cache = true }, opts or {})
  for ft, tbl in pairs(opts.ft_patterns) do
    if type(ft) ~= 'string' then H.error('Keys of `opts.ft_patterns` should be string filetype names') end
    if not H.is_array_of(tbl, H.is_string) then H.error('Keys of `opts.ft_patterns` should be string arrays') end
  end

  local cache, read_opts = opts.cache, { cache = opts.cache }
  local read = function() return MiniSnippets.read_file(path, read_opts) end
  return function()
    local ft = vim.bo.filetype
    if cache then
      local res = H.cache_loaders.filetype[ft]
      if res ~= nil then return res end
    end

    local patterns = opts.ft_patterns[ft]
    if patterns == nil and ft == '' then return end
    patterns = patterns or { ft .. '.{json,lua}', ft .. '/**.{json,lua}' }
    patterns = vim.tbl_map(function(p) return 'snippets/' .. p end, patterns)

    local res = vim.tbl_map(read, vim.api.nvim_get_runtime_file(pattern, true))
    H.cache_loaders.filetype[ft] = res
    return res
  end
end

---@param pattern string Pattern of files to read which will be searched in "snippets"
---   subdirectory inside 'runtimepath' paths. Can contain wildcards as described
---   in |nvim_get_runtime_file()|.
---@param opts table|nil Options. Possible fields:
---   - <all> `(boolean)` - whether to load from all matching runtime files or
---     only the first one. Default: `true`.
---   - __minisnippets_cache_opt
MiniSnippets.gen_loader.from_runtime = function(pattern, opts)
  if type(pattern) ~= 'string' then H.error('`pattern` should be string') end
  opts = vim.tbl_extend('force', { all = true, cache = true }, opts or {})

  pattern = 'snippets/' .. pattern
  local cache, read_opts = opts.cache, { cache = opts.cache }
  local read = function() return MiniSnippets.read_file(path, read_opts) end
  return function()
    if cache then
      local res = H.cache_loaders.runtime[pattern]
      if res ~= nil then return res end
    end

    local res = vim.tbl_map(read, vim.api.nvim_get_runtime_file(pattern, opts.all))
    H.cache_loaders.filetype[ft] = res
    return res
  end
end

---@param path string Path for file to load. Allowed extensions: "json", "lua".
---   Relative paths are resolved against |current-directory|.
MiniSnippets.gen_loader.from_file = function(path, opts)
  if type(path) ~= 'string' then H.error('`path` should be string') end
  local read_opts = { cache = opts.cache }
  return function() return MiniSnippets.read_file(path, read_opts) end
end

---@param path string Path with snippets to read. Supported extensions:
---   - "json" - should have same format as in 'friendly-snippets'.
---   - "lua" - should return array of snippets. See |MiniSnippets-specification|.
---@param opts table|nil Options. Possible fields:
---   - __minisnippets_cache_opt
MiniSnippets.read_file = function(path, opts)
  opts = vim.tbl_extend('force', { cache = true }, opts or {})

  local full_path = vim.fn.fnamemodify(path, ':p')
  if opts.cache then
    local res = H.cache_loaders.file[full_path]
    if res ~= nil then return res end
  end

  if (vim.loop.fs_stat(full_path) or {}).type ~= 'file' then
    H.error('Path ' .. full_path .. ' is not a readable file on disk.')
  end
  local ext = full_path:match('%.([^%.]+)$')
  if ext == nil or not (ext == 'lua' or ext == 'json') then
    H.error('Path ' .. full_path .. ' is neither .lua nor .json')
  end

  local res = ext == 'lua' and H.read_file_lua(full_path) or H.read_file_json(full_path)
  H.cache_loaders.file[full_path] = res
  return res
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniSnippets.config)

-- Namespaces for extmarks
H.ns_id = {}

-- Cache for various uses
H.cache_loaders = { filetype = {}, runtime = {}, file = {} }

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  vim.validate({
    snippets = { config.snippets, 'table' },
    mappings = { config.mappings, 'table' },
    match = { config.match, 'table' },
    expand = { config.expand, 'table' },
  })

  vim.validate({
    ['mappings.expand'] = { config.mappings.expand, 'string' },
    ['mappings.jump_next'] = { config.mappings.jump_next, 'string' },
    ['mappings.jump_prev'] = { config.mappings.jump_prev, 'string' },
  })

  return config
end

H.apply_config = function(config)
  MiniSnippets.config = config

  -- Reset loader cache
  H.cache_loaders = { filetype = {}, runtime = {}, file = {} }
end

H.create_autocommands = function()
  local gr = vim.api.nvim_create_augroup('MiniSnippets', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = gr, pattern = pattern, callback = callback, desc = desc })
  end

  au('ColorScheme', '*', H.create_default_hl, 'Ensure colors')
end

--stylua: ignore
H.create_default_hl = function()
  vim.api.nvim_set_hl(0, 'MiniSnippetsCurrent', { default = true, link = 'CurSearch' })
  vim.api.nvim_set_hl(0, 'MiniSnippetsPlaceholder', { default = true, link = 'Search' })
  vim.api.nvim_set_hl(0, 'MiniSnippetsVisited', { default = true, link = 'Visual' })
end

H.is_disabled = function(buf_id) return vim.g.minisnippets_disable == true or vim.b.minisnippets_disable == true end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniSnippets.config, vim.b.minisnippets_config or {}, config or {})
end

-- Read -----------------------------------------------------------------------
H.read_file_lua = function(path)
  local ok, res = pcall(dofile, path)
  if not ok then H.error('Could not execute Lua file: ' .. path) end
  if not H.islist(res) then H.error('Lua snippet file ' .. path .. ' should return array') end
  for _, v in ipairs(res) do
    if not H.is_snippet(v) then
      H.error('Lua snippet file ' .. path .. ' contains a not snippet item:\n' .. vim.inspect(v))
    end
  end
  return res
end

H.read_file_json = function(path)
  local file = io.open(path)
  if file == nil then H.error('Could not open file: ' .. path) end
  local raw = file:read('*all')
  file:close()

  local ok, contents = pcall(vim.json.decode, raw)
  if not (ok and type(contents) == 'table') then H.error('File does not contain a valid JSON object: ' .. path) end

  local res = {}
  for name, t in pairs(contents) do
    if not H.is_snippet(t) then
      H.error('In file ' .. path .. ' value of key ' .. vim.inspect(name) .. ' is not a snippet')
    end
    t.description = t.description or name
    table.insert(res, t)
  end

  return res
end

-- -- Validate that all snippets from 'friendly-snippets' are readable
-- local dir = '~/.local/share/nvim/site/pack/deps/opt/friendly-snippets/snippets/'
-- _G.all_snippets = {}
-- for p, p_type in vim.fs.dir(dir, { depth = math.huge }) do
--   if p_type == 'file' then
--     local start_time = vim.loop.hrtime()
--     _G.all_snippets[p] = MiniSnippets.read_file(dir .. p)
--     -- _G.all_snippets[p] = H.read_file_json(dir .. p)
--     add_to_log({ path = p, duration = 0.000001 * (vim.loop.hrtime() - start_time) })
--   end
-- end

-- Validators -----------------------------------------------------------------
H.is_string = function(x) return type(x) == 'string' end

H.is_maybe_string_or_arr = function(x) return x == nil or H.is_string(x) or H.is_array_of(x, H.is_string) end

H.is_snippet = function(x)
  return type(x) == 'table'
    -- Allow nil `prefix` for "wrapping" snippets (utilizing TM_SELECTED_TEXT)
    -- Such snippet will be omitted during normalization
    and H.is_maybe_string_or_arr(x.prefix)
    -- Allow nil `body` to remove snippet with `prefix`
    and H.is_maybe_string_or_arr(x.body)
    -- Allow nil `description`, in which case "prefix" is used
    and H.is_maybe_string_or_arr(x.description)
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.snippets) ' .. msg, 0) end

H.is_array_of = function(x, predicate)
  if not H.islist(x) then return false end
  for i = 1, #x do
    if not predicate(x[i]) then return false end
  end
  return true
end

H.get_line = function(buf_id, line_num)
  return vim.api.nvim_buf_get_lines(buf_id, line_num - 1, line_num, false)[1] or ''
end

H.set_extmark = function(...) pcall(vim.api.nvim_buf_set_extmark, ...) end

H.get_extmarks = function(...)
  local ok, res = pcall(vim.api.nvim_buf_get_extmarks, ...)
  if not ok then return {} end
  return res
end

H.clear_namespace = function(...) pcall(vim.api.nvim_buf_clear_namespace, ...) end

-- TODO: Remove after compatibility with Neovim=0.9 is dropped
H.islist = vim.fn.has('nvim-0.10') == 1 and vim.islist or vim.tbl_islist

return MiniSnippets
