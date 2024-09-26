-- TODO:
--
-- Code:
-- - A system to load and manage custom snippets:
--
-- - A system to match snippet based on prefix:
--     - Think about the issue that `@rel` will match `l` exactly although it
--       is probably more reasonable to say there are no exact matches.
--       Maybe accept exact match if it is preceded by whitespace?
--
--       Or more generally allow `opts.boundary` for `default_find()` which
--       should match the character *before* the exact match? The problem with
--       it seems to be the lack of a robust default: `%s` will not expand in
--       cases like `aaa(f`, while `[^%w_-]` seems too arbitrary.
--
-- - A system to expand, navigate, and edit snippet:
--     - Make indent be computed as in 'mini.splitjoin', so that multiline
--       snippets in comments works.
--     - Make sure that linked tabstops are updated not only when typing text,
--       but also on `<BS>`.
--
-- Docs:
-- - Manage:
--     - Normalized snippets for buffer are cached. Execute `:edit` to clear
--       current buffer cache.
--
-- - Match:
--     - Calling `match.expand`:
--         - Preserves Insert mode and ensures Normal mode.
--         - Places cursor at the start of removed region (if there is one).
--
-- Tests:
-- - Management:
--     - `cache = false` should not write to cache (to possibly save memory).
--     - `gen_loader.from_filetype()` results in preferring snippets:
--         - From exact file over ancestor.
--         - From .lua over .json.
--     - `gen_loader.from_filetype()` processes pattern array in order.
--       Resulting in preferring later ones over earlier.
--
-- - Match:
--     - `match.expand` is called with proper active mode and cursor.
--       Test edge cases when region/cursor is in start/middle/end of line
--       and in both supported modes.

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
--- - 'dcampos/nvim-snippy':
---     - ???
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

--- # Mappings ~
---
--- This module doesn't define any mappings. Here are examples for common setups:
---
--- - ...
---
--- # Common snippets configuration ~
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
--- - <prefix> `(string|table|nil)` - string used to match against user typed base.
---    If array, all strings are used as separate prefixes.
---    If absent / `nil`, inferred as empty string.
---
--- - <body> `(string|table|nil)` - content of a snippet which follows
---    the |MiniSnippets-syntax-specification|. Array is concatenated with "\n".
---    If absent / `nil`, removes <prefix> from normalized buffer snippets.
---
--- - <desc> `(string|table|nil)` - description of snippet. Can be used to display
---   snippets in a more human readable form. Array is concatenated with "\n".
---   If absent / `nil`, <prefix> or <body> is used.
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
  -- Array of snippets and loaders (see |MiniSnippets.config| for details).
  -- Nothing is defined by default. Add manually to have snippets to match.
  snippets = {},
  match = {
    -- Function to compute matching snippets
    find = nil,
    -- Function which interactively selects match to expand
    select = nil,
    -- Function which starts snippet expansion session
    expand = nil,
  },
}
--minidoc_afterlines_end

--- Match snippets and act
---
---@param opts table|nil Options. Same structure as `match` in |MiniSnippets.config|
---   and uses its values as default. There are differences in allowed values:
---   - Use `find = false` to have all buffer snippets as matches.
---   - Use `select = false` to always expand the best match (if any).
---   - Use `expand = false` to return all matches without expanding.
---
---@return table|nil If `expand` is `false`, an array of matched snippets as
---   was an output of `match.find`. Otherwise `nil`.
---
---@usage >lua
---   -- Find and expand the best match (if any)
---   MiniSnippets.match({ select = false })
---
---   -- Show all buffer snippets and select one to expand
---   MiniSnippets.match({ find = false })
---
---   -- Get all matched snippets
---   local matches = MiniSnippets.match({ expand = false })
---
---   -- Get all buffer snippets
---   local all = MiniSnippets.match({ find = false, expand = false })
--- <
MiniSnippets.match = function(opts)
  opts = vim.tbl_extend('force', H.get_config().match, opts or {})

  -- Validate
  local find = false
  if opts.find ~= false then find = opts.find or MiniSnippets.default_find end
  if not (find == false or vim.is_callable(find)) then H.error('`opts.find` should be `false` or callable') end

  local select = false
  if opts.select ~= false then select = opts.select or MiniSnippets.default_select end
  if not (select == false or vim.is_callable(select)) then H.error('`opts.select` should be `false` or callable') end

  local expand = false
  if opts.expand ~= false then expand = opts.expand or MiniSnippets.default_expand end
  if not (expand == false or vim.is_callable(expand)) then H.error('`opts.expand` should be `false` or callable') end

  -- Match
  local all_snippets = vim.deepcopy(H.get_buf_snippets())
  local matches = find == false and all_snippets or find(all_snippets)
  if not H.is_array_of(matches, H.is_snippet) then H.error('`find` returned not an array of snippets') end

  -- Act
  if expand == false then return matches end
  if #all_snippets == 0 then return H.notify('There are no buffer snippets', 'WARN') end
  if #matches == 0 then return H.notify('There are no matches', 'WARN') end

  local expand_ext = H.make_extended_expand(expand)

  if select == false then return expand_ext(matches[1]) end
  local best_match = select(matches, expand_ext)
  if H.is_snippet(best_match) then expand_ext(best_match) end
