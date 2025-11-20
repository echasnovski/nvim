-- TODO:
--
-- Code:
--
-- - Autocomplete:
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

--- *mini.cmdline* Command line tweaks
---
--- MIT License Copyright (c) 2025 Evgeni Chasnovski

--- Features:
---
--- - Autocomplete with customizable delay. Enhances |cmdline-completion| and
---   manual |'wildchar'| pressing experience.
---
--- - Autocorrect command names.
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

    predicate = nil,
  },

  -- Autocorrection: correct non-existing command name
  autocorrect = {
    enable = true,
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

  -- Act on command line events
  au('CmdlineEnter', '*', vim.schedule_wrap(H.on_cmdline_enter), 'Act on Command line enter')
  au('CmdlineChanged', '*', vim.schedule_wrap(H.on_cmdline_changed), 'Act on Command line change')
  au('CmdlineLeave', '*', vim.schedule_wrap(H.on_cmdline_leave), 'Act on Command line leave')
end

H.is_disabled = function() return vim.g.minicmdline_disable == true or vim.b.minicmdline_disable == true end

H.get_config = function() return vim.tbl_deep_extend('force', MiniCmdline.config, vim.b.minicmdline_config or {}) end

-- Autocommands ---------------------------------------------------------------
H.on_cmdline_enter = function()
  if H.is_disabled() or vim.fn.mode() ~= 'c' then return end

  H.cache = {
    config = H.get_config(),
    wildchar = vim.fn.nr2char(vim.o.wildchar),
    cmd_type = vim.fn.getcmdtype(),
    line = '',
    pos = 1,
  }
  H.cache.autocomplete_predicate = H.cache.config.autocomplete.predicate or MiniCmdline.default_autocomplete_predicate
end

H.on_cmdline_changed = function()
  if H.cache.config == nil then return end
  local config = H.cache.config

  H.cache.line, H.cache.pos = vim.fn.getcmdline(), vim.fn.getcmdpos()

  if config.autocomplete.enable then H.autocomplete() end
  if config.autocorrect.enable then H.autocorrect(false) end
  if config.preview_range.enable then H.preview_range() end
end

H.on_cmdline_leave = function()
  if H.cache.config == nil then return end
  if H.cache.config.autocorrect.enable then H.autocorrect(true) end
  H.cache = {}
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
    return #vim.fn.getcompletion(H.cache.line:sub(1, H.cache.pos - 1), 'cmdline') == 0
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
  -- Try correcting if just finished typing the command or on `CmdlineLeave`
  local has_just_typed_command = H.cache.line:find('^%s*%S+%s+$') ~= nil and H.cache.pos == (H.cache.line:len() + 1)
  if not (has_just_typed_command or is_final) then return end

  -- Correct (only if typed command name is unknown) by finding valid command
  -- name closest to the one typed
  if H.parse_cmd(H.cache.line).name ~= nil or H.cache.line:find('^%s*$') ~= nil then return end

  local range, word = H.cache.line:match('^%s*(%S+)'):match('^(%S-)(%w+)$')
  if range:sub(-1, -1) == "'" and range:sub(-2, -2) ~= "'" then
    range, word = range .. word:sub(1, 1), word:sub(2)
  end

  local all = vim.fn.getcompletion('', 'command')
  local closest_ind = H.find_closest_string(vim.fn.tolower(word), vim.tbl_map(vim.fn.tolower, all))

  local new_line = H.cache.line:gsub('^%s*%S+', range .. all[closest_ind])
  vim.fn.setcmdline(new_line)
end

H.find_closest_string = function(word, candidates)
  -- TODO
  return #candidates
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
