-- TODO:
--
-- Code:
--
-- - Autocomplete.
--
-- - Autocorrect.
--
-- - Range preview.
--
-- Docs:
--
-- - ...
--
-- Tests:
--
-- - Make sure that every feature works in all command types (`getcmdtype()`).
--
-- - Arrow mappings should work.
--
-- - Weird `:h :range` should work in every feature. In particular:
--     - `:/pattern/`
--     - `'a,'b` (with punctuation and alphabetic marks). Special case is `''`.
--       Requires those marks to actually be set.
--     - Arithmetics on line ranges
--
-- - Autocomplete:
--     - Should autocomplete for first letters of "bad" (for Neovim<0.12)
--       command names (like `g`, `v`, `s`).
--
--     - Works for problematic completion types (like `file`/`file_in_path`;
--       `:edit f` or `:grep f`) without infinite loop.
--
--     - Works with bang (like `:q!`) without extra wildchar.
--
--     - Does not trigger wildchar after the delay if not inside command line.
--
--     - Does not trigger wildchar in case of `delay=0` and Command-line mode
--       triggered via mapping (like `:<C-u>...` in Visual mode).
--
-- - Autocorrect:

--- *mini.cmdline* Command line tweaks
---
--- MIT License Copyright (c) 2025 Evgeni Chasnovski

