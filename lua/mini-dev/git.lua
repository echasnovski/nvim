-- TODO:
--
-- Code:
-- - Think about directly setting up HEAD data for new buffer if it was already
--   computed. Probably, requires separate `H.roots` cache.
--
-- - `refresh()` / `update()`. Either for buffer, root, or combination?
--
-- - `:Git` command with as much completion as reasonable:
--     - Normalize progress reports in `stderr`. For example, `stderr` of
--     `git rebase HEAd~~ --interactive` is something like (with literal `\r`):
--     `Rebasing (2/3)\rRebasing (3/3)\r\r\27[KSuccessfully rebased and updated
--     refs/heads/master.`
--
--     - Debug why sometimes there is a "process reached timeout" exit.
--
--     - Implement completion based on cursor position inside command:
--         - If `--` is present and cursor is after it - suggest file paths.
--           Maybe take a look at broader targets (like branch names, etc.).
--         - Otherwise get completion items via `git help <current-command>`
--           and parsing its output for subcommands, "-"-options and
--           "--"-options. Choose which set to use as completion items based
--           on the currently completed word.
--
--     - Ensure resaonable treatment of quote escaping
--       (like in `git branch --list --format='%(refname:short)'`)
--
-- - Blame functionality?
--
-- - Exported functionality to get file status/data based on an array of paths
--   alone? This maybe can be utilized by 'mini.files' to show Git status next
--   to the file.
--
-- Tests:
--
-- Docs:
-- - Use `:Git -C <cwd>` to execute command in current working directory.
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
  local exec = config.job.git_executable
  H.has_git = vim.fn.executable(exec) == 1
  if not H.has_git then H.notify('There is no `' .. exec .. '` executable', 'WARN') end

  -- Define behavior
  H.create_autocommands()
  for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
    H.auto_enable({ buf = buf_id })
  end

  -- Create user commands
  H.create_user_commands()
end

