-- TODO:
--
-- Code:
-- - Setup git dir tracking more efficiently: one file watcher per git
--   directory (not per buffer).
--
-- Tests:
--
-- Docs:
--

--- *mini.git* Git integration
--- *MiniGit*
---
--- MIT License Copyright (c) 2024 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Features:
---
--- - Automated tracking of Git related data.
---
--- - |:Git| command for executing any Git command inside current Neovim instance.
---
--- - Blame functionality?
---
--- What it doesn't do:
---
--- - Provide functionality to work Git outside of integration with current
---   Neovim instance. General rule: if something does not rely on a particular
---   state of current Neovim (opened buffers, etc.), it is out of scope.
---   For more functionality, use fully featured Git client.
---
--- Sources with more details:
--- - |MiniGit-overview|
--- - |:Git|
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.git').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniGit`
--- which you can use for scripting or manually (with `:lua MiniGit.*`).
---
--- See |MiniGit.config| for `config` structure and default values.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.minigit_config` which should have same structure as
--- `MiniGit.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons ~
---
--- - 'tpope/vim-fugitive':
---     - Has more functionality as a dedicated Git client.
---     - Does not provide buffer-local data related to Git.
--- - 'NeogitOrg/neogit':
---     - Has more functionality as a dedicated Git client.
---
--- # Disabling ~
---
--- To temporarily disable features without relying on |MiniGit.disable()|,
--- set `vim.g.minigit_disable` (globally) or `vim.b.minigit_disable` (for
--- a buffer) to `true`. Considering high number of different scenarios and
--- customization intentions, writing exact rules for disabling module's
--- functionality is left to user.
--- See |mini.nvim-disabling-recipes| for common recipes.

---@alias __git_buf_id number Target buffer identifier. Default: 0 for current buffer.

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local
---@diagnostic disable:cast-local-type
---@diagnostic disable:undefined-doc-name
---@diagnostic disable:luadoc-miss-type-name

-- Module definition ==========================================================
MiniGit = {}
H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniGit.config|.
---
---@usage `require('mini.git').setup({})` (replace `{}` with your `config` table).
MiniGit.setup = function(config)
  -- Export module
  _G.MiniGit = MiniGit

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Ensure proper Git executable
  local exec = config.job.executable
  H.has_git = vim.fn.executable(exec) == 1
  if not H.has_git then H.notify('There is no `' .. exec .. '` executable', 'WARN') end

  -- Define behavior
  H.create_autocommands()
  for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
    H.auto_enable({ buf = buf_id })
  end
end

--stylua: ignore
--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text !!!!!
MiniGit.config = {
  job = {
    executable = 'git',
    timeout = 10000,
  }
}
--minidoc_afterlines_end

--- Enable Git tracking in buffer
---
---@param buf_id __git_buf_id
MiniGit.enable = function(buf_id)
  buf_id = H.validate_buf_id(buf_id)

  -- Don't enable more than once
  if H.is_buf_enabled(buf_id) or H.is_disabled(buf_id) or not H.has_git then return end

  -- Enable only in buffers which *can* be part of Git repo
  local path = vim.api.nvim_buf_get_name(buf_id)
  if path == '' or vim.fn.filereadable(path) ~= 1 then return end

  -- Register enabled buffer with cached data for performance
  H.update_buf_cache(buf_id)

  -- Create buffer autocommands
  H.setup_buf_autocommands(buf_id)

  -- Start Git tracking
  H.start_tracking(buf_id, path)
end

--- Disable Git tracking in buffer
---
---@param buf_id __git_buf_id
MiniGit.disable = function(buf_id)
  buf_id = H.validate_buf_id(buf_id)

  local buf_cache = H.cache[buf_id]
  if buf_cache == nil then return end
  H.cache[buf_id] = nil

  pcall(vim.api.nvim_del_augroup_by_id, buf_cache.augroup)
  pcall(vim.loop.fs_event_stop, buf_cache.fs_event)
  pcall(vim.loop.timer_stop, buf_cache.timer)
end

--- Toggle Git tracking in buffer
---
--- Enable if disabled, disable if enabled.
---
---@param buf_id __git_buf_id
MiniGit.toggle = function(buf_id)
  buf_id = H.validate_buf_id(buf_id)
  if H.is_buf_enabled(buf_id) then return MiniGit.disable(buf_id) end
  return MiniGit.enable(buf_id)
end