--- Features:
---
--- - Autocomplete with customizable delay. Enhances |cmdline-completion| and
---   manual |'wildchar'| pressing experience.
---   Requires Neovim>=0.11, but Neovim>=0.12 is recommended.
---
--- - Autocorrect words as-you-type. Only words that must come from a fixed set of
---   candidates (like commands and options) are autocorrected by default.
---
--- - Preview command range.
---
--- - Map arrow keys to act independently of whether |'wildmenu'| is shown.
---
--- What it doesn't do:
---
--- - Customization of command line UI. Use |vim._extui| (on Neovim>=0.12).
---
--- - Customization of autocompletion candidates. They are computed
---   via |cmdline-completion|.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.cmdline').setup({})` (replace `{}`
--- with your `config` table). It will create global Lua table `MiniCmdline` which
--- you can use for scripting or manually (with `:lua MiniCmdline.*`).
---
--- See |MiniCmdline.config| for `config` structure and default values.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.minicmdline_config` which should have same structure as
--- `MiniCmdline.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Suggested option values ~
---
--- Some options are set automatically (if not set before |MiniCmdline.setup()|):
--- - |'wildmode'| is set to "noselect,full" for less intrusive autocompletion popup.
---   Requires Neovim>=0.11.
--- - |'wildoptions'| is set to "pum,fuzzy" to enable fuzzy matching.
---
--- # Comparisons ~
---
--- - [folke/noice.nvim](https://github.com/folke/noice.nvim):
---     - ...
---
--- - Built-in |cmdline-autocompletion| (on Neovim>=0.12):
---     - ...
---
--- # Highlight groups ~
---
--- - `MiniCmdlinePreviewBorder` - border of command range preview window.
--- - `MiniCmdlinePreviewNormal` - basic foreground/background of command range
---   preview window.
--- - `MiniCmdlinePreviewTitle` - title of command range preview window.
---
--- # Disabling ~
---
--- To disable acting in mappings, set `vim.g.minicmdline_disable` (globally) or
--- `vim.b.minicmdline_disable` (for a buffer) to `true`. Considering high number
--- of different scenarios and customization intentions, writing exact rules
--- for disabling module's functionality is left to user.
--- See |mini.nvim-disabling-recipes| for common recipes.
---@tag MiniCmdline

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local

-- Module definition ==========================================================
local MiniCmdline = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniCmdline.config|.
---
---@usage >lua
---   require('mini.cmdline').setup() -- use default config
---   -- OR
---   require('mini.cmdline').setup({}) -- replace {} with your config table
--- <
MiniCmdline.setup = function(config)
  -- Export module
  _G.MiniCmdline = MiniCmdline

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands()

  -- Create default highlighting
  H.create_default_hl()
end

--- Defaults ~
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # General ~
---
--- - Each feature is configured via separate table.
--- - Use `enable = false` to disable a feature.
---
---# Autocomplete ~
---
--- `config.autocomplete` is used to configure autocompletion: automatic show
--- of |'wildmenu'|.
---
--- `autocomplete.delay` defines a (debounce style) delay after which |'wildchar'|
--- is triggered to show wildmenu.
--- Default: 0. Note: Neovim>=0.12 is recommended for positive values to reduce
--- flicker (thanks to |wildtrigger()|).
---
--- `autocomplete.predicate` defines a condition of whether to trigger completion
--- at the current the command line state. Should return `true` to show
--- completion and `false` otherwise.
--- Default: |MiniCmdline.default_autocomplete_predicate()| (always show).
--- Example of blocking completion based on completion type (as some may be slow): >lua
---
---   local block_compltype = { shellcmd = true }
---   require('mini.cmdline').setup({
---     autocomplete = {
---       predicate = function()
---         return not block_compltype[vim.fn.getcmdcompltype()]
---       end,
---     },
---   })
--- <
---# Autocorrect ~
---
--- `config.autocorrect` is used to configure autocorrection: automatic adjustment
--- of bad words as you type them. This works only when appending text at the end
--- of the command line. Editing already typed words does not trigger autocorrect
--- (allows correcting the autocorrection).
---
--- When to autocorrect is computed automatically based on |getcmdcomplpat()| after
--- every key press: if it doesn't add its character to completion pattern, then
--- the pattern before the key press is attempted to be corrected.
--- There is also an autocorrection attempt for the last word just before
--- executing the command.
---
--- Notes:
--- - This is intended mostly for fixing typos and not as a shortcut for fuzzy
---   matching. The latter is too intrusive. Explicitly use fuzzy completion
---   for that (set up by default).
---
--- - Default autocorrection is done only for words that must come from a fixed
---   set of candidates (like commands and options) by choosing the one
---   with the lowest string distance.
---   See |MiniCmdline.default_autocorrect_func()| for details.
---
--- - If current command expects only a single argument (like |:colorscheme|), then
---   autocorrection will happen only just before executing the command.
---
--- `autocorrect.func` is a function that can be used to customize autocorrection.
--- Takes a table with input data and should return a string with the correct word
--- or `nil` for no autocorrection. Default: |MiniCmdline.default_autocorrect_func()|.
--- Input data fields:
--- - <word> `(string)` - word to be autocorrected. Never empty string.
--- - <type> `(string)` - word type. Output of |getcmdcompltype()|.
---
---# Preview range ~
---
--- TODO
MiniCmdline.config = {
  -- Autocompletion: show `:h 'wildmenu'` as you type
  autocomplete = {
    enable = true,

    -- Delay (in ms) after which to trigger completion
    -- Neovim>=0.12 is recommended for positive values
    delay = 0,

    -- Custom rule of when to trigger completion
    predicate = nil,

    -- Whether to map arrow keys for more consistent wildmenu behavior
    map_arrows = true,
  },

  -- Autocorrection: correct non-existing command name
  autocorrect = {
    enable = true,

    -- Custom autocorrection rule
    func = nil,
  },

  -- Range preview: show command's target range in a floating window
  preview_range = {
    enable = true,

    -- Window options
    window = {
      -- Floating window config
      config = {},

      -- Value of 'winblend' option
      winblend = 25,
    },
  },
}
--minidoc_afterlines_end

--- Default autocompletion predicate
---
---@return boolean If command line does not (yet) contain a letter - `false`,
---   otherwise - `true`. This makes command range preview feature easier to use.
MiniCmdline.default_autocomplete_predicate = function() return vim.fn.getcmdline():find('%a') ~= nil end

--- Default autocorrection function
---
--- - Return input word if `opts.strict_type` and input `type` is not proper.
--- - Get candidates via `opts.get_candidates()`.
---   Default: mostly via |getcompletion()| with empty pattern and input `type`.
---   Except `help` and `option` types, which list all available candidates in
---   their own ways.
--- - Choose the candidate with the lowest Damerau–Levenshtein distance
---   (smallest number of deletion/insertion/substitution/transposition needed
---   to transform one word into another; slightly prefers transposition).
---   Notes:
---     - Type `'command'` also chooses from all valid candidate abbreviations.
---     - Comparison is done both respecting and ignoring case.
---
---@param data table Input autocorrection data. As described in |MiniCmdline.config|.
---@param opts table|nil Options. Possible fields:
---   - <strict_type> `(boolean)` - whether to restrict output only for types which
---     must have words from a fixed set of candidates (like command or colorscheme
---     names). Default: `true`.
---   - <get_candidates> `(function)` - source of candidates. Will be called
---     with `data` as argument and should return array of string candidates to
---     choose from.
---     Default: for most types -  |getcompletion()| with empty pattern and
---     input `type`; for `help` type - all available help tags.
---
---@return string Autocorrected word.
MiniCmdline.default_autocorrect_func = function(data, opts)
  H.check_type('data', data, 'table')
  H.check_type('data.word', data.word, 'string')
  H.check_type('data.type', data.type, 'string')

  opts = opts or {}
  local strict_type = opts.strict_type == nil or opts.strict_type
  if strict_type and not H.autocorrect_strict_types[data.type] then return data.word end

  -- Get all valid words
  local all = vim.is_callable(opts.get_candidates) and opts.get_candidates(data) or H.get_autocorrect_candidates(data)
  if vim.tbl_contains(all, data.word) or data.word == '' then return data.word end

  -- Make results stable in case several candidates have the same distance
  table.sort(all)

  -- Handle commands separately: need dedicated abbreviation length
  -- computation and to allow `!`
  if data.type == 'command' then return H.get_nearest_command(data.word, all) end

  -- Fall back to computing nearest string without allowing abbreviations
  local abbr_lens = vim.tbl_map(string.len, all)
  return H.get_nearest_abbr(data.word, all, abbr_lens)
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniCmdline.config)

