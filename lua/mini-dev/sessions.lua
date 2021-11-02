-- MIT License Copyright (c) 2021 Evgeni Chasnovski

---@brief [[
--- Lua module for minimal session management (read, write, delete), which
--- works using |mksession| (meaning 'sessionoptions' is fully respected).
--- This is intended as a drop-in Lua replacement for session management part
--- of [mhinz/vim-startify](https://github.com/mhinz/vim-startify) (works out
--- of the box with sessions created by it).
---
--- Key design ideas:
--- - There is a (configurable) directory. Its readable files (searched with
---   |globpath|) represent sessions (result of applying |mksession|). All
---   these session files are detected during `MiniSessions.setup()` with
---   session names being file names (including their possible extension).
--- - Store information about detected sessions in separate table
---   (|MiniSessions.detected|) and operate only on it. Meaning if this
---   information changes, there will be no effect until next detection.
---
--- Features:
--- - Autoread latest session if Neovim was called without file arguments.
--- - Autowrite current session before quitting Neovim.
--- - Configurable severity of all actions.
---
--- # Setup
---
--- This module needs a setup with `require('mini.sessions').setup({})`
--- (replace `{}` with your `config` table).
---
--- Default `config`:
--- <pre>
--- {
---   -- Whether to autoread latest session if Neovim was called without file arguments
---   autoread = false,
---
---   -- Whether to write current session before quitting Neovim
---   autowrite = true,
---
---   -- Directory where sessions are stored
---   directory = --<"sessions" subdirectory of user data directory from |stdpath()|>,
---
---   -- Whether to force possibly harmful actions (meaning depends on function)
---   force = { read = false, write = true, delete = false },
--- }
--- </pre>
---
--- # Disabling
---
--- To disable core functionality, set `g:minisessions_disable` (globally) or
--- `b:minisessions_disable` (for a buffer) to `v:true`.
---@brief ]]
---@tag MiniSessions mini.sessions

-- Module and its helper
local MiniSessions = {}
local H = { path_sep = package.config:sub(1, 1) }

--- Module setup
---
---@param config table: Module config table.
---@usage `require('mini.sessions').setup({})` (replace `{}` with your `config` table)
function MiniSessions.setup(config)
  -- Export module
  _G.MiniSessions = MiniSessions

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Module behavior
  if config.autoread then
    vim.cmd([[au VimEnter * ++nested ++once lua if vim.fn.argc() == 0 then MiniSessions.read() end]])
  end

  if config.autowrite then
    vim.cmd([[au VimLeavePre * lua if vim.v.this_session ~= '' then MiniSessions.write(nil, true) end]])
  end
end

-- Module config
MiniSessions.config = {
  -- Whether to read latest session if Neovim was called without file arguments
  autoread = false,

  -- Whether to write current session before quitting Neovim
  autowrite = true,

  -- Directory where sessions are stored
  directory = vim.fn.stdpath('data') .. H.path_sep .. 'sessions',

  -- Whether to force possibly harmful actions (meaning depends on function)
  force = { read = false, write = true, delete = false },
}

---- Table of detected sessions
----
---- Keys represent session name. Values are tables with session information.
---- Currently this information consists from (but subject to change):
---- - `modify_time` - modification time (see |getftime|) of session file.
---- - `path` - full path to session file.
MiniSessions.detected = {}

-- Module functionality
--- Read detected session
---
--- What it does:
--- - Delete all current buffers with |bwipeout|. This is needed to correctly
---   restore buffers from target session. If `force` is not `true`, checks
---   beforehand for unsaved buffers and stops if there is any.
--- - Source session with supplied name.
---
---@param session_name string: Name of detected section to read. Default: `nil` for latest session (see |MiniSessions.get_latest|).
---@param force boolean: Whether to delete unsaved buffers. Default: `MiniSessions.config.force.read`.
function MiniSessions.read(session_name, force)
  if H.is_disabled() then
    return
  end
  if vim.tbl_count(MiniSessions.detected) == 0 then
    H.notify([[There is no detected sessions. Change `MiniSessions.config.directory` and run `MiniSessions.setup()`.]])
    return
  end

  session_name = session_name or MiniSessions.get_latest()
  force = (force == nil) and MiniSessions.config.force.read or force

  if not H.validate_detected(session_name) then
    return
  end
  if not H.wipeout_all_buffers(force) then
    return
  end

  local path = vim.fn.fnameescape(MiniSessions.detected[session_name].path)
  vim.cmd(string.format([[source %s]], path))
end

