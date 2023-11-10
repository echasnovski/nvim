-- TODO:
--
-- Code:
-- - ?Rename `get`, `set`, `normalize`, `read`, `write` with `_index` suffix?
--
-- - Implement `goto` ("next", "previous", "first", "last") with custom
--   `filter` and `sort`.
--
-- Tests:
-- - All combinations of empty/nonempty + path/cwd work for all cases.
--
-- - Can track both file and directory visits.
--
-- - How it works with several Neovim instances opened ("last who wrote wins").
--
-- Docs:

--- *mini.visits* Track and reuse file system visits
--- *MiniVisits*
---
--- MIT License Copyright (c) 2023 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Features:
---
--- - Persistently track file system visits per working directory.
---   Stored visit index is human readable and editable.
---
--- - Configurable automated visit register logic:
---     - On user-defined event.
---     - After staying in same path for user-defined amount of time.
---
--- - Function to list paths based on visit index with custom filter and sort
---   (uses "frecency" by default). Can be used as source for various pickers.
---
--- - Wrappers for |vim.ui.select()| to select paths or flags.
---   See |MiniVisits.select_paths()| and |MiniVisits.select_flags()|.
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
  -- How visit index is converted to list of paths
  list = {
    -- Predicate for which paths to include
    filter = nil,

    -- Sort paths based on the visit data
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

MiniVisits.register = function(path, cwd)
  path = H.validate_path(path)
  cwd = H.validate_cwd(cwd)
  if path == '' or cwd == '' then H.error('Both `path` and `cwd` should not be empty.') end

  H.ensure_index_entry(path, cwd)
  local path_tbl = H.index[cwd][path]
  path_tbl.count = path_tbl.count + 1
  path_tbl.latest = os.time()
end

MiniVisits.add_flag = function(flag, path, cwd)
  path = H.validate_path(path)
  cwd = H.validate_cwd(cwd)

  if flag == nil then
    -- Suggest all flags from cwd in completion
    flag = H.get_flag_from_user('Enter flag to add', MiniVisits.list_flags('', cwd))
    if flag == nil then return end
  end
  flag = H.validate_string(flag, 'flag')

  -- Add flag to all target path-cwd pairs
  local path_cwd_pairs = H.resolve_path_cwd(path, cwd)
  for _, pair in ipairs(path_cwd_pairs) do
    H.ensure_index_entry(pair.path, pair.cwd)
    local path_tbl = H.index[pair.cwd][pair.path]
    local flags = path_tbl.flags or {}
    flags[flag] = true
    path_tbl.flags = flags
  end
end

-- TODO: Rewrite to suggest list of present flags in `inputlist` and do nothing
-- if `path` doesn't exist in `cwd`
MiniVisits.remove_flag = function(flag, path, cwd)
  path = H.validate_path(path)
  cwd = H.validate_cwd(cwd)

  if flag == nil then
    -- Suggest only flags from target path-cwd pairs
    flag = H.get_flag_from_user('Enter flag to remove', MiniVisits.list_flags(path, cwd))
    if flag == nil then return end
  end
  flag = H.validate_string(flag, 'flag')

  -- Remove flag from all target path-cwd pairs (ignoring not present ones and
  -- collapsing `flags` if removed last flag)
  H.ensure_read_index()
  local path_cwd_pairs = H.resolve_path_cwd(path, cwd)
  for _, pair in ipairs(path_cwd_pairs) do
    local path_tbl = (H.index[pair.cwd] or {})[pair.path]
    if type(path_tbl) == 'table' and type(path_tbl.flags) == 'table' then
      path_tbl.flags[flag] = nil
      if vim.tbl_count(path_tbl.flags) == 0 then path_tbl.flags = nil end
    end
  end
end

MiniVisits.list_paths = function(cwd, opts)
  cwd = H.validate_cwd(cwd)

  opts = vim.tbl_deep_extend('force', H.get_config().list, opts or {})
  local filter = H.validate_filter(opts.filter)
  local sort = H.validate_sort(opts.sort)

  local path_data_arr = H.make_path_array('', cwd)
  local res_arr = sort(vim.tbl_filter(filter, path_data_arr))
  return vim.tbl_map(function(x) return x.path end, res_arr)
end

MiniVisits.list_flags = function(path, cwd, opts)
  path = H.validate_path(path)
  cwd = H.validate_cwd(cwd)

  opts = vim.tbl_deep_extend('force', H.get_config().list, opts or {})
  local filter = H.validate_filter(opts.filter)

  local path_data_arr = H.make_path_array(path, cwd)
  local res_arr = vim.tbl_filter(filter, path_data_arr)

  -- Count flags
  local flag_counts = {}
  for _, path_data in ipairs(res_arr) do
    for flag, _ in pairs(path_data.flags or {}) do
      flag_counts[flag] = (flag_counts[flag] or 0) + 1
    end
  end

  -- Sort from most to least common
  local flag_arr = {}
  for flag, count in pairs(flag_counts) do
    table.insert(flag_arr, { count, flag })
  end
  table.sort(flag_arr, function(a, b) return a[1] > b[1] end)
  return vim.tbl_map(function(x) return x[2] end, flag_arr)
end

MiniVisits.select_paths = function(cwd, opts)
  local paths = MiniVisits.list_paths(cwd, opts)
  local cwd_to_short = cwd == '' and vim.fn.getcwd() or cwd
  local items = vim.tbl_map(function(path) return { path = path, text = H.short_path(path, cwd_to_short) } end, paths)
  local select_opts = { prompt = 'Visited paths', format_item = function(item) return item.text end }
  local on_choice = function(item)
    if item == nil then return end
    pcall(vim.cmd, 'edit ' .. vim.fn.fnameescape(item.path))
  end

  vim.ui.select(items, select_opts, on_choice)
end

MiniVisits.select_flags = function(path, cwd, opts)
  local flags = MiniVisits.list_flags(path, cwd, opts)
  opts = opts or {}
  local on_choice = function(flag)
    if flag == nil then return end

    -- Select among subset of paths with chosen flag
    local filter_cur = (opts or {}).filter or MiniVisits.gen_filter.default()
    local new_opts = vim.deepcopy(opts)
    new_opts.filter = function(path_data)
      return filter_cur(path_data) and type(path_data.flags) == 'table' and path_data.flags[flag]
    end
    MiniVisits.select_paths(cwd, new_opts)
  end

  vim.ui.select(flags, { prompt = 'Visited flags' }, on_choice)
end

--- Get active visit index
---
---@return table Copy of currently active visit index table.
MiniVisits.get = function()
  H.ensure_read_index()
  return vim.deepcopy(H.index)
end

--- Set active visit index
---
---@param index table Visit index table.
MiniVisits.set = function(index)
  H.validate_index(index, '`index`')
  H.index = vim.deepcopy(index)
  H.cache.needs_index_read = false
end

MiniVisits.normalize = function(index)
  index = index or MiniVisits.get()
  H.validate_index(index, '`index`')

  local config = H.get_config()
  local normalize = config.store.normalize
  if not vim.is_callable(normalize) then normalize = MiniVisits.default_normalize end
  local new_index = normalize(vim.deepcopy(index))
  H.validate_index(new_index, 'normalized `index`')

  return new_index
end

MiniVisits.read = function(store_path)
  store_path = store_path or H.get_config().store.path
  if store_path == '' then return nil end
  H.validate_string(store_path, 'path')
  if vim.fn.filereadable(store_path) == 0 then return nil end

  local ok, res = pcall(dofile, store_path)
  if not ok then return nil end
  return res
end

MiniVisits.write = function(store_path, index)
  store_path = store_path or H.get_config().store.path
  H.validate_string(store_path, 'path')
  index = index or MiniVisits.get()
  H.validate_index(index, '`index`')

  -- Normalize index
  index = MiniVisits.normalize(index)

  -- Ensure writable path
  store_path = vim.fn.fnamemodify(store_path, ':p')
  local path_dir = vim.fn.fnamemodify(store_path, ':h')
  vim.fn.mkdir(path_dir, 'p')

  -- Write
  local lines = vim.split(vim.inspect(index), '\n')
  lines[1] = 'return ' .. lines[1]
  vim.fn.writefile(lines, store_path)
end

MiniVisits.gen_filter = {}

MiniVisits.gen_filter.default = function()
  return function(path_data) return true end
end

MiniVisits.gen_filter.this_session = function()
  return function(path_data) return H.cache.session_start_time <= path_data.latest end
end

MiniVisits.gen_sort = {}

MiniVisits.gen_sort.default = function(opts)
  opts = vim.tbl_deep_extend('force', { recency_weight = 0.5 }, opts or {})
  local recency_weight = opts.recency_weight
  local is_weight = type(recency_weight) == 'number' and 0 <= recency_weight and recency_weight <= 1
  if not is_weight then H.error('`opts.recency_weight` should be number between 0 and 1.') end

  return function(path_data_arr)
    -- Add ranks for `count` and `latest`
    table.sort(path_data_arr, function(a, b) return a.count > b.count end)
    H.tbl_add_rank(path_data_arr, 'count')
    table.sort(path_data_arr, function(a, b) return a.latest > b.latest end)
    H.tbl_add_rank(path_data_arr, 'latest')

    -- Compute final rank and sort by it
    for _, path_data in ipairs(path_data_arr) do
      path_data.rank = (1 - recency_weight) * path_data.count_rank + recency_weight * path_data.latest_rank
    end
    table.sort(path_data_arr, function(a, b) return a.rank < b.rank or (a.rank == b.rank and a.path < b.path) end)
    return path_data_arr
  end
end

MiniVisits.gen_sort.z = function()
  return function(path_data_arr)
    local now = os.time()
    for _, path_data in ipairs(path_data_arr) do
      -- Source: https://github.com/rupa/z/blob/master/z.sh#L151
      local dtime = math.max(now - path_data.latest, 0.0001)
      path_data.z = 10000 * path_data.count * (3.75 / ((0.0001 * dtime + 1) + 0.25))
    end
    table.sort(path_data_arr, function(a, b) return a.z > b.z or (a.z == b.z and a.path < b.path) end)
    return path_data_arr
  end
end

MiniVisits.default_normalize = function(index, opts)
  H.validate_index(index)
  local default_opts = { decay_threshold = 50, decay_target = 45, prune_threshold = 0.5, prune_paths = false }
  opts = vim.tbl_deep_extend('force', default_opts, opts or {})

  local res = vim.deepcopy(index)
  H.index_prune(res, opts.prune_paths, opts.prune_threshold)
  for cwd, cwd_tbl in pairs(res) do
    H.index_decay_cwd(cwd_tbl, opts.decay_threshold, opts.decay_target)
  end
  -- Ensure that no path has count smaller than threshold
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

-- Current visit index
H.index = {}

-- Various cache
H.cache = {
  -- Latest registered path used to not autoregister same path in a row
  latest_registered_path = nil,

  -- Whether index is yet to be read from the stored path, as it is not read
  -- right away delaying until it is absolutely necessary
  needs_index_read = true,

  -- Start time of this session to be used in `gen_filter.this_session`
  session_start_time = os.time(),
}

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
    -- Register only normal buffer if it is not the latest registered (avoids
    -- tracking visits from switching between normal and non-normal buffers)
    local path = H.buf_get_path(buf_id)
    if path == nil or path == H.cache.latest_registered_path then return end
    MiniVisits.register(path, vim.fn.getcwd())
    H.cache.latest_registered_path = path
  end)

  H.timers.register:start(H.get_config().register.delay, 0, f)