-- Timers
H.timers = {
  autocomplete = vim.loop.new_timer(),
}

-- Autocomplete requires `noselect` flag of 'wildmode'. Present in Neovim>=0.11
H.can_autocomplete = vim.fn.has('nvim-0.11') == 1

-- Autocorrect types for which words *must* be from some fixed set
-- Basically a subset of `:h :command-complete` which might lead to an error if
-- word is not from a fixed set. Can be adjusted for more nuances.
-- Reasons for not including a type:
-- - The main reason is because type's usage can be done in context when
--   creating a new object. Like `:edit new-file` for `file` type.
-- - No `help` because there already is an autocorrection with a "sophisticated
--   algorithm to decide which match is better than another one".
--stylua: ignore
H.autocorrect_strict_types = {
  arglist       = true, -- file names in argument list
  -- augroup       = true, -- autocmd groups
  -- breakpoint    = true, -- |:breakadd| suboptions
  buffer        = true, -- buffer names
  color         = true, -- color schemes
  command       = true, -- Ex command (and arguments)
  compiler      = true, -- compilers
  diff_buffer   = true, -- diff buffer names
  -- dir           = true, -- directory names
  -- dir_in_path   = true, -- directory names in |'cdpath'|
  -- environment   = true, -- environment variable names
  event         = true, -- autocommand events
  -- expression    = true, -- Vim expression
  -- file          = true, -- file and directory names
  -- file_in_path  = true, -- file and directory names in |'path'|
  filetype      = true, -- filetype names |'filetype'|
  -- ['function']  = true, -- function name
  -- help          = true, -- help subjects
  -- highlight     = true, -- highlight groups
  history       = true, -- |:history| suboptions
  keymap        = true, -- keyboard mappings
  locale        = true, -- locale names (as output of locale -a)
  -- lua           = true, -- Lua expression |:lua|
  mapclear      = true, -- buffer argument
  -- mapping       = true, -- mapping name
  -- menu          = true, -- menus
  messages      = true, -- |:messages| suboptions
  option        = true, -- options
  packadd       = true, -- optional package |pack-add| names
  -- runtime       = true, -- file and directory names in |'runtimepath'|
  -- scriptnames   = true, -- sourced script names
  -- shellcmd      = true, -- Shell command
  -- shellcmdline  = true, -- First is a shell command and subsequent ones are filenames
  sign          = true, -- |:sign| suboptions
  syntax        = true, -- syntax file names |'syntax'|
  syntime       = true, -- |:syntime| suboptions
  -- tag           = true, -- tags
  -- tag_listfiles = true, -- tags, file names are shown when CTRL-D is hit
  -- user          = true, -- user names
  -- var           = true, -- user variables
}

-- Various cache to use during command line edit
H.cache = {}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('autocomplete', config.autocomplete, 'table')
  H.check_type('autocomplete.enable', config.autocomplete.enable, 'boolean')
  H.check_type('autocomplete.delay', config.autocomplete.delay, 'number')
  H.check_type('autocomplete.predicate', config.autocomplete.predicate, 'function', true)
  H.check_type('autocomplete.map_arrows', config.autocomplete.map_arrows, 'boolean')

  H.check_type('autocorrect', config.autocorrect, 'table')
  H.check_type('autocorrect.enable', config.autocorrect.enable, 'boolean')
  H.check_type('autocorrect.func', config.autocorrect.func, 'function', true)

  H.check_type('preview_range', config.preview_range, 'table')
  H.check_type('preview_range.enable', config.preview_range.enable, 'boolean')
  H.check_type('preview_range.window', config.preview_range.window, 'table')
  local preview_win_config = config.preview_range.window.config
  if not (type(preview_win_config) == 'table' or vim.is_callable(preview_win_config)) then
    H.error('`preview_range.window.config` should be table or callable, not ' .. type(preview_win_config))
  end
  H.check_type('preview_range.window.winblend', config.preview_range.window.winblend, 'number')

  return config
