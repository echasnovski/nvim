-- TODO:
--
-- Code:
-- - Implement `list_files` with custom `filter` and `sort`.
--
-- - Implement "frecency" sort.
--
-- - Think about renaming "history" to something else (besides "data") to also
--   show that it tracks flags along with visit data.
--
-- - Implement `goto` ("next", "previous", "first", "last") with custom
--   `filter` and `sort`.
--
-- - Think about how to mitigate several opened Neovim instances using same
--   visits history.
--
-- - Think about the best approach to track custom data. Or even if it should
--   not be allowed.
--
-- - Implement helpers around flags as alternative to 'harpoon.nvim'.
--
-- Tests:
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
--- - Persistently track file visit history per working directory.
---
--- - Configurable automated visit register logic:
---     - On user-defined event.
---     - After staying in same file for user-defined amount of time.
---
--- - Function to list files based on visits history with custom filter and
---   sort (uses "frecency" by default). Can be used as source for various pickers.
---
--- - ??? Customizable history data ???.
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
  -- How visit history is converted to list of files
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

  -- How visit history is stored
  store = {
    -- Whether to write all history before Neovim is closed
    autowrite = true,

    -- Function to ensure that written history is relevant
    normalize = nil,

    -- Path to store visits history
    path = vim.fn.stdpath('data') .. '/mini-visits-history',
  },
}
--minidoc_afterlines_end

MiniVisits.register = function(file, cwd)
  H.validate_string(file, 'file')
  cwd = cwd or vim.fn.getcwd()
  H.validate_string(cwd, 'cwd')
  if cwd == '' then H.error('`cwd` should not be empty string.') end

  local cwd_tbl = H.history.current[cwd] or {}
  local file_tbl = cwd_tbl[file] or {}
  file_tbl.count = (file_tbl.count or 0) + 1
  file_tbl.latest = os.time()
  cwd_tbl[file] = file_tbl
  H.history.current[cwd] = cwd_tbl
end

MiniVisits.history_get = function(scope)
  scope = scope or 'all'
  H.validate_scope(scope)

  if scope == 'current' or scope == 'previous' then return H.history[scope] end
  return H.get_all_history()
end

MiniVisits.history_set = function(scope, history)
  scope = scope or 'all'
  H.validate_scope(scope)
  H.validate_history(history, '`history`')

  if scope == 'current' or scope == 'previous' then H.history[scope] = history end
  if scope == 'all' then
    H.history.previous, H.history.current = {}, history
  end
end

MiniVisits.history_read = function(path)
  local path = path or H.get_config().store.path
  H.validate_string(path, 'path')
  if vim.fn.filereadable(path) == 0 then return nil end

  local ok, res = pcall(dofile, path)
  if not ok then return nil end
  return res
end

MiniVisits.history_write = function(path, history)
  local store_config = H.get_config().store
  path = path or store_config.path
  H.validate_string(path, 'path')
  history = history or H.get_all_history()
  H.validate_history(history, '`history`')

  -- Normalize history
  local normalize = vim.is_callable(store_config.normalize) and store_config.normalize or MiniVisits.default_normalize
  history = normalize(history)
  H.validate_history(history, 'normalized `history`')

  -- Ensure writable path
  path = vim.fn.fnamemodify(path, ':p')
  local path_dir = vim.fn.fnamemodify(path, ':h')
  vim.fn.mkdir(path_dir, 'p')

  -- Write
  local lines = vim.split(vim.inspect(history), '\n')
  lines[1] = 'return ' .. lines[1]
  vim.fn.writefile(lines, path)

  -- Set written history (to make normalized history current)
  MiniVisits.history_set('all', history)
end

MiniVisits.default_filter = function(file_data) return true end

-- TODO
MiniVisits.default_sort = function(file_data_arr) return vim.deepcopy(file_data_arr) end

MiniVisits.default_normalize = function(history, opts)
  H.validate_history(history)
  local default_opts = { decay_threshold = 50, decay_target = 45, prune_threshold = 0.5, prune_non_paths = false }
  opts = vim.tbl_deep_extend('force', default_opts, opts or {})

  local res = vim.deepcopy(history)
  H.history_prune(res, opts.prune_non_paths, opts.prune_threshold)
  for cwd, cwd_tbl in pairs(res) do
    H.history_decay_cwd(cwd_tbl, opts.decay_threshold, opts.decay_target)
  end
  return res
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniVisits.config

-- Various timers
H.timers = {
  register = vim.loop.new_timer(),
}

