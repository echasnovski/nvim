-- TODO:
--
-- Code:
-- - Allow empty string for both `file` and `cwd` (meaning "all available") in
--   all their usage.
--
-- FIXME: READ THIS!
-- - Think about how to mitigate several opened Neovim instances using same
--   visit index. Ideas:
--     - Do not account for them at all, i.e. "last written wins". To make it
--       less visible, delay reading from stored file as much as possible, i.e.
--       read only when needed (`register` and `add_flag` does not need;
--       `remove_flag` does, though).
--
--       As a side effect of this approach, it seems better to remove the
--       notion of "scope" altogether. There doesn't seem to be much use cases
--       for "previous", while "current" can be emulated with having cutoff by
--       "latest" (?maybe even store initial time of loading?).
--
--     - Try to account for it by always having separate "previous" and
--       "current" indexes while allowing to manually (or automatically?)
--       update to the latest data.
--       This gets tedious when trying to account for anything outside of
--       "count" and "latest", i.e. "flags" and user data. For example,
--       removing flags properly is pretty much imposible here (as it implies
--       persistent modification of flags).
--
--       Another idea to allow this is to treat flags as not persistent and
--       only for current session.
--
-- - Implement `goto` ("next", "previous", "first", "last") with custom
--   `filter` and `sort`.
--
-- Tests:
-- - All combinations of empty/nonempty + file/cwd work for all cases.
--
-- Docs:

--- *mini.visits* Track and reuse file visits
--- *MiniVisits*
---
--- MIT License Copyright (c) 2023 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Features:
---
--- - Persistently track file visits per working directory. Stored visit index is
---   human readable and editable.
---
--- - Configurable automated visit register logic:
---     - On user-defined event.
---     - After staying in same file for user-defined amount of time.
---
--- - Function to list files based on visit index with custom filter and sort
---   (uses "frecency" by default). Can be used as source for various pickers.
---
--- - Wrappers for |vim.ui.select()| to select files or marks.
---   See |MiniVisits.select_files()| and |MiniVisits.select_marks()|.
---
--- - ??? Customizable index data ???.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.visits').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniVisits`
--- which you can use for scripting or manually (with `:lua MiniVisits.*`).
---
--- See |MiniVisits.config| for `config` structure and default values.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.minivisits_config` which should have same structure as
--- `MiniVisits.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons ~
---
--- - 'nvim-telescope/telescope-frecency.nvim':
---
--- - 'ThePrimeagen/harpoon':
---
--- # Disabling ~
---
--- To disable automated tracking, set `vim.g.minivisits_disable` (globally) or
--- `vim.b.minivisits_disable` (for a buffer) to `true`. Considering high
--- number of different scenarios and customization intentions, writing exact
--- rules for disabling module's functionality is left to user. See
--- |mini.nvim-disabling-recipes| for common recipes.

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local
---@diagnostic disable:cast-local-type
---@diagnostic disable:undefined-doc-name
---@diagnostic disable:luadoc-miss-type-name

-- Module definition ==========================================================
MiniVisits = {}
H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniVisits.config|.
---
---@usage `require('mini.visits').setup({})` (replace `{}` with your `config` table).
MiniVisits.setup = function(config)
  -- Export module
  _G.MiniVisits = MiniVisits

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands(config)
end

--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniVisits.config = {
  -- How visit file index is converted to list of files
  list = {
    -- Predicate for which files to include
    filter = nil,

    -- Sort files based on their visit data
    sort = nil,
  },

  -- How visit registering is done
  register = {
    -- Start visit register timer at this event
    -- Supply empty string (`''`) to not create this automatically
    event = 'BufEnter',

    -- Debounce delay after event to register a visit
    -- TODO: Change to 1000
    delay = 1,
  },

  -- How visit index is stored
  store = {
    -- Whether to write all visits before Neovim is closed
    autowrite = true,

    -- Function to ensure that written index is relevant
    normalize = nil,

    -- Path to store visit index
    path = vim.fn.stdpath('data') .. '/mini-visits-index',
  },
}
--minidoc_afterlines_end