end

H.apply_config = function(config)
  MiniCmdline.config = config

  -- Try setting suggested option values
  -- NOTE: This makes it more like 'mini.completion' (with 'noselect')
  local was_set = vim.api.nvim_get_option_info2('wildmode', { scope = 'global' }).was_set
  if not was_set and config.autocomplete.enable and H.can_autocomplete then vim.o.wildmode = 'noselect,full' end

  was_set = vim.api.nvim_get_option_info2('wildoptions', { scope = 'global' }).was_set
  if not was_set then vim.o.wildoptions = 'pum,fuzzy' end

  -- Set useful mappings
  if config.autocomplete.map_arrows then
    local map_arrow = function(dir, wildmenu_prefix, desc)
      local rhs = function() return (vim.fn.wildmenumode() == 1 and wildmenu_prefix or '') .. dir end
      vim.keymap.set('c', dir, rhs, { expr = true, desc = desc })
    end
    map_arrow('<Left>', '<Space><BS>', 'Move cursor left')
    map_arrow('<Right>', '<Space><BS>', 'Move cursor right')
    map_arrow('<Up>', '<C-e>', 'Go to earlier history')
    map_arrow('<Down>', '<C-e>', 'Go to newer history')
  end
end

H.create_autocommands = function()
  local gr = vim.api.nvim_create_augroup('MiniCmdline', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = gr, pattern = pattern, callback = callback, desc = desc })
  end

  -- Act on command line events. Notes:
  -- - Schedule for 'CmdlineEnter' to not act on mappings like `:...`
  --   (like `:<C-u>...` popular for Visual mode).
  -- - Schedule for 'CmdlineChanged' to work around autcompletion issues with
  --   mocking wildchar.
  -- - Do not schedule 'CmdlineLeave' to be able to set command line text.
  au('CmdlineEnter', '*', vim.schedule_wrap(H.on_cmdline_enter), 'Act on Command line enter')
  au('CmdlineChanged', '*', vim.schedule_wrap(H.on_cmdline_changed), 'Act on Command line change')
  au('CmdlineLeave', '*', H.on_cmdline_leave, 'Act on Command line leave')

  -- TODO: Probably add autocommand to detect Visual->Command-line mode
  -- transition to not show range preview in this case

  -- TODO: Maybe here autoreact to change in command line height?
  au('VimResized', '*', vim.schedule_wrap(function() H.preview_range(true) end), 'Adjust range preview')

  au('ColorScheme', '*', H.create_default_hl, 'Ensure colors')
end

H.create_default_hl = function()
  local hi = function(name, opts)
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end

  hi('MiniCmdlinePreviewBorder', { link = 'FloatBorder' })
  hi('MiniCmdlinePreviewNormal', { link = 'NormalFloat' })
  hi('MiniCmdlinePreviewTitle', { link = 'FloatTitle' })
end

H.is_disabled = function() return vim.g.minicmdline_disable == true or vim.b.minicmdline_disable == true end

H.get_config = function() return vim.tbl_deep_extend('force', MiniCmdline.config, vim.b.minicmdline_config or {}) end

-- Autocommands ---------------------------------------------------------------
H.on_cmdline_enter = function()
  -- Check for Command-line mode to not act on `:...` mappings
  if H.is_disabled() or vim.fn.mode() ~= 'c' then return end

  H.cache = {
    cmd_type = vim.fn.getcmdtype(),
    config = H.get_config(),
    preview = {},
    state = H.get_cmd_state(),
    state_prev = H.get_cmd_state(true),
    wildchar = H.get_wildchar(),
  }
  H.cache.autocomplete_predicate = H.cache.config.autocomplete.predicate or MiniCmdline.default_autocomplete_predicate

  if H.cache.config.preview_range.enable then H.preview_range() end
end

