-- TODO:
--
-- Code:
-- - A system to load and manage custom snippets:
--
-- - A system to match snippet based on prefix:
--     - Think about better name than `get_ref`. Candidates: `base_regions`,
--       `ref`, `needle`, `against`.
--
-- - A system to expand, navigate, and edit snippet:
--
-- Docs:
-- - Normalized snippets for buffer are cached. Execute `:edit` to clear
--   current buffer cache.
--
-- Tests:
-- - Management:
--     - `cache = false` should not write to cache (to possibly save memory).
--     - `gen_loader.from_filetype()` results in preferring snippets:
--         - From exact file over ancestor.
--         - From .lua over .json.
--     - `gen_loader.from_filetype()` processes pattern array in order.
--       Resulting in preferring later ones over earlier.

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
--- This module supports (only) snippet syntax defined in LSP specification.
--- See |MiniSnippets-syntax-specification|.
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
---     - Does not contain functionality to load or match snippets (by design),
---       while this module does.
---
--- - 'rafamadriz/friendly-snippets':
---     - A snippet collection plugin without functionality to manage them.
---       This module is designed with 'friendly-snippets' compatibility in mind.
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

--- # Snippet files specifications ~
---
--- One of the following:
--- - File with .lua extension with code that returns a table of snippet data.
--- - File with .json extension which contains an object with snippet data as
---   values. This is compatible with 'rafamadriz/friendly-snippets'.
---
--- Suggested location is in "snippets" subdirectory of any path in 'runtimepath'.
--- This is compatible with |MiniSnippets.gen_loader.from_runtime()|.
---
--- For format of supported snippet data see "Loaded snippets" |MiniSnippets.config|.
---@tag MiniSnippets-files-specification

--- # Snippet syntax specification ~
---@tag MiniSnippets-syntax-specification

--- # Common configuration examples ~
---
--- - Project-local snippets. Use |MiniSnippets.gen_loader.from_file()| with
---   relative path.
--- - Override certain files. Create `vim.b.minisnippets_config` with
---   `snippets = { MiniSnippets.gen_loader.from_file('path/to/file') }`.
--- - How to imitate <scope> field in snippet data. Put snippet separately in
---   different dedicated files and use |MiniSnippets.gen_loader.from_filetype()|.
---@tag MiniSnippets-examples