MiniVisits.register = function(file, cwd)
  file = H.validate_file(file)
  cwd = H.validate_cwd(cwd)
  if file == '' or cwd == '' then H.error('Both `file` and `cwd` should not be empty.') end

  H.ensure_current_index_entry(file, cwd)
  local file_tbl = H.index.current[cwd][file]
  file_tbl.count = file_tbl.count + 1
  file_tbl.latest = os.time()
end

MiniVisits.add_flag = function(flag, file, cwd)
  flag = flag or vim.fn.input('Enter flag to add: ')
  flag = H.validate_string(flag, 'flag')
  file = H.validate_file(file, true)
  cwd = H.validate_cwd(cwd, true)
  H.ensure_current_index_entry(file, cwd)

  local file_tbl = H.index.current[cwd][file]
  local flags = file_tbl.flags or {}
  flags[flag] = true
  file_tbl.flags = flags
end

MiniVisits.remove_flag = function(flag, file, cwd)
  flag = flag or vim.fn.input('Enter flag to remove: ')
  flag = H.validate_string(flag, 'flag')
  file = H.validate_file(file, true)
  cwd = H.validate_cwd(cwd, true)
  H.ensure_current_index_entry(file, cwd)

  local file_tbl = H.index.current[cwd][file]
  local flags = file_tbl.flags
  if type(flags) ~= 'table' then return end

  flags[flag] = nil
  if vim.tbl_count(flags) == 0 then file_tbl.flags = nil end
end

MiniVisits.list_files = function(cwd, opts)
  cwd = H.validate_cwd(cwd, false)

  opts = vim.tbl_deep_extend('force', { scope = 'all', filter = nil, sort = nil }, opts or {})
  local scope = H.validate_scope(opts.scope)
  local filter = H.validate_filter(opts.filter)
  local sort = H.validate_sort(opts.sort)

  local file_data_arr = H.get_file_data_arr(cwd, scope)
  local res_arr = sort(vim.tbl_filter(filter, file_data_arr))
  return vim.tbl_map(function(x) return x.path end, res_arr)
end

MiniVisits.list_flags = function(cwd, opts)
  cwd = H.validate_cwd(cwd, false)

  opts = vim.tbl_deep_extend('force', { scope = 'all', filter = nil }, opts or {})
  local scope = H.validate_scope(opts.scope)
  local filter = H.validate_filter(opts.filter)

  local file_data_arr = H.get_file_data_arr(cwd, scope)
  local res_arr = vim.tbl_filter(filter, file_data_arr)

  local all_flags = {}
  for _, file_data in ipairs(res_arr) do
    if type(file_data.flags) == 'table' then
      for flag, _ in pairs(file_data.flags) do
        all_flags[flag] = true
      end
    end
  end
  local res = vim.tbl_keys(all_flags)
  table.sort(res)
  return res
end

MiniVisits.select_files = function(cwd, opts)
  local files = MiniVisits.list_files(cwd, opts)
  local items = vim.tbl_map(function(path) return { path = path, text = H.short_path(path, cwd) } end, files)
  local select_opts = { prompt = 'Files from visits', format_item = function(item) return item.text end }
  local on_choice = function(item)
    if item == nil then return end
    pcall(vim.cmd, 'edit ' .. vim.fn.fnameescape(item.path))
  end

  vim.ui.select(items, select_opts, on_choice)
end

MiniVisits.select_flags = function(cwd, opts)
  local flags = MiniVisits.list_flags(cwd, opts)
  opts = opts or {}
  local on_choice = function(flag)
    if flag == nil then return end

    -- Select among subset of files with chosen flag
    local filter_cur = (opts or {}).filter or MiniVisits.gen_filter.default()
    local new_opts = vim.deepcopy(opts)
    new_opts.filter = function(file_data)
      return filter_cur(file_data) and type(file_data.flags) == 'table' and file_data.flags[flag]
    end
    MiniVisits.select_files(cwd, new_opts)
  end

  vim.ui.select(flags, { prompt = 'Flags from visits' }, on_choice)
