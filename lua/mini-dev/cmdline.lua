-- TODO:
--
-- Code:
--
-- - Carefully explore which modes need to be accounted for.
--   Like, autocompletion in `/` and `?` on Neovim>=0.12.
--   Maybe should be customizable.
--
-- - Autocomplete:
--   - It might be a good idea to just enable on Neovim>=0.12, as there are too
--     many workarounds on earlier versions.
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
-- - Autocomplete:
--     - Should autocomplete for first letters of blocklisted command names
--       (like `g`, `v`, `s`).
--
--     - Works for problematic completion types (like `file`/`file_in_path`;
--       `:edit f` or `:grep f`) without infinite loop.
--
--     - Works with bang (like `:q!`) without extra wildchar.

--- *mini.cmdline* Command line tweaks
---
--- MIT License Copyright (c) 2025 Evgeni Chasnovski

--- Features:
---
--- - Autocomplete with customizable delay. Enhances |cmdline-completion| and
---   manual |'wildchar'| pressing experience. Neovim>=0.12 is suggested.
---
--- - Autocorrect command names.
---
--- - Preview command range.
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
--- - |'wildode'| is set to "noselect:lastused,full" for less intrusive popup.
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
MiniCmdline.config = {
  autocomplete = {
    enable = true,

    -- Delay (in ms) after which to trigger completion
    -- TODO: The Neovim<0.12 is usable only with 0, otherwise it is too much
    -- flicker. Either try again to remedy this via code hacks, choose default
    -- based on Neovim version, or just foce delay=0 on Neovim<0.12.
    delay = 200,

    predicate = nil,
  },

  autocorrect = {
    enable = true,
  },

  preview_range = {
    enable = true,
  },
}
--minidoc_afterlines_end

--- Default autocompletion predicate
---
---@param data table Data about command line state. Fields:
--- - <line> `(string)` - current text. See |getcmdline()|.
--- - <line_prev> `(string)` - previous text.
--- - <pos> `(number)` - current cursor column. See |getcmdpos()|.
--- - <pos_prev> `(number)` - previous cursor column.
---
---@return boolean `True` if cursor is after a non-whitespace character.
MiniCmdline.default_autocomplete_predicate = function(data) return data.line:sub(1, data.pos - 1):find('%S$') ~= nil end

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
  -- NOTE: This makes it more like 'mini.completion' (with 'noselect'),
  -- but might be not good if triggered manually.
  local was_set = vim.api.nvim_get_option_info2('wildmode', { scope = 'global' }).was_set
  if not was_set then vim.o.wildmode = 'noselect:lastused,full' end

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
  au('CmdlineEnter', '*', H.on_cmdline_enter, 'Act on Command line enter')
  au('CmdlineChanged', '*', H.on_cmdline_changed, 'Act on Command line change')
  au('CmdlineLeave', '*', H.on_cmdline_leave, 'Act on Command line leave')
end

H.is_disabled = function() return vim.g.minicmdline_disable == true or vim.b.minicmdline_disable == true end

H.get_config = function() return vim.tbl_deep_extend('force', MiniCmdline.config, vim.b.minicmdline_config or {}) end

-- Autocommands ---------------------------------------------------------------
H.on_cmdline_enter = function()
  if H.is_disabled() then return end

  H.cache = {
    config = H.get_config(),
    wildchar = vim.fn.nr2char(vim.o.wildchar),
    cmd_type = vim.fn.getcmdtype(),
    line = '',
    pos = 1,
    -- Manually track state of a wildmenu as any typed text removes it.
    -- One of: "none", "wait", "show".
    wildmenu_state = 'none',
  }
  H.cache.autocomplete_predicate = H.cache.config.autocomplete.predicate or MiniCmdline.default_autocomplete_predicate

  if H.cache.config.autocomplete.enable then
    -- Set 'wildmode' more appropriate for an autocompletion
    local wildmode_cur, wildmode_ref = vim.o.wildmode, 'noselect:lastused,full'
    if wildmode_cur ~= wildmode_ref then
      H.cache.opt_wildmode = wildmode_cur
      vim.o.wildmode = wildmode_ref
    end
  end
end

H.on_cmdline_changed = function()
  if H.cache.config == nil then return end
  local config = H.cache.config

  H.cache.line_prev, H.cache.pos_prev = H.cache.line, H.cache.pos
  H.cache.line, H.cache.pos = vim.fn.getcmdline(), vim.fn.getcmdpos()
  H.cache.cmd = H.parse_cmd(H.cache.line)

  if config.autocomplete.enable then H.autocomplete() end
  if config.autocorrect.enable then H.autocorrect() end
  if config.preview_range.enable then H.preview_range() end
end

H.on_cmdline_leave = function()
  if H.cache.opt_wildmode ~= nil then vim.o.wildmode = H.cache.opt_wildmode end

  H.cache = {}
end

-- Autocomplete ---------------------------------------------------------------
H.autocomplete = function()
  H.timers.autocomplete:stop()

  -- MiniMisc.log_add('autocomplete', { cache = H.cache })
  MiniMisc.log_add('compltype', {
    line = H.cache.line,
    wildmenu_state = H.cache.wildmenu_state,
    wildmenumode = vim.fn.wildmenumode(),
    compltype = vim.fn.getcmdcompltype(),
  })

  -- React only for appropriate command line change events:
  -- - Text change actually happened. Might not be the case for some not
  --   immediate completion types (like `file` and `file_in_path`).
  -- - Wildmenu is visible. It means text was changed while navigating through
  --   completion candidates (<Tab>/<S-Tab>).
  if vim.fn.wildmenumode() == 1 or H.cache.line == H.cache.line_prev then return end

  -- Do nothing in some problematic cases (when wildmenu does not work)
  -- TODO: Remove after compatibility with Neovim=0.11 is dropped
  if H.block_autocomplete() then return end

  -- -- Stop showing wildmenu if predicate says so
  -- local data = { line = H.cache.line, pos = H.cache.pos, line_prev = H.cache.line_prev, pos_prev = H.cache.pos_prev }
  -- if not H.cache.autocomplete_predicate(data) then
  --   H.cache.wildmenu_state = 'none'
  --   return
  -- end

  -- Show wildmenu: immediately if already shown, after delay otherwise
  -- if H.cache.wildmenu_state == 'show' then return H.trigger_complete() end

  local delay = H.cache.config.autocomplete.delay
  if delay == 0 then return H.trigger_complete() end
  H.timers.autocomplete:start(delay, 0, H.trigger_complete_scheduled)
  -- TODO: tracking state manually is probably not worth it
  H.cache.wildmenu_state = 'wait'
end

H.block_autocomplete = function() return false end
if vim.fn.has('nvim-0.12') == 0 then
  H.block_autocomplete = function()
    -- Block for problematic command types
    local cmd_type = H.cache.cmd_type
    if cmd_type == '/' or cmd_type == '?' then return true end

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
  if vim.fn.mode() ~= 'c' or vim.fn.wildmenumode() == 1 then return end
  H.cache.wildmenu_state = 'show'
  H.trigger_wild()
end

H.trigger_complete_scheduled = vim.schedule_wrap(H.trigger_complete)

H.trigger_wild = function() vim.fn.wildtrigger() end
if vim.fn.has('nvim-0.12') == 0 then
  H.trigger_wild = function() vim.api.nvim_feedkeys(H.cache.wildchar, 'nt', false) end
end

-- Autocorrect ----------------------------------------------------------------
H.autocorrect = function()
  -- TODO
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
