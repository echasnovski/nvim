-- TODO:
--
-- Code:
-- - Think about directly setting up HEAD data for new buffer if it was already
--   computed. Probably, requires separate `H.roots` cache.
--
-- - `refresh()` / `update()`. Either for buffer, root, or combination?
--
-- - Blame functionality.
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
--         - Should respect `\ ` in base.
-- - Diff source:
--     - Should work for when "before" source is not available (like when file
--       was just created).
--     - Should work when cursor is at the first hunk line and it is '-'
--       (target line should not be zero).
--
-- Docs:
-- - Useful examples:
--     - Use `:Git -C <cwd>` to execute command in current working directory.
--     - Use `:vert Git show <cword>` to show word under cursor in a split
--       (like commit, branch, etc.).
--
-- - Command:
--     - How completions work: command, options, targets.
--     - Don't use quotes to make same value. Like `:Git commit -m 'Hello\ world'`
--       will result into commit message containing quotes.
--     - Use |:cabbrev| to set default modifiers. Lik `cabbrev Git vert Git`.
--     - Triggers `MiniGitCommandDone` `User` event when done.

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
  },

  command = {
    split = 'vertical',
  },
}
--minidoc_afterlines_end

-- NOTEs:
-- - Relies on `:Git command`.
-- - Needs a valid Git patch entry with unified diff preceded by commit
--   information. Like in `:Git log`.
-- - Needs cwd to be the Git root for relative paths to work.
MiniGit.show_diff_source = function(opts)
  opts = vim.tbl_deep_extend('force', { split = 'tab', target = 'after' }, opts or {})
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local src = H.diff_pos_to_source(lines, lnum)
  if src == nil then
    return H.notify('Could not find diff source. Ensure that cursor is inside a valid diff hunk of git log.', 'WARN')
  end

  H.validate_split_value(opts.split, 'opts.split')
  if not (opts.target == 'before' or opts.target == 'after' or opts.target == 'both') then
    H.error('`opts.target` should be one of "before", "after", "both".')
  end

  if opts.target ~= 'after' and src.path_before ~= nil then
    local before_cmd = string.format('%s Git show %s:%s', opts.split, src.commit_before, src.path_before)
    vim.cmd(before_cmd)
    vim.api.nvim_win_set_cursor(0, { src.lnum_before, 0 })
  end

  if opts.target ~= 'before' then
    local mods_after = opts.target == 'after' and opts.split or 'belowright vertical'
    local after_cmd = string.format('%s Git show %s:%s', mods_after, src.commit_after, src.path_after)
    vim.cmd(after_cmd)
    vim.api.nvim_win_set_cursor(0, { src.lnum_after, 0 })
  end
end

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
  -- Define editor state before and after editing path
  H.skip_timeout, H.skip_sync = true, true
  local cleanup = function()
    local _, channel = pcall(vim.fn.sockconnect, 'pipe', servername, { rpc = true })
    pcall(vim.rpcnotify, channel, 'nvim_exec2', 'quitall!', {})
    H.skip_timeout, H.skip_sync = false, false
  end

  -- Start file edit with proper modifiers in a special window
  if not H.mods_is_split(mods) then mods = MiniGit.config.command.split .. ' ' .. mods end
  vim.cmd(mods .. ' split ' .. vim.fn.fnameescape(path))
  H.define_minigit_window(cleanup)
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

-- Data about supported Git subcommands. Initialized lazily. Fields:
-- - <supported> - array of supported one word commands.
-- - <complete> - array of commands to complete directly after `:Git`.
-- - <info> - map with fields as commands which show something to user.
-- - <options> - map of cached options per command; initialized lazily.
H.git_subcommands = nil

