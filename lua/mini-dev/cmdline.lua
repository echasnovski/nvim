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
--     - Does not autocorrect valid built-in and user commands.
--
--     - Respects abbreviations (even for user commands), often hard-coded.
--       Test cases:
--         - `:tex` -> `:Tex`
--         - `:vex` -> `:Vex`
--
--     - Setting new command line text as a result of autocorrection should not
--       retrigger autocorrection. But should still trigger `CmdlineChanged`
--       and other features.
--
--     - Can be repeated within same "command line session".
--
--     - Should work with Command-line mode mappings that add text.
--       Like `:cnoremap <M-m> www\ `.

--- *mini.cmdline* Command line tweaks
---
--- MIT License Copyright (c) 2025 Evgeni Chasnovski

--- Features:
---
--- - Autocomplete with customizable delay. Enhances |cmdline-completion| and
---   manual |'wildchar'| pressing experience.
---
--- - Autocorrect command names.
---   TODO: Think about generalizing this.
---
--- - Preview command range.
---
--- - Map arrow keys to act independently of whether |'wildmenu'| is shown.
---
--- What it doesn't do:
---
--- - Customization of command line UI. Use |vim._extui| (on Neovim>=0.12).
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
--- - |'wildode'| is set to "noselect:lastused,full" for less intrusive popup
---   if autocompletion is enabled.
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
--- `autocomplete.predicate` defines a condition of whether to trigger completion.
--- Should return `true` to show completion and `false` otherwise.
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
--- TODO
---
--- Notes:
--- - It is not a fuzzy matching. Use fuzzy completion for that.
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
  },

  -- Autocorrection: correct non-existing command name
  autocorrect = {
    enable = true,

    -- Custom autocorrection rule
    func = nil,
  },

  -- Range preview: show command's target range in floating windows
  preview_range = {
    enable = true,
  },
}
--minidoc_afterlines_end

--- Default autocompletion predicate
---
---@return boolean Always `true`.
MiniCmdline.default_autocomplete_predicate = function() return true end

--- Default autocorrection function
---
--- Currently works only for command names and |:command-modifiers|
--- (i.e. `command` type).
--- TODO: Think about possible generalizations this.
---
---@param data table Input autocorrection data. As described in |MiniCmdline.config|.
---@param opts table|nil Options. Reserved for future use.
---
---@return string Autocorrected word.
MiniCmdline.default_autocorrect_func = function(data, opts)
  -- Act only for commands
  if data.type ~= 'command' then return data.word end

  -- Get all valid commands and command modifiers (like `:aboveleft`, etc.)
  local all = vim.fn.getcompletion('', 'cmdline')
  if vim.tbl_contains(all, data.word) then return data.word end

  -- Correct by finding valid command name abbreviation closest to reference
  return H.get_nearest_command(data.word, all)
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniCmdline.config)