H.on_cmdline_changed = function()
  if H.cache.config == nil then return end
  local config = H.cache.config

  -- Act only on actual line change
  local state = H.get_cmd_state()
  if state.line == H.cache.state.line then return end

  -- Update state accounting for some edge cases
  if H.cache.state_prev.compltype == 'option' then H.adjust_option_cmd_state(state) end
  H.cache.state_prev, H.cache.state = H.cache.state, state

  if config.autocomplete.enable and H.can_autocomplete then H.autocomplete() end
  if config.autocorrect.enable then H.autocorrect(false) end
  if config.preview_range.enable then H.preview_range() end
end

H.on_cmdline_leave = function()
  if H.cache.config == nil then return end
  if H.cache.config.autocorrect.enable and not vim.v.event.abort then H.autocorrect(true) end
  H.preview_hide()
  H.cache = {}
end

H.get_cmd_state = function(is_init)
  local compltype = vim.fn.getcmdcompltype()
  if is_init then return { complpat = '', compltype = compltype, line = '', pos = 0, cmd = {} } end
  -- TODO: Potentially optimize to not parse whole line on every keystroke.
  -- It is only needed for range preview and range can not change after command
  -- is entered. It is enough to only track relevant range and it can be not
  -- updated if the text is added (not deleted) past the command.
  local line = vim.fn.getcmdline()
  local cmd = H.parse_cmd(line)
  return { complpat = H.getcmdcomplpat(), compltype = compltype, line = line, pos = vim.fn.getcmdpos(), cmd = cmd }
end

H.adjust_option_cmd_state = function(state)
  -- Cases like `set nowrap invmagic` are completed specially. After `no`/`inv`
  -- there is a specialized completion only for boolean options. In practice it
  -- results into `compltype=''` and `complpat=<text after no/inv>`.
  -- This intefers with how autocorrection is detected, as it relies on whole
  -- `nowrap` / `invmagic` to be a singular complat *with compltype=option*.
  --
  -- The solution is to detect cases "it was compltype=option but now it isn't"
  -- and try to expand complpat to match the whole word on cursor's left.
  if state.compltype == 'option' then return end
  state.complpat = state.line:sub(1, state.pos - 1):match(' (%w+)$') or ''
  state.compltype = state.complpat ~= nil and 'option' or state.compltype
end

-- Autocomplete ---------------------------------------------------------------
H.autocomplete = function()
  H.timers.autocomplete:stop()

  -- Do not complete if predicate says so.
  if not H.cache.autocomplete_predicate() then return end

  -- Do nothing in some problematic cases (when wildmenu does not work)
  -- TODO: Remove after compatibility with Neovim=0.11 is dropped
  if H.block_autocomplete() then return end

  local delay = H.cache.config.autocomplete.delay
  if delay == 0 then return H.trigger_complete() end
  H.timers.autocomplete:start(delay, 0, H.trigger_complete_scheduled)
end