---@alias __minisnippets_cache_opt <cache> `(boolean)` - whether to use cached output. Default: `true`.
---@alias __minisnippets_silent_opt <silent> `(boolean)` - whether suppress non-error feedback. Default: `false`.
---@alias __minisnippets_loader_return function Snippet loader.

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
--- `config.snippets` is a (nested) array containing snippet data and loaders.
--- It is normalized for each buffer separately.
---
--- Snippet data is a table with the following fields:
---
--- - <prefix> `(string|table)` - string used to match against user typed base.
---    If array, all strings are used during match. Should always be present.
---
--- - <body> `(string|table|nil)` - content of a snippet which follows
---    the |MiniSnippets-syntax-specification|. Array is concatenated with "\n".
---    If absent / `nil`, removes prefix from normalized buffer snippets.
---
--- - <desc> `(string|table|nil)` - description of snippet. Can be used to display
---   snippets in a more human readable form. Array is concatenated with "\n".
---   If absent / `nil`, <prefix> is used.
---   For compatibility with popular snippet databases, field `<description>`
---   is used as a fallback.
---
--- Notes:
--- - All snippets in `config.snippets` are used in buffer after normalization.
---   Scoping via <scope> field is not supported. See |MiniSnippets-examples|.
---
--- Order in array is important: later ones will override earlier (similar to
--- how |ftplugin| behaves).
---
--- # Match ~
---
--- # Expand ~
---
--- # Mappings ~
MiniSnippets.config = {
  snippets = {},
  match = {
    -- Function to compute reference region containing base for matching
    get_ref = nil,
    -- How to match: "exact", "substring", "fuzzy"
    rule = 'exact',
  },
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
--- This is a table with function elements. Call to actually get a loader.
---
--- Common features for all produced loaders:
--- - Designed to work with |MiniSnippets-files-specification|.
--- - Caches output by default, i.e. second and later calls with same input value
---   don't read files from disk. Disable by setting `opts.cache` to `false`.
---   To reset cache, call |MiniSnippets.setup()|.
--- - Use |vim.notify()| to show problems during loading while trying to load
---   as much correctly defined snippet data as possible.
---   Disable by setting `opts.silent` to `true`.
MiniSnippets.gen_loader = {}

---@param opts table|nil Options. Possible values:
---   - <ft_patterns> `(table)` - map from filetype to array of runtime patterns
---     used to find snippet files. Patterns will be processed in order, so
---     snippets from reading later patterns will override earlier ones.
---     If non-empty filetype is absent, the default one is constructed:
---     searches for "json" and "lua" files that are inside directory named as
---     filetype (however deep) or are named as filetype.
---     Example for "lua" filetype: `{ 'lua/**.{json,lua}', 'lua.{json,lua}' }`.
---   - __minisnippets_cache_opt
---   - __minisnippets_silent_opt
---
---@return __minisnippets_loader_return
MiniSnippets.gen_loader.from_filetype = function(opts)
  opts = vim.tbl_extend('force', { ft_patterns = {}, cache = true, silent = false }, opts or {})
  for ft, tbl in pairs(opts.ft_patterns) do
    if type(ft) ~= 'string' then H.error('Keys of `opts.ft_patterns` should be string filetype names') end
    if not H.is_array_of(tbl, H.is_string) then H.error('Keys of `opts.ft_patterns` should be string arrays') end
  end

  local cache, read_opts = opts.cache, { cache = opts.cache, silent = opts.silent }
  local read = function(p) return MiniSnippets.read_file(p, read_opts) end
  return function()
    local ft = vim.bo.filetype
    if cache and H.cache.filetype[ft] ~= nil then return vim.deepcopy(H.cache.filetype[ft]) end

    local patterns = opts.ft_patterns[ft]
    if patterns == nil and ft == '' then return end
    patterns = patterns or { ft .. '/**.{json,lua}', ft .. '.{json,lua}' }
    patterns = vim.tbl_map(function(p) return 'snippets/' .. p end, patterns)

    local res = {}
    for _, pattern in ipairs(patterns) do
      table.insert(res, vim.tbl_map(read, vim.api.nvim_get_runtime_file(pattern, true)))
    end
    if cache then H.cache.filetype[ft] = vim.deepcopy(res) end
    return res
  end
end

---@param pattern string Pattern of files to read. Will be searched in "snippets"
---   subdirectory inside 'runtimepath' paths. Can contain wildcards as described
---   in |nvim_get_runtime_file()|.
---@param opts table|nil Options. Possible fields:
---   - <all> `(boolean)` - whether to load from all matching runtime files or
---     only the first one. Default: `true`.
---   - __minisnippets_cache_opt
---   - __minisnippets_silent_opt
---
---@return __minisnippets_loader_return
MiniSnippets.gen_loader.from_runtime = function(pattern, opts)
  if type(pattern) ~= 'string' then H.error('`pattern` should be string') end
  opts = vim.tbl_extend('force', { all = true, cache = true, silent = false }, opts or {})

  pattern = 'snippets/' .. pattern
  local cache, read_opts = opts.cache, { cache = opts.cache, silent = opts.silent }
  local read = function(p) return MiniSnippets.read_file(p, read_opts) end
  return function()
    if cache and H.cache.runtime[pattern] ~= nil then return vim.deepcopy(H.cache.runtime[pattern]) end

    local res = vim.tbl_map(read, vim.api.nvim_get_runtime_file(pattern, opts.all))
    if cache then H.cache.filetype[ft] = vim.deepcopy(res) end
    return res
  end
end

---@param path string Same as in |MiniSnippets.read_file()|.
---@param opts table|nil Same as in |MiniSnippets.read_file()|.
---
---@return __minisnippets_loader_return
MiniSnippets.gen_loader.from_file = function(path, opts)
  if type(path) ~= 'string' then H.error('`path` should be string') end
  opts = vim.tbl_extend('force', { cache = true, silent = false }, opts or {})

  return function()
    -- Always be silent about absent path to allow using with relative (project
    -- local) paths (not every cwd needs to have relative path with snippets).
    if vim.loop.fs_stat(vim.fn.fnamemodify(path, ':p')) == nil then return end
    return MiniSnippets.read_file(path, opts)
  end
end

MiniSnippets.default_get_ref = function(opts)
  opts = opts or {}
  local patterns = opts.patterns or { '%S+' }
  if not H.is_array_of(patterns, H.is_string) then H.error('`opts.patterns` should be array of strings') end

  -- In Insert mode match against what is strictly to cursor's left
  local to = vim.fn.col('.') + 1 - (vim.fn.mode() == 'i' and 1 or 0)
  local line_till_cursor, lnum, res = vim.api.nvim_get_current_line():sub(1, to), vim.fn.line('.'), {}
  for _, p in ipairs(patterns) do
    local from = line_till_cursor:find(p .. '$')
    if from ~= nil then table.insert(res, { from = { line = lnum, col = from }, to = { line = lnum, col = to } }) end
  end
  return res
end

---@param path string Path with snippets read. See |MiniSnippets-files-specification|.
---@param opts table|nil Options. Possible fields:
---   - __minisnippets_cache_opt
---   - __minisnippets_silent_opt
---
---@return table|nil Array of snippets or `nil` if reading failed.
MiniSnippets.read_file = function(path, opts)
  if type(path) ~= 'string' then H.error('`path` should be string') end
  opts = vim.tbl_extend('force', { cache = true, silent = false }, opts or {})

  path = vim.fn.fnamemodify(path, ':p')
  if opts.cache and H.cache.file[path] ~= nil then return vim.deepcopy(H.cache.file[path]) end

  if (vim.loop.fs_stat(path) or {}).type ~= 'file' then
    return H.notify('Path ' .. path .. ' is not a readable file on disk.', 'WARN', opts.silent)
  end
  local ext = path:match('%.([^%.]+)$')
  if ext == nil or not (ext == 'lua' or ext == 'json') then
    return H.notify('Path ' .. path .. ' is neither .lua nor .json', 'WARN', opts.silent)
  end

  local res = H.file_readers[ext](path, opts.silent)
  if res == nil then return nil end

  -- Notify about problems but still cache and return read snippets
  local prob = table.concat(res.problems, '\n')
  if prob ~= '' then H.notify('There were problems reading file ' .. path .. ':\n' .. prob, 'WARN', opts.silent) end

  if opts.cache then H.cache.file[path] = vim.deepcopy(res.snippets) end
  return res.snippets
end

MiniSnippets.get_matches = function(base, opts)
  opts = vim.tbl_extend('force', MiniSnippets.config.match, opts or {})
  if base == nil then
    local ref_regions = H.get_ref_regions(opts)
    base = (ref_regions[1] or {}).base or ''
  end

  local matcher = H.matchers[opts.rule]
  if matcher == nil then H.error('`opts.rule` should be one of "exact", "substring", "fuzzy"') end
  return matcher(base, H.get_buf_snippets())
end

MiniSnippets.select = function(base, opts)
  local matches = MiniSnippets.get_matches(base, opts)

  local prefix_width = 0
  for _, s in ipairs(matches) do
    prefix_width = math.max(prefix_width, vim.fn.strdisplaywidth(s.prefix))
  end
  local format_item = function(s)
    local pad = string.rep(' ', prefix_width - vim.fn.strdisplaywidth(s.prefix))
    return s.prefix .. pad .. ' │ ' .. s.desc
  end

  local on_choice = function()
    -- TODO. Should expand. **But** it needs regions, so `base` does not
    -- contain enough information.
  end
  vim.ui.select(matches, { prompt = 'Snippets', format_item = format_item }, on_choice)
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniSnippets.config)

