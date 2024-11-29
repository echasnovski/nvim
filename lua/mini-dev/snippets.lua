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
--       Or more generally allow `opts.boundary` for `default_match()` which
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
-- - Expand:
--     - Calling `expand.insert`:
--         - Preserves Insert mode and ensures Normal mode.
--         - Places cursor at the start of removed region (if there is one).
--
-- - Syntax:
--     - Escape `}` inside `if` of `${1:?if:else}`.
--     - Variable `TM_SELECTED_TEXT` is resolved as contents of |quote_quote|
--       register. It assumes that text is put there prior to expanding:
--       visually select and |c|; yank, etc.
--
-- - `default_insert`:
--     - Having independent nested sessions instead of merging sessions into
--       one has several benefits:
--         - Does not overload with highlighting: expanding "child" session in
--           current node will lead to current node's `MiniSnippetsVisited`
--           span across the whole "child" snippet session range.
--         - Allows nested sessions in different buffers.
--         - Doesn't need a complex logic of inserting one session into another
--           session. It is complex, as it requires careful node splicing, more
--           complex data structures for nodes (having "text-or-placeholder"
--           logic doesn't really apply here, as it will introduce problems
--           when trying to sync tabstops when "child" session is expanded
--           inside current node of "parent" session).
--       Instead realy on the following logic of independent nested sessions:
--         - Resuming session should sync its current tabstop. This leads to
--           the experience similar to editing in blockwise Visual mode: type
--           text in current session which will then be synced to relevant
--           nodes of "parent" session once "child" session is finished.
--         - Resuming session shouldn't change neither cursor nor buffer.
--           Most importantly this allows typing when $0 is current without
--           disrupting the typing flow.
--
-- - Examples:
--     - Autocommand for stopping active session on `ModeChanged *:n` when there
--       are no unvisited tabstops.
--     - How to setup "expand or jump" type of mapping.
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
-- - Expand:
--     - `expand.insert` is called with proper active mode and cursor.
--       Test edge cases when region/cursor is in start/middle/end of line
--       and in both supported modes.
--
-- - `default_insert`:
--     - Variables are evalueted exactly once.
--     - Treats '1' and '01' as different tabstops.
--     - Take special care for how session extmarks track snippet's range:
--         - What happens when initial expansion is done at the first column
--           and/or at the first row while text is later typed at the snippet's
--           first column. Is it reasonable to expect that session is expanding
--           or moving to the right (even if first node is plain text)?
--         - Same scenario but for the right side and expanding at last column.
--         - Should expand when typing text strictly inside snippet range.

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
--- - Match which snippet to insert based on the currently typed text.
---   Supports matching depending on tree-sitter local languages.
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
--- * `MiniSnippetsCurrentReplace` - current tabstop to be replaced on valid edit.
--- * `MiniSnippetsFinal` - special `$0` tabstop.
--- * `MiniSnippetsUnvisited` - not yet visited tabstop(s).
--- * `MiniSnippetsVisited` - visited tabstop(s).
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
--- - `MiniSnippetsSessionJumpPre`.
--- - `MiniSnippetsSessionJump`.
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
--     MiniSnippets.gen_loader.from_file('~/.config/nvim/snippets/test.code-snippets'),
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
--- # Mappings ~
---
--- # Expand ~
MiniSnippets.config = {
  -- Array of snippets and loaders (see |MiniSnippets.config| for details).
  -- Nothing is defined by default. Add manually to have snippets to match.
  snippets = {},

  -- Module mappings. Use `''` (empty string) to disable one.
  -- Created globally in Insert mode
  mappings = {
    -- Ways to expand snippets
    expand = '<C-j>',
    expand_all = '<C-g><C-j>',

    -- Interact with default `expand.insert` session
    jump_next = '<C-l>',
    jump_prev = '<C-h>',
    stop = '<C-c>',
  },

  -- Functions describing snippet expansion
  expand = {
    -- Match snippets at text position
    match = nil,
    -- Interactively select snippet to expand
    select = nil,
    -- Insert snippet
    insert = nil,
  },
}
--minidoc_afterlines_end