-- Visit history for current and previous sessions
H.history = {
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
    au('VimLeavePre', '*', function() pcall(MiniVisits.history_write) end, 'Autowrite visits history')
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

-- Visit history --------------------------------------------------------------
H.get_all_history = function()
  H.load_previous_history()

  local previous, current = vim.deepcopy(H.history.previous or {}), vim.deepcopy(H.history.current)

  -- Merge history tables per cwd
  local res = {}
  local cwd_arr = H.union_arr(vim.tbl_keys(previous), vim.tbl_keys(current))
  for _, cwd in ipairs(cwd_arr) do
    res[cwd] = H.merge_cwd_history_pair(previous[cwd], current[cwd])
  end

  return res
end

H.get_nocwd_history = function(history)
  local res = {}
  for cwd, cwd_tbl in pairs(history) do
    res = H.merge_cwd_history_pair(res, cwd_tbl)
  end
  return res
end

H.merge_cwd_history_pair = function(cwd_tbl_1, cwd_tbl_2)
  cwd_tbl_1, cwd_tbl_2 = cwd_tbl_1 or {}, cwd_tbl_2 or {}

  -- Merge two tables taking special care for `count` and `latest` for files
  -- present in both cwd tables
  local res = vim.tbl_deep_extend('force', cwd_tbl_1, cwd_tbl_2)
  local files_both = H.intersect_arr(vim.tbl_keys(cwd_tbl_1), vim.tbl_keys(cwd_tbl_2))
  for _, file in ipairs(files_both) do
    local file_tbl_1, file_tbl_2 = cwd_tbl_1[file], cwd_tbl_2[file]

    -- Add all counts together
    res[file].count = file_tbl_1.count + file_tbl_2.count

    -- Compute the latest visit
    res[file].latest = math.max(file_tbl_1.latest, file_tbl_2.latest)

    -- Flags should be already proper union of both flags
  end

  return res
end

H.load_previous_history = function()
  if type(H.history.previous) == 'table' then return end
  H.history.previous = MiniVisits.history_read()
end

H.history_prune = function(history, prune_non_paths, threshold)
  if type(threshold) ~= 'number' then H.error('Prune threshold should be number.') end

  for cwd, cwd_tbl in pairs(history) do
    if prune_non_paths and vim.fn.isdirectory(cwd) == 0 then history[cwd] = nil end
  end
  for cwd, cwd_tbl in pairs(history) do
    for file, file_tbl in pairs(cwd_tbl) do
      local should_prune = (prune_non_paths and vim.fn.filereadable(file) == 0) or file_tbl.count < threshold
      if should_prune then cwd_tbl[file] = nil end
    end
  end
end

H.history_decay_cwd = function(cwd_tbl, threshold, target)
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

-- Validators -----------------------------------------------------------------
H.validate_history = function(x, name)
  name = name or '`history`'
  if type(x) ~= 'table' then H.error(name .. ' should be a table.') end
  for cwd, cwd_tbl in pairs(x) do
    if type(cwd) ~= 'string' then H.error('First level keys in ' .. name .. ' should be strings.') end
    if type(cwd_tbl) ~= 'table' then H.error('First level values in ' .. name .. ' should be tables.') end

    for file, file_tbl in pairs(cwd_tbl) do
      if type(file) ~= 'string' then H.error('Second level keys in ' .. name .. ' should be strings.') end
      if type(file_tbl) ~= 'table' then H.error('Second level values in ' .. name .. ' should be tables.') end

      if type(file_tbl.count) ~= 'number' then H.error('`count` entries in ' .. name .. ' should be numbers.') end
      if type(file_tbl.latest) ~= 'number' then H.error('`latest` entries in ' .. name .. ' should be numbers.') end

      H.validate_flags(x.flags)
    end
  end
end

H.validate_flags = function(x)
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
  if x == 'all' or x == 'previous' or x == 'current' then return end
  H.error('`scope` should be one of "all", "previous", "current".')
end

H.validate_string = function(x, name)
  if type(x) == 'string' then return end
  H.error(string.format('`%s` should be string.', name))
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

H.union_arr = function(x, y)
  local res = {}
  for _, val in pairs(x) do
    res[val] = true
  end
  for _, val in pairs(y) do
    res[val] = true
  end
  return vim.tbl_keys(res)
end

H.intersect_arr = function(x, y)
  local x_map = {}
  for _, val in pairs(x) do
    x_map[val] = true
  end

  local res = {}
  for _, val in pairs(y) do
    if x_map[val] then table.insert(res, val) end
  end
  return res
end

return MiniVisits