end

MiniVisits.get = function(scope)
  scope = scope or 'all'
  H.validate_scope(scope)

  if scope == 'current' or scope == 'previous' then return H.index[scope] end
  return H.get_all_index()
end

MiniVisits.set = function(scope, index)
  scope = scope or 'all'
  H.validate_scope(scope)
  H.validate_index(index, '`index`')

  if scope == 'current' or scope == 'previous' then H.index[scope] = index end
  if scope == 'all' then
    H.index.previous, H.index.current = {}, index
  end
end

MiniVisits.read = function(path)
  path = path or H.get_config().store.path
  H.validate_string(path, 'path', true)
  if vim.fn.filereadable(path) == 0 then return nil end

  local ok, res = pcall(dofile, path)
  if not ok then return nil end
  return res
end

MiniVisits.write = function(path, index)
  local store_config = H.get_config().store
  path = path or store_config.path
  H.validate_string(path, 'path', true)
  index = index or H.get_all_index()
  H.validate_index(index, '`index`')

  -- Normalize index
  local normalize = vim.is_callable(store_config.normalize) and store_config.normalize or MiniVisits.default_normalize
  index = normalize(index)
  H.validate_index(index, 'normalized `index`')

  -- Ensure writable path
  path = vim.fn.fnamemodify(path, ':p')
  local path_dir = vim.fn.fnamemodify(path, ':h')
  vim.fn.mkdir(path_dir, 'p')

  -- Write
  local lines = vim.split(vim.inspect(index), '\n')
  lines[1] = 'return ' .. lines[1]
  vim.fn.writefile(lines, path)

  -- Set written index (to make normalized index current)
  MiniVisits.set('all', index)
end

MiniVisits.gen_filter = {}

MiniVisits.gen_filter.default = function()
  return function(file_data) return true end
end

MiniVisits.gen_sort = {}

MiniVisits.gen_sort.default = function(opts)
  opts = vim.tbl_deep_extend('force', { recency_weight = 0.5 }, opts or {})
  local recency_weight = opts.recency_weight
  local is_weight = type(recency_weight) == 'number' and 0 <= recency_weight and recency_weight <= 1
  if not is_weight then H.error('`opts.recency_weight` should be number between 0 and 1.') end

  return function(file_data_arr)
    -- Add ranks for `count` and `latest`
    table.sort(file_data_arr, function(a, b) return a.count > b.count end)
    H.add_rank(file_data_arr, 'count')
    table.sort(file_data_arr, function(a, b) return a.latest > b.latest end)
    H.add_rank(file_data_arr, 'latest')

    -- Compute final rank and sort by it
    for _, file_data in ipairs(file_data_arr) do
      file_data.rank = (1 - recency_weight) * file_data.count_rank + recency_weight * file_data.latest_rank
    end
    table.sort(file_data_arr, function(a, b) return a.rank < b.rank or (a.rank == b.rank and a.path < b.path) end)
    return file_data_arr
  end
end

MiniVisits.gen_sort.z = function()
  return function(file_data_arr)
    local now = os.time()
    for _, file_data in ipairs(file_data_arr) do
      -- Source: https://github.com/rupa/z/blob/master/z.sh#L151
      local dtime = math.max(now - file_data.latest, 0.0001)
      file_data.z = 10000 * file_data.count * (3.75 / ((0.0001 * dtime + 1) + 0.25))
    end
    table.sort(file_data_arr, function(a, b) return a.z > b.z or (a.z == b.z and a.path < b.path) end)
    return file_data_arr
  end
end

