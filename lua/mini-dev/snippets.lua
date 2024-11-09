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
--     - Should ensure presence of final tabstop (`$0`). Append at end if none.
--     - Placeholders of tabstops and variables should be independent / "local
--       only to node". This resolves cyclic cases like `${1:$2} ${2:$1}` in
--       a single pass. This still should update the "dependent" nodes during
--       typing: start as ` `; become `x x` after typing `x` on either tabstop,
--       allow becomeing `x y` or `y x` after the jump and typing.
--     - Think whether wrapping tabstops should be configurable.
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
-- - Syntax:
--     - Escape `}` inside `if` of `${1:?if:else}`.
--     - Variable `TM_SELECTED_TEXT` is resolved as contents of |quote_quote|
--       register. It assumes that text is put there prior to expanding:
--       visually select and |c|; yank, etc.
--
-- - Expand:
--
-- Tests:
-- - Management:
--     - `cache = false` should not write to cache (to possibly save memory).
--     - `gen_loader.from_lang()` results in preferring snippets:
--         - From exact file over ancestor.
--         - From .lua over .{json,code-snippets}.
--     - `gen_loader.from_lang()` processes `lang_patterns` array in order.
--       Resulting in preferring later ones over earlier.
--
-- - Match:
--     - `match.expand` is called with proper active mode and cursor.
--       Test edge cases when region/cursor is in start/middle/end of line
--       and in both supported modes.
--
-- - Expansion:
--     - Variables are evalueted exactly once.
--     - Treats '1' and '01' as different tabstops.

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
---   Supports matches depending on tree-sitter local languages.
---
--- - Expand, navigate, and edit snippet in a configurable manner:
---     - Works inside comments by preserving comment leader on new lines.
---     - Allows nested sessions (expand another snippet when there is one active).
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

--- POSITION Table representing position in a buffer. Fields:
---          - <line> `(number)` - line number (starts at 1).
---          - <col> `(number)` - column number (starts at 1).
--- REGION   Table representing region in a buffer. Fields: <from> and <to> for
---          inclusive start and end POSITIONs.
---@tag MiniSnippets-glossary

--- # Snippet files specifications ~
---
--- One of the following:
--- - File with `lua` extension with code that returns a table of snippet data.
--- - File with `json` or `code-snippets` extension which contains a JSON object with
---   snippet data as values. This is 'rafamadriz/friendly-snippets' compatible.
---
--- Suggested location is in "snippets" subdirectory of any path in 'runtimepath'.
--- This is compatible with |MiniSnippets.gen_loader.from_runtime()|.
---
--- For format of supported snippet data see "Loaded snippets" |MiniSnippets.config|.
---@tag MiniSnippets-files-specification

--- # Snippet syntax specification ~
---@tag MiniSnippets-syntax-specification

--- # Events ~
---
--- - `MiniSnippetsSessionStart`.
--- - `MiniSnippetsSessionStop`.
--- - `MiniSnippetsSessionSuspend`.
--- - `MiniSnippetsSessionResume`.
---@tag MiniSnippets-events

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
---   different dedicated files and use |MiniSnippets.gen_loader.from_lang()|.
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

