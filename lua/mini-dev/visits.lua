-- TODO:
--
-- Code:
-- - Implement `get_files` with custom `filter` and `sort`.
--
-- - Implement "frecency" sort.
--
-- - Decide on an interface for decay.
--
-- - Implement `next()` and `previous()` with custom `filter` and `sort`.
--
-- - Implement labels (other possible names: tags, flags, marks) as alternative
--   to 'harpoon.nvim'. Add `labels` along with `count` and `latest` to be
--   a map (not array, as it will allow more simple `vim.tbl_deep_extend`).
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
--- - Persistently track file visit data per working directory.
---
--- - Configurable automated visit register logic:
---     - On user-defined event.
---     - After staying in same file for user-defined amount of time.
---
--- - Convert visits data into an array of files based on custom filter and sort.
---   This can be used
---
--- - Built-in "frecency" sorting.
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

--stylua: ignore
--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniVisits.config = {
  -- Options for how visit registering is done
  register = {
    -- Start visit register timer at this event
    -- Supply empty string (`''`) to not create this automatically
    event = 'BufEnter',

    -- Duration after event to register a visit
    -- TODO: Change to 1000
    delay = 1,
  },

  store = {
    -- Whether to write all history before Neovim is closed
    autowrite = true,

  -- Path to store visits history
    path = vim.fn.stdpath('data') .. '/mini-visits-history'
  }
}
--minidoc_afterlines_end

MiniVisits.register = function(file, cwd)
  if type(file) ~= 'string' then H.error('`file` should be string.') end
  if type(cwd) ~= 'string' then H.error('`cwd` should be string.') end

  local cwd_tbl = H.data.session[cwd] or {}
  local file_tbl = cwd_tbl[file] or {}
  file_tbl.count = (file_tbl.count or 0) + 1
  file_tbl.latest = os.time()
  cwd_tbl[file] = file_tbl
  H.data.session[cwd] = cwd_tbl
end

MiniVisits.get_data = function(scope)
  scope = scope or 'all'
  H.validate_scope(scope)

  if scope == 'session' or scope == 'history' then return H.data[scope] end
  return H.get_all_data()
end

MiniVisits.set_data = function(scope, data)
  scope = scope or 'all'
  H.validate_scope(scope)
  H.validate_data(data)

  if scope == 'session' or scope == 'history' then H.data[scope] = data end
  if scope == 'all' then
    H.data.history, H.data.session = data, {}
  end
end

MiniVisits.read_data = function(path)
  local path = path or H.get_config().store.path
  H.validate_path(path)
  if vim.fn.filereadable(path) == 0 then return nil end

  local ok, res = pcall(dofile, path)
  if not ok then return nil end
  return res
end

MiniVisits.write_data = function(path, data)
  local path = path or H.get_config().store.path
  H.validate_path(path)
  data = data or H.get_all_data()
  H.validate_data(data)

  path = vim.fn.fnamemodify(path, ':p')
  local path_dir = vim.fn.fnamemodify(path, ':h')
  vim.fn.mkdir(path_dir, 'p')

  local data_lines = vim.split(vim.inspect(data), '\n')
  data_lines[1] = 'return ' .. data_lines[1]
  vim.fn.writefile(data_lines, path)
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniVisits.config

-- Various timers
H.timers = {
  register = vim.loop.new_timer(),
}

-- Visits for current session and pulled from history
H.data = {
  history = nil,
  session = {},
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
    register = { config.register, 'table' },
    store = { config.store, 'table' },
  })

  vim.validate({
    ['register.delay'] = { config.register.delay, 'number' },
    ['register.event'] = { config.register.event, 'string' },

    ['store.autowrite'] = { config.store.autowrite, 'boolean' },
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
    au('VimLeavePre', '*', function() MiniVisits.write_data() end, 'Autowrite visits history')
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
    local file = H.buf_get_file(buf_id)
    if file == nil or file == H.cache.latest_registered_file then return end
    MiniVisits.register(file, vim.fn.getcwd())
    H.cache.latest_registered_file = file
  end)

  H.timers.register:start(H.get_config().register.delay, 0, f)
end

-- Visit data -----------------------------------------------------------------
H.get_all_data = function()
  H.load_history_data()

  -- Merge two data tables taking special care for `count` and `latest`
  local history, session = vim.deepcopy(H.data.history or {}), vim.deepcopy(H.data.session)
  local res = vim.tbl_deep_extend('force', history, session)
  for cwd, cwd_table in pairs(res) do
    local hist_cwd_table, sess_cwd_table = history[cwd] or {}, session[cwd] or {}
    for file, file_table in pairs(cwd_table) do
      local hist_file_table, sess_file_table = hist_cwd_table[file] or {}, sess_cwd_table[file] or {}

      -- Add all counts together
      file_table.count = (hist_file_table.count or 0) + (sess_file_table.count or 0)

      -- Compute the latest visit
      file_table.latest = math.max((hist_file_table.latest or 0), (sess_file_table.latest or 0))
    end
  end

  return res
end

H.load_history_data = function()
  if type(H.data.history) == 'table' then return end
  H.data.history = MiniVisits.read_data()
end

H.validate_data = function(x)
  if type(x) ~= 'table' then H.error('`data` should be a table.') end
  for cwd, cwd_data in pairs(x) do
    if type(cwd) ~= 'string' then H.error('First level keys in `data` should be strings.') end
    if type(cwd_data) ~= 'table' then H.error('First level values should be a tables.') end

    for file, file_data in pairs(x) do
      if type(file) ~= 'string' then H.error('Second level keys in `data` should be strings.') end
      if type(file_data) ~= 'table' then H.error('Second level values should be a tables.') end

      -- TODO: Decide whether to validate `count` and `latest`
    end
  end
end

H.validate_scope = function(x)
  if x == 'all' or x == 'history' or x == 'session' then return end
  H.error('`scope` should be one of "all", "history", "session".')
end

H.validate_path = function(x)
  if type(x) == 'string' then return end
  H.error('`path` should be string.')
end

-- Json -----------------------------------------------------------------------
H.data_encode = function(data)
  local res = vim.fn.json_encode(data):gsub('^{', '{\n'):gsub('$}', '\n}')
  -- res = res:gsub('%b{},', function(match) return string.format('{\n\t%s\n},', match:sub(2, -2)) end)
  res = res:gsub('%b{}, ', function(match) return match:sub(1, -1) .. '\n\t' end)
  return vim.split(res, '\n')
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

H.is_valid_win = function(win_id) return type(win_id) == 'number' and vim.api.nvim_win_is_valid(win_id) end

H.full_path = function(path) return (vim.fn.fnamemodify(path, ':p'):gsub('(.)/$', '%1')) end

H.short_path = function(path, cwd)
  cwd = cwd or vim.fn.getcwd()
  if not vim.startswith(path, cwd) then return path end
  local res = path:sub(cwd:len() + 1):gsub('^/+', ''):gsub('/+$', '')
  return res
end

return MiniVisits