-- Whether to temporarily skip some checks (like when inside `GIT_EDITOR`)
H.skip_timeout = false
H.skip_sync = false

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  vim.validate({
    job = { config.job, 'table' },
    command = { config.command, 'table' },
  })

  vim.validate({
    ['job.git_executable'] = { config.job.git_executable, 'string' },
    ['job.timeout'] = { config.job.timeout, 'number' },
    ['command.split'] = { config.command.split, function(x) return H.validate_split_value(x, 'command.split') end, '' },
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
    H.ensure_git_subcommands()
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
    local repo, root = H.command_get_cwd_data()

    local is_done = false
    local on_done = vim.schedule_wrap(function(code, out, err)
      -- Register that command is done executing
      is_done = true
      vim.api.nvim_exec_autocmds('User', { pattern = 'MiniGitCommandDone' })

      -- Show CLI stderr and stdout
      if H.cli_err_notify(code, out, err) then return end
      H.show_git_cli_output(out, input.mods, command)

      -- Ensure that repo data is up to date. This is not always taken care of
      -- by repo watching, like file status after `:Git commit` (probably due
      -- to `git status` still using old repo data).
      H.on_repo_change(repo)

      -- Ensure that all buffers are up to date (avoids "The file has been
      -- changed since reading it" warning)
      vim.tbl_map(function(buf_id) vim.cmd('checktime ' .. buf_id) end, vim.api.nvim_list_bufs())
    end)

    H.cli_run(command, root, on_done, { env = env })

    -- If needed, synchronously wait for job to finish
    local sync_check = function() return H.skip_sync or is_done end
    if not input.bang then vim.wait(MiniGit.config.job.timeout + 10, sync_check, 1) end
  end

  local opts = { bang = true, nargs = '+', complete = H.command_complete, desc = 'Execute Git command' }
  vim.api.nvim_create_user_command('Git', git_execute, opts)
end

-- Command --------------------------------------------------------------------
--stylua: ignore
H.ensure_git_subcommands = function()
  if H.git_subcommands ~= nil then return end
  local git_subcommands = {}

  -- Compute all supported commands. All 'list-' are taken from Git source
  -- 'command-list.txt' file. Be so granular and not just `main,nohelpers` in
  -- order to not include purely man-page worthy items (like "remote-ext").
  local lists_all = {
    'list-mainporcelain',
    'list-ancillarymanipulators', 'list-ancillaryinterrogators',
    'list-foreignscminterface',
    'list-plumbingmanipulators', 'list-plumbinginterrogators',
    'others', 'alias',
  }
  local supported = H.git_cli_output({ '--list-cmds=' .. table.concat(lists_all, ',') })
  if #supported == 0 then
    -- Fall back only on basics if previous one failed for some reason
    supported = {
      'add', 'bisect', 'branch', 'clone', 'commit', 'diff', 'fetch', 'grep', 'init', 'log', 'merge',
      'mv', 'pull', 'push', 'rebase', 'reset', 'restore', 'rm', 'show', 'status', 'switch', 'tag',
    }
  end
  table.sort(supported)
  git_subcommands.supported = supported

  -- Compute complete list for commands by enhancing with two word commands.
  -- Keep those lists manual as there is no good way to compute lazily.
  local complete = vim.deepcopy(supported)
  local add_twoword = function(prefix, suffixes)
    for _, suf in ipairs(suffixes) do table.insert(complete, prefix .. ' ' .. suf) end
  end
  add_twoword('bundle',           { 'create', 'list-heads', 'unbundle', 'verify' })
  add_twoword('bisect',           { 'bad', 'good', 'log', 'replay', 'reset', 'run', 'skip', 'start', 'terms', 'view', 'visualize' })
  add_twoword('commit-graph',     { 'verify', 'write' })
  add_twoword('maintenance',      { 'run', 'start', 'stop', 'register', 'unregister' })
  add_twoword('multi-pack-index', { 'expire', 'repack', 'verify', 'write' })
  add_twoword('notes',            { 'add', 'append', 'copy', 'edit', 'get-ref', 'list', 'merge', 'prune', 'remove', 'show' })
  add_twoword('p4',               { 'clone', 'rebase', 'submit', 'sync' })
  add_twoword('reflog',           { 'delete', 'exists', 'expire', 'show' })
  add_twoword('remote',           { 'add', 'get-url', 'prune', 'remove', 'rename', 'rm', 'set-branches', 'set-head', 'set-url', 'show', 'update' })
  add_twoword('rerere',           { 'clear', 'diff', 'forget', 'gc', 'remaining', 'status' })
  add_twoword('sparse-checkout',  { 'add', 'check-rules', 'disable', 'init', 'list', 'reapply', 'set' })
  add_twoword('stash',            { 'apply', 'branch', 'clear', 'create', 'drop', 'list', 'pop', 'save', 'show', 'store' })
  add_twoword('submodule',        { 'absorbgitdirs', 'add', 'deinit', 'foreach', 'init', 'set-branch', 'set-url', 'status', 'summary', 'sync', 'update' })
  add_twoword('subtree',          { 'add', 'merge', 'pull', 'push', 'split' })
  add_twoword('worktree',         { 'add', 'list', 'lock', 'move', 'prune', 'remove', 'repair', 'unlock' })
  git_subcommands.complete = complete

  -- Compute commands which are meant to show information. These will show CLI
  -- output in separate buffer opposed to `vim.notify`.
  local info_args = { '--list-cmds=list-info,list-ancillaryinterrogators,list-plumbinginterrogators' }
  local info_commands = H.git_cli_output(info_args)
  if #info_commands == 0 then info_commands = { 'bisect', 'diff', 'grep', 'log', 'show', 'status' } end
  local info = {}
  for _, cmd in ipairs(info_commands) do
    info[cmd] = true
  end
  git_subcommands.info = info

  -- Initialize cache for command options. Initialize with `false` so that
  -- actual values are computed lazily when needed for a command.
  local options = { git = false }
  for _, command in ipairs(supported) do
    options[command] = false
  end
  git_subcommands.options = options

  -- Cache results
  H.git_subcommands = git_subcommands
end

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

H.command_get_cwd_data = function()
  local buf_cache = H.cache[vim.api.nvim_get_current_buf()] or {}
  local repo, root = buf_cache.repo or vim.fn.getcwd(), buf_cache.root or vim.fn.getcwd()
  return repo, root
end

H.command_complete = function(_, line, col)
  -- Compute completion base manually to be "at cursor" and respect `\ `
  local base = H.get_complete_base(line:sub(1, col))
  local candidates, compl_type = H.command_get_complete_candidates(line, col, base)
  -- Allow several "//" at the end for path completion for easier "chaining"
  if compl_type == 'path' then base = base:gsub('/+$', '/') end
  return vim.tbl_filter(function(x) return vim.startswith(x, base) end, candidates)
end

H.get_complete_base = function(line)
  local from, _, res = line:find('(%S*)$')
  while from ~= nil do
    local cur_from, _, cur_res = line:sub(1, from - 1):find('(%S*\\ )$')
    if cur_res ~= nil then res = cur_res .. res end
    from = cur_from
  end
  return (res:gsub([[\ ]], ' '))
end

H.command_get_complete_candidates = function(line, col, base)
  H.ensure_git_subcommands()

  -- Determine current Git command as the earliest present supported command
  local command, command_end = nil, math.huge
  for _, cmd in pairs(H.git_subcommands.supported) do
    local _, ind = line:find(' ' .. cmd .. ' ', 1, true)
    if ind ~= nil and ind < command_end then
      command, command_end = cmd, ind
    end
  end

  command = command or 'git'
  local _, cwd = H.command_get_cwd_data()

  -- Determine command candidates:
  -- - Commannd options if complete base starts with "-".
  -- - Git commands if there is none fully formed yet or cursor is at the end
  --   of the command (to also suggest subcommands).
  -- - Command targets specific for each command (if present).
  if vim.startswith(base, '-') then return H.command_complete_option(command) end
  if command_end == math.huge or (command_end - 1) == col then return H.git_subcommands.complete, 'subcommand' end
  if line:sub(1, col):find(' -- ') ~= nil then return H.command_complete_path(cwd, base) end

  local complete_targets = H.command_complete_subcommand_targets[command]
  if complete_targets == nil then return {}, nil end
  return complete_targets(cwd, base, line)
end

H.command_complete_option = function(command)
  local cached_candidates = H.git_subcommands.options[command]
  if cached_candidates == nil then return {} end
  if type(cached_candidates) == 'table' then return cached_candidates end

  -- Find command's flag options by parsing its help page. Needs a bit
  -- heuristic approach, but seems to work good enough.
  -- Alternative is to call command with `--git-completion-helper-all` flag (as
  -- is done in bash and vim-fugitive completion). This has both pros and cons:
  -- - Pros: faster; more targeted suggestions (like for two word subcommands);
  --         presumably more reliable.
  -- - Cons: works on smaller number of commands (for example, `rev-parse` or
  --         pure `git` do not work); does not provide single dash suggestions;
  --         does not work when not inside Git repo; needs recognizing two word
  --         commands before asking for completion.
  local lines = H.git_cli_output({ 'help', '--man', command })
  -- - Exit early before caching to try again later
  if #lines == 0 then return {} end

  -- Construct non-duplicating candidates by parsing lines of help page
  local candidates_map = {}

  -- Options are assumed to be listed inside "OPTIONS" or "XXX OPTIONS" (like
  -- "MODE OPTIONS" of `git rebase`) section on dedicated lines. Whether a line
  -- contains only options is determined heuristically: it is assumed to start
  -- exactly with "       -" indicating proper indent for subsection start.
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
  H.git_subcommands.options[command] = res
  return res, 'option'
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

H.command_complete_path = function(cwd, base)
  -- Treat base only as path relative to the command's cwd
  cwd = cwd:gsub('/+$', '') .. '/'
  local cwd_len = cwd:len()

  -- List elements from (absolute) target directory
  local target_dir = vim.fn.fnamemodify(base, ':h')
  target_dir = (cwd .. target_dir:gsub('^%.$', '')):gsub('/+$', '') .. '/'
  local ok, fs_entries = pcall(vim.fn.readdir, target_dir)
  if not ok then return {} end

  -- List directories and files separately
  local dirs, files = {}, {}
  for _, entry in ipairs(fs_entries) do
    local entry_abs = target_dir .. entry
    local arr = vim.fn.isdirectory(entry_abs) == 1 and dirs or files
    table.insert(arr, entry_abs)
  end
  dirs = vim.tbl_map(function(x) return x .. '/' end, dirs)

  -- List ordered directories first followed by ordered files
  local order_ignore_case = function(a, b) return a:lower() < b:lower() end
  table.sort(dirs, order_ignore_case)
  table.sort(files, order_ignore_case)

  -- Return candidates relative to command's cwd
  local all = dirs
  vim.list_extend(all, files)
  local res = vim.tbl_map(function(x) return x:sub(cwd_len + 1) end, all)
  return res, 'path'
end

H.command_complete_pullpush = function(cwd, _, line)
  -- Suggest remotes at `Git push |` and `Git push or|`, references otherwise
  -- Ignore options when deciding which suggestion to compute
  local _, n_words = line:gsub(' (%-%S+)', ''):gsub('%S+ ', '')
  if n_words <= 2 then return H.git_cli_output({ 'remote' }, cwd), 'remote' end
  return H.git_cli_output({ 'rev-parse', '--symbolic', '--branches', '--tags' }, cwd), 'ref'
end

H.git_cli_output = function(args, cwd)
  local command = { MiniGit.config.job.git_executable, unpack(args) }
  local res = H.cli_run(command, cwd).out
  if res == '' then return {} end
  return vim.split(res, '\n')
end

H.make_git_cli_complete = function(args, complete_type)
  return function(cwd, _) return H.git_cli_output(args, cwd), complete_type end
end

-- Cover at least all subcommands listed in `git help`
--stylua: ignore
H.command_complete_subcommand_targets = {
  -- clone - no targets
  -- init  - no targets

  -- Worktree
  add     = H.command_complete_path,
  mv      = H.command_complete_path,
  restore = H.command_complete_path,
  rm      = H.command_complete_path,

  -- Examine history
  -- bisect - no targets
  diff = H.command_complete_path,
  grep = H.command_complete_path,
  log  = H.make_git_cli_complete({ 'rev-parse', '--symbolic', '--branches', '--tags' }, 'ref'),
  show = H.make_git_cli_complete({ 'rev-parse', '--symbolic', '--branches', '--tags' }, 'ref'),
  -- status - no targets

  -- Modify history
  branch = H.make_git_cli_complete({ 'rev-parse', '--symbolic', '--branches' },           'branch'),
  commit = H.command_complete_path,
  merge  = H.make_git_cli_complete({ 'rev-parse', '--symbolic', '--branches' },           'branch'),
  rebase = H.make_git_cli_complete({ 'rev-parse', '--symbolic', '--branches' },           'branch'),
  reset  = H.make_git_cli_complete({ 'rev-parse', '--symbolic', '--branches', '--tags' }, 'ref'),
  switch = H.make_git_cli_complete({ 'rev-parse', '--symbolic', '--branches' },           'branch'),
  tag    = H.make_git_cli_complete({ 'rev-parse', '--symbolic', '--tags' },               'tag'),

  -- Collaborate
  fetch = H.make_git_cli_complete({ 'remote' }, 'remote'),
  push = H.command_complete_pullpush,
  pull = H.command_complete_pullpush,

  -- Miscellaneous
  checkout = H.make_git_cli_complete({ 'rev-parse', '--symbolic', '--branches', '--tags', '--remotes' }, 'checkout'),
  config = H.make_git_cli_complete({ 'help', '--config-for-completion' }, 'config'),
  help = function()
    local res = { 'git', 'everyday' }
    vim.list_extend(res, H.git_subcommands.supported)
    return res, 'help'
  end,
}

H.mods_is_split = function(mods)
  return mods:find('vertical') ~= nil or mods:find('horizontal') ~= nil or mods:find('tab') ~= nil
end

-- Show command output --------------------------------------------------------
H.show_git_cli_output = function(out, mods, git_command)
  if out == '' or mods:find('silent') ~= nil then return end

  -- Show in a buffer if command is for showing info; else - `vim.notify`
  local is_info = false
  for _, cmd in ipairs(git_command) do
    is_info = is_info or H.git_subcommands.info[cmd]
  end
  if not is_info then return H.notify(out, 'INFO') end

  -- Populate special buffer in a window and make them current
  local buf_id, win_id = H.make_minigit_bufwin(mods)

  local cur_name = vim.api.nvim_buf_get_name(buf_id)
  local new_name = 'minigit://' .. buf_id .. '/' .. table.concat(git_command, ' ')
  vim.api.nvim_buf_set_name(buf_id, new_name)
  -- - Do not leave unlisted buffers when doing actual rename
  if cur_name ~= '' and cur_name ~= new_name then pcall(vim.cmd, 'bwipeout ' .. vim.fn.fnameescape(cur_name)) end

  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, vim.split(out, '\n'))
  local filetype = vim.filetype.match({ buf = buf_id })
  if filetype ~= nil then vim.bo[buf_id].filetype = filetype end

  vim.api.nvim_set_current_win(win_id)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
end

H.make_minigit_bufwin = function(mods)
  local split = function()
    local buf_id = vim.api.nvim_create_buf(false, true)
    vim.cmd(mods .. ' sbuffer ' .. buf_id)
    local win_id = vim.api.nvim_get_current_win()
    H.define_minigit_window()
    return buf_id, win_id
  end

  -- Force split of there are split command modifiers (intentionally omit rest)
  if H.mods_is_split(mods) then return split() end
  mods = MiniGit.config.command.split .. ' ' .. mods

  -- Try reusing already shown buffer-window pair
  for _, win_id in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local win_buf_id = vim.api.nvim_win_get_buf(win_id)
    local win_buf_name = vim.api.nvim_buf_get_name(win_buf_id)
    local minigit_buf_type = win_buf_name:match('^minigit://%d+/(%S+)')
    if minigit_buf_type ~= nil and minigit_buf_type ~= 'blame' then return win_buf_id, win_id end
  end

  return split()
end

H.define_minigit_window = function(cleanup)
  local buf_id, win_id = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  vim.bo.swapfile, vim.bo.buflisted = false, false
  vim.wo.foldlevel = 999

  -- Define action to finish editing Git related file
  local finish_au_id
  local finish = function(data)
    local should_close = data.buf == buf_id or (data.event == 'WinClosed' and tonumber(data.match) == win_id)
    if not should_close then return end

    if vim.is_callable(cleanup) then cleanup() end

    pcall(vim.api.nvim_del_autocmd, finish_au_id)
    pcall(vim.api.nvim_buf_delete, buf_id, { force = true })
    pcall(vim.api.nvim_win_close, win_id, true)
    vim.cmd('redraw')
  end
  -- - Use `nested` to allow other events (`WinEnter` for 'mini.statusline')
  local events = { 'WinClosed', 'BufDelete', 'BufWipeout', 'VimLeave' }
  local opts = { nested = true, callback = finish, desc = 'Cleanup window and buffer' }
  finish_au_id = vim.api.nvim_create_autocmd(events, opts)
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

H.validate_split_value = function(x, x_name)
  if x == 'horizontal' or x == 'vertical' or x == 'tab' then return true end
  H.error('`' .. x_name .. '` should be one of "horizontal", "vertical", "tab"')
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

-- History navigation ---------------------------------------------------------
H.diff_pos_to_source = function(lines, lnum)
  -- Assuming lines of unified combined diff, compute path and line number of
  -- both "before" and "after", plus target commit (corresponding to "after")
  local cur_lnum, offsets = lnum, { [' '] = 0, ['-'] = 0, ['+'] = 0 }
  while cur_lnum > 0 do
    local prefix = lines[cur_lnum]:sub(1, 1)
    if not (prefix == ' ' or prefix == '-' or prefix == '+') then break end
    offsets[prefix] = offsets[prefix] + 1
    cur_lnum = cur_lnum - 1
  end
  local hunk_start_before, hunk_start_after = string.match(lines[cur_lnum], '^@@ %-(%d+),?%d* %+(%d+),?%d* @@')
  if hunk_start_before == nil or cur_lnum <= 2 then return nil end

  -- Compute hunk's relative paths
  local path_after
  while cur_lnum > 0 do
    local path = string.match(lines[cur_lnum], '^%+%+%+ b/(.*)$')
    if path ~= nil then
      path_after = path
      break
    end
    cur_lnum = cur_lnum - 1
  end
  local path_before = string.match(lines[cur_lnum - 1], '^%-%-%- a/(.*)$')
  if path_after == nil then return nil end

  -- Try computing commit assuming at least `git log --pretty=short`
  local commit
  while cur_lnum > 0 do
    local try_commit = string.match(lines[cur_lnum], '^commit (%x+)$')
    if try_commit ~= nil then
      commit = try_commit
      break
    end
    cur_lnum = cur_lnum - 1
  end
  if commit == nil then return nil end

  return {
    lnum_before = math.max(1, tonumber(hunk_start_before) + offsets[' '] + offsets['-'] - 1),
    path_before = path_before,
    lnum_after = math.max(1, tonumber(hunk_start_after) + offsets[' '] + offsets['+'] - 1),
    path_after = path_after,
    commit_before = commit .. '~',
    commit_after = commit,
  }
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
  spawn_opts.args, spawn_opts.cwd, spawn_opts.stdio = args, cwd or vim.fn.getcwd(), { nil, stdout, stderr }

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
