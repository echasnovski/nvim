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

-- Print Lua objects in command line
--
-- @param ... Any number of objects to be printed each on separate line.
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

-- Print Lua objects in current buffer
--
-- @param ... Any number of objects to be printed each on separate line.
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

-- Execute `f` once and time how long it took
-- @param f Function which execution to benchmark
-- @param ... Arguments when calling `f`
-- @return duration, output Duration (in seconds; up to microseconds) and
--   output of function execution
function MiniMisc.bench_time(f, ...)
  local start_sec, start_usec = vim.loop.gettimeofday()
  local output = f(...)
  local end_sec, end_usec = vim.loop.gettimeofday()
  local duration = (end_sec - start_sec) + 0.000001 * (end_usec - start_usec)

  return duration, output
end

-- Compute width of gutter (info column on the left of the window)
--
-- @param Identifier of window (`:h win_getid()`) for which gutter width is
--   computed. Default: 0 for current.
function MiniMisc.get_gutter_width(win_id)
  -- Compute number of 'editable' columns in current window
  ---- Store current window metadata
  local virtualedit = vim.opt.virtualedit
  local curpos = vim.api.nvim_win_get_cursor(win_id)

  ---- Move cursor to the last visible column
  local last_col = vim.api.nvim_win_call(win_id, function()
    vim.opt.virtualedit = 'all'
    vim.cmd([[normal! g$]])
    return vim.fn.virtcol('.')
  end)

  ---- Restore current window metadata
  vim.opt.virtualedit = virtualedit
  vim.api.nvim_win_set_cursor(win_id, curpos)

  -- Compute result
  return vim.api.nvim_win_get_width(win_id) - last_col
end

-- Resize window to have exact number of editable columns
--
-- @param win_id Identifier of window to be resized (`:h win_getid()`).
--   Default: 0 for current.
-- @param text_width Number of editable columns resized window will display.
--   Default: first element of 'colorcolumn' or otherwise 'textwidth' (using
--   screen width as its default but not more than 79).
function MiniMisc.resize_window(win_id, text_width)
  win_id = win_id or 0
  text_width = text_width or H.default_text_width(win_id)

  vim.api.nvim_win_set_width(win_id, text_width + MiniMisc.get_gutter_width(win_id))
end

H.default_text_width = function(win_id)
  local buf = vim.api.nvim_win_get_buf(win_id)
  local textwidth = vim.api.nvim_buf_get_option(buf, 'textwidth')
  textwidth = (textwidth == 0) and math.min(vim.o.columns, 79) or textwidth

  local colorcolumn = vim.api.nvim_win_get_option(win_id, 'colorcolumn')
  if colorcolumn ~= '' then
    local cc = vim.split(colorcolumn, ',')[1]
    local is_cc_relative = vim.tbl_contains({ '-', '+' }, cc:sub(1, 1))

    if is_cc_relative then
      return textwidth + tonumber(cc)
    else
      return tonumber(cc)
    end
  else
    return textwidth
  end
end

-- Add possibility of nested comment leader.
--
-- This works by parsing 'commentstring' buffer option, extracting
-- non-whitespace comment leader (symbols on the left of commented line), and
-- modifying 'comments' option (by prepending `n:<leader>`). Does nothing if
-- 'commentstring' is empty or has comment symbols both in front and back (like
-- '/*%s*/').
--
-- Nested comment leader added with this function is useful for formatting
-- nested comments. For example, have in Lua 'first-level' comments with '--'
-- and 'second-level' comments with '----'. With nested comment leader second
-- type can be formatted with `gq` in the same way as first one.
--
-- Recommended usage is with `autocmd`:
-- `autocmd BufEnter * lua pcall(require('mini.misc').add_nested_comment_leader)`
--
-- @param buf_id Identifier of buffer in which function will operate. Default:
--   current buffer (identifier 0). NOTE: for most filetypes 'commentstring'
--   option is added only when buffer with this filetype is entered, so using
--   non-current `buf_id` can not lead to desired effect.
function MiniMisc.add_nested_comment_leader(buf_id)
  buf_id = buf_id or 0

  local commentstring = vim.api.nvim_buf_get_option(buf_id, 'commentstring')
  if commentstring == '' then
    return
  end

  -- Extract raw comment leader from 'commentstring' option
  local comment_parts = vim.tbl_filter(function(x)
    return x ~= ''
  end, vim.split(commentstring, '%s', true))

  -- Don't do anything if 'commentstring' is like '/*%s*/' (as in 'json')
  if #comment_parts > 1 then
    return
  end

  -- Get comment leader. Remove whitespace and escape 'dangerous' characters
  local leader = vim.trim(comment_parts[1])

  local comments = vim.api.nvim_buf_get_option(buf_id, 'comments')
  local new_comments = string.format('n:%s,%s', leader, comments)
  vim.api.nvim_buf_set_option(buf_id, 'comments', new_comments)
end

-- Return "first" elements of table as decided by `pairs`
--
-- NOTE: order of elements might vary.
--
-- @param t Table
-- @param n (default: 5) Maximum number of first elements
-- @return Table with at most `n` first elements of `t` (with same keys)
function MiniMisc.tbl_head(t, n)
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

-- Return "last" elements of table as decided by `pairs`
--
-- This function makes two passes through elements of `t`:
-- - First to count number of elements.
-- - Second to construct result.
--
-- NOTE: order of elements might vary.
--
-- @param t Table
-- @param n (default: 5) Maximum number of last elements
-- @return Table with at most `n` last elements of `t` (with same keys)
function MiniMisc.tbl_tail(t, n)
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

-- Zoom in and out of a buffer, making it full screen in a floating window
--
-- This function is useful when working with multiple windows but temporarily
-- needing to zoom into one to see more of the code from that buffer. Call it
-- again (without arguments) to zoom out.
--
-- @param buf_id Buffer to be zoomed. Default: 0 for current.
-- @param config Optional config for window (as for `vim.api.nvim_open_win`).
local zoom_winid = nil
function MiniMisc.zoom(buf_id, config)
  if zoom_winid and vim.api.nvim_win_is_valid(zoom_winid) then
    vim.api.nvim_win_close(zoom_winid, true)
    zoom_winid = nil
  else
    -- Currently very big `width` and `height` get truncated to maximum allowed
    local default_config = { relative = 'editor', row = 0, col = 0, width = 1000, height = 1000 }
    config = vim.tbl_deep_extend('force', default_config, config or {})
    zoom_winid = vim.api.nvim_open_win(buf_id, true, config)
    vim.cmd([[normal! zz]])
  end
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