end

-- Visit index ----------------------------------------------------------------
H.ensure_read_index = function()
  if not H.cache.needs_index_read then return end

  -- Try reading previous index
  local res_index = MiniVisits.read()
  local is_index = pcall(H.validate_index, res_index)
  if not is_index then return end

  -- Merge current index with stored
  for cwd, cwd_tbl in pairs(H.index) do
    local cwd_tbl_res = res_index[cwd] or {}
    for path, path_tbl_new in pairs(cwd_tbl) do
      local path_tbl_res = cwd_tbl_res[path] or { count = 0, latest = 0 }
      cwd_tbl_res[path] = H.merge_path_tbls(path_tbl_res, path_tbl_new)
    end
    res_index[cwd] = cwd_tbl_res
  end

  H.index = res_index
  H.cache.needs_index_read = false
end

H.ensure_index_entry = function(path, cwd)
  local cwd_tbl = H.index[cwd] or {}
  cwd_tbl[path] = cwd_tbl[path] or { count = 0, latest = 0 }
  H.index[cwd] = cwd_tbl
end

H.resolve_path_cwd = function(path, cwd)
  H.ensure_read_index()

  -- Empty cwd means all available cwds
  local cwd_arr = cwd == '' and vim.tbl_keys(H.index) or { cwd }

  -- Empty path means all available paths in all target cwds
  if path ~= '' then return vim.tbl_map(function(x) return { path = path, cwd = x } end, cwd_arr) end

  local res = {}
  for _, d in ipairs(cwd_arr) do
    local cwd_tbl = H.index[d] or {}
    for p, _ in pairs(cwd_tbl) do
      table.insert(res, { path = p, cwd = d })
    end
  end
  return res
