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
---     Execution is done when picker is still open.
---   - <info> `(function)` - Callable to be executed on item to show its
---     extended info. Should return a buffer identifier to be shown as info.
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
  source = H.expand_callable(source)
  if not vim.tbl_islist(source) or #source == 0 then
    H.error('`source` should be a non-empty array or function returning it.')
  end

  actions = actions or {}
  if type(actions) ~= 'table' then H.error('`actions` should be a table.') end

  opts = vim.tbl_deep_extend('force', H.get_config(), opts or {})
  opts.content.sort = opts.content.sort
    or function(match_inds, stritems, data) return MiniPick.default_sort('substring', match_inds, stritems, data) end

  local picker = H.picker_new(source, actions, opts)
  return H.picker_advance(picker)
end

MiniPick.default_sort = function(match_type, match_inds, stritems, data)
  if match_type == 'substring' then return H.sort_substring(match_inds, stritems, data) end
  if match_type == 'fuzzy' then return H.sort_fuzzy(match_inds, stritems, data) end
  H.error([[`match_type` should be one of 'substring' or 'fuzzy'.]])
end

MiniPick.builtin = {}

MiniPick.builtin.files = function(source_opts, actions, opts)
  local source = vim.fn.systemlist('rg --files --no-ignore --color never')
  actions = vim.tbl_deep_extend('force', { choose = H.file_edit, info = H.file_preview }, actions or {})
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
  -- Compute string items to work with and their initial matches
  local stritems = {}
  for i, x in ipairs(items) do
    x = H.expand_callable(x)
    if type(x) == 'table' then x = x.item end
    local to_add = type(x) == 'string' and x or tostring(x)
    table.insert(stritems, to_add)
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
    opts = opts,

    -- Associated Neovim objects
    buffers = { main = buf_id, info = nil, help = nil },
    windows = { main = win_id, init = vim.api.nvim_get_current_win() },

    -- Query data
    query = {},
    -- - Array of `stritems` indexes matching current query
    match_inds = nil,
    -- - History of `match_inds` for query for more performant deletion
    match_inds_history = {},

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

  -- - Set first item as current
  H.picker_set_current_ind(picker, 1)

  return picker
end

H.picker_advance = function(picker)
  local special_chars = H.picker_get_special_chars(picker)

  -- Start user query
  local is_abort, should_filtersort = false, false
  while true do
    -- Update picker
    H.picker_set_bordertext(picker)

    if should_filtersort then H.picker_filtersort(picker) end
    should_filtersort = false

    H.picker_set_lines(picker)
    vim.cmd('redraw')

    -- Advance query
    local char = H.getcharstr()
    if char == nil then
      is_abort = true
      break
    end

    local special = special_chars[char]
    if special ~= nil then
      local should_stop = H.special_actions[special](picker)
      if should_stop then break end
    else
      -- TODO: Handle unexpected chars (like arrow keys)

      -- Adding to query should always switch main buffer
      H.picker_show_main_buf(picker)

      table.insert(picker.query, char)
      -- NOTE: Filtersort only when query grows. When it shrinks,
      -- `match_inds_history` is used to set `match_inds`.
      should_filtersort = true
    end
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
  picker.match_inds_history[#picker.query] = match_inds
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
  local stritems, match_inds = picker.stritems, picker.match_inds
  local filter, sort = picker.opts.content.filter, picker.opts.content.sort

  local data = { query = picker.query }

  local new_match_inds = match_inds
  if filter ~= nil then
    new_match_inds = {}
    for i = 1, #match_inds do
      if filter(match_inds[i], stritems, data) then table.insert(new_match_inds, match_inds[i]) end
    end
  end

  new_match_inds = sort(new_match_inds, stritems, data)

  H.picker_set_match_inds(picker, new_match_inds)
  H.picker_set_current_ind(picker, 1)
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
  pcall(vim.api.nvim_win_close, picker.windows.main, true)
  pcall(vim.api.nvim_buf_delete, picker.buffers.main, { force = true })
end

H.special_actions = {
  choose = function(picker) return H.picker_choose(picker, nil) end,
  choose_in_split = function(picker) return H.picker_choose(picker, 'split') end,
  choose_in_tabpage = function(picker) return H.picker_choose(picker, 'tabnew') end,
  choose_in_vsplit = function(picker) return H.picker_choose(picker, 'vsplit') end,

  delete_all = function(picker) H.picker_delete(picker, #picker.query) end,
  delete_char = function(picker) H.picker_delete(picker, 1) end,
  delete_word = function(picker)
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

  move_down = function(picker) H.picker_move(picker, 1) end,
  move_up = function(picker) H.picker_move(picker, -1) end,

  scroll_down = function(picker) H.picker_move(picker, vim.api.nvim_win_get_height(picker.windows.main)) end,
  scroll_up = function(picker) H.picker_move(picker, -vim.api.nvim_win_get_height(picker.windows.main)) end,

  show_info = function(picker)
    local win_id, buf_id = picker.windows.main, picker.buffers.main
    if vim.api.nvim_win_get_buf(win_id) == picker.buffers.info then
      H.picker_show_main_buf(picker)
      picker.buffers.info = nil
      return
    end

    local info = picker.actions.info
    if not vim.is_callable(info) then return true end

    local item, index, data = H.picker_make_args(picker)
    if item == nil then return end

    local info_buf_id = info(item, index, data)
    if not H.is_valid_buf(info_buf_id) then return end

    picker.buffers.info = info_buf_id
    vim.api.nvim_win_set_buf(win_id, info_buf_id)
  end,

  stop = function(picker)
    H.picker_stop(picker)
    return true
  end,
}

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
    picker.match_inds_history[i] = nil
  end

  -- Restore `match_inds` from history
  picker.match_inds = picker.match_inds_history[left - 1]
  H.picker_set_current_ind(picker, 1)

  -- Ensure that main buffer is shown
  H.picker_show_main_buf(picker)
end

H.picker_move = function(picker, n)
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
H.sort_substring = function(match_inds, stritems, data)
  local query_pattern = vim.pesc(table.concat(data.query, ''))
  local new_match_inds = {}
  for _, ind in ipairs(match_inds) do
    if string.find(stritems[ind], query_pattern) ~= nil then table.insert(new_match_inds, ind) end
  end
  return new_match_inds
end

H.sort_fuzzy = function(match_inds, stritems, data)
  -- TODO
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
