-- TODO:
--
-- - Add help tags builtin.
--
-- - Async execution to allow more responsiveness:
--     - `get_querytick()`
--     - `check_running` utilizing coroutines and `vim.schedule()`
--     - Call `check_running()` during filter and sort iterations.
--
-- - Close on lost focus.
--
-- - ?Add `live_grep` builtin?
--
-- - ?Add `diagnostic` builtin?
--
-- - ?Add "recent picker"? Has implications about memory.
--
-- - Make sure all actions work when `items` is not yet set.
--
-- - Profile memory usage.
--
-- - Adapter for Telescope "native" sorters.
--
-- - Adapter for Telescope extensions.
--
-- Tests:
--
-- - All actions should work when `items` is not yet set.
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
--- * `MiniPickBorder` - window border.
--- * `MiniPickBorderBusy` - window border while picker is busy processing.
--- * `MiniPickBorderText` - non-prompt on border.
--- * `MiniPickInfoHeader` - headers in the info buffer.
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
---@text # Source ~
---
--- `config.source` defines single picker related data. Usually should be set
--- for each picker individually inside |MiniPick.start()|. Setting them directly
--- in config serves as default fallback.
---
--- `source.items` is an array of items to choose from or callable.
--- Each item can be either string or table containing string `item` field.
--- Callable can either return array of items directly (use as is) or not
--- (expected to call |MiniPick.set_items()| explicitly; right away or later).
---
--- `source.name` is a string containing the source name.
---
--- `source.preview` is a callable to be executed on item to show more
--- information about it. ??? What signature and what should it return ???
--- If `nil` (default) uses |MiniPick.default_preview()|.
---
--- `source.choose` is also a callable to be executed on the chosen item.
--- ??? What signature and what should it return ???
--- If `nil` (default) uses |MiniPick.default_choose()|.
MiniPick.config = {
  content = {
    match = nil,

    show = nil,

    direction = 'from_top',

    -- Cache matches to ~ncrease speed on repeated prompts (uses more memory)
    use_cache = false,
  },

  delay = {
    -- Delay between forced redraws when picker is active
    redraw = 10,

    -- Delay between start processing and visual feedback about it
    busy = 50,
  },

  -- Special keys for active picker
  mappings = {
    caret_left  = '<Left>',
    caret_right = '<Right>',

    choose            = '<CR>',
    choose_all        = '<C-a>',
    choose_in_split   = '<C-s>',
    choose_in_tabpage = '<C-t>',
    choose_in_vsplit  = '<C-v>',

    delete_char       = '<BS>',
    delete_char_right = '<Del>',
    delete_left       = '<C-u>',
    delete_word       = '<C-w>',

    execute = '<C-e>',

    move_down = '<C-n>',
    move_up   = '<C-p>',

    paste = '<C-r>',

    scroll_down  = '<C-f>',
    scroll_up    = '<C-b>',
    scroll_left  = '<C-h>',
    scroll_right = '<C-l>',

    stop = '<Esc>',

    toggle_info    = '<S-Tab>',
    toggle_preview = '<Tab>',
  },

  source = {
    name = nil,
    items = nil,
    preview = nil,
    choose = nil,
    choose_all = nil,
  },

  window = {
    config = nil,
  },
}
--minidoc_afterlines_end

---@param opts table|nil Options. Should have the same structure as |MiniPick.config|.
---   Default values are inferred from there. Should have proper `source.items`.
---
--- @return ... Tuple of current item and its index just before picker is stopped.
MiniPick.start = function(opts)
  opts = H.validate_picker_opts(opts)
  local picker = H.picker_new(opts)
  H.active_picker = picker
  return H.picker_advance(picker)
end

MiniPick.set_picker_items = function(items)
  if not vim.tbl_islist(items) then H.error('`items` should be list.') end
  local picker = H.active_picker
  if picker == nil then return end
  H.picker_set_items(picker, items)
  H.picker_update(picker, true)
end

MiniPick.get_picker_items = function()
  local picker = H.active_picker
  if picker == nil then return end
  return picker.items
end

MiniPick.get_picker_matches = function()
  local picker = H.active_picker
  if picker == nil then return end
  if picker.items == nil then return { all = nil, current = nil } end
  local matches = vim.tbl_map(function(ind) return picker.items[ind] end, picker.match_inds)
  return { all = matches, current = H.picker_get_current_item(picker) }
end

MiniPick.set_picker_opts = function(opts)
  local picker = H.active_picker
  if picker == nil then return nil end
  picker.opts = vim.tbl_deep_extend('force', picker.opts, opts or {})
end

MiniPick.get_picker_opts = function(opts)
  local picker = H.active_picker
  if picker == nil then return nil end
  return picker.opts
end

MiniPick.get_picker_data = function()
  local picker = H.active_picker
  if picker == nil then return nil end
  return { query = picker.query, is_busy = picker.is_busy, windows = picker.windows, buffers = picker.buffers }
end

MiniPick.get_querytick = function() return H.querytick end

MiniPick.default_match = function(inds, stritems, query)
  local match_data = H.match_filter(inds, stritems, query)
  return match_data ~= nil and H.match_sort(match_data) or H.seq_along(stritems)
end

MiniPick.default_show = function(items, buf_id, opts)
  opts = opts or {}
  -- TODO: use commented line
  -- local show_icons = opts.show_icons
  local show_icons = true

  -- Compute and set lines
  local lines, prefixes = vim.tbl_map(H.item_to_string, items), {}

  if show_icons then prefixes = vim.tbl_map(H.get_icon, lines) end
  local lines_to_show = {}
  for i, l in ipairs(lines) do
    lines_to_show[i] = (prefixes[i] or '') .. l
  end

  H.set_buflines(buf_id, lines_to_show)

  -- Extract match offsets and highlight them
  local ns_id = H.ns_id.offsets
  H.clear_namespace(buf_id, ns_id)

  local stritems, query = lines, MiniPick.get_picker_data().query
  if H.query_is_ignorecase(query) then
    stritems, query = vim.tbl_map(vim.fn.tolower, stritems), vim.tbl_map(vim.fn.tolower, query)
  end
  local match_data, match_type, query_adjusted = H.match_filter(H.seq_along(stritems), stritems, query)
  if match_data == nil then return end

  local match_offsets_fun = match_type == 'fuzzy' and H.match_offsets_fuzzy or H.match_offsets_exact
  local match_offsets = match_offsets_fun(match_data, query_adjusted, stritems)

  local extmark_opts = { hl_group = 'MiniPickMatchOffsets', hl_mode = 'combine', priority = 200 }
  for i = 1, #match_data do
    local row, offsets = match_data[i][3], match_offsets[i]
    local start_offset = (prefixes[row] or ''):len()
    for _, off in ipairs(offsets) do
      extmark_opts.end_row, extmark_opts.end_col = row - 1, start_offset + H.get_next_char_bytecol(lines[row], off)
      H.set_extmark(buf_id, ns_id, row - 1, start_offset + off - 1, extmark_opts)
    end
  end
