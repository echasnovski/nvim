-- TODO:
--
-- Code:
--
-- Docs:
--
-- Tests:

--- *mini.notify* Show notifications
--- *MiniNotify*
---
--- MIT License Copyright (c) 2024 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Features:
---
--- - Show one or more notifications in top right corner.
---
--- - Manage notifications (add, update, remove, clear).
---
--- - Keep history which can be accessed with |MiniNotify.get_history()|.
---
--- - |vim.notify()| wrapper generator (see |MiniNotify.make_notify()|).
---
--- - Automated show of LSP progress report.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.notify').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniNotify`
--- which you can use for scripting or manually (with `:lua MiniNotify.*`).
---
--- See |MiniNotify.config| for `config` structure and default values.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.mininotify_config` which should have same structure as
--- `MiniNotify.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons ~
---
--- - 'j-hui/fidget.nvim':
---     - .
---
--- - 'rcarriga/nvim-notify':
---     - .

--- # Notification specification ~
---
--- Notification is a table with the following keys:
---
--- - <msg> `(string)` - single string with notification message.
--- - <level> `(string)` - notification level as key of |vim.log.levels|.
--- - <hl_group> `(string)` - highlight group with which notification is shown.
--- - <ts_add> `(number)` - timestamp of when notification was added.
--- - <ts_update> `(number)` - timestamp of the latest notification update.
--- - <ts_remove> `(number)` - timestamp of when notification was removed.
---@tag MiniNotify-specification

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local
---@diagnostic disable:cast-local-type
---@diagnostic disable:undefined-doc-name
---@diagnostic disable:luadoc-miss-type-name

-- Module definition ==========================================================
MiniNotify = {}
local H = {}

--- Module setup
---
--- Calling this function creates all user commands described in |MiniDeps-actions|.
---
---@param config table|nil Module config table. See |MiniNotify.config|.
---
---@usage `require('mini.notify').setup({})` (replace `{}` with your `config` table).
MiniNotify.setup = function(config)
  -- Export module
  _G.MiniNotify = MiniNotify

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)
end

--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniNotify.config = {
  -- Whether to set up notifications about LSP progress
  setup_lsp_progress = true,

  -- Function which orders notification array from most to least important
  -- By default orders first by level and then by update timestamp
  sort = nil,

  -- Window options
  window = {
    -- Value of 'winblend' option
    winblend = 25,

    -- Z-index
    zindex = 999,
  },
}
--minidoc_afterlines_end

-- Make vim.notify wrapper
--
-- Add notification and remove it after timeout.
MiniNotify.make_notify = function(opts)
  --stylua: ignore
  local default_opts = {
    ERROR = { timeout = 10000, hl = 'DiagnosticError' },
    WARN  = { timeout = 10000, hl = 'DiagnosticWarn'  },
    INFO  = { timeout = 10000, hl = 'DiagnosticInfo'  },
    DEBUG = { timeout = -1,    hl = 'DiagnosticHint'  },
    TRACE = { timeout = -1,    hl = 'DiagnosticOk'    },
  }
  opts = vim.tbl_deep_extend('force', default_opts, opts or {})

  return function(msg, level)
    -- TODO
  end
end

---@return number Notification identifier.
MiniNotify.add = function(msg, level, hl_group)
  H.validate_msg(msg)
  H.validate_level(level)
  H.validate_hl_group(hl_group)

  local cur_ts = vim.loop.hrtime()
  local new_notif = { msg = msg, level = level, hl_group = hl_group, ts_add = cur_ts, ts_update = cur_ts }

  local new_id = #H.history + 1
  -- NOTE: Crucial to use the same table here and later only update values
  -- inside of it in place. This makes sure that history entries are in sync.
  H.history[new_id], H.active[new_id] = new_notif, new_notif

  -- Refresh active notifications
  MiniNotify.refresh()

  return new_id
end

---@param id number Identifier of currently active notification
---   as returned by |MiniNotify.add()|.
---@param new_data table Table with data to update. Keys should be as in non-timestamp
---   fields of |MiniNotify-specification|.
MiniNotify.update = function(id, new_data)
  local notif = H.active[id]
  if notif == nil then H.error('`id` is not an identifier of active notification.') end
  if type(new_data) ~= 'table' then H.error('`new_data` should be table.') end

  if new_data.msg ~= nil then H.validate_msg(new_data.msg) end
  if new_data.level ~= nil then H.validate_level(new_data.level) end
  if new_data.hl_group ~= nil then H.validate_hl_group(new_data.hl_group) end

  notif.msg = new_data.msg or notif.msg
  notif.level = new_data.level or notif.level
  notif.hl_group = new_data.hl_group or notif.hl_group
  notif.ts_update = vim.loop.hrtime()

  MiniNotify.refresh()
end

MiniNotify.remove = function(id)
  H.active[id] = nil
  MiniNotify.refresh()
end

MiniNotify.clear = function()
  H.active = {}
  MiniNotify.refresh()
end

MiniNotify.refresh = function()
  -- - Normalize windows and buffers.
  --     - Discard windows which are not in the current tab page.
  -- - Sort entries of `H.active`.
  -- - Show from first to last but only until there is vertical space.

  -- TODO
end

-- Get history
--
-- In order from oldest to newest based on the creation time.
-- Content is based on the last valid update.
MiniNotify.get_history = function() return vim.deepcopy(H.history) end

MiniNotify.default_sort = function(arr)
  local arr_copy = vim.deepcopy(arr)
  table.sort(arr_copy, H.notif_compare)
  return arr_copy
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniNotify.config

-- Map of currently active notifications with their id as key
H.active = {}

-- History of all notifications in order they are created
H.history = {}

-- Priorities of levels
H.level_priority = { ERROR = 6, WARN = 5, INFO = 4, DEBUG = 3, TRACE = 2, OFF = 1 }

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  vim.validate({
    setup_lsp_progress = { config.setup_lsp_progress, 'boolean' },
    sort = { config.sort, 'function', true },
  })

  return config
end

H.apply_config = function(config)
  MiniNotify.config = config

  if config.setup_lsp_progress then
    -- TODO
  end
end

H.create_autocommands = function()
  local augroup = vim.api.nvim_create_augroup('MiniNotify', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = augroup, pattern = pattern, callback = callback, desc = desc })
  end

  au('TabEnter', '*', function() MiniNotify.refresh() end, 'Refresh in notifications in new tabpage')
end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniNotify.config, vim.b.mininotify_config or {}, config or {})
end

-- Notifications --------------------------------------------------------------
H.validate_msg = function(x)
  if type(x) ~= 'string' then H.error('`msg` should be string.') end
end

H.validate_level = function(x)
  if vim.log.levels[x] == nil then H.error('`level` should be key of `vim.log.levels`.') end
end

H.validate_hl_group = function(x)
  if type(x) ~= 'string' then H.error('`hl_group` should be string.') end
end

H.notif_compare = function(a, b)
  local a_priority, b_priority = H.level_priority[a.level], H.level_priority[b.level]
  return a_priority > b_priority or (a_priority == b_priority and a.ts_update > b.ts_update)
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.notify) %s', msg), 0) end

H.is_valid_buf = function(buf_id) return type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id) end

H.is_valid_win = function(win_id) return type(win_id) == 'number' and vim.api.nvim_win_is_valid(win_id) end

H.is_win_in_tabpage = function(win_id) return vim.api.nvim_win_get_tabpage(win_id) == vim.api.nvim_get_current_tabpage() end

return MiniNotify