end

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

--- Default match find
---
--- Match snippets based on the current line text before the cursor.
--- Tries two matching approaches consecutively:
--- - Find exact snippet prefix match to the left of cursor.
---   In case of any match, return the one with the longest prefix.
--- - Find fuzzy matches for base text extracted via `opts.pattern` to the left
---   of cursor. Fuzzy matching is done via |matchfuzzy()|.
---   All fuzzy matches are returned.
---
---@param snippets table Array of snippets which can be matched.
---@param opts table|nil Options. Possible fields:
---   - <pattern> `(string)` - Lua pattern to match just before the cursor.
---     Supply empty string to not do fuzzy match.
---     Default: `'%S+'` (as many as possible non-whitespace characters).
---
---@return table Array of snippets with added <region> field. Ordered from most to
---   least fit match.
---
---@usage >lua
---   -- Perform fuzzy match based only on alphanumeric characters
---   MiniSnippets.default_find(snippets, { pattern = '%w+' })
--- <
MiniSnippets.default_find = function(snippets, opts)
  -- Compute line before cursor. Treat Insert mode as exclusive for right edge.
  local to = vim.fn.col('.') - (vim.fn.mode() == 'i' and 1 or 0)
  local line_till_cursor, lnum = vim.api.nvim_get_current_line():sub(1, to), vim.fn.line('.')

  -- Exact. Use 0 as initial best match width to not match empty prefixes.
  local best_match, best_match_width = nil, 0
  for _, s in pairs(snippets) do
    if vim.endswith(line_till_cursor, s.prefix) and best_match_width < s.prefix:len() then
      s.region = { from = { line = lnum, col = to - s.prefix:len() + 1 }, to = { line = lnum, col = to } }
      best_match, best_match_width = s, s.prefix:len()
    end
  end
  if best_match ~= nil then return { best_match } end

  -- Fuzzy
  opts = opts or {}
  local pattern = opts.pattern or '%S+'
  if not H.is_string(pattern) then H.error('`opts.pattern` should be string') end
  if pattern == '' then return {} end

  local base = string.match(line_till_cursor, pattern .. '$')
  if base == nil then return {} end

  local snippets_with_prefix = vim.tbl_filter(function(s) return s.prefix ~= nil end, snippets)
  local fuzzy_matches = vim.fn.matchfuzzy(snippets_with_prefix, base, { key = 'prefix' })
  local from_col = to - base:len() + 1
  for _, s in ipairs(fuzzy_matches) do
    s.region = { from = { line = lnum, col = from_col }, to = { line = lnum, col = to } }
  end

  return fuzzy_matches
end

--- Default select best match
---
--- Show matched snippets as entries via |vim.ui.select()| and expand chosen one.
---
---@param snippets table Array of matched snippets; an output of `config.match`.
---@param expand function Function which expands matched snippet (along with
---   removing matched region, if present).
---@param opts table|nil Options. Possible fields:
---   - <expand_single> `(boolean)` - whether to skip |vim.ui.select()| for
---     single matched snippet. Default: `true`.
MiniSnippets.default_select = function(snippets, expand, opts)
  opts = opts or {}

  if #snippets == 1 and (opts.expand_single == nil or opts.expand_single == true) then
    expand(snippets[1])
    return
  end

  -- Format
  local prefix_width = 0
  for _, s in ipairs(snippets) do
    prefix_width = math.max(prefix_width, vim.fn.strdisplaywidth(s.prefix))
  end
  local format_item = function(s)
    local pad = string.rep(' ', prefix_width - vim.fn.strdisplaywidth(s.prefix))
    return s.prefix .. pad .. ' │ ' .. s.desc
  end

  -- Schedule expand to allow `vim.ui.select` override to restore window/cursor
  local on_choice = vim.schedule_wrap(expand)
  vim.ui.select(snippets, { prompt = 'Snippets', format_item = format_item }, on_choice)