H.block_autocomplete = function() return false end
if vim.fn.has('nvim-0.12') == 0 then
  H.block_autocomplete = function()
    -- Block for non-interactive command type
    if H.cache.cmd_type ~= ':' then return true end

    -- Block for cases when there is no completion candidates. This affects
    -- performance (completion candidates are computed twice), but it is
    -- the most robust way of dealing with problematic situations:
    -- - Some commands don't have completion defined: `:s`, `:g`, etc.
    -- - Some cases result in verbatim `^I` inserted. Like after bang (`:q!`).
    --
    -- The `vim.fn.getcmdcompltype() == ''` condition is too wide as it denies
    -- legitimate cases of when there are available completion candidates.
    -- Like in user commands created with `vim.api.nvim_create_user_command()`.
    local line_before_pos = H.cache.state.line:sub(1, H.cache.state.pos - 1)
    -- `getcompletion` may result in error, like after `:ltag `
    local ok, candidates = pcall(vim.fn.getcompletion, line_before_pos, 'cmdline')
    return not (ok and #candidates > 0)
  end
end

H.trigger_complete = function()
  if vim.fn.mode() ~= 'c' then return end
  H.trigger_wild()
end

H.trigger_complete_scheduled = vim.schedule_wrap(H.trigger_complete)

H.trigger_wild = function() vim.fn.wildtrigger() end
if vim.fn.has('nvim-0.12') == 0 then
  H.trigger_wild = function()
    -- Not triggerring when wildmenu is shown helps avoiding trigger after
    -- manually pressing wildchar (as text is also changes).
    if vim.fn.wildmenumode() == 1 then return end
    vim.api.nvim_feedkeys(H.cache.wildchar, 'nt', false)
  end
end

-- Autocorrect ----------------------------------------------------------------
H.autocorrect = function(is_final)
  -- Act only for normal Ex commands after a word is just finished typing
  if not (H.cache.cmd_type == ':' and H.cache.state.line:find('%S') ~= nil) then return end

  local state, state_prev = H.cache.state, H.cache.state_prev
  local line, line_prev = state.line, state_prev.line
  local pos, pos_prev = state.pos, state_prev.pos

  -- Act only at line end. It allows a natural way to adjust autocorrected text
  -- by going back and editing it. This is also easier to implement.
  local is_text_append = vim.startswith(line, line_prev) and pos == (line:len() + 1) and pos > pos_prev
  local is_word_finished = not vim.startswith(state.complpat, state_prev.complpat)

  if not (is_text_append and (is_word_finished or is_final)) then return end

  -- Compute autocorrection
  local state_to_use = is_final and state or state_prev
  local word = state_to_use.complpat
  if word == '' then return end

  local func = H.cache.config.autocorrect.func or MiniCmdline.default_autocorrect_func
  local new_word = func({ word = word, type = state_to_use.compltype }) or word

  if word == new_word then return end
  if type(new_word) ~= 'string' then return H.notify('Can not autocorrect for ' .. vim.inspect(word), 'WARN') end

  local init_pos = state_to_use.pos
  local new_line = line:sub(1, init_pos - word:len() - 1) .. new_word .. line:sub(init_pos)
  vim.fn.setcmdline(new_line, new_line:len() + 1)
end

H.get_autocorrect_candidates = function(data)
  if data.type == 'help' then
    local help_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[help_buf].buftype = 'help'
    -- - NOTE: no dedicated buffer name because it is immediately wiped out
    local tags = vim.api.nvim_buf_call(help_buf, function() return vim.fn.taglist('.*') end)
    vim.api.nvim_buf_delete(help_buf, { force = true })
    return vim.tbl_map(function(x) return x.name end, tags)
  end

  if data.type == 'option' then
    local all = {}
    for name, info in pairs(vim.api.nvim_get_all_options_info()) do
      table.insert(all, name)

      local is_bool = info.type == 'boolean'
      table.insert(all, is_bool and ('no' .. name) or nil)
      table.insert(all, is_bool and ('inv' .. name) or nil)

      local has_shortname = info.shortname ~= ''
      table.insert(all, has_shortname and info.shortname or nil)
      table.insert(all, (has_shortname and is_bool) and ('no' .. info.shortname) or nil)
      table.insert(all, (has_shortname and is_bool) and ('inv' .. info.shortname) or nil)
    end
    return all
  end

  local ok, all = pcall(vim.fn.getcompletion, '', data.type)
  return ok and all or { data.word }
end

H.get_nearest_command = function(ref, all)
  -- Do not alter `:=` command, as it is not a command special Lua shorthand
  if ref:sub(1, 1) == '=' then return ref end

  -- Allow trailing special punctuation (specific to commands)
  local word, suffix = ref:match('^(.+)([!|]?)$')

  -- Account for the fact that commands can be abbreviated (`:h |20.2|`):
  local cmd_abbr_lens, usr_cmds, usr_max_len = {}, {}, 0
  for _, cmd in ipairs(all) do
    -- User command abbreviation needs to uniquely identify command name
    if cmd:find('^[A-Z]') ~= nil then
      usr_cmds[cmd] = true
      usr_max_len = math.max(usr_max_len, cmd:len())
    else
      -- ANY abbreviation of ANY built-in command is a valid command (may be
      -- different; `wincmd`->`w`==`write`). Its an internal optimization.
      -- EXCEPT: `:def` abbreviation of `:defer` is not allowed.
      cmd_abbr_lens[cmd] = cmd == 'defer' and 4 or 1
    end
  end

  -- Slice user commands with increasing abbreviation length to find which
  -- ones can be uniquely identified by it
  for cur_abbr_len = 1, usr_max_len do
    local cur_abbrs = {}
    for cmd, _ in pairs(usr_cmds) do
      local abbr = cmd:sub(1, cur_abbr_len)
      cur_abbrs[abbr] = cur_abbrs[abbr] or {}
      table.insert(cur_abbrs[abbr], cmd)
    end

    for _, cmd_arr in pairs(cur_abbrs) do
      if #cmd_arr == 1 then
        local cmd = cmd_arr[1]
        cmd_abbr_lens[cmd] = math.min(cur_abbr_len, cmd:len())
        usr_cmds[cmd] = nil
      end
    end
  end

  local abbr_lens = vim.tbl_map(function(x) return cmd_abbr_lens[x] end, all)
  return H.get_nearest_abbr(word, all, abbr_lens) .. suffix
end

H.get_nearest_abbr = function(word, candidates, abbr_lens)
  local tolower = vim.fn.tolower
  local word_split = vim.split(word, '')
  local word_split_l = vim.split(tolower(word), '')

  -- Prefer closest string respecting case first, then try ignorecase
  local res, res_dist = nil, math.huge
  for i, cand in ipairs(candidates) do
    local min_abbr_len = abbr_lens[i]
    local d, abbr_len = H.string_abbr_dist(word_split, vim.split(cand, ''), min_abbr_len)
    if d < res_dist then
      res, res_dist = cand:sub(1, abbr_len), d
    end
  end
  for i, cand in ipairs(candidates) do
    local min_abbr_len = abbr_lens[i]
    local cand_word_l = tolower(cand)
    local d_l, abbr_len_l = H.string_abbr_dist(word_split_l, vim.split(cand_word_l, ''), min_abbr_len)
    if d_l < res_dist then
      res, res_dist = cand:sub(1, abbr_len_l), d_l
    end
  end

  return res
end

H.string_abbr_dist = function(ref, cand, min_abbr_len)
  -- Source: https://en.wikipedia.org/wiki/Damerau-Levenshtein_distance
  -- d[i][j] - distance between `ref[1:i]` and `cand[1:j]` abbreviations
  local d = {}
  for i = 0, #ref do
    d[i] = { [0] = i }
  end
  for j = 0, #cand do
    d[0][j] = j
  end
  for i = 1, #ref do
    for j = 1, #cand do
      local cost = ref[i] == cand[j] and 0 or 1
      -- Account for deletion, insertion, substitution
      d[i][j] = math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
      -- Account for transposition. Slightly favor them over others, as it is
      -- a common source for autocorrection
      if i > 1 and j > 1 and ref[i] == cand[j - 1] and ref[i - 1] == cand[j] then
        d[i][j] = math.min(d[i][j], d[i - 2][j - 2] + 0.99 * cost)
      end
    end
  end

  -- Find the candidate abbreviation with the smallest distance
  local abbr_d = d[#ref]
  local dist, abbr_len = math.huge, nil
  for j = min_abbr_len, #cand do
    if abbr_d[j] < dist then
      dist, abbr_len = abbr_d[j], j
    end
  end

  return dist, abbr_len
end

-- Preview range --------------------------------------------------------------
H.preview_range = function(force)
  -- Decide if preview needs to be shown or hidden
  if H.cache.state == nil then return end
  local range = H.cache.state.cmd.range
  if range == nil then return H.preview_hide() end

  local cur_range = H.cache.preview.range or {}
  if not force and range[1] == cur_range[1] and range[2] == cur_range[2] then return end

  -- Normalize range
  local n_lines = vim.api.nvim_buf_line_count(0)
  local from = range[1] ~= nil and math.min(math.max(range[1], 1), n_lines) or nil
  local to = range[2] ~= nil and math.min(math.max(range[2], 1), n_lines) or nil
  if from == nil and to == nil then return H.preview_hide() end

  local is_inverted = from ~= nil and to ~= nil and to < from
  from, to = is_inverted and to or from, is_inverted and from or to

  -- Show range
  H.cache.preview.win_id = H.preview_show(from, to, is_inverted)
  H.cache.preview.range = range
end

H.preview_show = function(from, to, is_inverted)
  -- Ensure opened window
  local config = H.preview_get_config(from, to, is_inverted)
  local win_id = H.cache.preview.win_id
  win_id = H.is_valid_win(win_id) and win_id or vim.api.nvim_open_win(0, false, config)
  vim.api.nvim_win_set_config(win_id, config)

  -- Define window-local options
  vim.wo[win_id].cursorline = false
  vim.wo[win_id].foldenable = true
  vim.wo[win_id].foldlevel = 0
  vim.wo[win_id].foldmethod = 'manual'
  vim.wo[win_id].foldminlines = 1
  vim.wo[win_id].number = true
  vim.wo[win_id].winblend = H.cache.config.preview_range.window.winblend
  vim.wo[win_id].winhighlight = 'NormalFloat:MiniCmdlinePreviewNormal'
    .. ',FloatBorder:MiniCmdlinePreviewBorder'
    .. ',FloatTitle:MiniCmdlinePreviewTitle'

  vim.api.nvim_win_set_cursor(win_id, { from, 0 })

  -- Make fold between range lines
  vim.api.nvim_win_call(win_id, function()
    pcall(vim.cmd, '%foldopen!')
    vim.cmd('normal! zt')
    if from ~= nil and to ~= nil and to - from > 1 then vim.cmd(string.format('%s,%sfold', from + 1, to - 1)) end
  end)

  -- NOTE: Need explicit redraw because otherwise window is not shown
  vim.cmd('redraw')
  return win_id
end

H.preview_get_config = function(from, to, is_inverted)
  -- TODO: Make it more robust to also adjust after command line height changes
  -- during typing too much text. On Neovim>=0.11 using `relative='laststatus'`
  -- migth be doable (especially if it reacts to change in command height when
  -- typing).
  local cmdheight = math.max(vim.o.cmdheight, 1)

  local has_tabline = vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)
  local has_statusline = vim.o.laststatus > 0
  local max_height = vim.o.lines - vim.o.cmdheight - (has_tabline and 1 or 0) - (has_statusline and 1 or 0)
  local max_width = vim.o.columns

  local default_config = { relative = 'editor', style = 'minimal', zindex = 249 }
  default_config.anchor = 'SE'
  default_config.row = vim.o.lines - cmdheight
  default_config.col = 1
  default_config.width = vim.o.columns
  default_config.height = (from == nil or to == nil or from == to) and 1 or ((to - from) == 1 and 2 or 3)

  default_config.border = (vim.fn.exists('+winborder') == 0 or vim.o.winborder == '') and 'single' or nil
  default_config.title = ' Range' .. (is_inverted and ' (inverted)' or '') .. ' '
  default_config.focusable = false

  local win_config = H.cache.config.preview_range.window.config
  if vim.is_callable(win_config) then win_config = win_config() end
  local config = vim.tbl_deep_extend('force', default_config, win_config or {})

  if type(config.title) == 'string' then config.title = H.fit_to_width(config.title, config.width) end

  -- Tweak config values to ensure they are proper, accounting for border
  local offset = config.border == 'none' and 0 or 2
  config.height = math.min(config.height, max_height - offset)
  config.width = math.min(config.width, max_width - offset)

  return config
end

H.preview_hide = function()
  local info = H.cache.preview or {}
  H.win_close_safely(info.win_id)
  H.cache.preview = {}
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.cmdline) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.notify = function(msg, level_name, silent)
  if not silent then vim.notify('(mini.cmdline) ' .. msg, vim.log.levels[level_name]) end