end

H.make_path_array = function(path, cwd)
  local index = MiniVisits.get()
  local path_tbl = {}
  for _, pair in ipairs(H.resolve_path_cwd(path, cwd)) do
    local path_tbl_to_merge = (index[pair.cwd] or {})[pair.path]
    if type(path_tbl_to_merge) == 'table' then
      local p = pair.path
      path_tbl[p] = path_tbl[p] or { path = p, count = 0, latest = 0 }
      path_tbl[p] = H.merge_path_tbls(path_tbl[p], path_tbl_to_merge)
    end
  end

  return vim.tbl_values(path_tbl)
end

H.merge_path_tbls = function(path_tbl_ref, path_tbl_new)
  local path_tbl = vim.tbl_deep_extend('force', path_tbl_ref, path_tbl_new)

  -- Add all counts together
  path_tbl.count = path_tbl_ref.count + path_tbl_new.count

  -- Compute the latest visit
  path_tbl.latest = math.max(path_tbl_ref.latest, path_tbl_new.latest)

  -- Flags should be already a proper union of both flags

  return path_tbl
end

H.index_prune = function(index, prune_paths, threshold)
  if type(threshold) ~= 'number' then H.error('Prune threshold should be number.') end

  for cwd, cwd_tbl in pairs(index) do
    if prune_paths and vim.fn.isdirectory(cwd) == 0 then index[cwd] = nil end
  end
  for cwd, cwd_tbl in pairs(index) do
    for path, path_tbl in pairs(cwd_tbl) do
      local should_prune_path = prune_paths and not (vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1)
      local should_prune = should_prune_path or path_tbl.count < threshold
      if should_prune then cwd_tbl[path] = nil end
    end
  end