-- -- Set useful snippets for easier local development
-- -- TODO: remove when not needed
-- vim.schedule(function()
--   local lang_patterns = { tex = { 'latex.json' }, plaintex = { 'latex.json' } }
--   MiniSnippets.config.snippets = {
--     MiniSnippets.gen_loader.from_lang({ lang_patterns = lang_patterns }),
--     MiniSnippets.gen_loader.from_file('~/.config/nvim/snippets/global.code-snippets'),
--   }
-- end)

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
---   Extra allowed fields:
---   - <pos> `(table)` - position (see |MiniSnippets-glossary) at which to
---     find snippets. Default: cursor position.
---
---@return table|nil If `expand` is `false`, an array of matched snippets as
---   was an output of `match.find`. Otherwise `nil`.
---
---@usage >lua
---   -- Find and force expand the best match (if any)
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

  local pos = opts.pos
  if pos == nil then pos = { line = vim.fn.line('.'), col = vim.fn.col('.') } end
  if not H.is_position(pos) then H.error('`opts.pos` should be table with numeric `line` and `col` fields') end

  -- Match
  local all_snippets = vim.deepcopy(H.get_context_snippets(pos))
  local matches = find == false and all_snippets or find(all_snippets, pos)
  if not H.is_array_of(matches, H.is_snippet) then H.error('`find` returned not an array of snippets') end

  -- Act
  if expand == false then return matches end
  if #all_snippets == 0 then return H.notify('There are no snippets in given context', 'WARN') end
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
---   - <lang_patterns> `(table)` - map from language to array of runtime patterns
---     used to find snippet files. Patterns will be processed in order, so
---     snippets from reading later patterns will override earlier ones.
---     The default pattern array (for non-empty language) is constructed as
---     to: search for "json" and "lua" files that are inside directory named
---     as language (however deep) or are named as language.
---     Example for "lua" language: `{ 'lua/**.{json,lua}', 'lua.{json,lua}' }`.
---   - __minisnippets_cache_opt
---   - __minisnippets_silent_opt
---
---@return __minisnippets_loader_return
MiniSnippets.gen_loader.from_lang = function(opts)
  opts = vim.tbl_extend('force', { lang_patterns = {}, cache = true, silent = false }, opts or {})
  for lang, tbl in pairs(opts.lang_patterns) do
    if type(lang) ~= 'string' then H.error('Keys of `opts.lang_patterns` should be string language names') end
    if not H.is_array_of(tbl, H.is_string) then H.error('Keys of `opts.lang_patterns` should be string arrays') end
  end

  local cache, read_opts = opts.cache, { cache = opts.cache, silent = opts.silent }
  local read = function(p) return MiniSnippets.read_file(p, read_opts) end
  return function(context)
    local lang = context.lang
    if cache and H.cache.lang[lang] ~= nil then return vim.deepcopy(H.cache.lang[lang]) end

    local patterns = opts.lang_patterns[lang]
    if patterns == nil and lang == '' then return end
    patterns = patterns or { lang .. '/**.{json,lua}', lang .. '.{json,lua}' }
    patterns = vim.tbl_map(function(p) return 'snippets/' .. p end, patterns)

    local res = {}
    for _, pattern in ipairs(patterns) do
      table.insert(res, vim.tbl_map(read, vim.api.nvim_get_runtime_file(pattern, true)))
    end
    if cache then H.cache.lang[lang] = vim.deepcopy(res) end
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
    if cache then H.cache.runtime[pattern] = vim.deepcopy(res) end
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
  if ext == nil or not (ext == 'lua' or ext == 'json' or ext == 'code-snippets') then
    return H.notify('File does not contain a supported extension: ' .. path, 'WARN', opts.silent)
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
---@param pos table|nil Position at which match snippets. Default: cursor position.
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
MiniSnippets.default_find = function(snippets, pos, opts)
  if pos == nil then pos = { line = vim.fn.line('.'), col = vim.fn.col('.') } end
  if not H.is_position(pos) then H.error('`pos` should be table with numeric `line` and `col` fields') end

  -- Compute line before cursor. Treat Insert mode as exclusive for right edge.
  local to = pos.col - (vim.fn.mode() == 'i' and 1 or 0)
  local line_till_cursor, lnum = vim.fn.getline(pos.line):sub(1, to), pos.line

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

--- Press `<C-c>` in Insert mode to stop active session (and stay in Insert mode).
MiniSnippets.default_expand = function(snippet, opts)
  -- TODO
  return vim.snippet.expand(snippet.body)

  -- H.expand(snippet, opts)
end

--- Work with snippet session from |MiniSnippets.default_expand()|
MiniSnippets.session = {}

MiniSnippets.session.get = function()
  local session = H.get_active_session()
  if session == nil then return end
  return {
    buf_id = session.buf_id,
    expand_opts = vim.deepcopy(session.expand_opts),
    nodes = vim.deepcopy(session.nodes),
    ns_id = session.ns_id,
    extmark_id = session.extmark_id,
    snippet = vim.deepcopy(session.snippet),
  }
end

MiniSnippets.session.jump = function(direction)
  if not (direction == 'prev' or direction == 'next') then H.error('`direction` should be one of "prev", "next"') end
  H.session_jump(H.get_active_session(), direction)
end