--- Expand snippet
---
---@param opts table|nil Options. Same structure as `expand` in |MiniSnippets.config|
---   and uses its values as default. There are differences in allowed values:
---   - Use `match = false` to have all buffer snippets as matches.
---   - Use `select = false` to always expand the best match (if any).
---   - Use `insert = false` to return all matches without inserting.
---
---   Extra allowed fields:
---   - <pos> `(table)` - position (see |MiniSnippets-glossary) at which to
---     find snippets. Default: cursor position.
---
---@return table|nil If `insert` is `false`, an array of matched snippets as
---   was an output of `expand.match`. Otherwise `nil`.
---
---@usage >lua
---   -- Match and force expand the best match (if any)
---   MiniSnippets.expand({ select = false })
---
---   -- Use all buffer snippets and select one to insert
---   MiniSnippets.expand({ match = false })
---
---   -- Get all matched snippets
---   local matches = MiniSnippets.expand({ insert = false })
---
---   -- Get all snippets of current context (buffer + language)
---   local all = MiniSnippets.expand({ match = false, insert = false })
--- <
MiniSnippets.expand = function(opts)
  opts = vim.tbl_extend('force', H.get_config().expand, opts or {})

  -- Validate
  local match = false
  if opts.match ~= false then match = opts.match or MiniSnippets.default_match end
  if not (match == false or vim.is_callable(match)) then H.error('`opts.match` should be `false` or callable') end

  local select = false
  if opts.select ~= false then select = opts.select or MiniSnippets.default_select end
  if not (select == false or vim.is_callable(select)) then H.error('`opts.select` should be `false` or callable') end

  local insert = false
  if opts.insert ~= false then insert = opts.insert or MiniSnippets.default_insert end
  if not (insert == false or vim.is_callable(insert)) then H.error('`opts.insert` should be `false` or callable') end

  local pos = opts.pos
  if pos == nil then pos = { line = vim.fn.line('.'), col = vim.fn.col('.') } end
  if not H.is_position(pos) then H.error('`opts.pos` should be table with numeric `line` and `col` fields') end

  -- Match
  local all_snippets = vim.deepcopy(H.get_context_snippets(pos))
  local matches = match == false and all_snippets or match(all_snippets, pos)
  if not H.is_array_of(matches, H.is_snippet) then H.error('`match` returned not an array of snippets') end

  -- Act
  if insert == false then return matches end
  if #all_snippets == 0 then return H.notify('There are no snippets in given context', 'WARN') end
  if #matches == 0 then return H.notify('There are no matches at position', 'WARN') end

  local insert_ext = H.make_extended_insert(insert)

  if select == false then return insert_ext(matches[1]) end
  local best_match = select(matches, insert_ext)
  if H.is_snippet(best_match) then insert_ext(best_match) end
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

--- Default match
---
--- Match snippets based on the current line text before the cursor.
--- Tries two matching approaches consecutively:
--- - Find exact snippet prefix match to the left of cursor.
---   In case of any match, return the one with the longest prefix.
--- - Fuzzy match base text to the left of cursor (extracted via `opts.pattern`).
---   Matching is done via |matchfuzzy()|. All fuzzy matches are returned.
---
---@param snippets table Array of snippets which can be matched.
---@param pos table|nil Position at which to match snippets. Default: cursor position.
---@param opts table|nil Options. Possible fields:
---   - <pattern> `(string)` - Lua pattern to extract base to the left of cursor.
---     Supply empty string to not do fuzzy matching.
---     Default: `'%S+'` (as many as possible non-whitespace characters).
---
---@return table Array of snippets with <region> field. Ordered from best to worst match.
---
---@usage >lua
---   -- Perform fuzzy match based only on alphanumeric characters
---   MiniSnippets.default_match(snippets, { pattern = '%w+' })
--- <
MiniSnippets.default_match = function(snippets, pos, opts)
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

--- Default select
---
--- Show snippets as entries via |vim.ui.select()| and insert the chosen one.
---
---@param snippets table Array of snippets (as an output of `config.expand.match`).
---@param insert function Function to insert chosen snippet. Should also remove
---   snippet's matched region (if present as a field).
---@param opts table|nil Options. Possible fields:
---   - <expand_single> `(boolean)` - whether to skip |vim.ui.select()| for
---     `snippets` with single entry. Default: `true`.
---
---@return ... The result of calling `vim.ui.select()`. Usually `nil`.
MiniSnippets.default_select = function(snippets, insert, opts)
  opts = opts or {}

  if #snippets == 1 and (opts.expand_single == nil or opts.expand_single == true) then
    insert(snippets[1])
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

  -- Schedule insert to allow `vim.ui.select` override to restore window/cursor
  local on_choice = vim.schedule_wrap(insert)
  return vim.ui.select(snippets, { prompt = 'Snippets', format_item = format_item }, on_choice)