end

H.index_decay_cwd = function(cwd_tbl, threshold, target)
  if type(threshold) ~= 'number' then H.error('Decay threshold should be number.') end
  if type(target) ~= 'number' then H.error('Decay target should be number.') end

  -- Decide whether to decay (if total count exceeds threshold)
  local total_count = 0
  for _, path_tbl in pairs(cwd_tbl) do
    total_count = total_count + path_tbl.count
  end
  if total_count == 0 or total_count <= threshold then return end

  -- Decay (multiply counts by coefficient to have total count equal target)
  local coef = target / total_count
  for _, path_tbl in pairs(cwd_tbl) do
    -- Round to track only two decimal places
    path_tbl.count = math.floor(100 * coef * path_tbl.count + 0.5) / 100
  end
end

H.get_flag_from_user = function(prompt, flags_complete)
  MiniVisits._complete = function(arg_lead)
    return vim.tbl_filter(function(x) return x:find(arg_lead, 1, true) ~= nil end, flags_complete)
  end
  local completion = 'customlist,v:lua.MiniVisits._complete'
  local input_opts = { prompt = prompt .. ': ', completion = completion, cancelreturn = false }
  local ok, res = pcall(vim.fn.input, input_opts)
  MiniVisits._complete = nil
  if not ok or res == false then return nil end
  return res