MiniVisits.default_normalize = function(index, opts)
  H.validate_index(index)
  local default_opts = { decay_threshold = 50, decay_target = 45, prune_threshold = 0.5, prune_non_paths = false }
  opts = vim.tbl_deep_extend('force', default_opts, opts or {})

  local res = vim.deepcopy(index)
  H.index_prune(res, opts.prune_non_paths, opts.prune_threshold)
  for cwd, cwd_tbl in pairs(res) do
    H.index_decay_cwd(cwd_tbl, opts.decay_threshold, opts.decay_target)
  end
  -- Ensure that no file has count smaller than threshold
  H.index_prune(res, false, opts.prune_threshold)
  return res
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniVisits.config

-- Various timers
H.timers = {
  register = vim.loop.new_timer(),
}

-- Visit index for current and previous sessions
H.index = {
  previous = nil,
  current = {},
}

-- Various cache
H.cache = {}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  vim.validate({
    list = { config.list, 'table' },
    register = { config.register, 'table' },
    store = { config.store, 'table' },
  })

  vim.validate({
    ['list.filter'] = { config.list.filter, 'function', true },
    ['list.sort'] = { config.list.sort, 'function', true },

    ['register.delay'] = { config.register.delay, 'number' },
    ['register.event'] = { config.register.event, 'string' },

    ['store.autowrite'] = { config.store.autowrite, 'boolean' },
    ['store.normalize'] = { config.store.normalize, 'function', true },
    ['store.path'] = { config.store.path, 'string' },
  })

  return config
end

H.apply_config = function(config) MiniVisits.config = config end

H.create_autocommands = function(config)
  local augroup = vim.api.nvim_create_augroup('MiniVisits', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = augroup, pattern = pattern, callback = callback, desc = desc })
  end

  if config.register.event ~= '' then au(config.register.event, '*', H.autoregister_visit, 'Auto register visit') end
  if config.store.autowrite then
    au('VimLeavePre', '*', function() pcall(MiniVisits.write) end, 'Autowrite visit index')
  end
end

H.is_disabled = function() return vim.g.minivisits_disable == true or vim.b.minivisits_disable == true end

H.get_config = function(config, buf_id)
  return vim.tbl_deep_extend('force', MiniVisits.config, vim.b.minivisits_config or {}, config or {})
end

-- Autocommands ---------------------------------------------------------------
H.autoregister_visit = function(data)
  H.timers.register:stop()
  if H.is_disabled() then return end

  local buf_id = data.buf
  local f = vim.schedule_wrap(function()
    -- Register only normal file if it is not the latest registered (avoids
    -- tracking visits from switching between normal and non-normal buffers)
    local file = H.buf_get_file(buf_id)
    if file == nil or file == H.cache.latest_registered_file then return end
    MiniVisits.register(file, vim.fn.getcwd())
    H.cache.latest_registered_file = file
  end)

  H.timers.register:start(H.get_config().register.delay, 0, f)
end

-- Visit index ----------------------------------------------------------------
H.get_all_index = function()
  H.load_previous_index()

  -- Extend previous index per cwd with current
  local res = vim.deepcopy(H.index.previous or {})
  for cwd, cwd_tbl in pairs(H.index.current) do
    res[cwd] = res[cwd] or {}
    H.extend_cwd_index(res[cwd], cwd_tbl)
  end

  return res
end

H.get_nocwd_index = function(index)
  local res = {}
  for cwd, cwd_tbl in pairs(index) do
    H.extend_cwd_index(res, cwd_tbl)
  end
  return res
end

H.extend_cwd_index = function(cwd_tbl_ref, cwd_tbl_new)
  cwd_tbl_new = vim.deepcopy(cwd_tbl_new)

  -- Add data from the new table taking special care for `count` and `latest`
  for file, file_tbl_new in pairs(cwd_tbl_new) do
    local file_tbl_ref = cwd_tbl_ref[file] or {}
    local file_tbl = vim.tbl_deep_extend('force', file_tbl_ref, file_tbl_new)

    -- Add all counts together
    file_tbl.count = (file_tbl_ref.count or 0) + file_tbl_new.count

    -- Compute the latest visit
    file_tbl.latest = math.max(file_tbl_ref.latest or -math.huge, file_tbl_new.latest)

    -- Flags should be already proper union of both flags

    cwd_tbl_ref[file] = file_tbl
  end