-- Namespaces for extmarks
H.ns_id = {}

-- Various cache
H.cache = {
  -- Loaders output
  filetype = {},
  runtime = {},
  file = {},
  -- Buffer snippets
  buf = {},
}

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
    ['match.get_ref'] = { config.match.get_ref, 'function', true },
    ['match.rule'] = { config.match.rule, 'string' },
    ['mappings.expand'] = { config.mappings.expand, 'string' },
    ['mappings.jump_next'] = { config.mappings.jump_next, 'string' },
    ['mappings.jump_prev'] = { config.mappings.jump_prev, 'string' },
  })

  return config
end

H.apply_config = function(config)
  MiniSnippets.config = config

  -- Reset loader cache
  H.cache = { buf = {}, filetype = {}, runtime = {}, file = {} }
end

H.create_autocommands = function()
  local gr = vim.api.nvim_create_augroup('MiniSnippets', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = gr, pattern = pattern, callback = callback, desc = desc })
  end

  au('ColorScheme', '*', H.create_default_hl, 'Ensure colors')
  -- Clear buffer cache: after `:edit` ('BufUnload') or after filetype has
  -- changed ('FileType', useful with `gen_loader.from_filetype`)
  au({ 'BufUnload', 'FileType' }, '*', function(args) H.cache.buf[args.buf] = nil end, 'Clear buffer cache')
