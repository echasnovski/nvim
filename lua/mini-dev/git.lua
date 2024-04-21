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
--         - Handle command targets: path, revision, ref. See
--           'command-list.txt' for possible automation which ones should be
--           used for particular command.
--
--     - Don't show output in the special buffer for some `git` commands,
--       use `H.notify(out, 'INFO')` instead. Like:
--         - `commit` (with its information about what was committed).
--         - `stash` (with its feedback).
--
-- - Blame functionality?
--
-- - Exported functionality to get file status/data based on an array of paths
--   alone? This maybe can be utilized by 'mini.files' to show Git status next
--   to the file.
--
-- Tests:
-- - Command:
--     - Completions:
--         - Some options are explicitly documented in both `--xxx` and
--           `--xxx=` forms:
--           `--[no-]signed, --signed=(true|false|if-asked)` or
--           `--[no-]force-with-lease, --force-with-lease=<refname>,
--           --force-with-lease=<refname>:<expect>` from `git push`.
--         - Single dash options can have more than one char: `git branch -vv`.
--
-- Docs:
-- - Command:
--     - Use `:Git -C <cwd>` to execute command in current working directory.
--     - How completions work: command, options, targets.
--     - Don't use quotes to make same value. Like `:Git commit -m 'Hello\ world'`
--       will result into commit message containing quotes.
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
    repo   = buf_cache.repo,   root        = buf_cache.root,
    head   = buf_cache.head,   head_name   = buf_cache.head_name,
    status = buf_cache.status, in_progress = buf_cache.in_progress,
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
-- - <status> - current file status.
-- - <in_progress> - string name of action in progress (bisect, merge, etc.)
H.cache = {}

-- Cache per repo (git directory) path. Values are tables with fields:
-- - <fs_event> - `vim.loop` event for watching repo dir.
-- - <timer> - timer to debounce repo changes.
-- - <buffers> - map of buffers which should are part of repo.
H.repos = {}

-- Termporary file used as config for `GIT_EDITOR`
H.git_editor_config = nil

-- Array of supported Git commands
H.git_supported_commands = nil

-- Map from supported Git command to string array of options command supports.
-- Option arrays are computed and cached lazily (if entry is not a table)
H.git_options = nil

-- Table with keys being commands which show something to user
H.git_info_commands = nil

-- Array of git subcommands which have subcommands themselves.
-- There appears to be no good way to lazily compute them.
H.git_subcommands = {}
--stylua: ignore start
local _add_subcmd = function(prefix, suffixes)
  for _, suf in ipairs(suffixes) do table.insert(H.git_subcommands, prefix .. ' ' .. suf) end