end

H.get_file_data_arr = function(cwd, scope)
  local index = MiniVisits.get(scope)
  local cwd_tbl = cwd == '' and H.get_nocwd_index(index) or vim.deepcopy(index[cwd] or {})
  local file_data_arr = {}
  for file, file_tbl in pairs(cwd_tbl) do
    file_tbl.path = file
    table.insert(file_data_arr, file_tbl)
  end
  return file_data_arr
end

-- H.resolve_file_cwd_pairs = function(file, cwd, scope)
--   if scope == 'previous' then H.load_previous_index() end
--   local index = H.index[scope] or {}
--
--   -- Empty cwd means all available cwds
--   local cwd_arr = cwd == '' and vim.tbl_keys(index) or { cwd }
--
--   -- Empty file means all available files in all target cwds
--   if file ~= '' then return vim.tbl_map(function(x) return { file = file, cwd = x } end, cwd_arr) end
--   local res = {}
--   for _, dir in ipairs(cwd_arr) do
--     local cwd_tbl = index[dir] or {}
--     for f, _ in pairs(cwd_tbl) do
--       table.insert(res, { file = f, cwd = dir })
--     end
--   end
--   return res
-- end

H.load_previous_index = function()
  if type(H.index.previous) == 'table' then return end
  H.index.previous = MiniVisits.read()
end

H.ensure_current_index_entry = function(file, cwd)
  local cwd_tbl = H.index.current[cwd] or {}
  cwd_tbl[file] = cwd_tbl[file] or { count = 0, latest = 0 }
  H.index.current[cwd] = cwd_tbl
end

H.index_prune = function(index, prune_non_paths, threshold)
  if type(threshold) ~= 'number' then H.error('Prune threshold should be number.') end

  for cwd, cwd_tbl in pairs(index) do
    if prune_non_paths and vim.fn.isdirectory(cwd) == 0 then index[cwd] = nil end
  end
  for cwd, cwd_tbl in pairs(index) do
    for file, file_tbl in pairs(cwd_tbl) do
      local should_prune = (prune_non_paths and vim.fn.filereadable(file) == 0) or file_tbl.count < threshold
      if should_prune then cwd_tbl[file] = nil end
    end
  end
end

H.index_decay_cwd = function(cwd_tbl, threshold, target)
  if type(threshold) ~= 'number' then H.error('Decay threshold should be number.') end
  if type(target) ~= 'number' then H.error('Decay target should be number.') end

  -- Decide whether to decay (if total count exceeds threshold)
  local total_count = 0
  for _, file_tbl in pairs(cwd_tbl) do
    total_count = total_count + file_tbl.count
  end
  if total_count == 0 or total_count <= threshold then return end

  -- Decay (multiply counts by coefficient to have total count equal target)
  local coef = target / total_count
  for _, file_tbl in pairs(cwd_tbl) do
    -- Round to track only two decimal places
    file_tbl.count = math.floor(100 * coef * file_tbl.count + 0.5) / 100
  end
end

H.add_rank = function(arr, key)
  local rank_key, ties = key .. '_rank', {}
  for i, tbl in ipairs(arr) do
    -- Assumes `arr` is an array of tables sorted from best to worst
    tbl[rank_key] = i

    -- Track ties
    if i > 1 and tbl[key] == arr[i - 1][key] then
      local val = tbl[key]
      local data = ties[val] or { n = 1, sum = i - 1 }
      data.n, data.sum = data.n + 1, data.sum + i
      ties[val] = data
    end
  end

  -- Correct for ties using mid-rank
  for i, tbl in ipairs(arr) do
    local tie_data = ties[tbl[key]]
    if tie_data ~= nil then tbl[rank_key] = tie_data.sum / tie_data.n end
  end