--stylua: ignore
--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text !!!!!
MiniGit.config = {
  job = {
    git_executable = 'git',
    timeout = 2000,
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

  -- Start tracking
  H.cache[buf_id] = {}
  H.setup_buf_behavior(buf_id)
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

  -- Cleanup
  pcall(vim.api.nvim_del_augroup_by_id, buf_cache.augroup)
  vim.b[buf_id].minigit_summary = nil

  -- - Unregister buffer from repo watching with possibly more cleanup
  local repo = buf_cache.repo
  if H.repos[repo] == nil then return end
  H.repos[repo].buffers[buf_id] = nil
  if vim.tbl_count(H.repos[repo].buffers) == 0 then
    H.teardown_repo_watch(repo)
    H.repos[repo] = nil
  end
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
  --stylua: ignore
  return vim.deepcopy({
    repo = buf_cache.repo, root = buf_cache.root,
    head = buf_cache.head, head_name = buf_cache.head_name,
    status = buf_cache.status,
  })
end

MiniGit.edit = function(path, servername)
  H.skip_timeout = true
  vim.cmd('tabedit ' .. vim.fn.fnameescape(path))

  local buf_id = vim.api.nvim_get_current_buf()
  vim.bo[buf_id].swapfile = false
  local tab_num, win_id = vim.api.nvim_tabpage_get_number(0), vim.api.nvim_get_current_win()

  -- Define action to finish editing Git related file
  local finish_au_id
  local finish = function(data)
    local should_close = data.event == 'VimLeave' or (data.event == 'WinClosed' and tonumber(data.match) == win_id)
    if not should_close then return end

    -- Clean up Git editor Neovim instance
    local _, channel = pcall(vim.fn.sockconnect, 'pipe', servername, { rpc = true })
    pcall(vim.rpcnotify, channel, 'nvim_exec2', 'quitall!', {})
    H.skip_timeout = false

    -- Clean up current instance
    pcall(vim.api.nvim_del_autocmd, finish_au_id)
    pcall(vim.api.nvim_buf_delete, buf_id, { force = true })
    pcall(function() vim.cmd('tabclose ' .. tab_num) end)
    vim.cmd('redraw')
  end
  -- - Use `nested` to allow other events (`WinEnter` for 'mini.statusline')
  finish_au_id = vim.api.nvim_create_autocmd({ 'VimLeave', 'WinClosed' }, { nested = true, callback = finish })
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniGit.config

-- Cache per enabled buffer. Values are tables with fields:
-- - <augroup> - identifier of augroup defining buffer behavior.
-- - <repo> - path to buffer's repo ('.git' directory).
-- - <root> - path to worktree root.
-- - <head> - full commit of `HEAD`.
-- - <head_name> - short name of `HEAD` (`'HEAD'` for detached head).
H.cache = {}

-- Cache per repo (git directory) path. Values are tables with fields:
-- - <fs_event> - `vim.loop` event for watching repo dir.
-- - <timer> - timer to debounce repo changes.
-- - <buffers> - map of buffers which should are part of repo.
H.repos = {}

-- Termporary file used as config for `GIT_EDITOR`
H.git_editor_config = nil

-- Whether to temporarily skip job timeout (like when inside `GIT_EDITOR`)
H.skip_timeout = false

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
    ['job.git_executable'] = { config.job.git_executable, 'string' },
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

H.get_buf_var = function(buf_id, name)
  if not vim.api.nvim_buf_is_valid(buf_id) then return nil end
  return vim.b[buf_id or 0][name]
end

H.create_user_commands = function()
  local git_execute = function(input)
    -- Define Git editor to be used if needed. It is a fresh headless process
    -- which in turn calls `MiniGit.edit()` in the current instance and does
    -- not exit until forced (from current instance after window with target
    -- file is closed).
    H.ensure_git_editor_config()
    -- NOTE: use `vim.v.progpath` to have same runtime
    local editor = vim.v.progpath .. ' --clean --headless -u ' .. H.git_editor_config

    -- Setup all environment variables (`vim.loop.spawn()` by default has none)
    local environ = vim.loop.os_environ()
    environ.GIT_EDITOR, environ.GIT_SEQUENCE_EDITOR, environ.GIT_PAGER, environ.NO_COLOR = editor, editor, '', 1
    local env = {}
    for k, v in pairs(environ) do
      table.insert(env, string.format('%s=%s', k, tostring(v)))
    end

    -- Setup spawn arguments
    local args = vim.tbl_map(H.expandcmd, input.fargs)
    local command = { MiniGit.config.job.git_executable, unpack(args) }

    local buf_cache = H.cache[vim.api.nvim_get_current_buf()]
    local cwd = buf_cache ~= nil and buf_cache.root or vim.fn.getcwd()

    add_to_log(':Git', { input = input, args = args, editor = editor })
    local on_done = vim.schedule_wrap(function(code, out, err)
      add_to_log(':Git on_done', { code = code, out = vim.split(out, '\n'), err = err })
      if code ~= 0 then return H.notify(err, 'ERROR') end
      if err ~= '' then H.notify(err, 'WARN') end
      if out ~= '' then H.notify(out, 'INFO') end
    end)

    H.cli_run(command, cwd, on_done, { env = env })
  end

  local opts = { nargs = '+', complete = H.command_complete, desc = 'Execute Git command' }
  vim.api.nvim_create_user_command('Git', git_execute, opts)
end

-- Command --------------------------------------------------------------------
-- H.command_complete = function(_, line, col)
H.command_complete = function(...) add_to_log('command_complete', { ... }) end

H.ensure_git_editor_config = function()
  if H.git_editor_config == nil or not vim.fn.filereadable(H.git_editor_config) == 0 then
    H.git_editor_config = vim.fn.tempname()
  end
  -- Start editing file from first argument (as how `GIT_EDITOR` works) in
  -- current instance and don't close until explicitly closed later from this
  -- instance in `MiniGit.edit()`
  local lines = {
    'lua << EOF',
    string.format('local channel = vim.fn.sockconnect("pipe", %s, { rpc = true })', vim.inspect(vim.v.servername)),
    'local lua_cmd = string.format("MiniGit.edit(%s, %s)", vim.inspect(vim.fn.argv(0)), vim.inspect(vim.v.servername))',
    'vim.rpcrequest(channel, "nvim_exec_lua", lua_cmd, {})',
    'EOF',
  }
  vim.fn.writefile(lines, H.git_editor_config)
end

-- TODO: Remove after development is done
H.create_user_commands()

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
H.is_buf_enabled = function(buf_id) return H.cache[buf_id] ~= nil and vim.api.nvim_buf_is_valid(buf_id) end

H.setup_buf_behavior = function(buf_id)
  local augroup = vim.api.nvim_create_augroup('MiniGitBuffer' .. buf_id, { clear = true })
  H.cache[buf_id].augroup = augroup

  vim.api.nvim_buf_attach(buf_id, false, {
    -- Called when buffer content is changed outside of current session
    -- Needed as otherwise `on_detach()` is called without later auto enabling
    on_reload = function()
      local buf_cache = H.cache[buf_id]
      if buf_cache == nil or buf_cache.root == nil then return end
      H.update_git_head(buf_cache.root, { buf_id })
      H.update_git_status(buf_cache.root, { buf_id })
    end,

    -- Called when buffer is unloaded from memory (`:h nvim_buf_detach_event`),
    -- **including** `:edit` command. Together with auto enabling it makes
    -- `:edit` command serve as "restart".
    on_detach = function() MiniGit.disable(buf_id) end,
  })

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
  local command = H.git_cmd({ 'rev-parse', '--path-format=absolute', '--git-dir', '--show-toplevel' })

  -- If path is not in Git, disable buffer but make sure that it will not try
  -- to re-attach until buffer is properly disabled
  local on_not_in_git = function()
    MiniGit.disable(buf_id)
    H.cache[buf_id] = {}
  end

  local on_done = vim.schedule_wrap(function(code, out, err)
    -- Watch git directory only if there was no error retrieving path to it
    if code ~= 0 then return on_not_in_git() end
    if err ~= '' then H.notify(err, 'WARN') end

    -- Update cache
    local repo, root = string.match(out, '^(.-)\n(.*)$')
    if repo == nil or root == nil then return H.notify('No initial data for buffer ' .. buf_id, 'WARN') end
    H.update_buf_data(buf_id, { repo = repo, root = root })

    -- Set up repo watching to react to Git index changes
    H.setup_repo_watch(buf_id, repo)

    -- Set up worktree watching to react to file changes
    H.setup_path_watch(buf_id)

    -- Immediately update buffer tracking data
    H.update_git_head(root, { buf_id })
    H.update_git_status(root, { buf_id })
  end)

  H.cli_run(command, vim.fn.fnamemodify(path, ':h'), on_done)
end

H.setup_repo_watch = function(buf_id, repo)
  local repo_cache = H.repos[repo] or {}

  -- Ensure repo is watched
  local is_set_up = repo_cache.fs_event ~= nil and repo_cache.fs_event:is_active()
  if not is_set_up then
    H.teardown_repo_watch(repo)
    local fs_event, timer = vim.loop.new_fs_event(), vim.loop.new_timer()

    local on_change = vim.schedule_wrap(function() H.on_repo_change(repo) end)
    local watch = function(_, filename, _)
      -- Ignore temporary changes
      if vim.endswith(filename, 'lock') then return end

      -- Debounce to not overload during incremental staging (like in script)
      timer:stop()
      timer:start(50, 0, on_change)
    end
    fs_event:start(repo, { recursive = true }, watch)

    repo_cache.fs_event, repo_cache.timer = fs_event, timer
    H.repos[repo] = repo_cache
  end

  -- Register buffer to be updated on repo change
  local repo_buffers = repo_cache.buffers or {}
  repo_buffers[buf_id] = true
  repo_cache.buffers = repo_buffers
end

H.teardown_repo_watch = function(repo)
  if H.repos[repo] == nil then return end
  pcall(vim.loop.fs_event_stop, H.repos[repo].fs_event)
  pcall(vim.loop.timer_stop, H.repos[repo].timer)
end

H.setup_path_watch = function(buf_id, repo)
  if not H.is_buf_enabled(buf_id) then return end

  local on_file_change = function(data) H.update_git_status(H.cache[buf_id].root, { buf_id }) end
  vim.api.nvim_create_autocmd(
    { 'BufWritePost', 'FileChangedShellPost' },
    { desc = 'Update Git status', group = H.cache[buf_id].augroup, callback = on_file_change }
  )
end

H.on_repo_change = function(repo)
  if H.repos[repo] == nil then return end

  -- Collect repo's worktrees with their buffers while doing cleanup
  local repo_bufs, root_bufs = H.repos[repo].buffers, {}
  for buf_id, _ in pairs(repo_bufs) do
    if H.is_buf_enabled(buf_id) then
      local root = H.cache[buf_id].root
      local bufs = root_bufs[root] or {}
      table.insert(bufs, buf_id)
      root_bufs[root] = bufs
    else
      repo_bufs[buf_id] = nil
      MiniGit.disable(buf_id)
    end
  end

  -- Update Git data for every worktree
  for root, bufs in pairs(root_bufs) do
    H.update_git_head(root, bufs)
    -- Status could have also changed as it depends on the index
    H.update_git_status(root, bufs)
  end
end

H.update_git_head = function(root, bufs)
  local command = H.git_cmd({ 'rev-parse', 'HEAD', '--abbrev-ref', 'HEAD' })

  local on_done = vim.schedule_wrap(function(code, out, err)
    -- Ensure proper data
    if code ~= 0 then return H.notify('Could not update HEAD data for root ' .. root .. '\n' .. err, 'WARN') end
    if err ~= '' then H.notify(err, 'WARN') end

    local head, head_name = string.match(out, '^(.-)\n(.*)$')
    if head == nil or head_name == nil then
      return H.notify('Could not parse HEAD data for root ' .. root .. '\n' .. out, 'WARN')
    end

    -- Update data for all buffers from target `root`
    local new_data = { head = head, head_name = head_name }
    for _, buf_id in ipairs(bufs) do
      H.update_buf_data(buf_id, new_data)
    end

    -- Redraw statusline to have possible statusline component up to date
    vim.cmd('redrawstatus')
  end)

  H.cli_run(command, root, on_done)
end

H.update_git_status = function(root, bufs)
  local command = H.git_cmd({ 'status', '--verbose', '--untracked-files=all', '--ignored', '--porcelain', '-z', '--' })
  local root_len, path_data = string.len(root), {}
  for _, buf_id in ipairs(bufs) do
    -- Use paths relative to the root as in `git status --porcelain` output
    local rel_path = vim.api.nvim_buf_get_name(buf_id):sub(root_len + 2)
    table.insert(command, rel_path)
    -- Completely not modified paths should be the only ones missing in the
    -- output. Use this status as default.
    path_data[rel_path] = { status = '  ', buf_id = buf_id }
  end

  local on_done = vim.schedule_wrap(function(code, out, err)
    if code ~= 0 then return H.notify('Could not update status data for root ' .. root .. '\n' .. err, 'WARN') end
    if err ~= '' then H.notify(err, 'WARN') end

    -- Parse CLI output, which is separated by `\0` to not escape "bad" paths
    for _, l in ipairs(vim.split(out, '\0')) do
      local status, rel_path = string.match(l, '^(..) (.*)$')
      if path_data[rel_path] ~= nil then path_data[rel_path].status = status end
    end

    -- Update data for all buffers
    for path, data in pairs(path_data) do
      local new_data = { status = data.status }
      H.update_buf_data(data.buf_id, new_data)
    end

    -- Redraw statusline to have possible statusline component up to date
    vim.cmd('redrawstatus')
  end)

  H.cli_run(command, root, on_done)
end

H.update_buf_data = function(buf_id, new_data)
  if not H.is_buf_enabled(buf_id) then return end

  local summary = vim.b[buf_id].minigit_summary or {}
  for key, val in pairs(new_data) do
    H.cache[buf_id][key], summary[key] = val, val
  end
  vim.b[buf_id].minigit_summary = summary
end

-- CLI ------------------------------------------------------------------------
H.git_cmd = function(args)
  -- Use '-c gc.auto=0' to disable `stderr` "Auto packing..." messages
  return { MiniGit.config.job.git_executable, '-c', 'gc.auto=0', unpack(args) }
end

H.cli_run = function(command, cwd, on_done, opts)
  local spawn_opts = opts or {}
  local executable, args = command[1], vim.list_slice(command, 2, #command)
  local process, stdout, stderr = nil, vim.loop.new_pipe(), vim.loop.new_pipe()
  spawn_opts.args, spawn_opts.cwd, spawn_opts.stdio = args, cwd, { nil, stdout, stderr }

  local out, err, is_done = {}, {}, false
  local on_exit = function(code)
    is_done = true
    if process:is_closing() then return end
    process:close()

    out, err = H.cli_stream_tostring(out), H.cli_stream_tostring(err)
    on_done(code, out, err)
  end

  process = vim.loop.spawn(executable, spawn_opts, on_exit)
  H.cli_read_stream(stdout, out)
  H.cli_read_stream(stderr, err)
  vim.defer_fn(function()
    if H.skip_timeout or not process:is_active() then return end
    H.notify('PROCESS REACHED TIMEOUT', 'WARN')
    on_exit(1)
  end, MiniGit.config.job.timeout)
  return process
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

H.expandcmd = function(x)
  if x == '<cwd>' then return vim.fn.getcwd() end
  local ok, res = pcall(vim.fn.expandcmd, x)
  return ok and res or x
end

return MiniGit