end

MiniSnippets.default_insert = function(snippet, opts)
  if not H.is_snippet(snippet) then H.error('`snippet` should be a snippet table') end

  local default_opts = { empty_tabstop = '•', empty_tabstop_final = '∎', vars_lookup = {} }
  opts = vim.tbl_deep_extend('force', default_opts, opts or {})
  if type(opts.vars_lookup) ~= 'table' then H.error('`opts.vars_lookup` should be table') end

  H.session_init(H.session_new(snippet, opts), true)
end

--- Work with snippet session from |MiniSnippets.default_insert()|
MiniSnippets.session = {}

MiniSnippets.session.get = function(all) return vim.deepcopy(all and H.sessions or H.get_active_session()) end

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
  if #H.sessions == 0 then
    vim.api.nvim_del_augroup_by_name('MiniSnippetsTrack')
    H.unmap_in_sessions()
  end
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
---     - Add `text` field for tabstops present in `opts.lookup`.
---     - Ensure every node contains exactly one of `text` or `placeholder` fields.
---       If there are none, add default `placeholder` (one empty string text node).
---       If there are both, remove `placeholder` field.
---     - Ensure present final tabstop: append to end if absent.
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
MiniSnippets.parse = function(snippet_body, opts)
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

  -- Verify, post-process, normalize
  H.parse_verify(state)
  local nodes = H.parse_post_process(state.depth_arrays[1], state.name)
  return opts.normalize and H.parse_normalize(nodes, opts) or nodes
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

-- Array of current (nested) snippet sessions from `default_insert`
H.sessions = {}

-- Various cache
H.cache = {
  -- Loaders output
  lang = {},
  runtime = {},
  file = {},
  -- Snippets per context
  context = {},
  -- Data for possibly overridden session mappings
  mappings = {},
}

-- Whether current Neovim version supports inline extmarks
H.has_inline_extmark_support = vim.fn.has('nvim-0.10') == 1

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  vim.validate({
    snippets = { config.snippets, 'table' },
    expand = { config.expand, 'table' },
    mappings = { config.mappings, 'table' },
  })

  vim.validate({
    ['mappings.expand'] = { config.mappings.expand, 'string' },
    ['mappings.expand_all'] = { config.mappings.expand_all, 'string' },
    ['mappings.jump_next'] = { config.mappings.jump_next, 'string' },
    ['mappings.jump_prev'] = { config.mappings.jump_prev, 'string' },
    ['mappings.stop'] = { config.mappings.stop, 'string' },
    ['expand.match'] = { config.expand.match, 'function', true },
    ['expand.select'] = { config.expand.select, 'function', true },
    ['expand.insert'] = { config.expand.insert, 'function', true },
  })

  return config
end

H.apply_config = function(config)
  MiniSnippets.config = config

  -- Reset loader cache
  H.cache = { context = {}, lang = {}, runtime = {}, file = {}, mappings = {} }

  -- Make mappings
  local mappings = config.mappings
  local map = function(lhs, rhs, desc)
    if lhs == '' then return end
    vim.keymap.set('i', lhs, rhs, { desc = desc })
  end
  map(mappings.expand, '<Cmd>lua MiniSnippets.expand()<CR>', 'Expand snippet')
  map(mappings.expand_all, '<Cmd>lua MiniSnippets.expand({ match = false })<CR>', 'Expand without matching')

  -- Register 'code-snippets' extension as JSON (helps with highlighting)
  vim.schedule(function() vim.filetype.add({ extension = { ['code-snippets'] = 'json' } }) end)
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

  -- TODO: Clean up `H.sessions` on `BufUnload` from outdated sessions
end

H.create_default_hl = function()
  local get_hl_data = vim.fn.has('nvim-0.9') == 1
      and function(x) return vim.api.nvim_get_hl(0, { name = x, link = false }) end
    or function(x) return vim.api.nvim_get_hl_by_name(x, true) end
  local hi_link_underdouble = function(to, from)
    local data = get_hl_data(from)
    data.default = true
    data.underdouble, data.underline, data.undercurl, data.underdotted, data.underdashed =
      true, false, false, false, false
    data.cterm = { underdouble = true }
    data.fg, data.bg, data.ctermfg, data.ctermbg = 'NONE', 'NONE', 'NONE', 'NONE'
    vim.api.nvim_set_hl(0, to, data)
  end
  hi_link_underdouble('MiniSnippetsCurrent', 'DiagnosticUnderlineWarn')
  hi_link_underdouble('MiniSnippetsCurrentReplace', 'DiagnosticUnderlineError')
  hi_link_underdouble('MiniSnippetsUnvisited', 'DiagnosticUnderlineHint')
  hi_link_underdouble('MiniSnippetsVisited', 'DiagnosticUnderlineInfo')
  hi_link_underdouble('MiniSnippetsFinal', 'DiagnosticUnderline' .. (vim.fn.has('nvim-0.9') == 1 and 'Ok' or 'Hint'))