end

MiniPick.default_preview = function(item, win_id, opts)
  opts = vim.tbl_deep_extend('force', { file_n_context = 2 * vim.o.lines, file_line_position = 'top' }, opts or {})
  local item_type, item_value = H.get_item_type(item)
  if item_type == 'file' then return H.preview_file(item_value, win_id, opts) end
  if item_type == 'directory' then return H.preview_directory(item_value, win_id) end
  H.preview_inspect(item, win_id)
end

MiniPick.default_choose = function(item)
  local item_type, item_value = H.get_item_type(item)
  if item_type == 'file' or item_type == 'directory' then return H.choose_file(item_value) end
  H.choose_print(item)
end

MiniPick.default_choose_all = function(items, opts)
  opts = vim.tbl_deep_extend('force', { list_type = 'quickfix' }, opts or {})
  local list = {}
  for _, item in ipairs(items) do
    local item_type, item_value = H.get_item_type(item)
    if item_type == 'file' then
      local path, line, col, rest = H.parse_file_path(item_value)
      table.insert(list, { filename = path, lnum = line or 1, col = col or 1, text = rest or '' })
    end
  end

  local win_init = MiniPick.get_picker_data().windows.init
  if opts.list_type == 'location' then
    vim.fn.setloclist(win_init, list, ' ')
    vim.schedule(function() vim.cmd('lopen') end)
  end

  vim.fn.setqflist(list, ' ')
  local qf_title =
    string.format('%s:%s', MiniPick.get_picker_opts().source.name, table.concat(MiniPick.get_picker_data().query))
  vim.fn.setqflist({}, 'a', { title = qf_title })
  vim.schedule(function() vim.cmd('copen') end)
end

MiniPick.ui_select = function(items, opts, on_choice)
  local items_ext = {}
  for i = 1, #items do
    table.insert(items_ext, { index = i, item = items[i] })
  end

  local picker_opts = {
    source = {
      items = items_ext,
      name = opts.prompt,
      choose = function(item) on_choice(item.item, item.index) end,
      preview = function() end,
    },
    -- No support of `format_item`: use its output as `item` key of table item.
  }
  MiniPick.start(picker_opts)
end

MiniPick.builtin = {}

MiniPick.builtin.files = function(source_opts, opts)
  opts = vim.tbl_deep_extend('force', { source = { name = 'Files' } }, opts or {})
  -- TODO: Remove '--no-ignore'
  return MiniPick.builtin.shell_output({ 'rg', '--files', '--no-ignore', '--color', 'never' }, opts)
end

MiniPick.builtin.grep = function(source_opts, opts)
  opts = vim.tbl_deep_extend('force', { source = { name = 'Grep' } }, opts or {})
  local command =
    { 'rg', '--column', '--line-number', '--no-heading', '--color=never', '--smart-case', '--max-columns=4096', '-e' }
  table.insert(command, vim.fn.input('Grep pattern: '))
  return MiniPick.builtin.shell_output(command, opts)
end

MiniPick.builtin.help = function(opts)
  -- Get all tags
  local help_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[help_buf].buftype = 'help'
  local tags
  vim.api.nvim_buf_call(help_buf, function() tags = vim.fn.taglist('.*') end)
  vim.api.nvim_buf_delete(help_buf, { force = true })

  local choose = function(item)
    local data = MiniPick.get_picker_data()
    pcall(vim.api.nvim_win_set_buf, data.windows.main, data.buffers.main)
    vim.api.nvim_win_call(data.windows.init, function()
      vim.cmd('help ' .. (item or ''))
      local help_win = vim.api.nvim_get_current_win()
      vim.schedule(function() vim.api.nvim_set_current_win(help_win) end)
    end)
  end

  -- TODO: This whole approach works but it forces "minimal" window options.
  -- Try to explore better options.
  local preview = function(item, win_id)
    vim.api.nvim_win_call(win_id, function()
      if H.is_valid_buf(help_buf) then
        vim.api.nvim_win_set_buf(help_buf)
      else
        vim.cmd('silent noautocmd keepalt edit ' .. vim.o.helpfile)
        vim.bo.buftype, vim.bo.bufhidden = 'help', 'wipe'
        help_buf = vim.api.nvim_get_current_buf()
      end
      vim.cmd('help ' .. item)
    end)
  end

  local source = {
    items = vim.tbl_map(function(x) return x.name end, tags),
    name = 'Help',
    choose = choose,
    choose_all = function(items) choose(items[1]) end,
    preview = preview,
  }
  MiniPick.start({ source = source })
end