end

--stylua: ignore
H.create_default_hl = function()
  vim.api.nvim_set_hl(0, 'MiniSnippetsCurrent', { default = true, link = 'CurSearch' })
  vim.api.nvim_set_hl(0, 'MiniSnippetsPlaceholder', { default = true, link = 'Search' })
  vim.api.nvim_set_hl(0, 'MiniSnippetsVisited', { default = true, link = 'Visual' })
end

H.is_disabled = function(buf_id) return vim.g.minisnippets_disable == true or vim.b.minisnippets_disable == true end

H.get_config = function() return vim.tbl_deep_extend('force', MiniSnippets.config, vim.b.minisnippets_config or {}) end

-- Read -----------------------------------------------------------------------
H.file_readers = {}

H.file_readers.lua = function(path, silent)
  local ok, contents = pcall(dofile, path)
  if not ok then return H.notify('Could not execute Lua file: ' .. path, 'WARN', silent) end
  if type(contents) ~= 'table' then return H.notify('File ' .. path .. ' should return table', 'WARN', silent) end
  return H.read_snippet_array(contents)
end

H.file_readers.json = function(path, silent)
  local file = io.open(path)
  if file == nil then return H.notify('Could not open file: ' .. path, 'WARN', silent) end
  local raw = file:read('*all')
  file:close()

  local ok, contents = pcall(vim.json.decode, raw)
  if not (ok and type(contents) == 'table') then
    return H.notify('File does not contain a valid JSON object: ' .. path, 'WARN', silent)
  end

  return H.read_snippet_array(contents)
end

H.read_snippet_array = function(contents)
  local res, problems = {}, {}
  for name, t in pairs(contents) do
    if H.is_snippet(t) then
      t.desc = t.desc or t.description or (type(name) == 'string' and name or nil)
      table.insert(res, t)
    else
      table.insert(problems, 'The following is not a valid snippet data:\n' .. vim.inspect(t))
    end
  end
  return { snippets = res, problems = problems }
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