end

-- Validators -----------------------------------------------------------------
H.validate_path = function(x)
  x = x or H.buf_get_path(vim.api.nvim_get_current_buf())
  H.validate_string(x, 'path')
  return x == '' and '' or H.full_path(x)
end

H.validate_cwd = function(x)
  x = x or vim.fn.getcwd()
  H.validate_string(x, 'cwd')
  return x == '' and '' or H.full_path(x)
end

H.validate_filter = function(x)
  x = x or MiniVisits.gen_filter.default()
  if type(x) == 'string' then
    local flag = x
    x = function(path_data) return (path_data.flags or {})[flag] end
  end
  if not vim.is_callable(x) then H.error('`filter` should be callable or string flag name.') end
  return x
end

H.validate_sort = function(x)
  x = x or MiniVisits.gen_sort.default()
  if not vim.is_callable(x) then H.error('`sort` should be callable.') end
  return x
end

H.validate_index = function(x, name)
  name = name or '`index`'
  if type(x) ~= 'table' then H.error(name .. ' should be a table.') end
  for cwd, cwd_tbl in pairs(x) do
    if type(cwd) ~= 'string' then H.error('First level keys in ' .. name .. ' should be strings.') end
    if type(cwd_tbl) ~= 'table' then H.error('First level values in ' .. name .. ' should be tables.') end

    for path, path_tbl in pairs(cwd_tbl) do
      if type(path) ~= 'string' then H.error('Second level keys in ' .. name .. ' should be strings.') end
      if type(path_tbl) ~= 'table' then H.error('Second level values in ' .. name .. ' should be tables.') end

      if type(path_tbl.count) ~= 'number' then H.error('`count` entries in ' .. name .. ' should be numbers.') end
      if type(path_tbl.latest) ~= 'number' then H.error('`latest` entries in ' .. name .. ' should be numbers.') end

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

H.validate_string = function(x, name)
  if type(x) == 'string' then return x end
  H.error(string.format('`%s` should be string.', name))
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.visits) %s', msg), 0) end

H.is_valid_buf = function(buf_id) return type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id) end

H.buf_get_path = function(buf_id)
  -- Get Path only for valid normal buffers
  if not H.is_valid_buf(buf_id) or vim.bo[buf_id].buftype ~= '' then return nil end
  local res = vim.api.nvim_buf_get_name(buf_id)
  if res == '' then return end
  return res
end

H.tbl_add_rank = function(arr, key)
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

H.full_path = function(path) return (vim.fn.fnamemodify(path, ':p'):gsub('(.)/$', '%1')) end

H.short_path = function(path, cwd)
  cwd = cwd or vim.fn.getcwd()
  if not vim.startswith(path, cwd) then return vim.fn.fnamemodify(path, ':~') end
  local res = path:sub(cwd:len() + 1):gsub('^/+', ''):gsub('/+$', '')
  return res
end

return MiniVisits
