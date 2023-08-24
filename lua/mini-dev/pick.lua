-- TODO:
--
-- Code:
-- - Help.
--
-- - ??Async callable `source`??
--
-- - Async execution to allow more responsiveness.
--
-- - Profile memory usage.
--
-- - Close on lost focus.
--
-- - Adapter for Telescope "native" sorters.
--
-- - Adapter for Telescope extensions.
--
-- Tests:
--
-- - Automatically respects 'ignorecase'/'smartcase' by adjusting `stritems`.
--
-- - Works with multibyte characters.
--
-- Docs:
--
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
--- * `MiniPickMatchCurrent` - current matched item.
--- * `MiniPickMatchOffsets` - offset characters matching query elements.
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
    direction = 'from_top',
    match = nil,
  },

  delay = {
    -- Delay between forced redraws when picker is active
    redraw = 10,
  },

  -- Special keys for active picker
  mappings = {
    caret_left = '<Left>',
    caret_right = '<Right>',

    choose = '<CR>',
    choose_in_split = '<C-s>',
    choose_in_tabpage = '<C-t>',
    choose_in_vsplit = '<C-v>',
    choose_in_quickfix = '<C-q>',

    delete_char = '<BS>',
    delete_char_right = '<Del>',
    delete_left = '<C-u>',
    delete_word = '<C-w>',

    move_down = '<C-n>',
    move_up = '<C-p>',

    scroll_down = '<C-f>',
    scroll_up = '<C-b>',

    show_help = '<C-h>',
    show_item = '<Tab>',

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
---     Execution is done when picker is still open.
---   - <show_item> `(function)` - Callable to be executed on item to show more
---     information about it. Should return a buffer identifier to be shown.
---
---   All actions will be called with the following arguments:
---   - `item` - selected item; `nil` if user manually stopped picker.
---   - `index` - index of selected item; `nil` if user manually stopped picker.
---   - `data` - extra useful data. A table with the following fields:
---       - <win_id_picker> - identifier of the picker window.
---       - <win_id_init> - identifier of the window where picker was started.
---@param opts table|nil Options. Should have the same structure as |MiniPick.config|.
---   Default values are inferred from there.
---
--- @return ... Tuple of selected item and its index. Both are `nil` if user
---   manually stopped picker.
MiniPick.start = function(source, actions, opts)
  -- TODO: Refactor to be `local_opts` and `global_opts`? This allows adding `source_name`, etc.
  source = H.expand_callable(source)
  if not vim.tbl_islist(source) or #source == 0 then
    H.error('`source` should be a non-empty array or function returning it.')
  end

  actions = actions or {}
  if type(actions) ~= 'table' then H.error('`actions` should be a table.') end

  opts = vim.tbl_deep_extend('force', H.get_config(), opts or {})
  opts.content.match = opts.content.match or MiniPick.default_match

  local picker = H.picker_new(source, actions, opts)
  return H.picker_advance(picker)
end

_G.profile = {}
MiniPick.default_match = function(inds, stritems, data)
  local start_time = vim.loop.hrtime()

  local match_data = H.match_filter(inds, stritems, data)
  local duration_match = 0.000001 * (vim.loop.hrtime() - start_time)

  local new_inds, new_offsets
  if match_data ~= nil then
    table.sort(match_data, H.match_compare)
    new_inds = vim.tbl_map(function(x) return x[3] end, match_data)
    new_offsets = vim.tbl_map(function(x) return x[4] end, match_data)
  else
    new_inds = vim.deepcopy(inds)
  end

  local duration_total = 0.000001 * (vim.loop.hrtime() - start_time)
  local n_sorted = #inds
  table.insert(_G.profile, {
    n_input = #inds,
    n_output = #new_inds,
    prompt = table.concat(data.query, ''),
    duration_match = duration_match,
    duration_match_per_item = duration_match / math.max(#inds, 1),
    duration_sort = (duration_total - duration_match),
    duration_sort_per_item = (duration_total - duration_match) / math.max(#new_inds, 1),
    duration_total = duration_total,
    duration_total_per_item = duration_total / math.max(#inds, 1),
  })

  return new_inds, new_offsets
end

MiniPick.ui_select = function(items, opts, on_choice)
  MiniPick.start(items, { choose = function(item, index, _) on_choice(item, index) end }, {})
end

MiniPick.builtin = {}

MiniPick.builtin.files = function(source_opts, actions, opts)
  local source = vim.fn.systemlist('rg --files --no-ignore --color never')
  actions = vim.tbl_deep_extend('force', { choose = H.file_edit, show_item = H.file_preview }, actions or {})
  return MiniPick.start(source, actions, opts)
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniPick.config

-- Namespaces
H.ns_id = {
  current = vim.api.nvim_create_namespace('MiniPickCurrent'),
  offsets = vim.api.nvim_create_namespace('MiniPickOffsets'),
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
    ['content.direction'] = { config.content.direction, 'string' },
    ['content.match'] = { config.content.match, 'function', true },

    ['delay.redraw'] = { config.delay.redraw, 'number' },

    ['mappings.caret_left'] = { config.mappings.caret_left, 'string' },
    ['mappings.caret_right'] = { config.mappings.caret_right, 'string' },
    ['mappings.choose'] = { config.mappings.choose, 'string' },
    ['mappings.choose_in_split'] = { config.mappings.choose_in_split, 'string' },
    ['mappings.choose_in_tabpage'] = { config.mappings.choose_in_tabpage, 'string' },
    ['mappings.choose_in_vsplit'] = { config.mappings.choose_in_vsplit, 'string' },
    ['mappings.choose_in_quickfix'] = { config.mappings.choose_in_quickfix, 'string' },
    ['mappings.delete_char'] = { config.mappings.delete_char, 'string' },
    ['mappings.delete_char_right'] = { config.mappings.delete_char_right, 'string' },
    ['mappings.delete_left'] = { config.mappings.delete_left, 'string' },
    ['mappings.delete_word'] = { config.mappings.delete_word, 'string' },
    ['mappings.move_up'] = { config.mappings.move_up, 'string' },
    ['mappings.scroll_down'] = { config.mappings.scroll_down, 'string' },
    ['mappings.scroll_up'] = { config.mappings.scroll_up, 'string' },
    ['mappings.show_help'] = { config.mappings.show_help, 'string' },
    ['mappings.show_item'] = { config.mappings.show_item, 'string' },
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
  hi('MiniPickMatchCurrent',     { link = 'CursorLine' })
  hi('MiniPickMatchOffsets',            { link = 'DiagnosticFloatingHint' })
  hi('MiniPickNormal',           { link = 'NormalFloat' })
  hi('MiniPickPrompt',           { link = 'DiagnosticFloatingInfo' })
end

-- Picker object --------------------------------------------------------------
H.picker_new = function(items, actions, opts)
  -- Compute string items to work with and their initial matches
  local stritems, stritems_ignorecase = {}, {}
  for i, x in ipairs(items) do
    x = H.expand_callable(x)
    if type(x) == 'table' then x = x.item end
    local to_add = type(x) == 'string' and x or tostring(x)
    table.insert(stritems, to_add)
    table.insert(stritems_ignorecase, to_add:lower())
  end

  -- Create buffer
  local buf_id = H.picker_new_buf()

  -- Create window
  local win_id = H.picker_new_win(buf_id, opts)

  -- Constuct and return object
  local picker = {
    -- Permanent data about picker (should not change)
    actions = actions,
    items = items,
    stritems = stritems,
    stritems_ignorecase = stritems_ignorecase,
    opts = opts,

    -- Associated Neovim objects
    buffers = { main = buf_id, item = nil, help = nil },
    windows = { main = win_id, init = vim.api.nvim_get_current_win() },

    -- Query data
    query = {},
    -- - Query index at which new entry will be inserted
    caret = 1,
    -- - Data about matches
    matches = {
      -- Array of `stritems` indexes matching current query
      inds = nil,
      -- Array of arrays: contains for every match byte indexes of where
      -- query element matched. Should have same length as `inds`.
      offsets = nil,
    },

    -- Cache for `matches` per prompt for more performant querying
    cache = {},

    -- View data
    -- - Index range of `matches.inds` currently visible. Present for significant
    --   performance increase to render only what is visible.
    visible_range = { from = nil, to = nil },
    -- - Index of `matches.inds` pointing at current item
    current_ind = nil,
  }

  -- - All items are matched at the start but no query items are matched
  H.picker_set_matches(picker, H.seq_along(items), nil)

  return picker
end

H.picker_advance = function(picker)
  local special_chars = H.picker_get_special_chars(picker)

  -- Start user query
  local is_abort, should_match, should_show_main_buf = false, false, true
  while true do
    -- Update picker
    if should_show_main_buf then H.picker_show_main_buf(picker) end
    if should_match then H.picker_match(picker) end

    H.picker_set_bordertext(picker)
    H.picker_set_lines(picker)
    H.redraw()

    -- Advance query
    local char = H.getcharstr()
    if char == nil then
      is_abort = true
      break
    end

    local action_name = special_chars[char]
    H.actions[action_name](picker, char)

    local should_stop = action_name == 'stop' or vim.startswith(action_name or '', 'choose')
    if should_stop then break end

    should_match = action_name == nil or vim.startswith(action_name or '', 'delete')
    should_show_main_buf = not vim.startswith(action_name or '', 'show')
  end

  local item, index, data = H.picker_make_args(picker)
  H.picker_stop(picker)

  if is_abort then return nil, nil end
  return item, index
end

H.picker_new_buf = function()
  local buf_id = vim.api.nvim_create_buf(false, true)
  vim.bo[buf_id].filetype = 'minipick'
  vim.b[buf_id].minicursorword_disable = true
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
  vim.wo[win_id].foldenable = false
  vim.wo[win_id].list = true
  vim.wo[win_id].listchars = 'extends:…'
  vim.wo[win_id].wrap = false
  H.window_update_highlight(win_id, 'NormalFloat', 'MiniPickNormal')
  H.window_update_highlight(win_id, 'FloatBorder', 'MiniPickBorder')

  return win_id
end

H.picker_set_matches = function(picker, inds, offsets)
  picker.matches = { inds = inds, offsets = offsets }
  picker.cache[table.concat(picker.query)] = { inds = inds, offsets = offsets }

  -- Reset current index if match indexes are updated
  H.picker_set_current_ind(picker, 1)
end

H.picker_set_current_ind = function(picker, ind)
  local n_matches = #picker.matches.inds
  if n_matches == 0 then
    picker.current_ind, picker.visible_range = nil, {}
    return
  end
  if not H.is_valid_win(picker.windows.main) then return end

  -- Wrap index around edges
  ind = (ind - 1) % n_matches + 1

  -- Compute visible range (tries to center current index)
  local win_height = vim.api.nvim_win_get_height(picker.windows.main)
  local to = math.min(n_matches, math.floor(ind + 0.5 * win_height))
  local from = math.max(1, to - win_height + 1)
  to = from + math.min(win_height, n_matches) - 1

  -- Set data
  picker.current_ind = ind
  picker.visible_range = { from = from, to = to }
end

H.picker_set_lines = function(picker)
  local buf_id = picker.buffers.main
  if not H.is_valid_buf(buf_id) then return end

  H.clear_namespace(buf_id, H.ns_id.current)
  H.clear_namespace(buf_id, H.ns_id.offsets)

  local visible_range = picker.visible_range
  if visible_range.from == nil or visible_range.to == nil then
    H.set_buflines(buf_id, {})
    return
  end

  -- Construct lines and extmarks data to show
  local stritems, inds, offsets = picker.stritems, picker.matches.inds, picker.matches.offsets or {}

  local lines, line_offsets = {}, {}
  local cur_ind, cur_line = picker.current_ind, nil
  for i = picker.visible_range.from, picker.visible_range.to do
    table.insert(lines, stritems[inds[i]])
    table.insert(line_offsets, offsets[i])
    if i == cur_ind then cur_line = #lines end
  end

  -- Set lines
  H.set_buflines(buf_id, lines)

  -- Hlighlight line for current matched item
  local cur_extmark_opts = { end_row = cur_line, end_col = 0, hl_eol = true, hl_group = 'MiniPickMatchCurrent' }
  cur_extmark_opts.priority = 200
  H.set_extmark(buf_id, H.ns_id.current, cur_line - 1, 0, cur_extmark_opts)

  -- Add match offset highlighting
  local ns_id_offsets = H.ns_id.offsets
  for i = 1, #line_offsets do
    H.picker_highlight_offsets(buf_id, ns_id_offsets, i, line_offsets[i], lines[i])
  end
end

H.picker_highlight_offsets = function(buf_id, ns_id, line_num, cols, line_str)
  local opts = { hl_group = 'MiniPickMatchOffsets', hl_mode = 'combine', priority = 199 }
  for _, col in ipairs(cols) do
    opts.end_row, opts.end_col = line_num - 1, H.get_next_char_bytecol(line_str, col)
    H.set_extmark(buf_id, ns_id, line_num - 1, col - 1, opts)
  end
end

H.picker_match = function(picker)
  -- Try to use cache first
  local prompt_cache = picker.cache[table.concat(picker.query)]
  if prompt_cache ~= nil then return H.picker_set_matches(picker, prompt_cache.inds, prompt_cache.offsets) end

  local is_ignorecase = H.picker_is_ignorecase(picker)
  local stritems = is_ignorecase and picker.stritems_ignorecase or picker.stritems
  local data = { query = is_ignorecase and vim.tbl_map(vim.fn.tolower, picker.query) or picker.query }

  local new_inds, new_offsets = picker.opts.content.match(picker.matches.inds, stritems, data)
  H.picker_set_matches(picker, new_inds, new_offsets)
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

H.picker_is_ignorecase = function(picker)
  if not vim.o.ignorecase then return false end
  if not vim.o.smartcase then return true end
  local prompt = table.concat(picker.query, '')
  return vim.fn.match(prompt, '[[:upper:]]') < 0
end

H.picker_set_bordertext = function(picker)
  local win_id = picker.windows.main
  if vim.fn.has('nvim-0.9') == 0 or not H.is_valid_win(win_id) then return end

  -- Compute prompt truncated from left to fit into window
  local query, caret = picker.query, picker.caret
  local before_caret = table.concat(vim.list_slice(query, 1, caret - 1), '')
  local after_caret = table.concat(vim.list_slice(query, caret, #query), '')
  local prompt_text = '> ' .. before_caret .. '▏' .. after_caret

  local win_width = vim.api.nvim_win_get_width(win_id)
  prompt_text = vim.fn.strcharpart(prompt_text, vim.fn.strchars(prompt_text) - win_width, win_width)
  local prompt = { { prompt_text, 'MiniPickPrompt' } }

  -- TODO:
  -- - Utilize footer for extra border info after
  --   https://github.com/neovim/neovim/pull/24739 is merged
  vim.api.nvim_win_set_config(win_id, { title = prompt })
  vim.wo[win_id].list = true
end

H.picker_stop = function(picker)
  -- Close window and delete buffers
  pcall(vim.api.nvim_win_close, picker.windows.main, true)
  pcall(vim.api.nvim_buf_delete, picker.buffers.main, { force = true })
  picker.cache = nil
end

--stylua: ignore
H.actions = {
  caret_left  = function(picker, _) H.picker_move_caret(picker, -1) end,
  caret_right = function(picker, _) H.picker_move_caret(picker, 1)  end,

  choose            = function(picker, _) H.picker_choose(picker, nil)      end,
  choose_in_split   = function(picker, _) H.picker_choose(picker, 'split')  end,
  choose_in_tabpage = function(picker, _) H.picker_choose(picker, 'tabnew') end,
  choose_in_vsplit  = function(picker, _) H.picker_choose(picker, 'vsplit') end,

  delete_char       = function(picker, _) H.picker_delete(picker, 1)           end,
  delete_char_right = function(picker, _) H.picker_delete(picker, 0)           end,
  delete_left       = function(picker, _) H.picker_delete(picker, picker.caret - 1)  end,
  delete_word = function(picker, _)
    local init, n_del = picker.caret - 1, 0
    if init == 0 then return end
    local ref_is_keyword = vim.fn.match(picker.query[init], '[[:keyword:]]') >= 0
    for i = init, 1, -1 do
      local cur_is_keyword = vim.fn.match(picker.query[i], '[[:keyword:]]') >= 0
      if (ref_is_keyword and not cur_is_keyword) or (not ref_is_keyword and cur_is_keyword) then break end
      n_del = n_del + 1
    end
    H.picker_delete(picker, n_del)
  end,

  move_down = function(picker, _) H.picker_move_current(picker, 1)  end,
  move_up   = function(picker, _) H.picker_move_current(picker, -1) end,

  scroll_down = function(picker, _) H.picker_move_current(picker, vim.api.nvim_win_get_height(picker.windows.main))  end,
  scroll_up   = function(picker, _) H.picker_move_current(picker, -vim.api.nvim_win_get_height(picker.windows.main)) end,

  show_help = function(picker, _)
    -- TODO
  end,

  show_item = function(picker, _)
    local win_id, buf_id = picker.windows.main, picker.buffers.main
    if vim.api.nvim_win_get_buf(win_id) == picker.buffers.item then
      H.picker_show_main_buf(picker)
      picker.buffers.item = nil
      return
    end

    local show_item = picker.actions.show_item
    if not vim.is_callable(show_item) then return true end

    local item, index, data = H.picker_make_args(picker)
    if item == nil then return end

    local info_buf_id = show_item(item, index, data)
    if not H.is_valid_buf(info_buf_id) then return end

    picker.buffers.item = info_buf_id
    vim.api.nvim_win_set_buf(win_id, info_buf_id)
  end,

  stop = function(picker, _) H.picker_stop(picker) end,
}
setmetatable(H.actions, {
  -- If no special action, add character to the query
  __index = function()
    -- TODO: Handle unexpected chars (like arrow keys)
    return function(picker, char)
      table.insert(picker.query, picker.caret, char)
      picker.caret = picker.caret + 1
    end
  end,
})

H.picker_choose = function(picker, pre_command)
  local choose = picker.actions.choose
  if not vim.is_callable(choose) then return true end

  local win_id_init = picker.windows.init
  if pre_command ~= nil and H.is_valid_win(win_id_init) then
    vim.api.nvim_win_call(win_id_init, function() vim.cmd(pre_command) end)
  end

  local item, index, data = H.picker_make_args(picker)
  choose(item, index, data)

  return true
end

H.picker_delete = function(picker, n)
  local delete_to_left = n > 0
  local left = delete_to_left and math.max(picker.caret - n, 1) or picker.caret
  local right = delete_to_left and picker.caret - 1 or math.min(picker.caret + n, #picker.query)
  for i = right, left, -1 do
    table.remove(picker.query, i)
  end
  picker.caret = left
end

H.picker_move_caret = function(picker, n) picker.caret = math.min(math.max(picker.caret + n, 1), #picker.query + 1) end

H.picker_move_current = function(picker, n)
  local n_matches = #picker.matches.inds
  if n_matches == 0 then return end

  local current_ind = picker.current_ind
  -- Wrap around edges only if current index is at edge
  if current_ind == 1 and n < 0 then
    current_ind = n_matches
  elseif current_ind == n_matches and n > 0 then
    current_ind = 1
  else
    current_ind = current_ind + n
  end
  current_ind = math.min(math.max(current_ind, 1), n_matches)

  H.picker_set_current_ind(picker, current_ind)
  H.picker_set_lines(picker)
end

H.picker_make_args = function(picker)
  local ind = picker.matches.inds[picker.current_ind]
  local item = picker.items[ind]
  local data = { win_id_picker = picker.windows.main, win_id_init = picker.windows.init }
  return item, ind, data
end

H.picker_show_main_buf = function(picker) vim.api.nvim_win_set_buf(picker.windows.main, picker.buffers.main) end

-- Sort -----------------------------------------------------------------------
H.match_filter = function(inds, stritems, data)
  local query, n_query = data.query, #data.query
  -- 'abc' - fuzzy match; "'abc" and 'a' - exact substring match;
  -- '^abc' and 'abc$' - exact substring match at start and end.
  local is_exact_plain, is_exact_start, is_exact_end = query[1] == "'", query[1] == '^', query[n_query] == '$'

  local start_offset = (is_exact_plain or is_exact_start) and 2 or 1
  local end_offset = (not is_exact_plain and is_exact_end) and (n_query - 1) or n_query
  query = vim.list_slice(data.query, start_offset, end_offset)
  n_query = #query

  if n_query == 0 then return nil end

  if not (is_exact_plain or is_exact_start or is_exact_end) and n_query > 1 then
    return H.match_filter_fuzzy(inds, stritems, query)
  end

  local prefix = is_exact_start and '^' or ''
  local suffix = is_exact_end and '$' or ''
  local pattern = prefix .. vim.pesc(table.concat(query)) .. suffix

  return H.match_filter_exact(inds, stritems, query, pattern)
end

H.match_filter_exact = function(inds, stritems, query, pattern)
  -- All matches have same match offsets relative to match start
  local rel_offsets, offset = { 0 }, 0
  for i = 2, #query do
    offset = offset + query[i - 1]:len()
    rel_offsets[i] = offset
  end

  local match_single = H.match_filter_exact_single
  local match_data = {}
  for _, ind in ipairs(inds) do
    local data = match_single(stritems[ind], ind, pattern, rel_offsets)
    if data ~= nil then table.insert(match_data, data) end
  end

  return match_data
end

H.match_filter_exact_single = function(candidate, index, pattern, rel_offsets)
  local start = string.find(candidate, pattern)
  if start == nil then return nil end

  local offsets = {}
  for i = 1, #rel_offsets do
    offsets[i] = start + rel_offsets[i]
  end
  return { 0, start, index, offsets }
end

H.match_filter_fuzzy = function(inds, stritems, query)
  local match_single, find_query = H.match_filter_fuzzy_single, H.find_query
  local match_data = {}
  for _, ind in ipairs(inds) do
    local data = match_single(stritems[ind], ind, query, find_query)
    if data ~= nil then table.insert(match_data, data) end
  end
  return match_data
end

H.match_filter_fuzzy_single = function(candidate, index, query, find_query)
  -- Search for query chars match positions with the following properties:
  -- - All are present in `candidate` in the same order.
  -- - Has smallest width among all such match positions.
  -- - Among same width has smallest first match.
  -- This same algorithm is used in 'mini.fuzzy' and has more comments.

  -- Search forward to find matching positions with left-most last char match
  local first, last = find_query(candidate, query, 1)
  if first == nil then return nil end
  if first == last then return { 0, first, index, { first } } end

  -- Iteratively try to find better matches by advancing last match
  local best_first, best_last, best_width = first, last, last - first
  while last do
    local width = last - first
    if width < best_width then
      best_first, best_last, best_width = first, last, width
    end

    first, last = find_query(candidate, query, first + 1)
  end

  -- Actually compute best matched positions from best last letter match
  local best_offsets = { best_first }
  local offset, to = best_first, best_first
  for i = 2, #query do
    offset, to = string.find(candidate, query[i], to + 1, true)
    table.insert(best_offsets, offset)
  end

  return { best_last - best_first, best_first, index, best_offsets }
end

H.find_query = function(s, query, init)
  local first, to = string.find(s, query[1], init, true)
  if first == nil then return nil, nil end

  -- Both `first` and `last` indicate the start byte of first and last match
  local last = first
  for i = 2, #query do
    last, to = string.find(s, query[i], to + 1, true)
    if not last then return nil, nil end
  end
  return first, last
end

H.match_compare = function(a, b)
  return a[1] < b[1] or (a[1] == b[1] and (a[2] < b[2] or (a[2] == b[2] and a[3] < b[3])))

  -- return a.width < b.width or (a.width == b.width and (a.start < b.start or (a.start == b.start and a.ind < b.ind)))

  -- if a[1] ~= b[1] then return a[1] < b[1] end
  -- if a[2] ~= b[2] then return a[2] < b[2] end
  -- return a[3] < b[3]

  -- return a.width < b.width
  --   or (a.width == b.width and a.start < b.start)
  --   or (a.width == b.width and a.start == b.start and a.ind < b.ind)

  -- return a[1] < b[1]
  --   or (a[1] == b[1] and a[2] < b[2])
  --   or (a[1] == b[1] and a[2] == b[2] and a[3] < b[3])
end

-- Built-ins ------------------------------------------------------------------
H.file_edit = function(path, _, data)
  if not H.is_valid_win(data.win_id_init) then return end

  -- Try to use already created buffer, if present. This avoids not needed
  -- `:edit` call and avoids some problems with auto-root from 'mini.misc'.
  local path_buf_id
  for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
    if H.is_valid_buf(buf_id) and vim.api.nvim_buf_get_name(buf_id) == path then path_buf_id = buf_id end
  end

  if path_buf_id ~= nil then
    vim.api.nvim_win_set_buf(data.win_id_init, path_buf_id)
  elseif vim.fn.filereadable(path) == 1 then
    -- Avoid possible errors with `:edit`, like present swap file
    pcall(vim.fn.win_execute, data.win_id_init, 'edit ' .. vim.fn.fnameescape(path))
  end
end

H.file_preview = function(path)
  -- Createe buffer
  local buf_id = vim.api.nvim_create_buf(false, true)

  -- Determine if file is text. This is not 100% proof, but good enough.
  -- Source: https://github.com/sharkdp/content_inspector
  local fd = vim.loop.fs_open(path, 'r', 1)
  local is_text = vim.loop.fs_read(fd, 1024):find('\0') == nil
  vim.loop.fs_close(fd)
  if not is_text then
    H.set_buflines(buf_id, { '-Non-text-file-' })
    return buf_id
  end

  -- Compute lines. Limit number of read lines to work better on large files.
  local has_lines, read_res = pcall(vim.fn.readfile, path, '', vim.o.lines)
  -- - Make sure that lines don't contain '\n' (might happen in binary files).
  local lines = has_lines and vim.split(table.concat(read_res, '\n'), '\n') or {}

  -- Set lines
  H.set_buflines(buf_id, lines)

  -- Add highlighting on Neovim>=0.8 which has stabilized API
  if vim.fn.has('nvim-0.8') == 1 then
    local ft = vim.filetype.match({ buf = buf_id, filename = path })
    local ok, _ = pcall(vim.treesitter.start, buf_id, ft)
    if not ok then vim.bo[buf_id].syntax = ft end
  end

  return buf_id
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.pick) %s', msg), 0) end

H.is_valid_buf = function(buf_id) return type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id) end

H.is_valid_win = function(win_id) return type(win_id) == 'number' and vim.api.nvim_win_is_valid(win_id) end

H.replace_termcodes = function(x)
  if x == nil then return nil end
  return vim.api.nvim_replace_termcodes(x, true, true, true)
end

H.set_buflines = function(buf_id, lines) pcall(vim.api.nvim_buf_set_lines, buf_id, 0, -1, false, lines) end

H.set_extmark = function(...) pcall(vim.api.nvim_buf_set_extmark, ...) end

H.clear_namespace = function(buf_id, ns_id) pcall(vim.api.nvim_buf_clear_namespace, buf_id, ns_id, 0, -1) end

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

  -- Terminate if couldn't get input (like with <C-c>)
  if not ok or char == '' then return end
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

H.seq_along = function(arr)
  local res = {}
  for i = 1, #arr do
    table.insert(res, i)
  end
  return res
end

H.get_next_char_bytecol = function(line_str, col)
  local utf_index = vim.str_utfindex(line_str, math.min(line_str:len(), col))
  return vim.str_byteindex(line_str, utf_index)
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

-- _G.source_random = {}
-- for _ = 1, 1000000 do
--   local len = math.random(100)
--   local t = {}
--   for i = 1, len do
--     table.insert(t, string.char(96 + math.random(26)))
--   end
--   table.insert(_G.source_random, table.concat(t, ''))
-- end

return MiniPick