end

H.is_disabled = function() return vim.g.minisnippets_disable == true or vim.b.minisnippets_disable == true end

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
    local msg = ok and 'Object is not a dictionary' or contents
    return H.notify('File does not contain a valid JSON object: ' .. path .. '\nReason: ' .. msg, 'WARN', silent)
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

-- Expand ---------------------------------------------------------------------
H.make_extended_insert = function(insert)
  return function(snippet)
    if snippet == nil then return end

    -- Ensure proper mode: Insert if Insert, Normal otherwise
    -- NOTE: Normal mode is chosen because ensuring Insert is troublesome.
    -- Any reasonable approach (`:normal! \28\14a`, `:startinsert`,
    -- `vim.fn.feedkeys('\28\14a', 'n')`) does not immediately start Insert
    -- mode, only "after function or script is finished".
    local mode = vim.fn.mode()
    if not (mode == 'i' or mode == 'n') then H.set_mode('n') end

    -- Remove snippet's region
    local r = snippet.region
    if H.is_region(r) then
      -- Set cursor before deleting text to ensure working at end of line
      H.set_cursor({ r.from.line, r.from.col - 1 })
      vim.api.nvim_buf_set_text(0, r.from.line - 1, r.from.col - 1, r.to.line - 1, r.to.col, {})
    end

    -- Insert at cursor
    insert(snippet)
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

H.parse_normalize = function(node_arr, opts)
  local lookup = {}
  for key, val in pairs(opts.lookup) do
    if type(key) == 'string' then lookup[key] = tostring(val) end
  end

  local has_final_tabstop = false
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

    -- Track presence of final tabstop
    has_final_tabstop = has_final_tabstop or n.tabstop == '0'
  end
  -- - Ensure proper random random variables
  math.randomseed(vim.loop.hrtime())
  local res = H.nodes_traverse(node_arr, normalize)

  -- Possibly append final tabstop
  if not has_final_tabstop then table.insert(node_arr, { tabstop = '0', text = '' }) end

  return node_arr
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

