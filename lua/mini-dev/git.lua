-- TODO:
--
-- Code:
-- - Think about directly setting up HEAD data for new buffer if it was already
--   computed. Probably, requires separate `H.roots` cache.
--
-- - `refresh()` / `update()`. Either for buffer, root, or combination?
--
-- - `:Git` command with as much completion as reasonable:
--     - Implement completion based on cursor position inside command:
--         - If `--` is present and cursor is after it - suggest file paths.
--           Maybe take a look at broader targets (like branch names, etc.).
--         - Otherwise get completion items via `git help <current-command>`
--           and parsing its output for subcommands, "-"-options and
--           "--"-options. Choose which set to use as completion items based
--           on the currently completed word.
--
--     - Don't show output in the special buffer for some `git` commands,
--       use `H.notify(out, 'INFO')` instead. Like:
--         - `commit` (with its information about what was committed).
--         - `stash` (with its feedback).
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
-- - How to read options completions:
--     - `[xxx]` describes optional text which can be omitted.
--       Like `:Giti log --decorate[=short|full|auto|no]`.
--     - `<xxx>` is a placeholder for something mandatory.
--       Like `:Git log --after=<date>`.
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
    timeout = 30000,
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

MiniGit._edit = function(path, servername, mods)
  H.skip_timeout = true

  -- Start file edit but with proper modifiers
  vim.cmd(mods .. ' split ' .. vim.fn.fnameescape(path))

  local buf_id, win_id = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  vim.bo[buf_id].swapfile = false

  -- Define action to finish editing Git related file
  local finish_au_id
  local finish = function(data)
    local should_close = data.buf == buf_id or (data.event == 'WinClosed' and tonumber(data.match) == win_id)
    if not should_close then return end

    -- Clean up Git editor Neovim instance
    local _, channel = pcall(vim.fn.sockconnect, 'pipe', servername, { rpc = true })
    pcall(vim.rpcnotify, channel, 'nvim_exec2', 'quitall!', {})
    H.skip_timeout = false

    -- Clean up current instance
    pcall(vim.api.nvim_del_autocmd, finish_au_id)
    pcall(vim.api.nvim_buf_delete, buf_id, { force = true })
    vim.cmd('redraw')
  end
  -- - Use `nested` to allow other events (`WinEnter` for 'mini.statusline')
  local events = { 'WinClosed', 'BufDelete', 'BufWipeout', 'VimLeave' }
  finish_au_id = vim.api.nvim_create_autocmd(events, { nested = true, callback = finish })
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

-- Map of completion candidate arrays per supported Git command.
-- Candidates are created lazily (if entry is not a table)
H.git_completions = nil

-- Whether to temporarily skip job timeout (like when inside `GIT_EDITOR`)
H.skip_timeout = false