--- Write session
---
--- What it does:
--- - Check if file for supplied session name already exists. If it does and
---   `force` is not `true`, then stop.
--- - Write session with |mksession| to a file named `session_name` inside
---   `MiniSessions.config.directory`.
---
---@param session_name string: Name of section to write. Default: `nil` for current session.
---@param force boolean: Whether to ignore existence of session file. Default: `MiniSessions.config.force.write`.
function MiniSessions.write(session_name, force)
  if H.is_disabled() then
    return
  end

  session_name = tostring(session_name or H.get_current_session_name())
  force = (force == nil) and MiniSessions.config.force.write or force

  if #session_name == 0 then
    H.notify([[Supply non-empty session name to write.]])
    return
  end

  local session_file = MiniSessions.config.directory .. H.path_sep .. session_name
  session_file = vim.fn.fnamemodify(session_file, ':p')
  if not force and vim.fn.filereadable(session_file) == 1 then
    H.notify([[Can't write to existing session when `force` is not `true`.]])
    return
  end

  local cmd = string.format([[mksession%s]], force and '!' or '')
  vim.cmd(string.format([[%s %s]], cmd, vim.fn.fnameescape(session_file)))
end

--- Delete detected session
---
--- What it does:
--- - Check if session name is a current one. If yes and `force` is not `true`,
---   then stop.
--- - Delete session.
---
---@param session_name string: Name of section to delete. Default: `nil` for current session.
---@param force boolean: Whether to ignore deletion of current session. Default: `MiniSessions.config.force.delete`.
function MiniSessions.delete(session_name, force)
  if H.is_disabled() then
    return
  end
  if vim.tbl_count(MiniSessions.detected) == 0 then
    H.notify([[There is no detected sessions. Change `MiniSessions.config.directory` and run `MiniSessions.setup()`.]])
    return
  end

  session_name = session_name or H.get_current_session_name()
  force = (force == nil) and MiniSessions.config.force.delete or force

  if not H.validate_detected(session_name) then
    return
  end

  local is_current_session = session_name == H.get_current_session_name()
  if not force and is_current_session then
    H.notify([[Can't delete current session when `force` is not `true`.]])
    return
  end

  vim.fn.delete(MiniSessions.detected[session_name].path)
  MiniSessions.detected[session_name] = nil
  if is_current_session then
    vim.v.this_session = ''
  end
end

--- Get name of latest detected session
---
--- Latest session is the session with the latest modification time determined
--- by |getftime|.
---
---@return string|nil: Name of latest session or `nil` if there is no sessions.
function MiniSessions.get_latest()
  if vim.tbl_count(MiniSessions.detected) == 0 then
    return
  end

  local latest_time, latest_name = -1, nil
  for name, data in pairs(MiniSessions.detected) do
    if data.modify_time > latest_time then
      latest_time, latest_name = data.modify_time, name
    end
  end

  return latest_name
end

-- Helper data
---- Module default config
H.default_config = MiniSessions.config

-- Helper functions
---- Settings
function H.setup_config(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    autoread = { config.autoread, 'boolean' },
    directory = { config.directory, 'string' },
    force = { config.force, 'table' },
    ['force.read'] = { config.force.read, 'boolean' },
    ['force.write'] = { config.force.write, 'boolean' },
    ['force.delete'] = { config.force.delete, 'boolean' },
    autowrite = { config.autowrite, 'boolean' },
  })

  return config
end

function H.apply_config(config)
  MiniSessions.config = config

  MiniSessions.detected = H.detect_sessions(config.directory)
end

function H.is_disabled()
  return vim.g.minisessions_disable == true or vim.b.minisessions_disable == true
end

---- Work with sessions
function H.detect_sessions(dir_path)
  dir_path = vim.fn.fnamemodify(dir_path, ':p')
  if vim.fn.isdirectory(dir_path) ~= 1 then
    H.notify(string.format([[%s is not a directory path.]], vim.inspect(dir_path)))
    return {}
  end

  local globs = vim.fn.globpath(dir_path, '*')
  if #globs == 0 then
    return {}
  end

  local res = {}
  for _, f in pairs(vim.split(globs, '\n')) do
    -- Add glob only if it is a readable file
    if vim.fn.isdirectory(f) ~= 1 and vim.fn.getfperm(f):sub(1, 1) == 'r' then
      local name = vim.fn.fnamemodify(f, ':t')
      res[name] = {
        modify_time = vim.fn.getftime(f),
        path = vim.fn.fnamemodify(f, ':p'),
      }
    end
  end
  return res
end

function H.validate_detected(session_name)
  local is_detected = vim.tbl_contains(vim.tbl_keys(MiniSessions.detected), session_name)
  if is_detected then
    return true
  end

  H.notify(string.format([[%s is not a name for detected session.]], vim.inspect(session_name)))
  return false
end

function H.wipeout_all_buffers(force)
  if force then
    vim.cmd([[%bwipeout!]])
    return true
  end

  -- Check for unsaved buffers and do nothing if they are present
  local unsaved_buffers = vim.tbl_filter(function(buf_id)
    vim.api.nvim_buf_get_option(buf_id, 'modified')
  end, vim.api.nvim_list_bufs())

  if #unsaved_buffers > 0 then
    H.notify(string.format([[There are unsaved buffers: %s]], table.concat(unsaved_buffers, ', ')))
    return false
  end

  vim.cmd([[%bwipeout]])
  return true
end

function H.get_current_session_name()
  return vim.fn.fnamemodify(vim.v.this_session, ':t')
end

---- Utilities
function H.notify(msg)
  vim.notify(string.format([[(mini.sessions) %s]], msg))
end

return MiniSessions