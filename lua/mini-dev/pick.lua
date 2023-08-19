-- TODO:
--
-- Code:
-- - Close on lost focus.
--
-- - Info.
--
-- - Info.
--
-- - ??Async callable `source`??
--
-- - Adapter for Telescope "native" sorters.
--
-- - Adapter for Telescope extensions.
--
-- Tests:
--
-- Docs:
--

--- *mini.pick* Pick anything
--- *MiniPick*
---
--- MIT License Copyright (c) 2023 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Features:
--- - Single-window interface for picking element from any array with
---   interactive filtering and/or vertical navigation.
---
--- - Customizable
---     - "On choice" action.
---     - Filter and sort.
---     - On-demand item's extended info (usually preview).
---     - Mappings for special actions.
---
--- - Converters for Telescope pickers and sorters.
---
--- - |vim.ui.select()| wrapper.
---
--- Notes:
--- - Works on all supported versions but using Neovim>=0.9 is recommended.
---
--- See |MiniPick-overview| for more details.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.pick').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniPick`
--- which you can use for scripting or manually (with `:lua MiniPick.*`).
---
--- See |MiniPick.config| for available config settings.
---
--- You can override runtime config settings (but not `config.mappings`) locally
--- to buffer inside `vim.b.minioperators_config` which should have same structure
--- as `MiniPick.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons ~
---
--- - 'nvim-telescope/telescope.nvim':
---
--- - 'ibhagwan/fzf-lua':
---
--- # Highlight groups ~
---
--- * `MiniPickBorderInfo` - information on border opposite prompt.
--- * `MiniPickBorderProcessing` - window border while processing is in place.
--- * `MiniPickBorder` - window border.
--- * `MiniPickItemCurrent` - current item.
--- * `MiniPickMatch` - characters withing items matching query.
--- * `MiniPickNormal` - basic foreground/background highlighting.
--- * `MiniPickPrompt` - prompt.
---
--- To change any highlight group, modify it directly with |:highlight|.
---
--- # Disabling ~
---
--- To disable main functionality, set `vim.g.minipick_disable` (globally) or
--- `vim.b.minipick_disable` (for a buffer) to `true`. Considering high number
--- of different scenarios and customization intentions, writing exact rules
--- for disabling module's functionality is left to user. See
--- |mini.nvim-disabling-recipes| for common recipes.

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local
---@diagnostic disable:cast-local-type

-- Module definition ==========================================================
MiniPick = {}
H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniPick.config|.
---
---@usage `require('mini.pick').setup({})` (replace `{}` with your `config` table).
--- **Neds to have triggers configured**.
MiniPick.setup = function(config)
  -- Export module
  _G.MiniPick = MiniPick

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Create default highlighting
  H.create_default_hl()
end

--stylua: ignore
--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # Delay ~
MiniPick.config = {
  content = {
    filter = nil,
    sort = nil,
    direction = 'from_top',
  },

  delay = {
    -- Delay between forced redraws when picker is active
    redraw = 10,
  },

  -- Special keys for active picker
  mappings = {
    choose = '<CR>',
    choose_in_split = '<C-s>',
    choose_in_tabpage = '<C-t>',
    choose_in_vsplit = '<C-v>',
    choose_in_quickfix = '<C-q>',

    move_down = '<C-n>',
    move_up = '<C-p>',

    scroll_down = '<C-d>',
    scroll_up = '<C-u>',

    show_help = '<C-h>',
    show_info = '<C-i>',

    stop = '<Esc>',
  },

  window = {
    config = nil,
  },
}
--minidoc_afterlines_end

---@param source table|function Array of items to choose from or callable returning
---   such array.
---@param actions table|nil Table of actions to perform on certain special keys.
---   Possible fields:
---   - <choose> `(function)` - Callable to be executed on the chosen item.
---     Will be called with item and its index as arguments. Both will be `nil`
---     if user manually stopped picker. Execution is done after picker is closed.
---   - <info> `(function)` - Callable to be executed on item to show its
---     extended info. Will be called with item and its index as arguments.
---     Should return a buffer identifier to be shown as info.
---@param opts table|nil Options. Should have the same structure as |MiniPick.config|.
---   Default values are inferred from there.
---
--- @return ... Result of `actions.on_choice` on chosen item.
MiniPick.start = function(source, actions, opts)
  source = H.expand_callable(source)
  if not vim.tbl_islist(source) or #source == 0 then
    H.error('`source` should be a non-empty array or function returning it.')
  end

  actions = actions or {}
  if type(actions) ~= 'table' then H.error('`actions` should be a table.') end
  actions.on_choice = actions.on_choice or function(item, item_index) return item, item_index end

  opts = vim.tbl_deep_extend('force', H.get_config(), opts or {})

  local picker = H.picker_new(source, actions, opts)
  return H.picker_advance(picker)
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniPick.config

-- Namespaces
H.ns_id = {
  matches = vim.api.nvim_create_namespace('MiniPickMatches'),
}

-- Timers
H.timers = {
  getcharstr = vim.loop.new_timer(),
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    content = { config.content, 'table' },
    delay = { config.delay, 'table' },
    mappings = { config.mappings, 'table' },
    window = { config.window, 'table' },
  })

  vim.validate({
    ['content.filter'] = { config.content.filter, 'function', true },
    ['content.sort'] = { config.content.sort, 'function', true },

    ['delay.redraw'] = { config.delay.redraw, 'number' },

    ['mappings.choose'] = { config.mappings.choose, 'string' },
    ['mappings.choose_in_split'] = { config.mappings.choose_in_split, 'string' },
    ['mappings.choose_in_tabpage'] = { config.mappings.choose_in_tabpage, 'string' },
    ['mappings.choose_in_vsplit'] = { config.mappings.choose_in_vsplit, 'string' },
    ['mappings.move_down'] = { config.mappings.move_down, 'string' },
    ['mappings.move_up'] = { config.mappings.move_up, 'string' },
    ['mappings.scroll_down'] = { config.mappings.scroll_down, 'string' },
    ['mappings.scroll_up'] = { config.mappings.scroll_up, 'string' },
    ['mappings.send_to_quickfix'] = { config.mappings.send_to_quickfix, 'string' },
    ['mappings.show_help'] = { config.mappings.show_help, 'string' },
    ['mappings.show_info'] = { config.mappings.show_info, 'string' },
    ['mappings.stop'] = { config.mappings.stop, 'string' },

    ['window.config'] = {
      config.window.config,
      function(x) return x == nil or type(x) == 'table' or vim.is_callable(x) end,
      'table or callable',
    },
  })

  return config
end

H.apply_config = function(config) MiniPick.config = config end

H.is_disabled = function() return vim.g.minipick_disable == true or vim.b.minipick_disable == true end

H.get_config =
  function(config) return vim.tbl_deep_extend('force', MiniPick.config, vim.b.minipick_config or {}, config or {}) end

--stylua: ignore
H.create_default_hl = function()
  local hi = function(name, opts)
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end

  hi('MiniPickBorderInfo',       { link = 'FloatBorder' })
  hi('MiniPickBorderProcessing', { link = 'DiagnosticFloatingWarn' })
  hi('MiniPickBorder',           { link = 'FloatBorder' })
  hi('MiniPickItemCurrent',      { link = 'CursorLine' })
  hi('MiniPickMatch',            { link = 'Search' })
  hi('MiniPickNormal',           { link = 'NormalFloat' })
  hi('MiniPickPrompt',           { link = 'DiagnosticFloatingInfo' })
end

-- Picker object --------------------------------------------------------------
H.picker_new = function(items, actions, opts)
  -- Compute lines to show
  local lines = {}
  for _, x in ipairs(items) do
    x = H.expand_callable(x)
    if type(x) == 'table' then x = x.item end
    local to_add = type(x) == 'string' and x or tostring(x)
    table.insert(lines, to_add)
  end

  -- Create buffer
  local buf_id = H.picker_new_buf(lines)

  -- Create window
  local win_id = H.picker_new_win(buf_id, opts)

  -- Return object
  return {
    actions = actions,
    buffers = { main = buf_id },
    current_index = 1,
    items = items,
    lines = lines,
    opts = opts,
    query = {},
    windows = { main = win_id },
  }
end

H.picker_new_buf = function(lines)
  local buf_id = vim.api.nvim_create_buf(false, true)
  vim.bo[buf_id].filetype = 'minipick'
  vim.b[buf_id].minicursorword_disable = true

  vim.api.nvim_buf_set_lines(buf_id, 0, -1, true, lines)
  return buf_id
end

H.picker_new_win = function(buf_id, opts)
  -- Get window config
  local has_tabline = vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)
  local has_statusline = vim.o.laststatus > 0
  local max_height = vim.o.lines - vim.o.cmdheight - (has_tabline and 1 or 0) - (has_statusline and 1 or 0)
  local max_width = vim.o.columns

  local default_config = {
    relative = 'editor',
    anchor = 'SW',
    width = math.floor(0.618 * max_width),
    height = math.floor(0.618 * max_height),
    col = 0,
    row = max_height + (has_tabline and 1 or 0),
    border = 'single',
    style = 'minimal',
  }
  local config = vim.tbl_deep_extend('force', H.expand_callable(opts.window.config) or {}, default_config)

  -- Tweak config values to ensure they are proper
  if config.border == 'none' then config.border = { ' ' } end
  -- - Account for border
  config.height = math.min(config.height, max_height - 2)
  config.width = math.min(config.width, max_width - 2)

  -- Create window
  local win_id = vim.api.nvim_open_win(buf_id, false, config)

  -- Set window-local data
  vim.wo[win_id].wrap = false
  H.window_update_highlight(win_id, 'NormalFloat', 'MiniPickNormal')
  H.window_update_highlight(win_id, 'FloatBorder', 'MiniPickBorder')

  return win_id
end

H.picker_advance = function(picker)
  local special_chars = H.picker_get_special_chars(picker)

  -- Start user query
  local bs_key = H.replace_termcodes('<BS>')
  _G.char_log = {}
  local is_abort = false
  while true do
    H.picker_set_bordertext(picker)

    -- Temp filter test
    local query_pattern = vim.pesc(table.concat(picker.query))
    local lines = vim.tbl_filter(function(x) return string.find(x, query_pattern) ~= nil end, picker.items)
    vim.api.nvim_buf_set_lines(picker.buffers.main, 0, -1, true, lines)

    vim.wo[picker.windows.main].cursorline = true
    vim.cmd('redraw')

    local char = H.getcharstr()
    if char == nil then
      is_abort = true
      break
    end

    table.insert(_G.char_log, char)

    local special = special_chars[char]
    _G.info = { special = special }
    if special ~= nil then
      local do_continue = H.special_actions[special](picker)
      if not do_continue then break end
    elseif char == bs_key then
      picker.query[#picker.query] = nil
    else
      -- TODO: Handle unexpected chars (like arrow keys)
      table.insert(picker.query, char)
    end
  end

  H.picker_stop(picker)

  return picker.items[2]
end

H.picker_get_special_chars = function(picker)
  local term = H.replace_termcodes
  local res = {}

  -- Process config mappings
  for action_name, action_char in pairs(picker.opts.mappings) do
    res[term(action_char)] = action_name
  end

  -- Add some hand picked ones
  res[term('<Down>')] = 'move_down'
  res[term('<Up>')] = 'move_up'
  res[term('<PageDown>')] = 'scroll_down'
  res[term('<PageUp>')] = 'scroll_up'

  return res
end

H.picker_set_bordertext = function(picker)
  local win_id = picker.windows.main
  if vim.fn.has('nvim-0.9') == 0 or not H.is_valid_win(win_id) then return end

  -- Compute prompt truncated from left to fit into window
  local win_width = vim.api.nvim_win_get_width(win_id)
  local prompt_text = '> ' .. table.concat(picker.query, '') .. '▏'
  prompt_text = vim.fn.strcharpart(prompt_text, vim.fn.strchars(prompt_text) - win_width, win_width)
  local prompt = { { prompt_text, 'MiniPickPrompt' } }

  -- TODO:
  -- - Utilize footer for extra border info after
  --   https://github.com/neovim/neovim/pull/24739 is merged
  vim.api.nvim_win_set_config(picker.windows.main, { title = prompt })
  H.redraw()
end

H.picker_stop = function(picker)
  -- Close window and delete buffers
  vim.api.nvim_win_close(picker.windows.main, true)
  vim.api.nvim_buf_delete(picker.buffers.main, { force = true })
end

H.special_actions = {
  move_down = function(picker) return H.picker_move(picker, 'down') end,
  move_up = function(picker) return H.picker_move(picker, 'up') end,
}

H.picker_move = function(picker, direction)
  local cursor = vim.api.nvim_win_get_cursor(picker.windows.main)

  local new_line = cursor[1] + (direction == 'up' and -1 or 1)
  new_line = (new_line - 1) % vim.api.nvim_buf_line_count(picker.buffers.main) + 1
  vim.api.nvim_win_set_cursor(picker.windows.main, { new_line, 0 })

  return true
end

-- Special keys ---------------------------------------------------------------
H.get_special_keys = function()
  local res = {}
  for action_name, action_key in pairs(H.get_config().mappings) do
    res[H.replace_termcodes(action_key)] = action_name
  end
  return res
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.pick) %s', msg), 0) end

H.is_valid_buf = function(buf_id) return type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id) end

H.is_valid_win = function(win_id) return type(win_id) == 'number' and vim.api.nvim_win_is_valid(win_id) end

H.replace_termcodes = function(x)
  if x == nil then return nil end
  return vim.api.nvim_replace_termcodes(x, true, true, true)
end

H.expand_callable = function(x)
  if vim.is_callable(x) then return x() end
  return x
end

H.redraw = function() vim.cmd('redraw') end

H.redraw_scheduled = vim.schedule_wrap(H.redraw)

H.getcharstr = function(redraw_delay)
  -- Ensure that redraws still happen
  redraw_delay = redraw_delay or H.get_config().delay.redraw
  H.timers.getcharstr:start(0, redraw_delay, H.redraw_scheduled)
  local ok, char = pcall(vim.fn.getcharstr)
  H.timers.getcharstr:stop()

  -- Terminate if couldn't get input (like with <C-c>) or it is `<Esc>`
  if not ok or char == '\27' or char == '' then return end
  -- Replacing termcodes is probably not needed. Here just in case to ensure
  -- proper future lookup.
  -- return H.replace_termcodes(char)
  return char
end

H.window_update_highlight = function(win_id, new_from, new_to)
  local new_entry = new_from .. ':' .. new_to
  local replace_pattern = string.format('(%s:[^,]*)', vim.pesc(new_from))
  local new_winhighlight, n_replace = vim.wo[win_id].winhighlight:gsub(replace_pattern, new_entry)
  if n_replace == 0 then new_winhighlight = new_winhighlight .. ',' .. new_entry end

  -- Use `pcall()` because Neovim<0.8 doesn't allow non-existing highlight
  -- groups inside `winhighlight` (like `FloatTitle` at the time).
  pcall(function() vim.wo[win_id].winhighlight = new_winhighlight end)
end

--stylua: ignore
_G.source = {
  'abc', 'bcd', 'cde', 'def', 'efg', 'fgh', 'ghi', 'hij',
  'ijk', 'jkl', 'klm', 'lmn', 'mno', 'nop', 'opq', 'pqr',
  'qrs', 'rst', 'stu', 'tuv', 'uvw', 'vwx', 'wxy', 'xyz',
}
-- for _ = 1, 10 do
--   _G.source = vim.list_extend(_G.source, _G.source)
-- end

return MiniPick