-- Session --------------------------------------------------------------------
H.get_active_session = function() return H.sessions[#H.sessions] end

H.session_new = function(snippet, opts)
  local nodes = MiniSnippets.parse(snippet.body, { normalize = true, vars_lookup = opts.vars_lookup })

  -- Compute all present tabstops in session traverse order
  local taborder = H.compute_tabstop_order(nodes)
  local tabstops = {}
  for i, id in ipairs(taborder) do
    tabstops[id] =
      { prev = taborder[i - 1] or taborder[#taborder], next = taborder[i + 1] or taborder[1], is_visited = false }
  end

  return {
    buf_id = vim.api.nvim_get_current_buf(),
    cur_tabstop = taborder[1],
    extmark_id = H.extmark_new(0, vim.fn.line('.') - 1, vim.fn.col('.') - 1),
    insert_args = vim.deepcopy({ snippet = snippet, opts = opts }),
    nodes = nodes,
    ns_id = H.ns_id.nodes,
    tabstops = tabstops,
  }
end

H.session_init = function(session, full)
  if session == nil then return end
  local buf_id = session.buf_id

  -- Prepare
  if full then
    -- Set buffer text
    H.nodes_set_text(buf_id, session.nodes, session.extmark_id, H.get_indent())

    -- No session if no input needed: single final tabstop without placeholder
    if session.cur_tabstop == '0' then
      local ref_node = H.session_get_ref_node(session)
      local row, col, opts = H.extmark_get(buf_id, ref_node.extmark_id)
      local is_empty = row == opts.end_row and col == opts.end_col
      if is_empty then
        H.extmark_set_cursor(buf_id, ref_node.extmark_id, 'left')
        -- Clean up
        H.nodes_traverse(session.nodes, function(n) H.extmark_del(buf_id, n.extmark_id) end)
        return H.extmark_del(buf_id, session.extmark_id)
      end
    end

    -- Register new session
    H.session_deinit(H.get_active_session(), false)
    table.insert(H.sessions, session)

    -- Focus on the current tabstop
    H.session_tabstop_focus(session, session.cur_tabstop)

    -- Set tracking behavior
    H.track_sessions()

    -- Make mappings for all sessions
    H.map_in_sessions()
  else
    -- Sync current tabstop for resumed session. This is useful when nested
    -- session was done inside reference tabstop node (most common case).
    -- On purpose don't change cursor/buffer/focus to allow smoother typing.
    H.session_sync_current_tabstop(session)
  end

  -- Ensure Insert mode. NOTE: it does not have immediate effect.
  if vim.fn.mode() ~= 'i' then H.set_mode('i') end

  -- Trigger proper event
  H.trigger_event('MiniSnippetsSession' .. (full and 'Start' or 'Resume'))
end

H.track_sessions = function()
  -- Create tracking autocommands only once for all nested sessions
  if #H.sessions > 1 then return end
  local gr = vim.api.nvim_create_augroup('MiniSnippetsTrack', { clear = true })

  -- React to text changes
  local latest_changedticks = {}
  local on_textchanged = function(args)
    local session, buf_id = H.get_active_session(), args.buf
    -- React only to text changes in session's buffer for performance
    if session.buf_id ~= buf_id or latest_changedticks[buf_id] == vim.b[buf_id].changedtick then return end
    latest_changedticks[buf_id] = vim.b[buf_id].changedtick
    H.session_sync_current_tabstop(session)
  end
  local text_events = { 'TextChanged', 'TextChangedI', 'TextChangedP' }
  vim.api.nvim_create_autocmd(text_events, { group = gr, callback = on_textchanged, desc = 'React to text change' })

  -- Stop if final tabstop is current: exit to Normal mode or *any* user typing
  -- NOTE: Use `schedule_wrap` to possibly replace placeholder in final tabstop
  local stop_if_final = vim.schedule_wrap(function(args)
    local session, buf_id = H.get_active_session(), args.buf
    if not (session.buf_id == buf_id and session.cur_tabstop == '0') then return end
    MiniSnippets.session.stop()
  end)
  local modechanged_opts = { group = gr, pattern = '*:n', callback = stop_if_final, desc = 'Stop on final tabstop' }
  vim.api.nvim_create_autocmd('ModeChanged', modechanged_opts)
  -- NOTE: Don't use `TextChanged*` as they may unexpectedly trigger with
  -- built-in completion (as it might "delete and add" text when not needed)
  vim.api.nvim_create_autocmd('InsertCharPre', { group = gr, callback = stop_if_final, desc = 'Stop on final tabstop' })
end

H.map_in_sessions = function()
  -- Create mapping only once for all nested sessions
  if #H.sessions > 1 then return end
  local mappings = H.get_config().mappings
  local map_with_cache = function(lhs, call, desc)
    if lhs == '' then return end
    H.cache.mappings[lhs] = vim.fn.maparg(lhs, 'i', false, true)
    -- NOTE: Map globally to work in nested sessions in different buffers
    vim.keymap.set('i', lhs, '<Cmd>lua MiniSnippets.session.' .. call .. '<CR>', { desc = desc })
  end
  map_with_cache(mappings.jump_next, 'jump("next")', 'Jump to next snippet tabstop')
  map_with_cache(mappings.jump_prev, 'jump("prev")', 'Jump to previous snippet tabstop')
  map_with_cache(mappings.stop, 'stop()', 'Stop active snippet session')
end

H.unmap_in_sessions = function()
  for lhs, data in pairs(H.cache.mappings) do
    local needs_restore = vim.tbl_count(data) > 0
    if needs_restore then vim.fn.mapset('i', false, data) end
    if not needs_restore then vim.keymap.del('i', lhs) end
  end
  H.cache.mappings = {}
end

H.session_tabstop_focus = function(session, tabstop_id)
  session.cur_tabstop = tabstop_id
  session.tabstops[tabstop_id].is_visited = true

  -- Update highlighting
  H.session_update_hl(session)

  -- Focus cursor on the reference node in proper side: left side if it has
  -- placeholder (and will be replaced), right side otherwise (to append).
  local ref_node = H.session_get_ref_node(session)
  local side = ref_node.placeholder ~= nil and 'left' or 'right'
  H.extmark_set_cursor(session.buf_id, ref_node.extmark_id, side)

  -- Ensure proper gravity as reference node has changed
  H.session_ensure_gravity(session)

  -- TODO: Show choices if reference node has choices
end

H.session_ensure_gravity = function(session)
  -- Ensure proper gravity relative to reference node (first node with current
  -- tabstop): "left" before, "expand" at, "right" after. This should account
  -- for typing in snippets like `$1$2$1$2$1` (in both 1 and 2).
  local buf_id, cur_tabstop, base_gravity = session.buf_id, session.cur_tabstop, 'left'
  local ensure = function(n)
    local is_ref_node = n.tabstop == cur_tabstop and base_gravity == 'left'
    H.extmark_set_gravity(buf_id, n.extmark_id, is_ref_node and 'expand' or base_gravity)
    base_gravity = (is_ref_node or base_gravity == 'right') and 'right' or 'left'
  end
  -- NOTE: This relies on `H.nodes_traverse` to first apply to the node and
  -- only later (recursively) to placeholder nodes, which makes them all have
  -- "right" gravity and thus being removable during replacing placeholder (as
  -- they will not cover newly inserted text).
  H.nodes_traverse(session.nodes, ensure)
end

H.session_get_ref_node = function(session)
  local res, cur_tabstop = nil, session.cur_tabstop
  local find = function(n) res = res or (n.tabstop == cur_tabstop and n or nil) end
  H.nodes_traverse(session.nodes, find)
  return res
end

H.session_sync_current_tabstop = function(session)
  -- TODO: Figure out why it is called twice as much.
  -- Is it indeed because of 'mini.completion' and popups?
  if session._no_sync then return end

  local buf_id, ref_node = session.buf_id, H.session_get_ref_node(session)
  local ref_extmark_id = ref_node.extmark_id

  -- With present placeholder, decide whether there was a valid change (then
  -- remove it) or not (then no sync)
  if ref_node.placeholder ~= nil then
    local ref_row, ref_col = H.extmark_get_range(buf_id, ref_extmark_id)
    local phd_row, phd_col = H.extmark_get_range(buf_id, ref_node.placeholder[1].extmark_id)
    if ref_row == phd_row and ref_col == phd_col then return end

    -- Remove placeholder to get extmark representing newly added text
    H.nodes_del(buf_id, ref_node.placeholder)
    ref_node.placeholder = nil
  end

  -- Compute target text
  local row, col, end_row, end_col = H.extmark_get_range(buf_id, ref_extmark_id)
  local cur_text = vim.api.nvim_buf_get_text(0, row, col, end_row, end_col, {})
  cur_text = table.concat(cur_text, '\n')

  -- Sync nodes with current tabstop to have text from reference node
  local cur_tabstop = session.cur_tabstop
  local sync = function(n)
    if n.tabstop == cur_tabstop then
      if n.placeholder ~= nil then H.nodes_del(buf_id, n.placeholder) end
      H.extmark_set_gravity(buf_id, n.extmark_id, 'expand')
      if n.extmark_id ~= ref_extmark_id then H.extmark_set_text(buf_id, n.extmark_id, 'inside', cur_text) end
      n.placeholder, n.text = nil, cur_text
    end
    -- Make sure node's extmark doesn't move when setting later text
    H.extmark_set_gravity(buf_id, n.extmark_id, 'left')
  end
  -- - Temporarily disable running this function (as autocommands will trigger)
  session._no_sync = true
  H.nodes_traverse(session.nodes, sync)
  session._no_sync = nil
  H.session_ensure_gravity(session)

  -- Make highlighting up to date
  H.session_update_hl(session)
end

H.session_jump = vim.schedule_wrap(function(session, direction)
  if session == nil then return end
  local cur_tabstop = session.cur_tabstop
  -- TODO: Make sure that `new_tabstop` is an actually present tabstop
  -- Example why needed: `${1:$2}$3`, setting text in $1 removes $2 tabstop.
  local new_tabstop = session.tabstops[cur_tabstop][direction]
  if new_tabstop == cur_tabstop then return end

  local event_data = { tabstop_from = cur_tabstop, tabstop_to = new_tabstop }
  H.trigger_event('MiniSnippetsSessionJumpPre', event_data)
  H.session_tabstop_focus(session, new_tabstop)
  H.trigger_event('MiniSnippetsSessionJump', event_data)
end)

H.session_update_hl = function(session)
  local buf_id, insert_opts = session.buf_id, session.insert_args.opts
  local empty_tabstop, empty_tabstop_final = insert_opts.empty_tabstop, insert_opts.empty_tabstop_final
  local cur_tabstop, tabstops = session.cur_tabstop, session.tabstops
  local is_replace = H.session_get_ref_node(session).placeholder ~= nil
  local current_hl = 'MiniSnippetsCurrent' .. (is_replace and 'Replace' or '')
  local priority = 101

  local update_hl = function(n)
    if n.tabstop == nil then return end
    local is_final, is_visited = n.tabstop == '0', tabstops[n.tabstop].is_visited
    local hl_group = n.tabstop == cur_tabstop and current_hl
      or (is_final and 'MiniSnippetsFinal' or (is_visited and 'MiniSnippetsVisited' or 'MiniSnippetsUnvisited'))

    local row, col, opts = H.extmark_get(buf_id, n.extmark_id)
    opts.hl_group, opts.virt_text, opts.virt_text_pos = hl_group, nil, nil
    if H.has_inline_extmark_support and row == opts.end_row and col == opts.end_col then
      opts.virt_text_pos = 'inline'
      opts.virt_text = { { is_final and empty_tabstop_final or empty_tabstop, hl_group } }
      -- Make inline extmarks preserve order if placed at same position
      priority = priority + 1
      opts.priority = priority
    end
    vim.api.nvim_buf_set_extmark(buf_id, H.ns_id.nodes, row, col, opts)
  end
  H.nodes_traverse(session.nodes, update_hl)
end

H.session_deinit = function(session, full)
  if session == nil then return end

  -- Delete or hide (make invisible) extmarks
  local extmark_fun = full and H.extmark_del or H.extmark_hide
  extmark_fun(session.buf_id, session.extmark_id)
  H.nodes_traverse(session.nodes, function(n) extmark_fun(session.buf_id, n.extmark_id) end)

  -- Trigger proper event
  H.trigger_event('MiniSnippetsSession' .. (full and 'Stop' or 'Suspend'))
end

H.nodes_set_text = function(buf_id, nodes, tracking_extmark_id, indent)
  for _, n in ipairs(nodes) do
    -- Add tracking extmark
    local _, _, row, col = H.extmark_get_range(buf_id, tracking_extmark_id)
    n.extmark_id = H.extmark_new(buf_id, row, col)

    -- Adjust node's text and append it to currently set text
    if n.text ~= nil then
      local new_text = n.text:gsub('\n', '\n' .. indent)
      if vim.bo.expandtab then
        local sw = vim.bo.shiftwidth
        new_text = new_text:gsub('\t', string.rep(' ', sw == 0 and vim.bo.tabstop or sw))
      end
      H.extmark_set_text(buf_id, tracking_extmark_id, 'right', new_text)
    end

    -- Process (possibly nested) placeholder nodes
    if n.placeholder ~= nil then H.nodes_set_text(buf_id, n.placeholder, tracking_extmark_id, indent) end

    -- Make sure that node's extmark doesn't move when adding next node text
    H.extmark_set_gravity(buf_id, n.extmark_id, 'left')
  end
end

H.nodes_del = function(buf_id, nodes)
  local del = function(n)
    H.extmark_set_text(buf_id, n.extmark_id, 'inside', {})
    H.extmark_del(buf_id, n.extmark_id)
  end
  H.nodes_traverse(nodes, del)
end

H.nodes_traverse = function(nodes, f)
  for i, n in ipairs(nodes) do
    -- Visit whole node first to allow `f` to modify placeholder. This is also
    -- important to ensure proper gravity inside placeholder nodes.
    local out = f(n)
    if out ~= nil then n = out end
    if n.placeholder ~= nil then n.placeholder = H.nodes_traverse(n.placeholder, f) end
    nodes[i] = n
  end
  return nodes
end

H.compute_tabstop_order = function(nodes)
  local tabstops_map, traverse_tabstops = {}, nil
  H.nodes_traverse(nodes, function(n) tabstops_map[n.tabstop or true] = true end)
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

-- Extmarks -------------------------------------------------------------------
-- All extmark functions work in current buffer with same global namespace.
-- This is because interaction with snippets eventually requires buffer to be
-- current, so instead rely on it becoming such as soon as possible.
H.extmark_new = function(buf_id, row, col)
  -- Create expanding extmark by default
  local opts = { end_row = row, end_col = col, right_gravity = false, end_right_gravity = true }
  return vim.api.nvim_buf_set_extmark(buf_id, H.ns_id.nodes, row, col, opts)
end

H.extmark_get = function(buf_id, ext_id)
  local data = vim.api.nvim_buf_get_extmark_by_id(buf_id, H.ns_id.nodes, ext_id, { details = true })
  data[3].id, data[3].ns_id = ext_id, nil
  return data[1], data[2], data[3]
end

H.extmark_get_range = function(buf_id, ext_id)
  local row, col, opts = H.extmark_get(buf_id, ext_id)
  return row, col, opts.end_row, opts.end_col
end

H.extmark_del = function(buf_id, ext_id) vim.api.nvim_buf_del_extmark(buf_id, H.ns_id.nodes, ext_id or -1) end

H.extmark_hide = function(buf_id, ext_id)
  local row, col, opts = H.extmark_get(buf_id, ext_id)
  opts.hl_group, opts.virt_text, opts.virt_text_pos = nil, nil, nil
  vim.api.nvim_buf_set_extmark(buf_id, H.ns_id.nodes, row, col, opts)
end

H.extmark_set_gravity = function(buf_id, ext_id, gravity)
  local row, col, opts = H.extmark_get(buf_id, ext_id)
  opts.right_gravity, opts.end_right_gravity = gravity == 'right', gravity ~= 'left'
  vim.api.nvim_buf_set_extmark(buf_id, H.ns_id.nodes, row, col, opts)
end

--stylua: ignore
H.extmark_set_text = function(buf_id, ext_id, side, text)
  local row, col, end_row, end_col = H.extmark_get_range(buf_id, ext_id)
  if side == 'left'  then end_row, end_col = row,     col     end
  if side == 'right' then row,     col     = end_row, end_col end
  text = type(text) == 'string' and vim.split(text, '\n') or text
  vim.api.nvim_buf_set_text(buf_id, row, col, end_row, end_col, text)
end

H.extmark_set_cursor = function(buf_id, ext_id, side)
  H.ensure_cur_buf(buf_id)
  local row, col, end_row, end_col = H.extmark_get_range(buf_id, ext_id)
  local pos = side == 'left' and { row + 1, col } or { end_row + 1, end_col }
  H.set_cursor(pos)
end

-- Indent ---------------------------------------------------------------------
H.get_indent = function(lnum)
  local line, comment_indent = vim.fn.getline(lnum or '.'), ''
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

H.trigger_event = function(event_name, data) vim.api.nvim_exec_autocmds('User', { pattern = event_name, data = data }) end

H.is_array_of = function(x, predicate)
  if not H.islist(x) then return false end
  for i = 1, #x do
    if not predicate(x[i]) then return false end
  end
  return true
end

H.is_valid_buf = function(buf_id) return type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id) end

H.ensure_cur_buf = function(buf_id)
  if buf_id == 0 or buf_id == vim.api.nvim_get_current_buf() or not H.is_valid_buf(buf_id) then return end
  local win_id = vim.fn.win_findbuf(buf_id)[1]
  if win_id == nil then return vim.api.nvim_win_set_buf(0, buf_id) end
  vim.api.nvim_set_current_win(win_id)
end

H.set_cursor = function(pos)
  -- Ensure no built-in completion window
  -- NOTE: `complete()` instead of emulating `<C-y>` has immeiate result
  -- (without the need to `vim.schedule()`).
  -- HACK: Always clearing (and not *only* when pumvisible) accounts for weird
  -- edge case when it is not visible (i.e. candidates *just* got exhausted)
  -- but will still "clear and restore" text leading to squashing of extmarks.
  if vim.fn.mode() == 'i' then vim.cmd('noautocmd call complete(col("."), [])') end

  -- Make possible positioning cursor after line end
  if vim.fn.mode() ~= 'i' then
    local cache_virtualedit = vim.wo.virtualedit
    vim.wo.virtualedit = 'onemore'
    vim.schedule(function() vim.wo.virtualedit = cache_virtualedit end)
  end

  vim.api.nvim_win_set_cursor(0, pos)
end

H.set_mode = function(target_mode)
  -- This is seemingly the only "good" way to ensure Normal mode.
  -- This also works with `vim.snippet.expand()` as its implementation uses
  -- `vim.api.nvim_feedkeys(k, 'n', true)` to select text in Select mode.
  local keys = '\28\14' .. (target_mode == 'i' and 'i' or '')
  vim.api.nvim_feedkeys(keys, 'n', false)
end

-- TODO: Remove after compatibility with Neovim=0.9 is dropped
H.islist = vim.fn.has('nvim-0.10') == 1 and vim.islist or vim.tbl_islist

return MiniSnippets