end
_add_subcmd('bundle',           { 'create', 'list-heads', 'unbundle', 'verify' })
_add_subcmd('bisect',           { 'bad', 'good', 'log', 'replay', 'reset', 'run', 'skip', 'start', 'terms', 'view', 'visualize' })
_add_subcmd('commit-graph',     { 'verify', 'write' })
_add_subcmd('maintenance',      { 'run', 'start', 'stop', 'register', 'unregister' })
_add_subcmd('multi-pack-index', { 'expire', 'repack', 'verify', 'write' })
_add_subcmd('notes',            { 'add', 'append', 'copy', 'edit', 'get-ref', 'list', 'merge', 'prune', 'remove', 'show' })
_add_subcmd('p4',               { 'clone', 'rebase', 'submit', 'sync' })
_add_subcmd('reflog',           { 'delete', 'exists', 'expire', 'show' })
_add_subcmd('remote',           { 'add', 'get-url', 'prune', 'remove', 'rename', 'rm', 'set-branches', 'set-head', 'set-url', 'show', 'update' })
_add_subcmd('rerere',           { 'clear', 'diff', 'forget', 'gc', 'remaining', 'status' })
_add_subcmd('sparse-checkout',  { 'add', 'check-rules', 'disable', 'init', 'list', 'reapply', 'set' })
_add_subcmd('stash',            { 'apply', 'branch', 'clear', 'create', 'drop', 'list', 'pop', 'save', 'show', 'store' })
_add_subcmd('submodule',        { 'absorbgitdirs', 'add', 'deinit', 'foreach', 'init', 'set-branch', 'set-url', 'status', 'summary', 'sync', 'update' })
_add_subcmd('subtree',          { 'add', 'merge', 'pull', 'push', 'split' })
_add_subcmd('worktree',         { 'add', 'list', 'lock', 'move', 'prune', 'remove', 'repair', 'unlock' })
--stylua: ignore end

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
    H.ensure_supported_git_commands()
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

      -- Show CLI stderr and stdout
      if H.cli_err_notify(code, out, err) then return end
      H.cli_show_output(out, input.mods, command)

      -- Ensure that repo data is up to date. This is not always taken care of
      -- by repo watching, like file status after `:Git commit` (probably due
      -- to `git status` still using old repo data).
      H.on_repo_change(repo)

      -- Ensure that all buffers are up to date (avoids "The file has been
      -- changed since reading it" warning)
      vim.tbl_map(function(buf_id) vim.cmd('checktime ' .. buf_id) end, vim.api.nvim_list_bufs())
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
  local command, command_end = nil, math.huge
  for _, cmd in pairs(H.git_supported_commands) do
    local _, ind = line:find(' ' .. cmd .. ' ', 1, true)
    if ind ~= nil and ind < command_end then
      command, command_end = cmd, ind
    end
  end

  command = command or 'git'

  -- Determine command candidates:
  -- - Commannd options if complete base starts with "-".
  -- - Git commands if there is none fully formed yet or cursor is at the end
  --   of the command (to also suggest subcommands).
  -- - Command targets specific for each command (if present).
  if vim.startswith(base, '-') then return H.command_get_complete_options(command) end
  if command_end == math.huge or (command_end - 1) == col then return H.git_supported_commands end
  return H.command_get_complete_targets(command, base)
end

H.ensure_supported_git_commands = function()
  if H.git_supported_commands ~= nil and H.git_options ~= nil and H.git_info_commands ~= nil then return end

  -- Compute all supported commands. All 'list-' are taken from Git source
  -- 'command-list.txt' file. Be so granular and not just `main,nohelpers` in
  -- order to not include purely man-page worthy items (like "remote-ext").
  --stylua: ignore
  local lists_all = {
    'list-mainporcelain',
    'list-ancillarymanipulators', 'list-ancillaryinterrogators',
    'list-foreignscminterface',
    'list-plumbingmanipulators', 'list-plumbinginterrogators',
    'others', 'alias',
  }
  local all_commands = H.cli_run({ 'git', '--list-cmds=' .. table.concat(lists_all, ',') }, vim.fn.getcwd()).out
  all_commands = vim.split(all_commands, '\n')
  table.sort(all_commands)
  H.git_supported_commands = all_commands

  -- Initialize cache for command options. Initialize with `false` so that
  -- actual candidates are computed lazily.
  H.git_options = { git = false }
  for _, command in ipairs(all_commands) do
    H.git_options[command] = false
  end

  -- Compute commands which are meant to show information. These will show CLI
  -- output in separate buffer opposed to `vim.notify`.
  local lists_info = 'list-info,list-ancillaryinterrogators,list-plumbinginterrogators'
  local info_commands = H.cli_run({ 'git', '--list-cmds=' .. lists_info }, vim.fn.getcwd()).out
  H.git_info_commands = {}
  for _, cmd in ipairs(vim.split(info_commands, '\n')) do
    H.git_info_commands[cmd] = true
  end
  H.git_info_commands.bisect = nil
end

H.command_get_complete_options = function(command)
  local cached_candidates = H.git_options[command]
  if cached_candidates == nil then return {} end
  if type(cached_candidates) == 'table' then return cached_candidates end

  local help_page = H.cli_run({ 'git', 'help', '--man', command }, vim.fn.getcwd())
  if help_page.code ~= 0 then return {} end

  -- Construct non-duplicating candidates by parsing lines of help page
  local candidates_map, lines = {}, vim.split(help_page.out, '\n')

  -- Find command's flag options. Assumed to be listed inside "OPTIONS" or "XXX
  -- OPTIONS" (like "MODE OPTIONS" of `git rebase`) section of help page on
  -- separate lines. Whether a line contains only options is determined
  -- heuristically: it is assumed to start exactly with "       -" indicating
  -- proper indent for subsection start.
  -- Known not parsable options:
  -- - `git reset <mode>` (--soft, --hard, etc.): not listed in "OPTIONS".
  -- - All -<number> options, as they are not really completeable.
  local is_in_options_section = false
  for _, l in ipairs(lines) do
    if is_in_options_section and l:find('^%u[%u ]+$') ~= nil then is_in_options_section = false end
    if not is_in_options_section and l:find('^%u?[%u ]*OPTIONS$') ~= nil then is_in_options_section = true end
    if is_in_options_section and l:find('^       %-') ~= nil then H.parse_options(candidates_map, l) end
  end

  -- Finalize candidates. Should not contain "almost duplicates".
  -- Should also be sorted by relevance: short options (start with "-") should
  -- go before regular options (start with "--"). Inside groups sort
  -- alphabetically ignoring case.
  candidates_map['--'] = nil
  for cmd, _ in pairs(candidates_map) do
    -- There can be two explicitly documented options "--xxx" and "--xxx=".
    -- Use only one of them (without "=").
    if cmd:sub(-1, -1) == '=' and candidates_map[cmd:sub(1, -2)] ~= nil then candidates_map[cmd] = nil end
  end

  local res = vim.tbl_keys(candidates_map)
  table.sort(res, function(a, b)
    local a2, b2 = a:sub(2, 2) == '-', b:sub(2, 2) == '-'
    if a2 and not b2 then return false end
    if not a2 and b2 then return true end
    local a_low, b_low = a:lower(), b:lower()
    return a_low < b_low or (a_low == b_low and a < b)
  end)

  -- Cache and return
  H.git_options[command] = res
  return res
end

H.parse_options = function(map, line)
  -- Options are standalone words starting as "-xxx" or "--xxx"
  -- Include possible "=" at the end indicating mandatory value
  line:gsub('%s(%-[-%w][-%w]*=?)', function(match) map[match] = true end)

  -- Make exceptions for commonly documented "--[no-]xxx" two options
  line:gsub('%s%-%-%[no%-%]([-%w]+=?)', function(match)
    map['--' .. match], map['--no-' .. match] = true, true
  end)
end

H.command_get_complete_targets = function(command, base)
  if command == 'help' then
    local res = { 'git' }
    vim.list_extend(res, H.git_supported_commands)
    return res
  end
  -- TODO
  return { 'target' }
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
      H.update_git_in_progress(buf_cache.repo, { buf_id })
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
    H.update_git_in_progress(repo, { buf_id })
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

  -- Update Git data
  H.update_git_in_progress(repo, vim.tbl_keys(repo_bufs))
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

H.update_git_in_progress = function(repo, bufs)
  -- Get data about what process is in progress
  local in_progress = {}
  if H.is_fs_present(repo .. '/BISECT_LOG') then table.insert(in_progress, 'bisect') end
  if H.is_fs_present(repo .. '/CHERRY_PICK_HEAD') then table.insert(in_progress, 'cherry-pick') end
  if H.is_fs_present(repo .. '/MERGE_HEAD') then table.insert(in_progress, 'merge') end
  if H.is_fs_present(repo .. '/REVERT_HEAD') then table.insert(in_progress, 'revert') end
  if H.is_fs_present(repo .. '/rebase-apply') then table.insert(in_progress, 'apply') end
  if H.is_fs_present(repo .. '/rebase-merge') then table.insert(in_progress, 'rebase') end

  -- Update data for all buffers from target `root`
  local new_data = { in_progress = table.concat(in_progress, ',') }
  for _, buf_id in ipairs(bufs) do
    H.update_buf_data(buf_id, new_data)
  end

  -- Redraw statusline to have possible statusline component up to date
  vim.cmd('redrawstatus')
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

H.cli_show_output = function(out, mods, git_command)
  if out == '' or mods:find('silent') ~= nil then return end

  -- Show in a buffer if command is for showing info; else - `vim.notify`
  local is_info = false
  for _, cmd in ipairs(git_command) do
    is_info = is_info or H.git_info_commands[cmd]
  end
  if not is_info then return H.notify(out, 'INFO') end

  -- Reuse same buffer
  local buf_id = H.output_buf_id
  if buf_id == nil or not vim.api.nvim_buf_is_valid(buf_id) then buf_id = vim.api.nvim_create_buf(false, true) end
  H.output_buf_id = buf_id

  -- Populate special buffer and make it up to date, and show in split
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, vim.split(out, '\n'))
  local buf_name = 'minigit:///' .. table.concat(git_command, ' ')
  vim.api.nvim_buf_set_name(buf_id, buf_name)
  local filetype = vim.filetype.match({ buf = buf_id })
  if filetype ~= nil then vim.bo[buf_id].filetype = filetype end

  -- Try reusing existing window to not create extra splits; split otherwise
  local win_id = vim.fn.bufwinid(buf_id)
  if win_id ~= -1 then
    vim.api.nvim_win_set_buf(win_id, buf_id)
  else
    vim.cmd(mods .. ' split ' .. buf_name)
    vim.wo.foldlevel = 999
    -- Set 'nobuflisted' after 'split' as it resets it to 'buflisted'
    vim.bo[buf_id].buflisted = false
  end
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.git) %s', msg), 0) end

H.notify = function(msg, level_name) vim.notify('(mini.git) ' .. msg, vim.log.levels[level_name]) end

H.is_fs_present = function(path) return vim.loop.fs_stat(path) ~= nil end

H.expandcmd = function(x)
  if x == '<cwd>' then return vim.fn.getcwd() end
  local ok, res = pcall(vim.fn.expandcmd, x)
  return ok and res or x
end

return MiniGit