end

MiniSnippets.default_expand = function(snippet, opts)
  -- TODO
  return vim.snippet.expand(snippet.body)
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
    match = { config.match, 'table' },
  })

  vim.validate({
    ['match.find'] = { config.match.find, 'function', true },
    ['match.select'] = { config.match.select, 'function', true },
    ['match.expand'] = { config.match.expand, 'function', true },
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
  table.sort(res, function(a, b) return a.prefix < b.prefix end)
  H.cache.buf[buf_id] = res
  return res
end

H.traverse_config_snippets = function(x, target)
  if H.is_snippet(x) then
    local prefix = x.prefix or ''
    prefix = type(prefix) == 'string' and { prefix } or prefix

    local body
    if x.body ~= nil then body = type(x.body) == 'string' and x.body or table.concat(x.body, '\n') end

    local desc = x.desc or x.description
    if desc ~= nil then desc = type(desc) == 'string' and desc or table.concat(desc, '\n') end

    for _, pr in ipairs(prefix) do
      -- Add all snippets with empty prefixes separately
      local index = pr == '' and (#target + 1) or pr
      -- Allow absent `body` to result in completely removing prefix(es)
      target[index] = body ~= nil and { prefix = pr, body = body, desc = desc or (pr ~= '' and pr or body) } or nil
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
H.make_extended_expand = function(expand)
  return function(match)
    if match == nil then return end

    -- Ensure proper mode
    local mode = vim.fn.mode()
    if not (mode == 'i' or mode == 'n') then
      -- This is seemingly the only "good" way to ensure Normal mode.
      -- This also works with `vim.snippet.expand()` as its implementation uses
      -- `vim.api.nvim_feedkeys(k, 'n', true)` to select text in Select mode.
      vim.api.nvim_feedkeys('\28\14', 'n', false)
      -- NOTE: Normal mode is chosen because ensuring Insert is troublesome.
      -- Any reasonable approach (`:normal! \28\14a`, `:startinsert`,
      -- `vim.fn.feedkeys('\28\14a', 'n')`) does not immediately start Insert
      -- mode, only "after function or script is finished".
    end

    -- Remove matched region
    local r = match.region
    if H.is_region(r) then
      if mode ~= 'i' then
        -- Make position cursor after line end possible
        local cache_virtualedit = vim.wo.virtualedit
        vim.wo.virtualedit = 'onemore'
        vim.schedule(function() vim.wo.virtualedit = cache_virtualedit end)
      end

      -- Set cursor before deleting text to ensure working at end of line
      vim.api.nvim_win_set_cursor(0, { r.from.line, r.from.col - 1 })
      vim.api.nvim_buf_set_text(0, r.from.line - 1, r.from.col - 1, r.to.line - 1, r.to.col, {})
    end

    -- Expand
    expand(match)
  end
end

-- Validators -----------------------------------------------------------------
H.is_string = function(x) return type(x) == 'string' end

H.is_maybe_string_or_arr = function(x) return x == nil or H.is_string(x) or H.is_array_of(x, H.is_string) end

H.is_snippet = function(x)
  return type(x) == 'table'
    -- Allow nil `prefix`: inferred as empty string
    and H.is_maybe_string_or_arr(x.prefix)
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

H.get_visual_region = function()
  local left, right = vim.fn.getpos('v'), vim.fn.getpos('.')
  if right[2] < left[2] or (right[2] == left[2] and right[3] < left[3]) then
    left, right = right, left
  end
  local to_col_offset = vim.o.selection == 'exclusive' and 1 or 0
  return { from = { line = left[2], col = left[3] }, to = { line = right[2], col = right[3] - to_col_offset } }
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