-- Buffer snippets ------------------------------------------------------------
H.get_buf_snippets = function()
  local buf_id = vim.api.nvim_get_current_buf()
  if H.cache.buf[buf_id] ~= nil then return H.cache.buf[buf_id] end

  local res, config_snippets = {}, H.get_config().snippets
  H.traverse_config_snippets(config_snippets, res)
  res = vim.tbl_values(res)
  H.cache.buf[buf_id] = res
  return res
end

H.traverse_config_snippets = function(x, target)
  if H.is_snippet(x) then
    local prefix = type(x.prefix) == 'string' and { x.prefix } or x.prefix

    local body
    if x.body ~= nil then body = type(x.body) == 'string' and x.body or table.concat(x.body, '\n') end
    local desc = x.desc or x.description
    if desc ~= nil then desc = type(desc) == 'string' and desc or table.concat(desc, '\n') end

    for _, pr in ipairs(prefix) do
      -- Allow absent `body` to result in completely removing prefix(es)
      target[pr] = body ~= nil and { prefix = pr, body = body, desc = desc or pr } or nil
    end
  end

  if H.islist(x) then
    for _, v in ipairs(x) do
      H.traverse_config_snippets(v, target)
    end
  end

  if vim.is_callable(x) then H.traverse_config_snippets(x(), target) end
end

-- Matching -------------------------------------------------------------------
H.get_ref_regions = function(opts)
  local get_ref = opts.get_ref or H.get_config().match.get_ref or MiniSnippets.default_get_ref
  local regions = get_ref()
  if regions == nil then return end
  if H.is_region(regions) then regions = { regions } end
  if not H.is_array_of(regions, H.is_region) then H.error('Output of `match.get_ref` should be region(s)') end

  local res = {}
  for i, reg in ipairs(regions) do
    local text = vim.api.nvim_buf_get_text(0, reg.from.line - 1, reg.from.col - 1, reg.to.line - 1, reg.to.col, {})
    res[i] = { base = table.concat(text, '\n'), from = reg.from, to = reg.to }
  end
  return res
end

H.matchers = {}

H.matchers.exact = function(base, snippets)
  if base == '' then return snippets end
  local res = {}
  for _, s in ipairs(snippets) do
    if base == s.prefix then return { s } end
  end
  return res
end

H.matchers.substring = function(base, snippets)
  local res = {}
  for _, s in ipairs(snippets) do
    if string.find(s.prefix, base, 1, true) then table.insert(res, s) end
  end
  return res
end

H.matchers.fuzzy = function(base, snippets)
  if base == '' then return snippets end
  local snippets_ext = {}
  for i, s in ipairs(snippets) do
    snippets_ext[i] = { prefix = s.prefix, snip = s }
  end
  local res_raw = vim.fn.matchfuzzy(snippets_ext, base, { key = 'prefix' })
  return vim.tbl_map(function(x) return x.snip end, res_raw)
end

-- Validators -----------------------------------------------------------------
H.is_string = function(x) return type(x) == 'string' end

H.is_maybe_string_or_arr = function(x) return x == nil or H.is_string(x) or H.is_array_of(x, H.is_string) end

H.is_snippet = function(x)
  return type(x) == 'table'
    and (H.is_string(x.prefix) or H.is_array_of(x.prefix, H.is_string))
    -- Allow nil `body` to remove snippet with `prefix`
    and H.is_maybe_string_or_arr(x.body)
    -- Allow nil `desc` / `description`, in which case "prefix" is used
    and H.is_maybe_string_or_arr(x.desc)
    and H.is_maybe_string_or_arr(x.description)
end

--stylua: ignore
H.is_region = function(x)
  return type(x) == 'table'
    and type(x.from) == 'table' and type(x.from.line) == 'number' and type(x.from.col) == 'number'
    and type(x.to) == 'table' and type(x.to.line) == 'number' and type(x.to.col) == 'number'
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.snippets) ' .. msg, 0) end

H.notify = function(msg, level_name, silent)
  if not silent then vim.notify('(mini.snippets) ' .. msg, vim.log.levels[level_name]) end
end

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