end

-- Validators -----------------------------------------------------------------
H.validate_file = function(x, noempty)
  x = x or H.buf_get_file(vim.api.nvim_get_current_buf())
  H.validate_string(x, 'file', noempty)
  return H.full_path(x)
end

H.validate_cwd = function(x, noempty)
  x = x or vim.fn.getcwd()
  H.validate_string(x, 'cwd', noempty)
  return x == '' and '' or H.full_path(x)
end

H.validate_filter = function(x)
  local config = H.get_config()
  x = x or config.list.filter or MiniVisits.gen_filter.default()
  if type(x) == 'string' then
    local flag = x
    x = function(file_data) return (file_data.flags or {})[flag] end
  end
  if not vim.is_callable(x) then H.error('`filter` should be callable or string flag name.') end
  return x
end

H.validate_sort = function(x)
  local config = H.get_config()
  x = x or config.list.sort or MiniVisits.gen_sort.default()
  if not vim.is_callable(x) then H.error('`sort` should be callable.') end
  return x
end

H.validate_index = function(x, name)
  name = name or '`index`'
  if type(x) ~= 'table' then H.error(name .. ' should be a table.') end
  for cwd, cwd_tbl in pairs(x) do
    if type(cwd) ~= 'string' then H.error('First level keys in ' .. name .. ' should be strings.') end
    if type(cwd_tbl) ~= 'table' then H.error('First level values in ' .. name .. ' should be tables.') end

    for file, file_tbl in pairs(cwd_tbl) do
      if type(file) ~= 'string' then H.error('Second level keys in ' .. name .. ' should be strings.') end
      if type(file_tbl) ~= 'table' then H.error('Second level values in ' .. name .. ' should be tables.') end

      if type(file_tbl.count) ~= 'number' then H.error('`count` entries in ' .. name .. ' should be numbers.') end
      if type(file_tbl.latest) ~= 'number' then H.error('`latest` entries in ' .. name .. ' should be numbers.') end

      H.validate_flags_field(x.flags)
    end
  end
end

H.validate_flags_field = function(x)
  if x == nil then return end
  if type(x) ~= 'table' then H.error('`flags` should be a table.') end

  for key, value in pairs(x) do
    if type(key) ~= 'string' then
      H.error('Keys in `flags` table should be strings (not ' .. vim.inspect(key) .. ').')
    end
    if value ~= true then
      H.error('Values in `flags` table should only be `true` (not ' .. vim.inspect(value) .. ').')
    end
  end
end

H.validate_scope = function(x)
  x = x or 'all'
  if x == 'all' or x == 'previous' or x == 'current' then return x end
  H.error('`scope` should be one of "all", "previous", "current".')
end

H.validate_string = function(x, name, noempty)
  if type(x) == 'string' and not (noempty and x == '') then return x end
  H.error(string.format('`%s` should be a non-empty string.', name))
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.visits) %s', msg), 0) end

H.is_valid_buf = function(buf_id) return type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id) end

H.buf_get_file = function(buf_id)
  -- Get file only for valid normal buffers
  if not H.is_valid_buf(buf_id) then return nil end
  if vim.bo[buf_id].buftype ~= '' then return nil end
  local res = vim.api.nvim_buf_get_name(buf_id)
  if res == '' then return end
  return res
end

H.full_path = function(path) return (vim.fn.fnamemodify(path, ':p'):gsub('(.)/$', '%1')) end

H.short_path = function(path, cwd)
  cwd = cwd or vim.fn.getcwd()
  if not vim.startswith(path, cwd) then return path end
  local res = path:sub(cwd:len() + 1):gsub('^/+', ''):gsub('/+$', '')
  return res
end

return MiniVisits