MiniPick.builtin.shell_output = function(command, opts)
  local items = function() H.execute_shell_command(command[1], vim.list_slice(command, 2, #command)) end
  opts = vim.tbl_deep_extend('force', { source = { name = 'Shell' } }, opts or {}, { source = { items = items } })
  MiniPick.start(opts)
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniPick.config

-- Namespaces
H.ns_id = {
  current = vim.api.nvim_create_namespace('MiniPickCurrent'),
  offsets = vim.api.nvim_create_namespace('MiniPickOffsets'),
  headers = vim.api.nvim_create_namespace('MiniPickHeaders'),
  preview = vim.api.nvim_create_namespace('MiniPickPreview'),
}

-- Timers
H.timers = {
  getcharstr = vim.loop.new_timer(),
  busy = vim.loop.new_timer(),
}

-- Picker-independent counter of query updates
H.querytick = 0

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
    ['content.match'] = { config.content.match, 'function', true },
    ['content.show'] = { config.content.show, 'function', true },
    ['content.direction'] = { config.content.direction, 'string' },
    ['content.use_cache'] = { config.content.use_cache, 'boolean' },

    ['delay.redraw'] = { config.delay.redraw, 'number' },
    ['delay.busy'] = { config.delay.busy, 'number' },

    ['mappings.caret_left'] = { config.mappings.caret_left, 'string' },
    ['mappings.caret_right'] = { config.mappings.caret_right, 'string' },
    ['mappings.choose'] = { config.mappings.choose, 'string' },
    ['mappings.choose_all'] = { config.mappings.choose_all, 'string' },
    ['mappings.choose_in_split'] = { config.mappings.choose_in_split, 'string' },
    ['mappings.choose_in_tabpage'] = { config.mappings.choose_in_tabpage, 'string' },
    ['mappings.choose_in_vsplit'] = { config.mappings.choose_in_vsplit, 'string' },
    ['mappings.delete_char'] = { config.mappings.delete_char, 'string' },
    ['mappings.delete_char_right'] = { config.mappings.delete_char_right, 'string' },
    ['mappings.delete_left'] = { config.mappings.delete_left, 'string' },
    ['mappings.delete_word'] = { config.mappings.delete_word, 'string' },
    ['mappings.execute'] = { config.mappings.execute, 'string' },
    ['mappings.move_down'] = { config.mappings.move_down, 'string' },
    ['mappings.move_up'] = { config.mappings.move_up, 'string' },
    ['mappings.paste'] = { config.mappings.paste, 'string' },
    ['mappings.scroll_down'] = { config.mappings.scroll_down, 'string' },
    ['mappings.scroll_up'] = { config.mappings.scroll_up, 'string' },
    ['mappings.scroll_left'] = { config.mappings.scroll_left, 'string' },
    ['mappings.scroll_right'] = { config.mappings.scroll_right, 'string' },
    ['mappings.stop'] = { config.mappings.stop, 'string' },
    ['mappings.toggle_info'] = { config.mappings.toggle_info, 'string' },
    ['mappings.toggle_preview'] = { config.mappings.toggle_preview, 'string' },

    ['source.items'] = { config.source.items, 'table', true },
    ['source.name'] = { config.source.name, 'string', true },
    ['source.preview'] = { config.source.preview, 'function', true },
    ['source.choose'] = { config.source.choose, 'function', true },
    ['source.choose_all'] = { config.source.choose_all, 'function', true },

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

  hi('MiniPickBorder',       { link = 'FloatBorder' })
  hi('MiniPickBorderBusy',   { link = 'DiagnosticFloatingWarn' })
  hi('MiniPickBorderText',   { link = 'FloatTitle' })
  hi('MiniPickInfoHeader',   { link = 'DiagnosticFloatingHint' })
  hi('MiniPickMatchCurrent', { link = 'CursorLine' })
  hi('MiniPickMatchOffsets', { link = 'DiagnosticFloatingHint' })
  hi('MiniPickNormal',       { link = 'NormalFloat' })
  hi('MiniPickPrompt',       { link = 'DiagnosticFloatingInfo' })
end

-- Picker object --------------------------------------------------------------
H.validate_picker_opts = function(opts)
  opts = H.get_config(opts)

  local validate_callable = function(x, x_name)
    if not vim.is_callable(x) then H.error(string.format('`%s` should be callable.', x_name)) end
  end

  -- Source
  local source = opts.source

  local items = source.items or {}
  local is_valid_items = vim.tbl_islist(items) or vim.is_callable(items)
  if not is_valid_items then H.error('`source.items` should be list or callable.') end

  source.name = tostring(source.name or '<No name>')

  source.preview = source.preview or MiniPick.default_preview
  validate_callable(source.preview, 'source.preview')

  source.choose = source.choose or MiniPick.default_choose
  validate_callable(source.choose, 'source.choose')

  source.choose_all = source.choose_all or MiniPick.default_choose_all
  validate_callable(source.choose_all, 'source.choose_all')

  -- Content
  local content = opts.content
  content.match = content.match or MiniPick.default_match
  validate_callable(content.match, 'content.match')

  content.show = content.show or MiniPick.default_show
  validate_callable(content.show, 'content.show')

  local is_valid_direction = content.direction == 'from_top' or content.direction == 'from_bottom'
  if not is_valid_direction then H.error('`content.direction` should be one of "from_top" or "from_bottom".') end

  if type(content.use_cache) ~= 'boolean' then H.error('`content.use_cache` should be boolean.') end

  -- Delay
  for key, value in pairs(opts.delay) do
    local is_valid_value = type(value) == 'number' and value > 0
    if not is_valid_value then H.error(string.format('`delay.%s` should be a positive number.', key)) end
  end

  -- Mappings
  for key, value in pairs(opts.mappings) do
    if type(value) ~= 'string' then H.error(string.format('`mappings.%s` should be string.', key)) end
  end

  -- Window
  local win_config = opts.window.config
  local is_valid_winconfig = win_config == nil or type(win_config) == 'table' or vim.is_callable(win_config)
  if not is_valid_winconfig then H.error('`window.config` should be table or callable.') end

  return opts
end

H.picker_new = function(opts)
  -- Create buffer
  local buf_id = H.picker_new_buf()

  -- Create window
  local win_id = H.picker_new_win(buf_id, opts.window.config)

  -- Constuct and return object
  local picker = {
    -- Permanent data about picker (should not change)
    opts = opts,

    -- Items to pick from
    items = nil,
    stritems = nil,
    stritems_ignorecase = nil,

    -- Associated Neovim objects
    buffers = { main = buf_id, preview = nil, info = nil },
    windows = { main = win_id, init = vim.api.nvim_get_current_win() },

    -- Query data
    query = {},
    -- - Query index at which new entry will be inserted
    caret = 1,
    -- - Array of `stritems` indexes matching current query
    match_inds = nil,

    -- Whether picker is currently busy processing data
    is_busy = false,

    -- Cache for `matches` per prompt for more performant querying
    cache = {},

    -- View data
    -- - Which buffer should currently be shown
    view_state = 'main',

    -- - Index range of `match_inds` currently visible. Present for significant
    --   performance increase to render only what is visible.
    visible_range = { from = nil, to = nil, querytick = H.querytick },

    -- - ~atest shown range. Used to call `content.show()` only when needed.
    latest_shown_range = { from = nil, to = nil, querytick = nil },

    -- - Index of `match_inds` pointing at current item
    current_ind = nil,
  }

  H.querytick = H.querytick + 1

  -- Set items. If already resolved to array, set right away.
  H.picker_set_busy(picker, true)
  local items = H.expand_callable(opts.source.items)
  if vim.tbl_islist(items) then H.picker_set_items(picker, items) end

  return picker
end

H.picker_advance = function(picker)
  local special_chars = H.picker_get_special_chars(picker)

  local should_match = false
  while true do
    H.picker_update(picker, should_match)

    local char = H.getcharstr()
    if char == nil then break end

    local action_name = special_chars[char]
    should_match = action_name == nil or vim.startswith(action_name, 'delete') or action_name == 'paste'

    local should_stop = H.actions[action_name](picker, char)
    if should_stop then break end
  end

  local item = H.picker_get_current_item(picker)
  H.picker_stop(picker)
  H.picker_free(picker)
  return item
end

H.picker_update = function(picker, should_match)
  if should_match then H.picker_match(picker) end
  H.picker_set_bordertext(picker)
  H.picker_set_lines(picker)
  H.redraw()
end

H.picker_new_buf = function()
  local buf_id = vim.api.nvim_create_buf(false, true)
  vim.bo[buf_id].filetype = 'minipick'
  return buf_id
end

H.picker_new_win = function(buf_id, win_config)
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
  local config = vim.tbl_deep_extend('force', default_config, H.expand_callable(win_config) or {})

  -- Tweak config values to ensure they are proper
  if config.border == 'none' then config.border = { ' ' } end
  -- - Account for border
  config.height = math.min(config.height, max_height - 2)
  config.width = math.min(config.width, max_width - 2)

  -- Create window without focus. Instead focus cursor on Command line to not
  -- have it seen on top of floating window text.
  local win_id = vim.api.nvim_open_win(buf_id, false, config)
  vim.cmd('noautocmd normal! :')

  -- Set window-local data
  vim.wo[win_id].foldenable = false
  vim.wo[win_id].list = true
  vim.wo[win_id].listchars = 'extends:…'
  vim.wo[win_id].wrap = false
  H.win_update_hl(win_id, 'NormalFloat', 'MiniPickNormal')
  H.win_update_hl(win_id, 'FloatBorder', 'MiniPickBorder')

  return win_id
end

H.picker_set_items = function(picker, items)
  -- Stop being busy
  H.picker_set_busy(picker, false)

  -- Compute string items to work with and their initial matches
  local stritems, stritems_ignorecase = {}, {}
  for i, x in ipairs(items) do
    local to_add = H.item_to_string(x)
    table.insert(stritems, to_add)
    table.insert(stritems_ignorecase, vim.fn.tolower(to_add))
  end

  picker.items, picker.stritems, picker.stritems_ignorecase = items, stritems, stritems_ignorecase

  -- All items are matched at first for empty query
  H.picker_set_matches(picker, H.seq_along(items), {})
end

H.item_to_string = function(item)
  item = H.expand_callable(item)
  if type(item) == 'table' then item = item.item end
  return type(item) == 'string' and item or tostring(item)
end

H.picker_set_busy = function(picker, value)
  picker.is_busy = value

  local win_id = picker.windows.main
  local new_hl_group = value and 'MiniPickBorderBusy' or 'MiniPickBorder'
  local update_border_hl = function() H.win_update_hl(win_id, 'FloatBorder', new_hl_group) end

  if value then
    H.timers.busy:start(picker.opts.delay.busy, 0, vim.schedule_wrap(update_border_hl))
  else
    H.timers.busy:stop()
    update_border_hl()
  end
end

H.picker_set_matches = function(picker, inds, cache_query)
  H.picker_set_busy(picker, false)

  picker.match_inds = inds

  local cache_prompt = table.concat(cache_query or picker.query)
  if picker.opts.content.use_cache then picker.cache[cache_prompt] = { inds = inds } end

  -- Reset current index if match indexes are updated
  H.picker_set_current_ind(picker, 1)

  -- Always show result of updated matches
  H.picker_show_main(picker)
end

H.picker_set_current_ind = function(picker, ind)
  if picker.items == nil or #picker.match_inds == 0 then
    picker.current_ind, picker.visible_range = nil, { querytick = H.querytick }
    return
  end

  -- Wrap index around edges
  local n_matches = #picker.match_inds
  ind = (ind - 1) % n_matches + 1

  -- (Re)Compute visible range (centers current index if it is currently outside)
  local from, to, querytick = picker.visible_range.from, picker.visible_range.to, picker.visible_range.querytick
  local should_update = querytick ~= H.querytick or from == nil or to == nil or not (from <= ind and ind <= to)
  if should_update and H.is_valid_win(picker.windows.main) then
    local win_height = vim.api.nvim_win_get_height(picker.windows.main)
    to = math.min(n_matches, math.floor(ind + 0.5 * win_height))
    from = math.max(1, to - win_height + 1)
    to = from + math.min(win_height, n_matches) - 1
  end

  -- Set data
  picker.current_ind = ind
  picker.visible_range = { from = from, to = to, querytick = H.querytick }
end

H.picker_set_lines = function(picker)
  local buf_id, win_id = picker.buffers.main, picker.windows.main
  if not (H.is_valid_buf(buf_id) and H.is_valid_win(win_id)) then return end

  local show = picker.opts.content.show

  local visible_range = picker.visible_range
  if picker.items == nil or visible_range.from == nil or visible_range.to == nil then
    show({}, buf_id)
    H.clear_namespace(buf_id, H.ns_id.current)
    return
  end

  -- Construct target items
  local items_to_show, items, inds = {}, picker.items, picker.match_inds
  local cur_ind, cur_line = picker.current_ind, nil
  local is_direction_bottom = picker.opts.content.direction == 'from_bottom'
  local from = is_direction_bottom and visible_range.to or visible_range.from
  local to = is_direction_bottom and visible_range.from or visible_range.to
  for i = from, to, (from <= to and 1 or -1) do
    table.insert(items_to_show, items[inds[i]])
    if i == cur_ind then cur_line = #items_to_show end
  end

  local from_bottom_buffer = is_direction_bottom and (vim.api.nvim_win_get_height(win_id) - #items_to_show) or 0
  cur_line = cur_line + from_bottom_buffer

  -- Possibly update visible content accounting for "from_bottom" direction
  local range = picker.latest_shown_range
  local should_show = range.querytick ~= H.querytick or range.from ~= visible_range.from or range.to ~= visible_range.to
  if should_show then
    show(items_to_show, buf_id)
    picker.latest_shown_range = { from = visible_range.from, to = visible_range.to, querytick = H.querytick }
    if from_bottom_buffer > 0 then
      local empty_lines = vim.fn['repeat']({ '' }, from_bottom_buffer)
      vim.api.nvim_buf_set_lines(buf_id, 0, 0, true, empty_lines)
    end
  end

  -- Update current item
  if cur_line > vim.api.nvim_buf_line_count(buf_id) then return end

  H.clear_namespace(buf_id, H.ns_id.current)
  local cur_opts = { end_row = cur_line, end_col = 0, hl_eol = true, hl_group = 'MiniPickMatchCurrent', priority = 201 }
  H.set_extmark(buf_id, H.ns_id.current, cur_line - 1, 0, cur_opts)

  -- Update cursor if showing item matches (needed for 'scroll_{left,right}')
  local is_not_curline = vim.api.nvim_win_get_cursor(win_id)[1] ~= cur_line
  if picker.view_state == 'main' and is_not_curline then vim.api.nvim_win_set_cursor(win_id, { cur_line, 0 }) end
end

H.picker_match = function(picker)
  if picker.items == nil then return end

  -- Try to use cache first
  local prompt_cache
  if picker.opts.content.use_cache then prompt_cache = picker.cache[table.concat(picker.query)] end
  if prompt_cache ~= nil then return H.picker_set_matches(picker, prompt_cache.inds) end

  local is_ignorecase = H.query_is_ignorecase(picker.query)
  local stritems = is_ignorecase and picker.stritems_ignorecase or picker.stritems
  local query = is_ignorecase and vim.tbl_map(vim.fn.tolower, picker.query) or picker.query
  if #query == 0 then return H.picker_set_matches(picker, H.seq_along(stritems), nil) end

  local new_inds = picker.opts.content.match(picker.match_inds, stritems, query)
  H.picker_set_matches(picker, new_inds)
end

H.query_is_ignorecase = function(query)
  if not vim.o.ignorecase then return false end
  if not vim.o.smartcase then return true end
  local prompt = table.concat(query, '')
  return vim.fn.match(prompt, '[[:upper:]]') < 0
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

  -- Compute main text managing views separately and truncating from left
  local view_state = picker.view_state
  local config
  if view_state == 'main' then
    local query, caret = picker.query, picker.caret
    local before_caret = table.concat(vim.list_slice(query, 1, caret - 1), '')
    local after_caret = table.concat(vim.list_slice(query, caret, #query), '')
    local prompt_text = '> ' .. before_caret .. '▏' .. after_caret
    local prompt = { { H.win_trim_to_width(win_id, prompt_text), 'MiniPickPrompt' } }
    config = { title = prompt }
  end

  local has_items = picker.items ~= nil
  if view_state == 'preview' and has_items then
    local stritem_cur = picker.stritems[picker.match_inds[picker.current_ind]] or ''
    config = { title = { { H.win_trim_to_width(win_id, stritem_cur), 'MiniPickBorderText' } } }
  end

  if view_state == 'info' then
    config = { title = { { H.win_trim_to_width(win_id, 'Info'), 'MiniPickBorderText' } } }
  end

  -- Compute helper footer only if Neovim version permits
  if vim.fn.has('nvim-0.10') == 1 then
    local info = H.picker_get_general_info(picker)
    local source_name = string.format(' %s ', info.source_name)
    local inds = string.format(' %s|%s|%s ', info.relative_current_ind, info.n_items_matched, info.n_items_total)
    local win_width, source_width, inds_width =
      vim.api.nvim_win_get_width(win_id), vim.fn.strchars(source_name), vim.fn.strchars(inds)

    local footer = { { source_name, 'MiniPickBorderText' } }
    local n_spaces_between = win_width - (source_width + inds_width)
    if n_spaces_between > 0 then
      footer[2] = { H.win_get_bottom_border(win_id):rep(n_spaces_between), 'MiniPickBorder' }
      footer[3] = { inds, 'MiniPickBorderText' }
    end
    config.footer, config.footer_pos = footer, 'left'

    if picker.opts.content.direction ~= 'from_top' then
      config.title, config.footer = config.footer, config.title
    end
  end

  vim.api.nvim_win_set_config(win_id, config)
  vim.wo[win_id].list = true
end

H.picker_stop = function(picker)
  H.clear_namespace(picker.buffers.main, -1)

  pcall(vim.api.nvim_win_close, picker.windows.main, true)
  local buf_del = function(buf_id) pcall(vim.api.nvim_buf_delete, buf_id, { force = true }) end
  buf_del(picker.buffers.main)
  buf_del(picker.buffers.info)

  H.active_picker = nil
  H.querytick = H.querytick + 1
  return true
end

H.picker_free = function(picker)
  picker.match_inds = nil
  picker.cache = nil
  picker.stritems, picker.stritems_ignorecase = nil, nil
  picker.items = nil
  picker = nil
  vim.schedule(function() collectgarbage('collect') end)
end

--stylua: ignore
H.actions = {
  caret_left  = function(picker, _) H.picker_move_caret(picker, -1) end,
  caret_right = function(picker, _) H.picker_move_caret(picker, 1)  end,

  choose             = function(picker, _) return H.picker_choose(picker, nil)      end,
  choose_all         = function(picker, _)
    local choose_all = picker.opts.source.choose_all
    if not vim.is_callable(choose_all) then return true end
    return not choose_all(MiniPick.get_picker_matches().all)
  end,
  choose_in_split    = function(picker, _) return H.picker_choose(picker, 'split')  end,
  choose_in_tabpage  = function(picker, _) return H.picker_choose(picker, 'tabnew') end,
  choose_in_vsplit   = function(picker, _) return H.picker_choose(picker, 'vsplit') end,

  delete_char       = function(picker, _) H.picker_query_delete(picker, 1)                end,
  delete_char_right = function(picker, _) H.picker_query_delete(picker, 0)                end,
  delete_left       = function(picker, _) H.picker_query_delete(picker, picker.caret - 1) end,
  delete_word = function(picker, _)
    local init, n_del = picker.caret - 1, 0
    if init == 0 then return end
    local ref_is_keyword = vim.fn.match(picker.query[init], '[[:keyword:]]') >= 0
    for i = init, 1, -1 do
      local cur_is_keyword = vim.fn.match(picker.query[i], '[[:keyword:]]') >= 0
      if (ref_is_keyword and not cur_is_keyword) or (not ref_is_keyword and cur_is_keyword) then break end
      n_del = n_del + 1
    end
    H.picker_query_delete(picker, n_del)
  end,

  execute = function(picker, _) vim.cmd(vim.fn.input('Execute: ')) end,

  move_down = function(picker, _) H.picker_move_current(picker, 1)  end,
  move_up   = function(picker, _) H.picker_move_current(picker, -1) end,

  paste = function(picker, _)
    local register = H.getcharstr()
    local has_register, reg_contents = pcall(vim.fn.getreg, register)
    if not has_register then return end
    for i = 1, vim.fn.strchars(reg_contents) do
      H.picker_query_add(picker, vim.fn.strcharpart(reg_contents, i - 1, 1))
    end
  end,

  scroll_down  = function(picker, _) H.picker_scroll(picker, 'down')  end,
  scroll_up    = function(picker, _) H.picker_scroll(picker, 'up')    end,
  scroll_left  = function(picker, _) H.picker_scroll(picker, 'left')  end,
  scroll_right = function(picker, _) H.picker_scroll(picker, 'right') end,

  toggle_info = function(picker, _)
    if picker.view_state == 'info' then return H.picker_show_main(picker) end
    H.picker_show_info(picker)
  end,

  toggle_preview = function(picker, _)
    if picker.view_state == 'preview' then return H.picker_show_main(picker) end
    H.picker_show_preview(picker)
  end,

  stop = function(_, _) return true end,
}
setmetatable(H.actions, {
  -- If no special action, add character to the query
  __index = function() return H.picker_query_add end,
})

H.picker_query_add = function(picker, char)
  -- Determine if it **is** proper single character
  if vim.fn.strchars(char) > 1 then return end
  local ok, char_byte = pcall(string.byte, char)
  if not ok or char_byte <= 31 or (127 < char_byte and char_byte <= 255) then return end

  table.insert(picker.query, picker.caret, char)
  picker.caret = picker.caret + 1
  H.querytick = H.querytick + 1
end

H.picker_query_delete = function(picker, n)
  local delete_to_left = n > 0
  local left = delete_to_left and math.max(picker.caret - n, 1) or picker.caret
  local right = delete_to_left and picker.caret - 1 or math.min(picker.caret + n, #picker.query)
  for i = right, left, -1 do
    table.remove(picker.query, i)
  end
  picker.caret = left
  H.querytick = H.querytick + 1

  -- Deleting query character increases number of possible matches, so need to
  -- reset already matched indexes prior deleting. Use cache to speed this up.
  picker.match_inds = H.seq_along(picker.items)
end

H.picker_choose = function(picker, pre_command)
  local choose = picker.opts.source.choose
  if not vim.is_callable(choose) then return true end

  local win_id_init = picker.windows.init
  if pre_command ~= nil and H.is_valid_win(win_id_init) then
    vim.api.nvim_win_call(win_id_init, function()
      vim.cmd(pre_command)
      picker.windows.init = vim.api.nvim_get_current_win()
    end)
  end

  -- Returning nothing, `nil`, or `false` should lead to picker stop
  return not choose(H.picker_get_current_item(picker))
end

H.picker_move_caret = function(picker, n) picker.caret = math.min(math.max(picker.caret + n, 1), #picker.query + 1) end

H.picker_move_current = function(picker, n)
  local n_matches = #picker.match_inds
  if n_matches == 0 then return end

  -- Account for content direction
  n = (picker.opts.content.direction == 'from_top' and 1 or -1) * n

  -- Wrap around edges only if current index is at edge
  local current_ind = picker.current_ind
  if current_ind == 1 and n < 0 then
    current_ind = n_matches
  elseif current_ind == n_matches and n > 0 then
    current_ind = 1
  else
    current_ind = current_ind + n
  end
  current_ind = math.min(math.max(current_ind, 1), n_matches)

  H.picker_set_current_ind(picker, current_ind)

  -- Update buffer(s)
  H.picker_set_lines(picker)
  if picker.view_state == 'info' then H.picker_show_info(picker) end
  if picker.view_state == 'preview' then H.picker_show_preview(picker) end
end

H.picker_scroll = function(picker, direction)
  local win_id = picker.windows.main
  if picker.view_state == 'main' and (direction == 'down' or direction == 'up') then
    local n = (direction == 'down' and 1 or -1) * vim.api.nvim_win_get_height(win_id)
    H.picker_move_current(picker, n)
  else
    local keys = ({ down = '<C-f>', up = '<C-b>', left = 'zH', right = 'zL' })[direction]
    vim.api.nvim_win_call(win_id, function() vim.cmd('normal! ' .. H.replace_termcodes(keys)) end)
  end
end

H.picker_get_current_item = function(picker)
  if picker.items == nil then return nil end
  return picker.items[picker.match_inds[picker.current_ind]]
end

H.picker_show_main = function(picker)
  H.set_winbuf(picker.windows.main, picker.buffers.main)
  picker.view_state = 'main'
end

H.picker_show_info = function(picker)
  -- General information
  local info = H.picker_get_general_info(picker)
  local lines = {
    'General',
    'Source name   │ ' .. info.source_name,
    'Total items   │ ' .. info.n_items_total,
    'Matched items │ ' .. info.n_items_matched,
    'Current index │ ' .. info.relative_current_ind,
    '',
    'Mappings',
  }

  -- Mappings
  local mappings_data, name_width = {}, 0
  for map_name, keys in pairs(picker.opts.mappings) do
    local name = map_name:sub(1, 1):upper() .. map_name:sub(2):gsub('_', ' ')
    name_width = math.max(name_width, name:len())
    table.insert(mappings_data, { name = name, keys = keys })
  end

  table.sort(mappings_data, function(a, b) return a.name < b.name end)

  local format = '%-' .. name_width .. 's │ %s'
  for _, data in ipairs(mappings_data) do
    table.insert(lines, string.format(format, data.name, data.keys))
  end

  -- Manage buffer/window/state
  local buf_id_info = picker.buffers.info
  if not H.is_valid_buf(buf_id_info) then buf_id_info = vim.api.nvim_create_buf(false, true) end
  picker.buffers.info = buf_id_info

  H.set_buflines(buf_id_info, lines)
  H.set_winbuf(picker.windows.main, buf_id_info)
  picker.view_state = 'info'

  local ns_id = H.ns_id.headers
  H.clear_namespace(buf_id_info, ns_id)
  H.set_extmark(buf_id_info, ns_id, 0, 0, { end_row = 1, end_col = 0, hl_group = 'MiniPickInfoHeader' })
  H.set_extmark(buf_id_info, ns_id, 6, 0, { end_row = 7, end_col = 0, hl_group = 'MiniPickInfoHeader' })
end

H.picker_get_general_info = function(picker)
  local has_items = picker.items ~= nil
  return {
    source_name = picker.opts.source.name or '---',
    n_items_total = has_items and #picker.items or '-',
    n_items_matched = has_items and #picker.match_inds or '-',
    relative_current_ind = has_items and picker.current_ind or '-',
  }
end

H.picker_show_preview = function(picker)
  local preview = picker.opts.source.preview
  local item = H.picker_get_current_item(picker)
  if not vim.is_callable(preview) or item == nil then return end

  local win_id = picker.windows.main
  preview(item, win_id)
  picker.buffers.preview = vim.api.nvim_win_get_buf(win_id)
  picker.view_state = 'preview'
end

-- Default match --------------------------------------------------------------
H.match_filter = function(inds, stritems, query)
  local n_query = #query
  -- 'abc' - fuzzy match; "'abc" and 'a' - exact substring match;
  -- '^abc' and 'abc$' - exact substring match at start and end.
  local is_exact_plain, is_exact_start, is_exact_end = query[1] == "'", query[1] == '^', query[n_query] == '$'

  local start_offset = (is_exact_plain or is_exact_start) and 2 or 1
  local end_offset = (not is_exact_plain and is_exact_end) and (n_query - 1) or n_query
  query = vim.list_slice(query, start_offset, end_offset)
  n_query = #query

  if n_query == 0 then return nil end

  -- End-matching filtering doesn't result into nested matches.
  -- Example: type "$", move caret to left, type "m" (filters for "m$") and
  -- type "d" (should filter for "md$" but it is not a subset of "m$" matches).
  inds = is_exact_end and H.seq_along(stritems) or inds

  if not (is_exact_plain or is_exact_start or is_exact_end) and n_query > 1 then
    return H.match_filter_fuzzy(inds, stritems, query), 'fuzzy', query
  end

  local prefix = is_exact_start and '^' or ''
  local suffix = is_exact_end and '$' or ''
  local pattern = prefix .. vim.pesc(table.concat(query)) .. suffix

  return H.match_filter_exact(inds, stritems, query, pattern), 'exact', query
end

H.match_filter_exact = function(inds, stritems, query, pattern)
  local match_single = H.match_filter_exact_single
  local match_data = {}
  for _, ind in ipairs(inds) do
    local data = match_single(stritems[ind], ind, pattern)
    if data ~= nil then table.insert(match_data, data) end
  end

  return match_data
end

H.match_filter_exact_single = function(candidate, index, pattern, rel_offsets)
  local start = string.find(candidate, pattern)
  if start == nil then return nil end

  return { 0, start, index }
end

H.match_offsets_exact = function(match_data, query)
  -- All matches have same match offsets relative to match start
  local rel_offsets = { 0 }
  for i = 2, #query do
    rel_offsets[i] = rel_offsets[i - 1] + query[i - 1]:len()
  end

  local res = {}
  for i = 1, #match_data do
    res[i] = vim.tbl_map(function(x) return match_data[i][2] + x end, rel_offsets)
  end

  return res
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

  -- NOTE: No field names is not clear code, but consistently better performant
  return { best_last - best_first, best_first, index }
end

H.match_offsets_fuzzy = function(match_data, query, stritems)
  local res, n_query = {}, #query
  for i_match, data in ipairs(match_data) do
    local offsets, to = { data[2] }, data[2]
    for j_query = 2, n_query do
      offsets[j_query], to = string.find(stritems[data[3]], query[j_query], to + 1, true)
    end
    res[i_match] = offsets
  end
  return res
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

H.match_sort = function(match_data)
  -- Spread indexes in width-start buckets
  local buckets, max_width, width_max_start = {}, 0, {}
  for i = 1, #match_data do
    local data, width, start = match_data[i], match_data[i][1], match_data[i][2]
    local buck_width = buckets[width] or {}
    local buck_start = buck_width[start] or {}
    table.insert(buck_start, data[3])
    buck_width[start] = buck_start
    buckets[width] = buck_width

    max_width = math.max(max_width, width)
    width_max_start[width] = math.max(width_max_start[width] or 0, start)
  end

  -- Sort index in place (to make stable sort) within buckets
  for _, buck_width in pairs(buckets) do
    for _, buck_start in pairs(buck_width) do
      table.sort(buck_start)
    end
  end

  -- Gather indexes back in order
  local res = {}
  for width = 0, max_width do
    local buck_width = buckets[width]
    for start = 1, (width_max_start[width] or 0) do
      local buck_start = buck_width[start] or {}
      for i = 1, #buck_start do
        table.insert(res, buck_start[i])
      end
    end
  end

  return res
end

-- Default show ---------------------------------------------------------------
H.get_icon = function(x)
  if vim.fn.isdirectory(x) == 1 then return ' ' end
  local path = H.parse_file_path(x)
  if vim.fn.filereadable(path) == 0 then return '  ' end
  local has_devicons, devicons = pcall(require, 'nvim-web-devicons')
  if not has_devicons then return ' ' end

  local icon = devicons.get_icon(path, nil, { default = false })
  return (icon or '') .. ' '
end

-- Default preview ------------------------------------------------------------
H.preview_file = function(file, win_id, opts)
  local buf_id = vim.api.nvim_create_buf(false, true)
  vim.bo[buf_id].bufhidden = 'wipe'
  H.set_winbuf(win_id, buf_id)

  local path, line, col = H.parse_file_path(file)
  local has_pos = line ~= nil
  line, col = line or 1, col or 1

  -- Determine if file is text. This is not 100% proof, but good enough.
  -- Source: https://github.com/sharkdp/content_inspector
  local fd = vim.loop.fs_open(path, 'r', 1)
  local is_text = vim.loop.fs_read(fd, 1024):find('\0') == nil
  vim.loop.fs_close(fd)
  if not is_text then return H.set_buflines(buf_id, { '-Non-text-file-' }) end

  -- Compute lines. Limit number of read lines to work better on large files.
  local start_line, end_line = math.max(line - opts.file_n_context, 1), line + opts.file_n_context
  local has_lines, read_res = pcall(vim.fn.readfile, path, '', end_line)
  local lines = {}
  if has_lines then lines = vim.list_slice(read_res, start_line, #read_res) end

  -- Set lines and location
  H.set_buflines(buf_id, lines)
  local pos = { line - start_line + 1, col - 1 }
  pcall(vim.api.nvim_win_set_cursor, win_id, pos)

  if has_pos then
    local pos_keys = ({ top = 'zt', center = 'zz', bottom = 'zb' })[opts.file_line_position] or 'zt'
    vim.api.nvim_win_call(win_id, function() vim.cmd('normal! ' .. pos_keys) end)
    local hl_opts = { end_row = pos[1], end_col = 0, hl_eol = true, hl_group = 'CursorLine' }
    H.set_extmark(buf_id, H.ns_id.preview, pos[1] - 1, 0, hl_opts)
  end

  -- Add highlighting on Neovim>=0.8 which has stabilized API
  if vim.fn.has('nvim-0.8') == 1 then
    local ft = vim.filetype.match({ buf = buf_id, filename = path })
    local ok, _ = pcall(vim.treesitter.start, buf_id, ft)
    if not ok then vim.bo[buf_id].syntax = ft end
  end
end

H.preview_directory = function(path, win_id)
  local buf_id = vim.api.nvim_create_buf(false, true)
  H.set_winbuf(win_id, buf_id)

  local lines = vim.tbl_map(
    function(x) return x .. (vim.fn.isdirectory(path .. '/' .. x) == 1 and '/' or '') end,
    vim.fn.readdir(path)
  )
  H.set_buflines(buf_id, lines)
end

H.preview_inspect = function(obj, win_id)
  local buf_id = vim.api.nvim_create_buf(false, true)
  H.set_buflines(buf_id, vim.split(vim.inspect(obj), '\n'))
  H.set_winbuf(win_id, buf_id)
end

H.get_item_type = function(item)
  local stritem = H.item_to_string(item)
  local item_path = type(item) == 'table' and item.path or ''

  if H.is_file_item(stritem) then return 'file', stritem end
  if H.is_file_item(item_path) then return 'file', item_path end

  if vim.fn.isdirectory(stritem) == 1 then return 'directory', stritem end
  if vim.fn.isdirectory(item_path) == 1 then return 'directory', item_path end

  if H.is_valid_buf(item) then return 'buffer', item end
  local buf_field = type(item) == 'table' and (item.buf_id or item.bufnr or item.buf) or nil
  if H.is_valid_buf(buf_field) then return 'buffer', buf_field end

  return nil, nil
end

H.parse_file_path = function(x)
  if type(x) ~= 'string' then return nil end
  -- Allow inputs like 'aa/bb', 'aa/bb:10', 'aa/bb:10:5', 'aa/bb:10:5:xxx'
  -- Should also work for paths like 'aa-5'
  local location_pattern = ':(%d+):?(%d*)(.*)$'
  local line, col, rest = x:match(location_pattern)
  local path = x:gsub(location_pattern, '', 1)
  return path, tonumber(line), tonumber(col), rest or ''
end

H.is_file_item = function(x)
  local path = H.parse_file_path(x)
  return vim.fn.filereadable(path) == 1
end

-- Default choose -------------------------------------------------------------
H.choose_file = function(file)
  local win_init = (MiniPick.get_picker_data().windows or {}).init
  if win_init == nil or not H.is_valid_win(win_init) then return end

  local path, line, col = H.parse_file_path(file)
  line, col = line or 1, col or 1

  -- Try to use already created buffer, if present. This avoids not needed
  -- `:edit` call and avoids some problems with auto-root from 'mini.misc'.
  local path_buf_id
  for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
    if H.is_valid_buf(buf_id) and vim.api.nvim_buf_get_name(buf_id) == path then path_buf_id = buf_id end
  end

  if path_buf_id ~= nil then return H.set_winbuf(win_init, path_buf_id) end
  -- Avoid possible errors with `:edit`, like present swap file
  local ok = pcall(vim.api.nvim_win_call, win_init, function()
    vim.cmd('edit ' .. vim.fn.fnameescape(path))
    vim.api.nvim_win_set_cursor(win_init, { line, col - 1 })
    vim.cmd('normal! zvzz')
  end)
  vim.api.nvim_set_current_win(win_init)
end

H.choose_print = function(x) print(vim.inspect(x)) end

-- Builtins -------------------------------------------------------------------
H.execute_shell_command = function(executable, args, opts)
  opts = vim.tbl_deep_extend('force', { postprocess = function(x) return x end }, opts or {})

  local process, stdout = nil, vim.loop.new_pipe()
  local spawn_opts = { args = args, stdio = { nil, stdout, nil } }
  process = vim.loop.spawn(executable, spawn_opts, function() process:close() end)

  local data_feed = {}
  stdout:read_start(function(err, data)
    assert(not err, err)
    if data then
      table.insert(data_feed, data)
    else
      local items = vim.split(table.concat(data_feed), '\n')
      items = opts.postprocess(items)
      data_feed = nil
      stdout:close()
      vim.schedule(function() MiniPick.set_picker_items(items) end)
    end
  end)
end

H.files_list_libuv = function()
  if vim.fn.has('nvim-0.8') == 0 then H.error('Fallback `files` source needs Neovim>=0.8.') end
  vim.schedule(function()
    local items = {}
    for path_name, path_type in vim.fs.dir('.', { depth = 10000 }) do
      -- TODO: Use `vim.schedule()` once in a while to make it more responsive
      if path_type == 'file' then table.insert(items, path_name) end
    end
    MiniPick.set_picker_items(items)
  end)
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

H.set_winbuf = function(win_id, buf_id) vim.api.nvim_win_set_buf(win_id, buf_id) end

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
  return char
end

H.win_update_hl = function(win_id, new_from, new_to)
  if not H.is_valid_win(win_id) then return end

  local new_entry = new_from .. ':' .. new_to
  local replace_pattern = string.format('(%s:[^,]*)', vim.pesc(new_from))
  local new_winhighlight, n_replace = vim.wo[win_id].winhighlight:gsub(replace_pattern, new_entry)
  if n_replace == 0 then new_winhighlight = new_winhighlight .. ',' .. new_entry end

  -- Use `pcall()` because Neovim<0.8 doesn't allow non-existing highlight
  -- groups inside `winhighlight` (like `FloatTitle` at the time).
  pcall(function() vim.wo[win_id].winhighlight = new_winhighlight end)
end

H.win_trim_to_width = function(win_id, text)
  local win_width = vim.api.nvim_win_get_width(win_id)
  return vim.fn.strcharpart(text, vim.fn.strchars(text) - win_width, win_width)
end

H.win_get_bottom_border = function(win_id)
  local border = vim.api.nvim_win_get_config(win_id).border or {}
  return border[6] or ' '
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
_G.test_opts = {
  source = {
    items = {
      'abc', 'bcd', 'cde', 'def', 'efg', 'fgh', 'ghi', 'hij',
      'ijk', 'jkl', 'klm', 'lmn', 'mno', 'nop', 'opq', 'pqr',
      'qrs', 'rst', 'stu', 'tuv', 'uvw', 'vwx', 'wxy', 'xyz',
    },
  },
}

_G.positions_opts = {
  source = {
    items = {
      'lua/mini-dev/pick.lua',
      'lua/mini-dev/pick.lua:200',
      'lua/mini-dev/pick.lua:180:50',
    },
  },
}

return MiniPick
