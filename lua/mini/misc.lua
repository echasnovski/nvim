-- MIT License Copyright (c) 2021 Evgeni Chasnovski
--
-- Lua module which implements miscellaneous useful functions.
--
-- This module is designed to not need activation, but it can be done to
-- improve usability. To activate, put this file somewhere into 'lua' folder
-- and call module's `setup()`. For example, put as 'lua/mini/misc.lua' and
-- execute `require('mini.misc').setup()` Lua code. It may have `config`
-- argument which should be a table overwriting default values using same
-- structure.
--
-- Default `config`:
-- {
--   -- List of fields to make global (to be used as independent variables)
--   make_global = { 'put', 'put_text' }
-- }
--
-- Features are described for every function separately.

-- Module and its helper
local MiniMisc = {}
local H = {}

-- Module setup
function MiniMisc.setup(config)
  -- Export module
  _G.MiniMisc = MiniMisc

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)
end

-- Module settings
---- List of fields to make global (to be used as independent variables)
MiniMisc.make_global = { 'put', 'put_text' }

-- Module functionality
---- Helper to print Lua objects in command line
function MiniMisc.put(...)
  local objects = {}
  -- Not using `{...}` because it removes `nil` input
  for i = 1, select('#', ...) do
    local v = select(i, ...)
    table.insert(objects, vim.inspect(v))
  end

  print(table.concat(objects, '\n'))

  return ...
end

---- Helper to print Lua objects in current buffer
function MiniMisc.put_text(...)
  local objects = {}
  -- Not using `{...}` because it removes `nil` input
  for i = 1, select('#', ...) do
    local v = select(i, ...)
    table.insert(objects, vim.inspect(v))
  end

  local lines = vim.split(table.concat(objects, '\n'), '\n')
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  vim.fn.append(lnum, lines)

  return ...
end

---- Execute `f` once and time how long it took
---- @param f Function which execution to benchmark
---- @param ... Arguments when calling `f`
---- @return duration, output Duration (in seconds; up to microseconds) and
----   output of function execution
function MiniMisc.bench_time(f, ...)
  local start_sec, start_usec = vim.loop.gettimeofday()
  local output = f(...)
  local end_sec, end_usec = vim.loop.gettimeofday()
  local duration = (end_sec - start_sec) + 0.000001 * (end_usec - start_usec)

  return duration, output
end

---- Return "first" elements of table as decided by `pairs`
----
---- NOTE: order of elements might be different.
----
---- @param t Table
---- @param n (default: 5) Maximum number of first elements
---- @return Table with at most `n` first elements of `t` (with same keys)
function MiniMisc.head(t, n)
  n = n or 5
  local res, n_res = {}, 0
  for k, val in pairs(t) do
    if n_res >= n then
      return res
    end
    res[k] = val
    n_res = n_res + 1
  end
  return res
end

---- Return "last" elements of table as decided by `pairs`
----
---- This function makes two passes through elements of `t`:
---- - First to count number of elements.
---- - Second to construct result.
----
---- NOTE: order of elements might be different.
----
---- @param t Table
---- @param n (default: 5) Maximum number of last elements
---- @return Table with at most `n` last elements of `t` (with same keys)
function MiniMisc.tail(t, n)
  n = n or 5

  -- Count number of elements on first pass
  local n_all = 0
  for _, _ in pairs(t) do
    n_all = n_all + 1
  end

  -- Construct result on second pass
  local res = {}
  local i, start_i = 0, n_all - n + 1
  for k, val in pairs(t) do
    i = i + 1
    if i >= start_i then
      res[k] = val
    end
  end
  return res
end

-- Helper data
---- Module default config
H.config = {
  make_global = MiniMisc.make_global,
}

-- Helper functions
---- Settings
function H.setup_config(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.config, config or {})

  vim.validate({
    make_global = {
      config.make_global,
      function(x)
        if type(x) ~= 'table' then
          return false
        end
        local present_fields = vim.tbl_keys(MiniMisc)
        for _, v in pairs(x) do
          if not vim.tbl_contains(present_fields, v) then
            return false
          end
        end
        return true
      end,
      '`make_global` should be a table with `MiniMisc` actual fields',
    },
  })

  return config
end

function H.apply_config(config)
  for _, v in pairs(config.make_global) do
    _G[v] = MiniMisc[v]
  end
end

return MiniMisc