-- Timers
H.timers = {
  autocomplete = vim.loop.new_timer(),
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

  H.check_type('autocorrect', config.autocorrect, 'table')
  H.check_type('autocorrect.enable', config.autocorrect.enable, 'boolean')
  H.check_type('autocorrect.func', config.autocorrect.func, 'func', true)

  H.check_type('preview_range', config.preview_range, 'table')
  H.check_type('preview_range.enable', config.preview_range.enable, 'boolean')

  return config
end

H.apply_config = function(config)
  MiniCmdline.config = config

  -- Try setting suggested option values
  -- NOTE: This makes it more like 'mini.completion' (with 'noselect')
  local was_set = vim.api.nvim_get_option_info2('wildmode', { scope = 'global' }).was_set
  if not was_set and config.autocomplete.enable then vim.o.wildmode = 'noselect,full' end

  was_set = vim.api.nvim_get_option_info2('wildoptions', { scope = 'global' }).was_set
  if not was_set then vim.o.wildoptions = 'pum,fuzzy' end

  -- Set useful mappings
  local map_arrow = function(dir, wildmenu_prefix, desc)
    local rhs = function() return (vim.fn.wildmenumode() == 1 and wildmenu_prefix or '') .. dir end
    vim.keymap.set('c', dir, rhs, { expr = true, desc = desc })
  end
  map_arrow('<Left>', '<Space><BS>', 'Move cursor left')
  map_arrow('<Right>', '<Space><BS>', 'Move cursor right')
  map_arrow('<Up>', '<C-e>', 'Go to earlier history')
  map_arrow('<Down>', '<C-e>', 'Go to newer history')
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
end

H.is_disabled = function() return vim.g.minicmdline_disable == true or vim.b.minicmdline_disable == true end

H.get_config = function() return vim.tbl_deep_extend('force', MiniCmdline.config, vim.b.minicmdline_config or {}) end

-- Autocommands ---------------------------------------------------------------
H.on_cmdline_enter = function()
  -- Check for Command-line mode to not act on `:...` mappings
  if H.is_disabled() or vim.fn.mode() ~= 'c' then return end

  H.cache = {
    config = H.get_config(),
    wildchar = vim.fn.nr2char(vim.o.wildchar),
    cmd_type = vim.fn.getcmdtype(),
    state = H.get_cmd_state(),
    state_prev = {},
  }
  H.cache.autocomplete_predicate = H.cache.config.autocomplete.predicate or MiniCmdline.default_autocomplete_predicate
end

H.on_cmdline_changed = function()
  if H.cache.config == nil then return end
  local config = H.cache.config

  -- Act only on actual line change
  local state = H.get_cmd_state()
  if state.line == H.cache.state.line then return end
  H.cache.state_prev, H.cache.state = H.cache.state, state

  if config.autocomplete.enable then H.autocomplete() end
  if config.autocorrect.enable then H.autocorrect(false) end
  if config.preview_range.enable then H.preview_range() end
end

H.on_cmdline_leave = function()
  if H.cache.config == nil then return end
  if H.cache.config.autocorrect.enable then H.autocorrect(true) end
  H.cache = {}
end

H.get_cmd_state = function()
  return {
    complpat = vim.fn.getcmdcomplpat(),
    compltype = vim.fn.getcmdcompltype(),
    line = vim.fn.getcmdline(),
    pos = vim.fn.getcmdpos(),
  }
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
    return #vim.fn.getcompletion(H.cache.state.line:sub(1, H.cache.state.pos - 1), 'cmdline') == 0
  end
end

H.trigger_complete = function()
  if vim.fn.mode() ~= 'c' then return end
  H.cache.wildmenu_state = 'show'
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
  if H.cache.just_autocorrected then
    H.cache.just_autocorrected = nil
    return
  end

  -- Act only for normal Ex commands after a word is just finished typing
  if not (H.cache.cmd_type == ':' and H.cache.state.line:find('%S') ~= nil) then return end

  local state, state_prev = H.cache.state, H.cache.state_prev
  local line, line_prev = state.line, state_prev.line
  local pos, pos_prev = state.pos, state_prev.pos

  local is_text_added = line_prev:sub(1, pos_prev - 1) == line:sub(1, pos_prev - 1)
    and line_prev:sub(pos_prev) == line:sub(pos)
  local is_word_finished = line:sub(pos - 1, pos - 1) == ' '

  -- MiniMisc.log_add('autocorrect', {
  --   is_char_added = is_char_added,
  --   is_word_finished = is_word_finished,
  --   state = state,
  --   state_prev = state_prev,
  --   is_final = is_final,
  -- })

  if not (is_text_added and (is_word_finished or is_final)) then return end

  -- Compute autocorrection
  local word = is_final and state.complpat or state_prev.complpat
  if word == '' then return end

  local func = H.cache.config.autocorrect.func or MiniCmdline.default_autocorrect_func
  local new_word = func({ word = word, type = state_prev.compltype }) or word

  if word == new_word then return end
  if type(new_word) ~= 'string' then return H.notify('Can not autocorrect for ' .. vim.inspect(word), 'WARN') end

  local init_pos = is_final and pos or pos_prev
  local new_line = line:sub(1, init_pos - word:len() - 1) .. new_word .. line:sub(init_pos)
  H.cache.just_autocorrected = true
  vim.fn.setcmdline(new_line, new_line:len() + 1)

  -- MiniMisc.log_add('autocorrect 2', {
  --   new_word = new_word,
  --   word = word,
  --   is_final = is_final,
  --   new_line = new_line,
  --   state = state,
  --   line = vim.fn.getcmdline(),
  -- })
end

H.get_nearest_command = function(ref, all)
  -- Check correction both respecting and ignoring case
  -- Account for the fact that commands can be abbreviated (`:h |20.2|`).
  -- So allow finding correction to the abbreviation (substring from the start)
  -- of the candidate.
  -- TODO: Not all abbreviations of user commands are a valid command. It needs
  -- to be unambiguous (i.e. uniquely identify the user command).
  -- This is not the case for built-in commands, though: ANY abbreviation of
  -- ANY built-in command is a valid (maybe different; `wincmd`->`w`==`write`)
  -- valid command. Its just the internal optimization.
  -- EXCEPT: `:def` abbreviation of `:defer` is not allowed (probably due to
  -- Vim9script reasons).
  -- Need to account for that. Probably when computing all commands, also
  -- compute their minimal abbreviation length: 1 for built-in, something
  -- computed for others.
  local res_ind, res_dist, res_abbr_len = H.get_nearest_string(ref, all)
  local res_l_ind, res_l_dist, res_l_abbr_len =
    H.get_nearest_string(vim.fn.tolower(ref), vim.tbl_map(vim.fn.tolower, all))
  if res_l_dist < res_dist then
    res_ind, res_abbr_len = res_l_ind, res_l_abbr_len
  end
  return all[res_ind]:sub(1, res_abbr_len)
end

H.get_nearest_string = function(word, candidates)
  local res_dist, res_ind, res_abbr_len = math.huge, nil, nil
  local word_split = vim.split(word, '')
  for i, cand in ipairs(candidates) do
    local d, abbr_len = H.string_dist_with_abbr(word_split, vim.split(cand, ''))
    if d < res_dist then
      res_ind, res_dist, res_abbr_len = i, d, abbr_len
    end
  end

  return res_ind, res_dist, res_abbr_len
end

H.string_dist_with_abbr = function(ref, cand)
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
      -- Account for transposition
      if i > 1 and j > 1 and ref[i] == cand[j - 1] and ref[i - 1] == cand[j] then
        d[i][j] = math.min(d[i][j], d[i - 2][j - 2] + cost)
      end
    end
  end

  -- Find the candidate abbreviation with the smallest distance
  local abbr_d = d[#ref]
  local dist, abbr_len = math.huge, nil
  for j = 1, #cand do
    if abbr_d[j] < dist then
      dist, abbr_len = abbr_d[j], j
    end
  end

  return dist, abbr_len
end

-- Preview range --------------------------------------------------------------
H.preview_range = function()
  -- TODO
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

return MiniCmdline