--- Get buffer data
---
---@param buf_id __git_buf_id
---
---@return table|nil Table with buffer Git data or `nil` if buffer is not enabled.
---   Table has the following fields:
MiniGit.get_buf_data = function(buf_id)
  buf_id = H.validate_buf_id(buf_id)
  local buf_cache = H.cache[buf_id]
  if buf_cache == nil then return nil end
  return vim.deepcopy({
    config = buf_cache.config,
    head = buf_cache.head,
    head_commit = buf_cache.head_commit,
    git_dir = buf_cache.git_dir,
    worktree = buf_cache.worktree,
  })
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniGit.config

-- Cache per enabled buffer
H.cache = {}

-- Cache for watching git directories (used as fields)
H.git_dir_cache = {}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  vim.validate({
    job = { config.job, 'table' },
  })

  vim.validate({
    ['job.executable'] = { config.job.executable, 'string' },
    ['job.timeout'] = { config.job.timeout, 'number' },
  })

  return config
end

H.apply_config = function(config) MiniGit.config = config end

H.create_autocommands = function()
  local augroup = vim.api.nvim_create_augroup('MiniGit', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = augroup, pattern = pattern, callback = callback, desc = desc })
  end

  -- NOTE: Try auto enabling buffer on every `BufEnter` to not have `:edit`
  -- disabling buffer, as it calls `on_detach()` from buffer watcher
  au('BufEnter', '*', H.auto_enable, 'Enable Git tracking')
end

H.is_disabled = function(buf_id)
  local buf_disable = H.get_buf_var(buf_id, 'minidiff_disable')
  return vim.g.minidiff_disable == true or buf_disable == true
end

H.get_config = function(config, buf_id)
  local buf_config = H.get_buf_var(buf_id, 'minidiff_config') or {}
  return vim.tbl_deep_extend('force', MiniGit.config, buf_config, config or {})
end

H.get_buf_var = function(buf_id, name)
  if not vim.api.nvim_buf_is_valid(buf_id) then return nil end
  return vim.b[buf_id or 0][name]
end

-- Autocommands ---------------------------------------------------------------
H.auto_enable = vim.schedule_wrap(function(data)
  if H.is_buf_enabled(data.buf) or H.is_disabled(data.buf) then return end
  if not vim.api.nvim_buf_is_valid(data.buf) or vim.bo[data.buf].buftype ~= '' then return end
  MiniGit.enable(data.buf)
end)

-- Validators -----------------------------------------------------------------
H.validate_buf_id = function(x)
  if x == nil or x == 0 then return vim.api.nvim_get_current_buf() end
  if not (type(x) == 'number' and vim.api.nvim_buf_is_valid(x)) then
    H.error('`buf_id` should be `nil` or valid buffer id.')
  end
  return x
end

-- Enabling -------------------------------------------------------------------
H.is_buf_enabled = function(buf_id) return H.cache[buf_id] ~= nil end

H.update_buf_cache = function(buf_id)
  local new_cache = H.cache[buf_id] or {}

  local buf_config = H.get_config({}, buf_id)
  new_cache.config = buf_config
  new_cache.path = vim.api.nvim_buf_get_name(buf_id)

  H.cache[buf_id] = new_cache
end

H.setup_buf_autocommands = function(buf_id)
  local augroup = vim.api.nvim_create_augroup('MiniGitBuffer' .. buf_id, { clear = true })
  H.cache[buf_id].augroup = augroup

  local buf_update = vim.schedule_wrap(function() H.update_buf_cache(buf_id) end)
  local bufwinenter_opts = { group = augroup, buffer = buf_id, callback = buf_update, desc = 'Update buffer cache' }
  vim.api.nvim_create_autocmd('BufWinEnter', bufwinenter_opts)

  local reset_if_enabled = vim.schedule_wrap(function(data)
    if not H.is_buf_enabled(data.buf) then return end
    MiniGit.disable(data.buf)
    MiniGit.enable(data.buf)
  end)
  local bufrename_opts = { group = augroup, buffer = buf_id, callback = reset_if_enabled, desc = 'Reset on rename' }
  -- NOTE: `BufFilePost` does not look like a proper event, but it (yet) works
  vim.api.nvim_create_autocmd('BufFilePost', bufrename_opts)

  local buf_disable = function() MiniGit.disable(buf_id) end
  local bufdelete_opts = { group = augroup, buffer = buf_id, callback = buf_disable, desc = 'Disable on delete' }
  vim.api.nvim_create_autocmd('BufDelete', bufdelete_opts)
end