-- Buffer to reuse for showing `:Git` output
H.output_buf_id = nil

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
    -- Define Git editor to be used if needed. The way it works is: execute
    -- command, wait for it to exit, use content of edited file. So to properly
    -- wait for user to finish edit, start fresh headless process which opens
    -- file in current session/process. It gets an exit after the user is done
    -- editing (deletes the buffer or closes the window).
    H.ensure_git_editor_config(input.mods)
    -- NOTE: use `vim.v.progpath` to have same runtime
    local editor = vim.v.progpath .. ' --clean --headless -u ' .. H.git_editor_config

    -- Setup all environment variables (`vim.loop.spawn()` by default has none)
    local environ = vim.loop.os_environ()
    -- - Use Git related variables to use instance for editing
    environ.GIT_EDITOR, environ.GIT_SEQUENCE_EDITOR, environ.GIT_PAGER = editor, editor, ''
    -- - Make output as much machine readable as possible
    environ.NO_COLOR, environ.TERM = 1, 'dumb'
    local env = {}
    for k, v in pairs(environ) do
      table.insert(env, string.format('%s=%s', k, tostring(v)))
    end

    -- Setup spawn arguments
    local args = vim.tbl_map(H.expandcmd, input.fargs)
    local command = { MiniGit.config.job.git_executable, unpack(args) }

    local buf_cache = H.cache[vim.api.nvim_get_current_buf()] or {}
    local repo, root = buf_cache.repo or vim.fn.getcwd(), buf_cache.root or vim.fn.getcwd()

    add_to_log(':Git', { input = input, args = args, editor = editor })
    local on_done = vim.schedule_wrap(function(code, out, err)
      add_to_log(':Git on_done', { code = code, out = vim.split(out, '\n'), err = err })
      if H.cli_err_notify(code, out, err) then return end
      H.cli_out_show(out, input.mods, command)

      -- Ensure that all buffers are up to date (avoids "The file has been
      -- changed since reading it" warning)
      vim.tbl_map(function(buf_id) vim.cmd('checktime ' .. buf_id) end, vim.api.nvim_list_bufs())

      -- Ensure that repo data is up to date. This is not always taken care of
      -- by repo watching, like file status after `:Git commit` (probably due
      -- to `git status` still using old repo data).
      H.on_repo_change(repo)
    end)

    H.cli_run(command, root, on_done, { env = env })
  end

  local opts = { nargs = '+', complete = H.command_complete, desc = 'Execute Git command' }
  vim.api.nvim_create_user_command('Git', git_execute, opts)
end

-- Command --------------------------------------------------------------------
H.ensure_git_editor_config = function(command_mods)
  if H.git_editor_config == nil or not vim.fn.filereadable(H.git_editor_config) == 0 then
    H.git_editor_config = vim.fn.tempname()
  end

  -- Start editing file from first argument (as how `GIT_EDITOR` works) in
  -- current instance and don't close until explicitly closed later from this
  -- instance as set up in `MiniGit.edit()`
  local lines = {
    'lua << EOF',
    string.format('local channel = vim.fn.sockconnect("pipe", %s, { rpc = true })', vim.inspect(vim.v.servername)),
    'local ins, mods = vim.inspect, ' .. vim.inspect(command_mods),
    'local lua_cmd = string.format("MiniGit._edit(%s, %s, %s)", ins(vim.fn.argv(0)), ins(vim.v.servername), ins(mods))',
    'vim.rpcrequest(channel, "nvim_exec_lua", lua_cmd, {})',
    'EOF',
  }
  vim.fn.writefile(lines, H.git_editor_config)
end

H.command_complete = function(_, line, col)
  local base = line:sub(1, col):match('%S*$')
  local candidates = H.command_get_complete_candidates(line, col, base)
  return vim.tbl_filter(function(x) return vim.startswith(x, base) end, candidates)
end

H.command_get_complete_candidates = function(line, col, base)
  H.ensure_supported_git_commands()

  -- Determine current Git command as the earliest present supported command
  local command, command_ind = nil, math.huge
  for cmd, _ in pairs(H.git_completions) do
    local ind = line:find(' ' .. cmd .. ' ', 1, true)
    if ind ~= nil and ind < command_ind then
      command, command_ind = cmd, ind
    end
  end

  -- If no command is yet used, use supported commands as candidates
  if command == nil then
    local res = vim.tbl_keys(H.git_completions)
    table.sort(res)
    return res
  end

  -- Determine command candidates based on the **explicit** "--":
  -- - Command targets (paths, branches, remotes, etc.) if on the right.
  -- - Options/subcommands if on the left or not present.
  if line:sub(1, col):find(' %-%- ') then return H.command_get_complete_targets(command, base) end
  return H.command_get_complete_options(command)
end

H.ensure_supported_git_commands = function()
  if H.git_completions ~= nil then return end
  local commands = H.cli_run({ 'git', '--list-cmds=main,others,alias,nohelpers' }, vim.fn.getcwd()).out
  if commands == '' then return end
  local completions = {}
  for _, command in ipairs(vim.split(commands, '\n')) do
    -- Initialize as `false` so that actual candidates are computed lazily
    completions[command] = false
  end
  H.git_completions = completions
end

H.command_get_complete_options = function(command)
  local cached_candidates = H.git_completions[command]
  if type(cached_candidates) == 'table' then return cached_candidates end

  local help_page = H.cli_run({ 'git', 'help', command }, vim.fn.getcwd())
  if help_page.code ~= 0 then return {} end
  local res, lines = {}, vim.split(help_page.out, '\n')

  -- Find command's flag options. Assumed to be inside "OPTIONS" section of
  -- help page on separate lines. If a line is an options line is determined
  -- euristically: it should start with `-`, follow subsection separator
  -- (blank line or initial "OPTIONS" line), and contain only words starting
  -- with appropriate characters.
  local is_in_options_section, is_after_subsection_sep = false, false
  for _, l in ipairs(lines) do
    local is_options_start = l:find('^%s*OPTIONS:?%s*$') ~= nil
    if is_in_options_section and l:find('^%s*%u+%s*$') ~= nil then is_in_options_section = false end
    if not is_in_options_section and is_options_start then is_in_options_section = true end

    if is_in_options_section and is_after_subsection_sep then H.try_parse_append_options(res, l) end
    is_after_subsection_sep = l:find('^%s*$') ~= nil or is_options_start
  end

  -- TODO: parse and append subcommands

  -- Sort by relevance
  -- Subcommands (no "-" at start) > short options (one "-") > regular options
  -- Inside groups sort alphabetically
  table.sort(res, function(a, b)
    local a1, a2, b1, b2 = a:sub(1, 1) == '-', a:sub(2, 2) == '-', b:sub(1, 1) == '-', b:sub(2, 2) == '-'
    if a1 and not b1 then return false end
    if not a1 and b1 then return true end
    if a2 and not b2 then return false end
    if not a2 and b2 then return true end
    return a < b
  end)

  add_to_log('command_get_complete_options', { lines = lines, res = res })

  -- Cache and return
  H.git_completions[command] = res
  return res
end

H.try_parse_append_options = function(arr, line)
  -- Should start with "-" and not contain "bad" words
  if not (line:find('^%s*%-%S') ~= nil and line:find(' [^-<: ]') == nil) then return end

  -- Parse line for present options. Assumed to be listed separated by ",".
  -- As special case, expand "--[no-]xxx" into two: "--xxx" and "--no-xxx".
  -- NOTE: This will result into present placeholders indicating how the flag
  -- should be used (like "-b <branch>"), which is arguably a good thing.
  for _, opt in ipairs(vim.split(line, ', ')) do
    opt = vim.trim(opt)
    local opt_nono = opt:gsub('%[no%-%]', '')
    local opt_no = opt:gsub('%[no%-%]', '')
    table.insert(arr, opt_nono)
    if opt_nono ~= opt then table.insert(arr, (opt:gsub('%[no%-%]', 'no-'))) end
  end
end

H.command_get_complete_targets = function(command, base)
  -- TODO
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
    H.cli_err_notify(code, out, err)

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
    H.cli_err_notify(code, out, err)

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
    H.cli_err_notify(code, out, err)

    -- Parse CLI output, which is separated by `\0` to not escape "bad" paths
    for _, l in ipairs(vim.split(out, '\0')) do
      local status, rel_path = string.match(l, '^(..) (.*)$')
      if path_data[rel_path] ~= nil then path_data[rel_path].status = status end
    end

    -- Update data for all buffers
    for _, data in pairs(path_data) do
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

  -- Allow `on_done = nil` to mean synchronous execution
  local is_sync, res = false, nil
  if on_done == nil then
    is_sync = true
    on_done = function(code, out, err) res = { code = code, out = out, err = err } end
  end

  local out, err, is_done = {}, {}, false
  local on_exit = function(code)
    is_done = true
    if process:is_closing() then return end
    process:close()

    -- Convert to strings appropriate for notifications
    out = H.cli_stream_tostring(out)
    err = H.cli_stream_tostring(err):gsub('\r+', '\n'):gsub('\n%s+\n', '\n\n')
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

  if is_sync then vim.wait(MiniGit.config.job.timeout + 10, function() return is_done end, 1) end
  return res
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

H.cli_err_notify = function(code, out, err)
  local should_stop = code ~= 0
  if should_stop then H.notify(err .. (out == '' and '' or ('\n' .. out)), 'ERROR') end
  if not should_stop and err ~= '' then H.notify(err, 'WARN') end
  return should_stop
end

H.cli_out_show = function(out, mods, git_command)
  if out == '' or mods:find('silent') ~= nil then return end

  -- Reuse same buffer
  local buf_id = H.output_buf_id
  if buf_id == nil or not vim.api.nvim_buf_is_valid(buf_id) then buf_id = vim.api.nvim_create_buf(false, true) end
  H.output_buf_id = buf_id

  -- Populate special buffer, make up to date, and show in split
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, vim.split(out, '\n'))
  local buf_name = 'minigit:///' .. table.concat(git_command, ' ')
  vim.api.nvim_buf_set_name(buf_id, buf_name)
  local filetype = vim.filetype.match({ buf = buf_id })
  if filetype ~= nil then vim.bo[buf_id].filetype = filetype end
  vim.cmd(mods .. ' split ' .. buf_name)
  vim.bo.buflisted = false
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.git) %s', msg), 0) end

H.notify = function(msg, level_name) vim.notify('(mini.git) ' .. msg, vim.log.levels[level_name]) end

H.expandcmd = function(x)
  if x == '<cwd>' then return vim.fn.getcwd() end
  local ok, res = pcall(vim.fn.expandcmd, x)
  return ok and res or x
end

return MiniGit
