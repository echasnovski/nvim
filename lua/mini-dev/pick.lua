-- TODO:
--
-- Code:
-- - Profile memory usage.
--
-- - ?Left/right arrows to adjust caret?
--
-- - Close on lost focus.
--
-- - Info.
--
-- - Help.
--
-- - ??Async callable `source`??
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
-- - Default `config.show_item` (`<C-i>`) is usually `<Tab>` on most terminal
--   emulators.
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
    filter = nil,
    sort = nil,
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

    delete_all = '<C-u>',
    delete_char = '<BS>',
    delete_word = '<C-w>',

    move_down = '<C-n>',
    move_up = '<C-p>',

    scroll_down = '<C-f>',
    scroll_up = '<C-b>',

    show_help = '<C-h>',
    show_item = '<C-i>',

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
  opts.content.sort = opts.content.sort or MiniPick.default_sort

  local picker = H.picker_new(source, actions, opts)
  return H.picker_advance(picker)
end

_G.profile = {}
MiniPick.default_sort = function(match_inds, stritems, data)
  local start_time = vim.loop.hrtime()

  local match_data, do_sort = H.sort_match(match_inds, stritems, data)
  local duration_match = 0.000001 * (vim.loop.hrtime() - start_time)

  local res
  if do_sort then
    table.sort(match_data, H.sort_compare)
    res = vim.tbl_map(function(x) return x.ind end, match_data)
  else
    res = match_data
  end

  local duration_total = 0.000001 * (vim.loop.hrtime() - start_time)
  local n_sorted = #match_inds
  table.insert(_G.profile, {
    n_input = #match_inds,
    n_output = #res,
    prompt = table.concat(data.query, ''),
    duration_match = duration_match,
    duration_match_per_item = duration_match / math.max(#match_inds, 1),
    duration_sort = (duration_total - duration_match),
    duration_sort_per_item = (duration_total - duration_match) / math.max(#res, 1),
    duration_total = duration_total,
    duration_total_per_item = duration_total / math.max(#match_inds, 1),
  })

  return res
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
    ['content.direction'] = { config.content.direction, 'string' },
    ['content.filter'] = { config.content.filter, 'function', true },
    ['content.sort'] = { config.content.sort, 'function', true },

    ['delay.redraw'] = { config.delay.redraw, 'number' },

    ['mappings.choose'] = { config.mappings.choose, 'string' },
    ['mappings.choose_in_split'] = { config.mappings.choose_in_split, 'string' },
    ['mappings.choose_in_tabpage'] = { config.mappings.choose_in_tabpage, 'string' },
    ['mappings.choose_in_vsplit'] = { config.mappings.choose_in_vsplit, 'string' },
    ['mappings.choose_in_quickfix'] = { config.mappings.choose_in_quickfix, 'string' },
    ['mappings.delete_all'] = { config.mappings.delete_all, 'string' },
    ['mappings.delete_char'] = { config.mappings.delete_char, 'string' },
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
  hi('MiniPickItemCurrent',      { link = 'CursorLine' })
  hi('MiniPickMatch',            { link = 'Search' })
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
    -- - Array of `stritems` indexes matching current query
    match_inds = nil,

    -- Cache per prompt for more performant querying
    cache = {},

    -- View data
    -- - Index range of `match_inds` currently visible. Present for significant
    --   performance increase to render only what is visible.
    visible_range = { from = nil, to = nil },
    -- - Index of `match_inds` pointing at current item
    current_ind = nil,
    -- - Extmark index of curent item
    current_extmark_id = nil,
  }

  -- - All items are matched at the start
  H.picker_set_match_inds(picker, H.seq_along(items))

  return picker
end

H.picker_advance = function(picker)
  local special_chars = H.picker_get_special_chars(picker)

  -- Start user query
  local is_abort, should_filtersort, should_show_main_buf = false, false, true
  while true do
    -- Update picker
    if should_show_main_buf then H.picker_show_main_buf(picker) end
    if should_filtersort then H.picker_filtersort(picker) end

    H.picker_set_bordertext(picker)
    H.picker_set_lines(picker)
    vim.cmd('redraw')

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

    should_filtersort = action_name == nil or vim.startswith(action_name or '', 'delete')
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
  vim.wo[win_id].wrap = false
  H.window_update_highlight(win_id, 'NormalFloat', 'MiniPickNormal')
  H.window_update_highlight(win_id, 'FloatBorder', 'MiniPickBorder')

  return win_id
end

H.picker_set_match_inds = function(picker, match_inds)
  picker.match_inds = match_inds
  picker.cache[table.concat(picker.query)] = match_inds

  -- Reset current index if match indexes are updated
  H.picker_set_current_ind(picker, 1)
end

H.picker_set_current_ind = function(picker, ind)
  local n_matches = #picker.match_inds
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

  local visible_range = picker.visible_range
  if visible_range.from == nil or visible_range.to == nil then
    vim.api.nvim_buf_set_lines(buf_id, 0, -1, true, {})
    pcall(vim.api.nvim_buf_del_extmark, buf_id, H.ns_id.current, picker.current_extmark_id)
    pcall(vim.api.nvim_buf_clear_namespace, buf_id, H.ns_id.matches, 0, -1)
    return
  end

  -- Construct lines and extmarks to show
  local stritems, match_inds = picker.stritems, picker.match_inds
  local lines = {}
  local current_ind, current_line = picker.current_ind, nil
  for i = picker.visible_range.from, picker.visible_range.to do
    table.insert(lines, stritems[match_inds[i]])
    if i == current_ind then current_line = #lines end
  end

  -- Set lines and extmarks
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, true, lines)

  local current_extmark_opts = {
    id = picker.current_extmark_id,
    end_row = current_line,
    end_col = 0,
    hl_eol = true,
    hl_group = 'MiniPickItemCurrent',
  }
  pcall(vim.api.nvim_buf_set_extmark, buf_id, H.ns_id.current, current_line - 1, 0, current_extmark_opts)

  -- TODO: Add match highlighting
end

H.picker_filtersort = function(picker)
  -- Try to use cache first
  local new_match_inds = picker.cache[table.concat(picker.query)]
  if new_match_inds ~= nil then return H.picker_set_match_inds(picker, new_match_inds) end

  local stritems = H.picker_is_ignorecase(picker) and picker.stritems_ignorecase or picker.stritems
  local match_inds = picker.match_inds
  local filter, sort = picker.opts.content.filter, picker.opts.content.sort

  local data = { query = picker.query }

  if filter ~= nil then
    new_match_inds = {}
    for i = 1, #match_inds do
      if filter(match_inds[i], stritems, data) then table.insert(new_match_inds, match_inds[i]) end
    end
  end

  new_match_inds = sort(new_match_inds or match_inds, stritems, data)
  H.picker_set_match_inds(picker, new_match_inds)
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
  pcall(vim.api.nvim_win_close, picker.windows.main, true)
  pcall(vim.api.nvim_buf_delete, picker.buffers.main, { force = true })
  picker.cache = nil
end

H.actions = {
  choose = function(picker, _) return H.picker_choose(picker, nil) end,
  choose_in_split = function(picker, _) return H.picker_choose(picker, 'split') end,
  choose_in_tabpage = function(picker, _) return H.picker_choose(picker, 'tabnew') end,
  choose_in_vsplit = function(picker, _) return H.picker_choose(picker, 'vsplit') end,

  delete_all = function(picker, _) H.picker_delete(picker, #picker.query) end,
  delete_char = function(picker, _) H.picker_delete(picker, 1) end,
  delete_word = function(picker, _)
    local n_query, n_del = #picker.query, 0
    if n_query == 0 then return end
    local ref_is_keyword = vim.fn.match(picker.query[n_query], '[[:keyword:]]') >= 0
    for i = n_query, 1, -1 do
      local cur_is_keyword = vim.fn.match(picker.query[i], '[[:keyword:]]') >= 0
      if (ref_is_keyword and not cur_is_keyword) or (not ref_is_keyword and cur_is_keyword) then break end
      n_del = n_del + 1
    end
    H.picker_delete(picker, n_del)
  end,

  move_down = function(picker, _) H.picker_move_current(picker, 1) end,
  move_up = function(picker, _) H.picker_move_current(picker, -1) end,

  scroll_down = function(picker, _) H.picker_move_current(picker, vim.api.nvim_win_get_height(picker.windows.main)) end,
  scroll_up = function(picker, _) H.picker_move_current(picker, -vim.api.nvim_win_get_height(picker.windows.main)) end,

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
    return function(picker, char) table.insert(picker.query, char) end
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
  local right, left = #picker.query, math.max(#picker.query - n + 1, 1)
  for i = right, left, -1 do
    picker.query[i] = nil
  end
end

H.picker_move_current = function(picker, n)
  local n_matches = #picker.match_inds
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
  local ind = picker.match_inds[picker.current_ind]
  local item = picker.items[ind]
  local data = { win_id_picker = picker.windows.main, win_id_init = picker.windows.init }
  return item, ind, data
end

H.picker_show_main_buf = function(picker) vim.api.nvim_win_set_buf(picker.windows.main, picker.buffers.main) end

-- Sort -----------------------------------------------------------------------
H.sort_match = function(match_inds, stritems, data)
  local is_exact_plain, is_exact_start, is_exact_end =
    data.query[1] == "'", data.query[1] == '^', data.query[#data.query] == '$'

  local start_offset = (is_exact_plain or is_exact_start) and 2 or 1
  local end_offset = (not is_exact_plain and is_exact_end) and -2 or -1
  local prompt = table.concat(data.query, ''):sub(start_offset, end_offset)

  if prompt == '' then return vim.deepcopy(match_inds), false end

  if not (is_exact_plain or is_exact_start or is_exact_end) then
    -- NOTE: Using manual query traversing is slower on small queries (1-3) but
    -- increasingly faster on bigger ones (5+). Probably due to how matching
    -- with many `.-` is implemented in `string.find()`.

    -- return H.sort_match_fuzzy(match_inds, stritems, data)
    return H.sort_match_fuzzy_2(match_inds, stritems, data)
  end

  local prefix = is_exact_start and '^' or ''
  local suffix = is_exact_end and '$' or ''
  local pattern = prefix .. vim.pesc(prompt) .. suffix

  return H.sort_match_exact(match_inds, stritems, pattern)
end

H.sort_match_exact = function(match_inds, stritems, pattern)
  local match_data = {}
  for _, ind in ipairs(match_inds) do
    local start = string.find(stritems[ind], pattern)
    if start ~= nil then table.insert(match_data, { width = 0, start = start, ind = ind }) end
  end
  return match_data, true
end

H.sort_match_fuzzy = function(match_inds, stritems, data)
  local query, query_rev = data.query, {}
  for i = #query, 1, -1 do
    -- Use `reverse`
    table.insert(query_rev, query[i]:reverse())
  end

  local find_best_positions = H.sort_find_best_positions
  local match_data = {}
  for _, ind in ipairs(match_inds) do
    local pos = find_best_positions(stritems[ind], query, query_rev)
    if pos ~= nil then table.insert(match_data, { width = pos[#pos] - pos[1] + 1, start = pos[1], ind = ind }) end
  end
  return match_data, true
end

H.sort_find_best_positions = function(candidate, query, query_rev)
  local n_query = #query
  if n_query == 0 or vim.fn.strchars(candidate) < n_query then return nil end

  -- Search for query chars match positions with the following properties:
  -- - All are present in `candidate` in the same order.
  -- - Has smallest width among all such match positions.
  -- This same algorithm is used in 'mini.fuzzy' and has more comments.

  local n = 1

  -- Search forward to find matching positions with left-most last char match
  local pos_last = 0
  for i = 1, n_query do
    _, pos_last = string.find(candidate, query[i], pos_last + 1)
    if not pos_last then break end
  end

  if not pos_last then
    table.insert(_G.back_and_fourth_n_iterations, n)
    return nil
  end
  if n_query == 1 then
    table.insert(_G.back_and_fourth_n_iterations, n)
    return { pos_last }
  end

  -- Iteratively try to find better matches by iteratively pulling up first
  -- matched position (results in smaller width) and advancing last match
  local best_pos_last, best_width = pos_last, math.huge
  local n_candidate, rev_candidate = candidate:len(), candidate:reverse()

  local cutoff = H.get_config().cutoff
  while pos_last do
    local rev_first = n_candidate - pos_last + 1
    for i = 2, #query_rev do
      rev_first = string.find(rev_candidate, query_rev[i], rev_first + 1)
    end
    local first = n_candidate - rev_first + 1
    local width = pos_last - first + 1

    if width < best_width then
      best_pos_last, best_width = pos_last, width
    end

    _, pos_last = string.find(candidate, query[n_query], pos_last + 1)
    n = n + 1
  end
  table.insert(_G.back_and_fourth_n_iterations, n)

  -- Actually compute best matched positions from best last letter match
  local best_positions = { best_pos_last }
  local rev_pos = n_candidate - best_pos_last + 1
  for i = 2, #query_rev do
    rev_pos = string.find(rev_candidate, query_rev[i], rev_pos + 1)
    table.insert(best_positions, 1, n_candidate - rev_pos + 1)
  end

  return best_positions
end

H.sort_match_fuzzy_2 = function(match_inds, stritems, data)
  local pattern = table.concat(vim.tbl_map(vim.pesc, data.query), '.-')

  local find_best_range = H.sort_find_best_range
  local match_data = {}
  for _, ind in ipairs(match_inds) do
    local range = find_best_range(stritems[ind], pattern)
    if range ~= nil then table.insert(match_data, { width = range[2] - range[1], start = range[1], ind = ind }) end
  end
  return match_data, true
end

_G.back_and_fourth_n_iterations = {}
H.sort_find_best_range = function(candidate, pattern)
  local match = { string.find(candidate, pattern) }
  if match[1] == nil then return nil end

  -- Possibly improve
  local best_match, best_width = match, match[2] - match[1]
  local n = 1
  while match[1] ~= nil do
    if (match[2] - match[1]) < best_width then
      best_match, best_width = match, match[2] - match[1]
    end
    match = { string.find(candidate, pattern, match[1] + 1) }
    n = n + 1
  end
  table.insert(_G.back_and_fourth_n_iterations, n)

  return best_match
end

H.sort_compare = function(a, b)
  return a.width < b.width
    or (a.width == b.width and a.start < b.start)
    or (a.width == b.width and a.start == b.start and a.ind < b.ind)
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
  else
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
