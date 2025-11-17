-- TODO:
--
-- Code:
--
-- - Decide on the `config` structure.
--
-- - Carefully explore which modes need to be accounted for.
--   Like, autocompletion in `/` and `?` on Neovim>=0.12.
--   Maybe should be customizable.
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
-- - ...

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
    delay = 250,
  },

  autocorrect = true,

  preview_range = true,
}
--minidoc_afterlines_end

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
  H.check_type('autocomplete.delay', config.autocomplete.delay, 'number')
  H.check_type('autocorrect', config.autocorrect, 'boolean')
  H.check_type('preview_range', config.preview_range, 'boolean')

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
  H.cache = { config = H.get_config(), wildchar = vim.fn.nr2char(vim.o.wildchar) }
  -- TODO
end

H.on_cmdline_changed = function()
  if H.cache.config == nil then return end
  local config = H.cache.config

  local line = vim.fn.getcmdline()
  local col = vim.fn.getcmdpos()
  local cmd_type = vim.fn.getcmdtype()
  local ok, cmd_parsed = pcall(vim.api.nvim_parse_cmd, line, {})

  -- Autocomplete
  H.timers.autocomplete:stop()

  -- TODO: Should ignore `:s` and other problematic commands on Neovim<0.12

  -- local is_char_keyword = vim.fn.match(line:sub(1, col - 1), '[[:keyword:]]$') >= 0

  -- local delay = vim.fn.wildmenumode() == 1 and 0 or config.autocomplete.delay
  local delay = config.autocomplete.delay

  if vim.fn.wildmenumode() == 0 then H.timers.autocomplete:start(delay, 0, H.trigger_complete) end

  MiniMisc.log_add('on_cmdline_changed', {
    cache = H.cache,
    line = line,
    col = col,
    cmd_parsed = cmd_parsed,
    cmd_type = cmd_type,
    complpat = vim.fn.getcmdcomplpat(),
    compltype = vim.fn.getcmdcompltype(),
    pumvisible = vim.fn.pumvisible(),
    wildmenumode = vim.fn.wildmenumode(),
  })

  -- Autocorrect
  -- TODO

  -- Preview range
  -- TODO
end

H.trigger_complete = vim.schedule_wrap(function()
  if vim.fn.wildmenumode() == 0 then vim.fn.wildtrigger() end
end)
if vim.fn.has('nvim-0.12') == 0 then
  H.trigger_complete = vim.schedule_wrap(function()
    if vim.fn.wildmenumode() == 0 then vim.api.nvim_feedkeys(H.cache.wildchar, 'nt', false) end
  end)
end

H.on_cmdline_leave = function()
  -- TODO
  -- Cleanup

  H.cache = {}

  MiniMisc.log_add('CmdlineLeave', { mode = vim.fn.mode(), pumvisible = vim.fn.pumvisible() })

  -- TODO: Maybe not needed, but on Neovim>=0.12 there might be issues after `wildtrigger()`
  if vim.fn.pumvisible() == 1 then vim.api.nvim_feedkeys('<C-y>', 'nt', true) end
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

return MiniCmdline