end

H.is_valid_win = function(win_id) return type(win_id) == 'number' and vim.api.nvim_win_is_valid(win_id) end

H.win_close_safely = function(win_id)
  if H.is_valid_win(win_id) then vim.api.nvim_win_close(win_id, true) end
end

H.fit_to_width = function(text, width)
  local t_width = vim.fn.strchars(text)
  return t_width <= width and text or ('…' .. vim.fn.strcharpart(text, t_width - width + 1, width - 1))
end

H.parse_cmd = function(line)
  local ok, parsed = pcall(vim.api.nvim_parse_cmd, line, {})
  -- Try extra parsing to have a result for a line containg only range
  local extra_parsing = false
  if not ok then
    ok, parsed = pcall(vim.api.nvim_parse_cmd, line .. 'sort', {})
    extra_parsing = true
  end
  if not ok then return {} end
  return { name = extra_parsing and '' or parsed.cmd, range = parsed.range, args = parsed.args }
end

H.getcmdcomplpat = function() return vim.fn.getcmdcomplpat() end
if vim.fn.has('nvim-0.11') == 0 then
  -- Match alphanumeric characters to cursor's left, if present
  -- This is not 100% how it works, but good enough
  H.getcmdcomplpat = function() return vim.fn.getcmdline():sub(1, vim.fn.getcmdpos() - 1):match('%w+$') or '' end
end

H.get_wildchar = function()
  local wc = vim.o.wildchar
  if wc >= 0 then return vim.fn.nr2char(wc) end
  -- Negative key means that 'wildchar' is mapped to some special non-printable
  -- key (like <Down>). Those are represented with multiple bytes starting with
  -- `k_special` (`\x80`). The following reverse engineers this logic.
  wc = -wc
  return '\x80' .. string.char(wc % 256) .. string.char(wc / 256)
end

return MiniCmdline