-- Tracking -------------------------------------------------------------------
H.start_tracking = function(buf_id, path)
  local config = H.cache[buf_id].config
  local command = H.git_cmd({ 'rev-parse', '--path-format=absolute', '--git-dir' }, config)

  -- If path is not in Git, disable buffer but make sure that it will not try
  -- to re-attach until buffer is properly disabled
  local on_not_in_git = vim.schedule_wrap(function()
    MiniGit.disable(buf_id)
    H.cache[buf_id] = {}
  end)

  local on_done = function(code, out, err)
    -- Watch git directory only if there was no error retrieving path to it
    if code ~= 0 then return on_not_in_git() end

    -- Update cache
    H.cache[buf_id].git_dir = out

    -- Set up git directory watching
    H.setup_git_dir_watch(buf_id, out)

    -- Compute tracking data immediately
    H.update_git_data(buf_id)
  end

  H.cli_run(command, vim.fn.fnamemodify(path, ':h'), on_done, config)
end

H.setup_git_dir_watch = function(buf_id, git_dir_path)
  local buf_fs_event, timer = vim.loop.new_fs_event(), vim.loop.new_timer()
  local buf_update_git_data = function() H.update_git_data(buf_id) end

  local watch_index = function(_, filename, _)
    if filename ~= 'index' then return end
    -- Debounce to not overload during incremental staging (like in script)
    timer:stop()
    timer:start(50, 0, buf_update_git_data)
  end
  buf_fs_event:start(git_dir_path, { recursive = true }, watch_index)

  local buf_cache = H.cache[buf_id]
  pcall(vim.loop.fs_event_stop, buf_cache.fs_event)
  buf_cache.fs_event = buf_fs_event
  pcall(vim.loop.timer_stop, buf_cache.timer)
  buf_cache.timer = timer
end

H.update_git_data = vim.schedule_wrap(function(buf_id)
  local cache = H.cache[buf_id]
  local config = cache.config

  local args = { 'rev-parse', '--path-format=absolute', '--git-dir', '--show-toplevel', 'HEAD', '--abbrev-ref', 'HEAD' }
  local command = H.git_cmd(args, config)

  local on_done = function(code, out, err)
    if code ~= 0 then return H.notify('Error with exit code ' .. code .. '\n' .. err, 'ERROR') end
    if err ~= '' then H.notify(err, 'WARN') end

    add_to_log('update_git_data', { out = out })
    local git_dir, worktree, head_commit, head = string.match(out, '^(.-)\n(.-)\n(.-)\n(.*)$')
    local c = H.cache[buf_id]
    c.git_dir, c.worktree, c.head_commit, c.head = git_dir, worktree, head_commit, head
    vim.b[buf_id].minigit_summary = { git_dir = git_dir, worktree = worktree, head_commit = head_commit, head = head }
  end

  local cwd = cache.worktree or vim.fn.fnamemodify(config.path, ':h')
  H.cli_run(command, cwd, on_done, config)
end)

-- CLI ------------------------------------------------------------------------
H.git_cmd = function(args, config)
  config = config or H.get_config()

  -- Use '-c gc.auto=0' to disable `stderr` "Auto packing..." messages
  return { config.job.executable, '-c', 'gc.auto=0', unpack(args) }
end

H.cli_run = function(command, cwd, on_done, config)
  config = config or H.get_config()
  local timeout = config.job.timeout

  -- Prepare data for `vim.loop.spawn`
  local executable, args = command[1], vim.list_slice(command, 2, #command)
  local process, stdout, stderr = nil, vim.loop.new_pipe(), vim.loop.new_pipe()
  local spawn_opts = { args = args, cwd = cwd, stdio = { nil, stdout, stderr } }

  local out, err, is_done = {}, {}, false
  local on_exit = function(code)
    is_done = true
    if process:is_closing() then return end
    process:close()
    on_done(code, H.cli_stream_tostring(out), H.cli_stream_tostring(err))
  end

  process = vim.loop.spawn(executable, spawn_opts, on_exit)
  H.cli_read_stream(stdout, out)
  H.cli_read_stream(stderr, err)
  vim.defer_fn(function()
    if not process:is_active() then return end
    H.notify('PROCESS REACHED TIMEOUT', 'WARN')
    on_exit(1)
  end, timeout)
end

H.cli_read_stream = function(stream, feed)
  local callback = function(err, data)
    if err then return table.insert(feed, 1, 'ERROR: ' .. err) end
    if data ~= nil then return table.insert(feed, data) end
    stream:close()
  end
  stream:read_start(callback)
end

H.cli_stream_tostring = function(stream) return (table.concat(stream):gsub('\n+$', '')) end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.git) %s', msg), 0) end

H.notify = function(msg, level_name) vim.notify('(mini.git) ' .. msg, vim.log.levels[level_name]) end

return MiniGit