--- Stop active session
---
--- To ensure that all nested sessions are stopped, use this: >lua
---
---   while MiniSnippets.get_active_session() do
---     MiniSnippets.stop()
---   end
--- <
MiniSnippets.session.stop = function()
  H.session_deinit(H.get_active_session(), true)
  H.sessions[#H.sessions] = nil
  H.session_init(H.get_active_session(), false)
end

--- Parse snippet
---
---@param snippet_body string|table Snippet body as string or array of strings.
---@param opts table|nil Options. Possible fields:
---   - <normalize> `(boolean)` - whether to normalize nodes:
---     - Evaluate variable nodes and add output as a `text` field.
---       If variable is not set, `text` field is `nil`.
---       Values from `opts.lookup` are preferred over evaluation output.
---       See |MiniSnippets-syntax-specification| for more info about variables.
---     - Add `text` field for tabstops if it is present in `opts.lookup`.
---     - Ensure every node contains exactly one of `text` or `placeholder` fields.
---       If there are none, add default `placeholder` (one empty string text node).
---       If there are both, remove `placeholder` field.
---     Default: `false`.
---   - <lookup> `(table)` - map from variable/tabstop (string) name to its value.
---     Default: `{}`.
---
---@return table Array of nodes: tables with fields depending on node type:
---   - Text node:
---     - <text> `(string)` - node's text.
---   - Tabstop node:
---     - <tabstop> `(string)` - tabstop identifier.
---     - <placeholder> `(table|nil)` - array of nodes to be used as placeholder.
---     - <choices> `(table|nil)` - array of string choices.
---     - <transform> `(table|nil)` - array of transformation string parts.
---   - Variable node:
---     - <var> `(string)` - variable name.
---     - <text> `(string|nil)` - variable value.
---     - <placeholder> `(table|nil)` - array of nodes to be used as placeholder.
---     - <transform> `(table|nil)` - array of transformation string parts.
---
---@usage -- TODO
---@private
MiniSnippets._parse = function(snippet_body, opts)
  -- TODO: Properly export after a long enough period of public testing
  if H.is_array_of(snippet_body, H.is_string) then snippet_body = table.concat(snippet_body, '\n') end
  if type(snippet_body) ~= 'string' then H.error('Snippet body should be string or array of strings') end

  opts = vim.tbl_extend('force', { normalize = false, lookup = {} }, opts or {})

  -- Overall idea: implement a state machine which updates on every character.
  -- This leads to a bit spaghetti code, but doesn't require `vim.lpeg` DSL
  -- knowledge and can provide more information in error messages.
  -- Output is array of nodes representing the snippet body.
  -- Format is mostly based on grammar in LSP spec 3.18 with small differences.

  -- State table. Each future string is tracked as array and merged later.
  --stylua: ignore
  local state = {
    name = 'text',
    -- Node array for depths of currently processed nested placeholders.
    -- Depth 1 is the original snippet.
    depth_arrays = { { { text = {} } } },
    set_name = function(self, name) self.name = name; return self end,
    add_node = function(self, node) table.insert(self.depth_arrays[#self.depth_arrays], node); return self end,
    set_in = function(self, node, field, value) node[field] = value; return self end,
    is_not_top_level = function(self) return #self.depth_arrays > 1 end,
  }

  for i = 0, vim.fn.strchars(snippet_body) - 1 do
    -- Infer helper data (for more concise manipulations inside processor)
    local depth = #state.depth_arrays
    local arr = state.depth_arrays[depth]
    local processor, node = H.parse_processors[state.name], arr[#arr]
    processor(vim.fn.strcharpart(snippet_body, i, 1), state, node)
  end

  -- Verify and post-process
  H.parse_verify(state)
  local nodes = H.parse_post_process(state.depth_arrays[1], state.name)

  if not opts.normalize then return nodes end

  -- Normalize
  local lookup = {}
  for key, val in pairs(opts.lookup) do
    if type(key) == 'string' then lookup[key] = tostring(val) end
  end

  local normalize = function(n)
    -- Evaluate variable
    local var_value
    if n.var ~= nil then var_value = H.parse_eval_var(n.var, lookup) end
    if type(var_value) == 'string' then n.text = var_value end

    -- Look up tabstop
    if n.tabstop ~= nil then n.text = lookup[n.tabstop] end

    -- Ensure text-or-placeholder
    if n.text == nil and n.placeholder == nil then n.placeholder = { { text = '' } } end
    if n.text ~= nil and n.placeholder ~= nil then n.placeholder = nil end
  end
  -- - Ensure proper random random variables
  math.randomseed(vim.loop.hrtime())
  return H.traverse_nodes(nodes, normalize)
end

--- Mock an LSP server for completion
MiniSnippets.mock_lsp_server = function()
  -- TODO: start an LSP server capable of "textDocument/completion" response
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniSnippets.config)

-- Namespaces for extmarks
H.ns_id = {
  nodes = vim.api.nvim_create_namespace('MiniSnippetsNodes'),
}

-- Array of current (nested) snippet sessions from `default_expand`
H.sessions = nil

-- Various cache
H.cache = {
  -- Loaders output
  lang = {},
  runtime = {},
  file = {},
  -- Snippets per context
  context = {},
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
  H.cache = { context = {}, lang = {}, runtime = {}, file = {} }
end

H.create_autocommands = function()
  local gr = vim.api.nvim_create_augroup('MiniSnippets', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = gr, pattern = pattern, callback = callback, desc = desc })
  end

  au('ColorScheme', '*', H.create_default_hl, 'Ensure colors')
  -- Clear buffer cache: after `:edit` ('BufUnload') or after filetype has
  -- changed ('FileType', useful with `gen_loader.from_lang`)
  au({ 'BufUnload', 'FileType' }, '*', function(args) H.cache.context[args.buf] = nil end, 'Clear buffer cache')
end

--stylua: ignore
H.create_default_hl = function()
  vim.api.nvim_set_hl(0, 'MiniSnippetsCurrent', { default = true, link = 'DiffText' })
  vim.api.nvim_set_hl(0, 'MiniSnippetsPlaceholder', { default = true, link = 'DiffAdd' })
  vim.api.nvim_set_hl(0, 'MiniSnippetsVisited', { default = true, link = 'DiffChange' })
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

H.file_readers['code-snippets'] = H.file_readers.json

H.read_snippet_array = function(contents)
  local res, problems = {}, {}
  for name, t in pairs(contents) do
    if H.is_snippet(t) then
      t.desc = t.desc or t.description or (type(name) == 'string' and name or nil)
      t.description = nil
      table.insert(res, t)
    else
      table.insert(problems, 'The following is not a valid snippet data:\n' .. vim.inspect(t))
    end
  end
  return { snippets = res, problems = problems }
end

-- Context snippets -----------------------------------------------------------
H.get_context_snippets = function(pos)
  local context = H.compute_context(pos)
  local buf_cache = H.cache.context[context.buf_id] or {}
  if buf_cache[context.lang] ~= nil then return buf_cache[context.lang] end

  local res, config_snippets = {}, H.get_config().snippets
  H.traverse_config_snippets(config_snippets, res, context)
  res = vim.tbl_values(res)
  table.sort(res, function(a, b) return a.prefix < b.prefix end)

  buf_cache[context.lang] = res
  H.cache.context[context.buf_id] = buf_cache

  return res
end

H.compute_context = function(pos)
  local buf_id = vim.api.nvim_get_current_buf()
  local lang = vim.bo[buf_id].filetype

  -- TODO: Remove `opts.error` after compatibility with Neovim=0.11 is dropped
  local has_parser, parser = pcall(vim.treesitter.get_parser, buf_id, nil, { error = false })
  if not has_parser or parser == nil then return { buf_id = buf_id, lang = lang } end

  -- Compute local TS language from the deepest parser covering position
  local ref_range, res_level = { pos.line - 1, pos.col - 1, pos.line - 1, pos.col }, 0
  local traverse
  traverse = function(lang_tree, level)
    if lang_tree:contains(ref_range) and level > res_level then lang = lang_tree:lang() or lang end
    for _, child_lang_tree in pairs(lang_tree:children()) do
      traverse(child_lang_tree, level + 1)
    end
  end
  traverse(parser, 1)

  return { buf_id = buf_id, lang = lang }
end

H.traverse_config_snippets = function(x, target, context)
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
      H.traverse_config_snippets(v, target, context)
    end
  end

  if vim.is_callable(x) then H.traverse_config_snippets(x(context), target, context) end
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
        -- Make possible positioning cursor after line end
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

-- Parse ----------------------------------------------------------------------
H.parse_verify = function(state)
  if state.name == 'dollar_lbrace' then H.error('"${" should be closed with "}"') end
  if state.name == 'choice' then H.error('Tabstop with choices should be closed with "|}"') end
  if vim.startswith(state.name, 'transform_') then
    H.error('Transform should contain 3 "/" outside of `${...}` and be closed with "}"')
  end
  if #state.depth_arrays > 1 then H.error('Placeholder should be closed with "}"') end
end

H.parse_post_process = function(node_arr, state_name)
  -- Allow "$" at the end of the snippet
  if state_name == 'dollar' then table.insert(node_arr, { text = { '$' } }) end

  -- Process
  local traverse
  traverse = function(arr)
    for _, node in ipairs(arr) do
      -- Clean up trailing `\`
      if node.after_slash and node.text ~= nil then table.insert(node.text, '\\') end
      node.after_slash = nil

      -- Convert arrays to strings
      if node.text then node.text = table.concat(node.text) end
      if node.tabstop then node.tabstop = table.concat(node.tabstop) end
      if node.choices then node.choices = vim.tbl_map(table.concat, node.choices) end
      if node.var then node.var = table.concat(node.var) end
      if node.transform then node.transform = vim.tbl_map(table.concat, node.transform) end

      -- Recursively post-process placeholders
      if node.placeholder ~= nil then node.placeholder = traverse(node.placeholder) end
    end
    arr = vim.tbl_filter(function(n) return n.text == nil or (n.text ~= nil and n.text:len() > 0) end, arr)
    if #arr == 0 then return { { text = '' } } end
    return arr
  end

  return traverse(node_arr)
end

H.parse_rise_depth = function(state)
  -- Set the deepest array as a placeholder of the last node in previous layer.
  -- This can happen only after `}` which does not close current node.
  local depth = #state.depth_arrays
  local cur_layer, prev_layer = state.depth_arrays[depth], state.depth_arrays[depth - 1]
  prev_layer[#prev_layer].placeholder = vim.deepcopy(cur_layer)
  state.depth_arrays[depth] = nil
  state:add_node({ text = {} }):set_name('text')
end

-- Each method processes single character based on the character (`c`),
-- state (`s`), and current node (`n`).
H.parse_processors = {}

H.parse_processors.text = function(c, s, n)
  if n.after_slash then
    -- Escape `$}\` and allow unescaped '\\' to preceed any character
    if not (c == '$' or c == '}' or c == '\\') then table.insert(n.text, '\\') end
    n.text[#n.text + 1], n.after_slash = c, nil
    return
  end
  if c == '}' and s:is_not_top_level() then return H.parse_rise_depth(s) end
  if c == '\\' then return s:set_in(n, 'after_slash', true) end
  if c == '$' then return s:set_name('dollar') end
  table.insert(n.text, c)
end

H.parse_processors.dollar = function(c, s, n)
  if c == '}' and s:is_not_top_level() then
    if n.text ~= nil then table.insert(n.text, '$') end
    if n.text == nil then s:add_node({ text = { '$' } }) end
    s:set_name('text')
    H.parse_rise_depth(s)
    return
  end

  if c:find('^[0-9]$') then return s:add_node({ tabstop = { c } }):set_name('dollar_tabstop') end -- Tabstops
  if c:find('^[_a-zA-Z]$') then return s:add_node({ var = { c } }):set_name('dollar_var') end -- Variables
  if c == '{' then return s:set_name('dollar_lbrace') end -- Cases of `${...}`
  table.insert(n.text, '$') -- Case of unescaped `$`
  if c == '$' then return end -- Case of `$$1` and `$${1}`
  table.insert(n.text, c)
  s:set_name('text')
end

H.parse_processors.dollar_tabstop = function(c, s, n)
  if c:find('^[0-9]$') then return table.insert(n.tabstop, c) end
  if c == '}' and s:is_not_top_level() then return H.parse_rise_depth(s) end
  local new_node = { text = {} }
  s:add_node(new_node)
  if c == '$' then return s:set_name('dollar') end -- Case of `$1$2` and `$1$a`
  table.insert(new_node.text, c) -- Case of `$1a`
  s:set_name('text')
end

H.parse_processors.dollar_var = function(c, s, n)
  if c:find('^[_a-zA-Z0-9]$') then return table.insert(n.var, c) end
  if c == '}' and s:is_not_top_level() then return H.parse_rise_depth(s) end
  local new_node = { text = {} }
  s:add_node(new_node)
  if c == '$' then return s:set_name('dollar') end -- Case of `$a$b` and `$a$1`
  table.insert(new_node.text, c) -- Case of `$a-`
  s:set_name('text')
end

H.parse_processors.dollar_lbrace = function(c, s, n)
  if n.tabstop == nil and n.var == nil then -- Detect the type of `${...}`
    if c:find('^[0-9]$') then return s:add_node({ tabstop = { c } }) end
    if c:find('^[_a-zA-Z]$') then return s:add_node({ var = { c } }) end
    H.error('`${` should be followed by digit (in tabstop) or letter/underscore (in variable), not ' .. vim.inspect(c))
  end
  if c == '}' then return s:add_node({ text = {} }):set_name('text') end -- Cases of `${1}` and `${a}`
  if c == ':' then -- Placeholder
    table.insert(s.depth_arrays, { { text = {} } })
    return s:set_name('text')
  end
  if c == '/' then return s:set_in(n, 'transform', { {}, {}, {} }):set_name('transform_regex') end -- Transform
  if n.var ~= nil then -- Variable
    if c:find('^[_a-zA-Z0-9]$') then return table.insert(n.var, c) end
    H.error('Variable name should be followed by "}", ":" or "/", not ' .. vim.inspect(c))
  else -- Tabstop
    if c:find('^[0-9]$') then return table.insert(n.tabstop, c) end
    if c == '|' then return s:set_name('choice') end
    H.error('Tabstop id should be followed by "}", ":", "|", or "/" not ' .. vim.inspect(c))
  end
end

H.parse_processors.choice = function(c, s, n)
  n.choices = n.choices or { {} }
  if n.after_bar then
    if c ~= '}' then H.error('Tabstop with choices should be closed with "|}"') end
    return s:set_in(n, 'after_bar', nil):add_node({ text = {} }):set_name('text')
  end

  local cur = n.choices[#n.choices]
  if n.after_slash then
    -- Escape `$}\` and allow unescaped '\\' to preceed any character
    if not (c == ',' or c == '|' or c == '\\') then table.insert(cur, '\\') end
    cur[#cur + 1], n.after_slash = c, nil
    return
  end
  if c == ',' then return table.insert(n.choices, {}) end
  if c == '\\' then return s:set_in(n, 'after_slash', true) end
  if c == '|' then return s:set_in(n, 'after_bar', true) end
  table.insert(cur, c)
end

-- Silently gather all the transform data and wait until proper `}`
H.parse_processors.transform_regex = function(c, s, n)
  table.insert(n.transform[1], c)
  if n.after_slash then return s:set_in(n, 'after_slash', nil) end
  if c == '\\' then return s:set_in(n, 'after_slash', true) end
  if c == '/' then return s:set_in(n.transform[1], #n.transform[1], nil):set_name('transform_format') end -- Assumes any `/` is escaped in regex
end

H.parse_processors.transform_format = function(c, s, n)
  table.insert(n.transform[2], c)
  if n.after_slash then return s:set_in(n, 'after_slash', nil) end
  if n.after_dollar then
    n.after_dollar = nil
    -- Inside `${}` wait until the first (unescaped) `}`. Techincally, this
    -- breaks LSP spec in `${1:?if:else}` (`if` doesn't have to escape `}`).
    -- Accept this as known limitation and ask to escape `}` in such cases.
    if c == '{' and not n.inside_braces then return s:set_in(n, 'inside_braces', true) end
  end
  if c == '\\' then return s:set_in(n, 'after_slash', true) end
  if c == '$' then return s:set_in(n, 'after_dollar', true) end
  if c == '}' and n.inside_braces then return s:set_in(n, 'inside_braces', nil) end
  if c == '/' and not n.inside_braces then
    return s:set_in(n.transform[2], #n.transform[2], nil):set_name('transform_options')
  end
end

H.parse_processors.transform_options = function(c, s, n)
  table.insert(n.transform[3], c)
  if n.after_slash then return s:set_in(n, 'after_slash', nil) end
  if c == '\\' then return s:set_in(n, 'after_slash', true) end
  if c == '}' then return s:set_in(n.transform[3], #n.transform[3], nil):add_node({ text = {} }):set_name('text') end
end

--stylua: ignore
H.parse_eval_var = function(var, lookup)
  -- Always prefer using lookup
  if lookup[var] ~= nil then return lookup[var] end

  -- Evaluate variable
  local value
  if H.var_evaluators[var] ~= nil then value = H.var_evaluators[var]() end
  -- - Fall back to environment variable or `-1` to not evaluate twice
  if value == nil then value = vim.loop.os_getenv(var) or -1 end

  -- Skip caching random variables (to allow several different in one snippet)
  if not (var == 'RANDOM' or var == 'RANDOM_HEX' or var == 'UUID') then lookup[var] = value end
  return value
end

--stylua: ignore
H.var_evaluators = {
  -- LSP
  TM_SELECTED_TEXT = function() return vim.fn.getreg('"') end,
  TM_CURRENT_LINE  = function() return vim.api.nvim_get_current_line() end,
  TM_CURRENT_WORD  = function() return vim.fn.expand('<cword>') end,
  TM_LINE_INDEX    = function() return tostring(vim.fn.line('.') - 1) end,
  TM_LINE_NUMBER   = function() return tostring(vim.fn.line('.')) end,
  TM_FILENAME      = function() return vim.fn.expand('%:t') end,
  TM_FILENAME_BASE = function() return vim.fn.expand('%:t:r') end,
  TM_DIRECTORY     = function() return vim.fn.expand('%:p:h') end,
  TM_FILEPATH      = function() return vim.fn.expand('%:p') end,

  -- VS Code
  CLIPBOARD         = function() return vim.fn.getreg('+') end,
  CURSOR_INDEX      = function() return tostring(vim.fn.col('.') - 1) end,
  CURSOR_NUMBER     = function() return tostring(vim.fn.col('.')) end,
  RELATIVE_FILEPATH = function() return vim.fn.expand('%:.') end,
  WORKSPACE_FOLDER  = function() return vim.fn.getcwd() end,

  LINE_COMMENT      = function() return vim.bo.commentstring:gsub('%s*%%s.*$', '') end,
  -- No BLOCK_COMMENT_{START,END} as there is no built-in way to get them

  CURRENT_YEAR             = function() return vim.fn.strftime('%Y') end,
  CURRENT_YEAR_SHORT       = function() return vim.fn.strftime('%y') end,
  CURRENT_MONTH            = function() return vim.fn.strftime('%m') end,
  CURRENT_MONTH_NAME       = function() return vim.fn.strftime('%B') end,
  CURRENT_MONTH_NAME_SHORT = function() return vim.fn.strftime('%b') end,
  CURRENT_DATE             = function() return vim.fn.strftime('%d') end,
  CURRENT_DAY_NAME         = function() return vim.fn.strftime('%A') end,
  CURRENT_DAY_NAME_SHORT   = function() return vim.fn.strftime('%a') end,
  CURRENT_HOUR             = function() return vim.fn.strftime('%H') end,
  CURRENT_MINUTE           = function() return vim.fn.strftime('%M') end,
  CURRENT_SECOND           = function() return vim.fn.strftime('%S') end,
  CURRENT_TIMEZONE_OFFSET  = function() return vim.fn.strftime('%z') end,

  CURRENT_SECONDS_UNIX = function() return tostring(os.time()) end,

  -- Random
  RANDOM     = function() return string.format('%06d', math.random(0, 999999)) end,
  RANDOM_HEX = function() return string.format('%06x', math.random(0, 16777216 - 1)) end,
  UUID       = function()
    -- Source: https://gist.github.com/jrus/3197011
    local template ='xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function (c)
      local v = c == 'x' and math.random(0, 0xf) or math.random(8, 0xb)
      return string.format('%x', v)
    end)
  end
}

-- Expand ---------------------------------------------------------------------
H.expand = function(snippet, opts)
  if not H.is_snippet(snippet) then H.error('`snippet` should be a snippet table') end

  local default_empty_symbols = { tabstop = '@', tabstop_final = '!' }
  local default_opts = { empty_symbols = default_empty_symbols, vars_lookup = {} }
  opts = vim.tbl_deep_extend('force', default_opts, opts or {})
  if type(opts.vars_lookup) ~= 'table' then H.error('`opts.vars_lookup` should be table') end

  -- Create and initialize session
  local session = H.session_new(snippet, opts)
  H.session_init(session, true)
  return session -- Temporary for testing
end

H.get_active_session = function() return H.sessions[#H.sessions] end

H.session_new = function(snippet, opts)
  local nodes = MiniSnippets._parse(snippet.body, { normalize = true, vars_lookup = opts.vars_lookup })

  -- Compute all present tabstops in session traverse order
  local taborder = H.compute_tabstop_order(nodes)
  local tabstops = {}
  for i, id in ipairs(tabstops) do
    tabstops[id] = { prev = taborder[i - 1] or taborder[#taborder], next = taborder[i + 1] or taborder[1] }
  end

  return {
    buf_id = vim.api.nvim_get_current_buf(),
    current_tabstop = taborder[1],
    tabstops = tabstops,
    nodes = nodes,
    snippet = vim.deepcopy(snippet),
    expand_opts = vim.deepcopy(opts),
  }
end

H.session_init = function(session, full)
  if session == nil then return end

  -- Set text for first-time-initialized session (i.e. not if resuming)
  if full then
    local pos = { vim.fn.line('.'), vim.fn.col('.') }
    local indent = H.get_indent(pos[1])
    session.ns_id = H.ns_id.nodes
    session.extmark_id = H.set_nodes_text(session.nodes, pos, indent)
  end

  -- Start new registered session (only if there are tabstops)
  if session.current_tabstop == nil then return H.session_del_extmarks(session) end
  if full then
    H.session_deinit(H.get_active_session(), false)
    table.insert(H.sessions, session)
  end

  -- TODO: Set tracking behavior:
  session.augroup_id = vim.api.nvim_create_augroup('MiniSnippetsSession' .. #H.sessions, { clear = true })
  -- - Update linked tabstops.
  -- - Automatically stop session after:
  --   - Exit to Normal mode if $0 is current or all present nodes are visited.
  --   - Typing something with $0 being current node.

  -- Set focus on current tabstop
  H.session_focus_tabstop(session, session.current_tabstop)

  -- Trigger proper event
  local pattern = 'MiniSnippetsSession' .. (full and 'Start' or 'Resume')
  vim.api.nvim_exec_autocmds('User', { pattern = pattern })
end

H.session_focus_tabstop = function(session, id)
  -- TODO: Highlight nodes for current tabstop with 'MiniSnippetsVisited'

  session.current_tabstop = id

  -- TODO: Highlight nodes for current tabstop with 'MiniSnippetsCurrent'

  -- TODO: Focus cursor on the first node of the new tabstop (probably,
  -- position of node's extmark)

  -- TODO: Probably change `right_gravity` and `end_right_gravity` for all extmarks:
  -- - Make them expanding for new tabstop.
  -- - Make them move to the left if they are to the left of cursor (???).
  -- - Make them move to the right if they are to the right of cursor (???).
  -- Account for something like `$1$2$1`.
end

H.session_jump = function(session, direction)
  if session == nil then return end
  local new_tabstop = session.tabstops[session.current_tabstop][direction]
  if session.current_tabstop == new_tabstop then return end
  session.focus_tabstop(new_tabstop)
end

H.session_deinit = function(session, full)
  if session == nil then return end

  -- Stop current session tracking
  vim.api.nvim_del_augroup_by_id(session.augroup_id)

  -- Delete or hide (make invisible) extmarks
  local extmark_fun = full and H.extmark_del or H.extmark_hide
  local buf_id, ns_id = session.buf_id, session.ns_id
  extmark_fun(buf_id, ns_id, session.extmark_id)
  H.traverse_nodes(session.nodes, function(n) extmark_fun(buf_id, ns_id, n.extmark_id) end)

  -- Trigger proper event
  local pattern = 'MiniSnippetsSession' .. (full and 'Stop' or 'Suspend')
  vim.api.nvim_exec_autocmds('User', { pattern = pattern })
end

H.set_nodes_text = function(nodes, pos, indent)
  -- TODO: Place all text starting at position `pos` and respecting indent
  -- In caseof placeholders recurse into them.
end

H.compute_tabstop_order = function(nodes)
  local tabstops_map, traverse_tabstops = {}, nil
  H.traverse_nodes(nodes, function(n) tabstops_map[n.tabstop or true] = true end)
  tabstops_map[true] = nil

  -- Order as numbers while allowing leading zeros. Put special `$0` last.
  local tabstops = vim.tbl_map(function(x) return { tonumber(x), x } end, vim.tbl_keys(tabstops_map))
  table.sort(tabstops, function(a, b)
    if a[2] == '0' then return false end
    if b[2] == '0' then return true end
    return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2])
  end)
  return vim.tbl_map(function(x) return x[2] end, tabstops)
end

H.traverse_nodes = function(nodes, f)
  for i, n in ipairs(nodes) do
    if n.placeholder ~= nil then n.placeholder = H.traverse_nodes(n.placeholder, f) end
    local out = f(n)
    if out ~= nil then nodes[i] = out end
  end
  return nodes
end

-- Extmarks -------------------------------------------------------------------
H.extmark_get = function(buf_id, ns_id, ext_id)
  local data = vim.api.nvim_buf_get_extmark_by_id(buf_id, ns_id, ext_id, { details = true })
  data[3].id, data[3].ns_id = ext_id, nil
  return data[1], data[2], data[3]
end

H.extmark_set = function(...) return vim.api.nvim_buf_set_extmark(...) end

H.extmark_del = function(buf_id, ns_id, ext_id) vim.api.nvim_buf_del_extmark(buf_id, ns_id, ext_id or -1) end

H.extmark_hide = function(buf_id, ns_id, ext_id)
  if ext_id == nil then return end
  local line, col, opts = H.extmark_get(buf_id, ns_id, ext_id)
  opts.hl_group, opts.virt_text = nil, nil
  H.extmark_set(buf_id, ns_id, line, col, opts)
end

H.extmark_set_gravity = function(buf_id, ns_id, ext_id, gravity)
  local line, col, opts = H.extmark_get(buf_id, ns_id, ext_id)
  opts.right_gravity, opts.end_right_gravity = gravity == 'right', gravity ~= 'left'
  H.extmark_set(buf_id, ns_id, line, col, opts)
end

--stlua: ignore
H.extmark_set_text = function(buf_id, ns_id, ext_id, side, text)
  local start_row, start_col, opts = H.extmark_get(buf_id, ns_id, ext_id)
  local end_row, end_col = opts.end_row, opts.end_col
  if side == 'left' then
    end_row, end_col = start_row, start_col
  end
  if side == 'right' then
    start_row, start_col = end_row, end_col
  end
  vim.api.nvim_buf_set_text(buf_id, start_row, start_col, end_row, end_col, text)
end

-- Indent ---------------------------------------------------------------------
H.get_indent = function(lnum)
  local line, comment_indent = vim.fn.getline(lnum), ''
  for _, leader in ipairs(H.get_comment_leaders()) do
    local cur_match = line:match('^%s*' .. vim.pesc(leader) .. '%s*')
    -- Use biggest match in case of several matches. Allows respecting "nested"
    -- comment leaders like "---" and "--".
    if type(cur_match) == 'string' and comment_indent:len() < cur_match:len() then comment_indent = cur_match end
  end
  return comment_indent ~= '' and comment_indent or line:match('^%s*')
end

H.get_comment_leaders = function()
  local res = {}

  -- From 'commentstring'
  local main_leader = vim.split(vim.bo.commentstring, '%%s')[1]
  table.insert(res, vim.trim(main_leader))

  -- From 'comments'
  for _, comment_part in ipairs(vim.opt_local.comments:get()) do
    local prefix, suffix = comment_part:match('^(.*):(.*)$')
    suffix = vim.trim(suffix)
    if prefix:find('b') then
      -- Respect `b` flag (for blank) requiring space, tab or EOL after it
      table.insert(res, suffix .. ' ')
      table.insert(res, suffix .. '\t')
    elseif prefix:find('f') == nil then
      -- Add otherwise ignoring `f` flag (only first line should have it)
      table.insert(res, suffix)
    end
  end

  return res
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

H.is_position = function(x) return type(x) == 'table' and type(x.line) == 'number' and type(x.col) == 'number' end

H.is_region = function(x) return type(x) == 'table' and H.is_position(x.from) and H.is_position(x.to) end

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

-- TODO: Remove after compatibility with Neovim=0.9 is dropped
H.islist = vim.fn.has('nvim-0.10') == 1 and vim.islist or vim.tbl_islist

return MiniSnippets
