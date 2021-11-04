-- MIT License Copyright (c) 2021 Evgeni Chasnovski

---@brief [[
--- Lua module for minimal, fast, and flexible start screen. This is mostly
--- inspired by [mhinz/vim-startify](https://github.com/mhinz/vim-startify).
---
--- Key design ideas:
--- - All available actions are defined by items. Each item should have the
---   following info:
---     - `action` - function or string for |vim.cmd| which will be executed
---       when item is chosen.
---     - `name` - string which will be displayed and used for choosing.
---     - `section` - string representing to which section item belongs.
--- - Choosing of item can be done in two ways:
---     - Type prefix query to filter item by matching its name ignoring case.
---       For every item its unique prefix is highlighted.
---     - Use Up/Down arrows and hit Enter.
---
--- Features:
--- - Customizable header and footer.
---
--- # Setup
---
--- This module needs a setup with `require('mini.starter').setup({})`
--- (replace `{}` with your `config` table).
---
--- Default `config`:
--- <code>
---   {
---   }
--- </code>
--- # Highlight groups
---
--- - `MiniStarterCurrent` - current item.
--- - `MiniStarterFooter` - footer lines.
--- - `MiniStarterHeader` - header lines.
--- - `MiniStarterInactive` - inactive item.
--- - `MiniStarterItem` - item name.
--- - `MiniStarterItemBullet` - string displayed before item name.
--- - `MiniStarterItemPrefix` - unique query for item.
--- - `MiniStarterSection` - section lines.
--- - `MiniStarterQuery` - current query in active items.
---
--- # Disabling
---
--- To disable core functionality, set `g:ministarter_disable` (globally) or
--- `b:ministarter_disable` (for a buffer) to `v:true`.
---@brief ]]
---@tag MiniStarter mini.starter

-- Module and its helper
local MiniStarter = {}
H = {}

--- Module setup
---
---@param config table: Module config table.
---@usage `require('mini.starter').setup({})` (replace `{}` with your `config` table)
function MiniStarter.setup(config)
  -- Export module
  _G.MiniStarter = MiniStarter

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Module behavior
  vim.api.nvim_exec(
    [[augroup MiniStarter
        au!
        au VimEnter * ++nested ++once lua MiniStarter.on_vimenter()
      augroup END]],
    false
  )

  -- Create highlighting
  vim.api.nvim_exec(
    [[hi default link MiniStarterCurrent    NONE
      hi default link MiniStarterFooter     Title
      hi default link MiniStarterHeader     Title
      hi default link MiniStarterInactive   Comment
      hi default link MiniStarterItem       Normal
      hi default link MiniStarterItemBullet Delimiter
      hi default link MiniStarterItemPrefix WarningMsg
      hi default link MiniStarterSection    Delimiter
      hi default link MiniStarterQuery      MoreMsg]],
    false
  )
end

-- Module config
MiniStarter.config = {
  -- Whether to open starter buffer if Neovim was called without file arguments
  autoopen = true,

  -- Whether to evaluate action of single active item
  evaluate_single = false,

  -- Items to be displayed. Should be a list with the following elements:
  -- - Item: table with `action`, `name`, and `section` keys.
  -- - Function: should return one of these three categories.
  -- - List: elements from these three categories (i.e. item, list, function).
  -- If `nil` (default), default items will be used (see |mini.starter|).
  items = nil,

  -- Header to be displayed before items. Should be a string or function
  -- evaluating to string.
  header = function()
    local hour = tonumber(vim.fn.strftime('%H'))
    -- [04:00, 12:00) - morning, [12:00, 20:00) - day, [20:00, 04:00) - evening
    local part_id = math.floor((hour + 4) / 8) + 1
    local day_part = ({ 'evening', 'morning', 'afternoon', 'evening' })[part_id]
    local username = vim.fn.getenv('USERNAME') or 'USERNAME'

    return string.format([[Good %s, %s]], day_part, username)
  end,

  -- Footer to be displayed after items. Should be a string or function
  -- evaluating to string.
  footer = table.concat({
    'Type query to filter items',
    '<BS> deletes latest character from query',
    '<Down>/<Up> and <M-j>/<M-k> move current item',
    '<CR> executes action of current item',
    '<C-c> closes this buffer',
  }, '\n'),

  -- List (table suitable for `ipairs()`) of functions to be applied
  -- consecutively to initial content. Each function should take and return
  -- content for 'Starter' buffer (see |mini.starter| for more details).
  content_hooks = nil,

  -- Characters to update query. Each character will have special buffer
  -- mapping overriding your global ones. Be careful to not add `:` as it
  -- allows you to go into command mode.
  query_updaters = [[abcdefghijklmnopqrstuvwxyz0123456789 _-.]],
}

-- Content of buffer. "2d list":
-- - Each element represent content line: a list with content units.
-- - Each content unit is a table with at least the following elements:
--     - 'type' - type of content. Something like 'item', 'section', 'header',
--       'footer', 'empty', etc.
--     - 'string' - which string should be displayed. May be empty string.
--     - 'hl' - which highlighting should be applied to content string. May be
--       `nil` for no highlighting.
-- Notes:
-- - Content units with type 'item' also have `item` element with all
--   information about an item it represents. Those elements are used directly
--   to create list of items used for query.
MiniStarter.content = {}

-- Module functionality
--- Act on |VimEnter|
---
--- - Normalize `items`, `header`, and `footer`.
--- - Compute content of 'Starter' buffer.
--- - Possibly autoopen buffer.
function MiniStarter.on_vimenter()
  -- Possibly autoopen
  if MiniStarter.config.autoopen and vim.fn.argc() == 0 then
    MiniStarter.open()
  end
end

--- Open starter buffer
---
--- End of opening results into issuing custom `MiniStarterOpened` event. Use
--- it with `autocmd User MiniStarterOpened <your command>`.
function MiniStarter.open()
  if H.is_disabled() then
    return
  end

  -- Reset helper data
  H.current_item_id = 1
  H.query = ''

  -- Create and open buffer
  H.buf_id = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(H.buf_id)

  -- Setup buffer behavior
  H.apply_buffer_options()
  H.apply_buffer_mappings()
  vim.cmd([[au VimResized <buffer> lua MiniStarter.refresh()]])
  vim.cmd([[au CursorMoved <buffer> lua MiniStarter.on_cursormoved()]])
  vim.cmd([[au BufLeave <buffer> echo '']])

  -- Populate buffer
  MiniStarter.refresh()

  -- Issue custom event
  vim.cmd([[doautocmd User MiniStarterOpened]])
end

function MiniStarter.refresh()
  if H.is_disabled() or H.buf_id == nil or not vim.api.nvim_buf_is_valid(H.buf_id) then
    return
  end

  -- Normalize certain config values.
  -- NOTE: having this inside `refresh()` and not in `on_vimenter()` allows to:
  -- - React on change in items during runtime (adding, deleting).
  -- - Evaluate items, header and footer on every `refresh()`. TODO: This might
  --   be both good and bad thing. Might want to reconsider.
  local items = H.normalize_items(MiniStarter.config.items or H.default_items)
  H.header = H.normalize_header_footer(MiniStarter.config.header, 'header')
  H.footer = H.normalize_header_footer(MiniStarter.config.footer, 'footer')

  -- Evaluate content
  H.make_initial_content(items)
  local hooks = MiniStarter.config.content_hooks or H.default_content_hooks
  for _, f in ipairs(hooks) do
    MiniStarter.content = f(MiniStarter.content)
  end
  H.items = MiniStarter.content_to_items()

  -- Add content
  vim.api.nvim_buf_set_option(H.buf_id, 'modifiable', true)
  vim.api.nvim_buf_set_lines(H.buf_id, 0, -1, false, MiniStarter.content_to_lines())
  vim.api.nvim_buf_set_option(H.buf_id, 'modifiable', false)

  -- Add highlighting
  H.content_highlight()
  H.items_highlight()

  -- -- Always position cursor on current item
  H.position_cursor_on_current_item()
  H.add_hl_current_item()

  -- Apply current query (clear command line afterwards)
  H.make_query()
end

function MiniStarter.close()
  vim.api.nvim_buf_delete(H.buf_id, {})
  H.buf_id = nil
end

function MiniStarter.section_sessions(n, mru)
  n = n or 5
  mru = mru == nil and true or mru

  return function()
    if _G.MiniSessions == nil then
      return { { name = [['mini.sessions' is not set up]], action = '', section = 'Sessions' } }
    end

    local items = {}
    for session_name, session in pairs(_G.MiniSessions.detected) do
      table.insert(items, {
        modify_time = session.modify_time,
        name = session_name,
        action = string.format([[lua _G.MiniSessions.read('%s')]], session_name),
        section = 'Sessions',
      })
    end

    if vim.tbl_count(items) == 0 then
      return { { name = [[There are no detected sessions in 'mini.sessions']], action = '', section = 'Sessions' } }
    end

    if mru then
      table.sort(items, function(a, b)
        return a.modify_time > b.modify_time
      end)
    end

    -- Take only first `n` elements and remove helper `modify_time`
    return vim.tbl_map(function(x)
      x.modify_time = nil
      return x
    end, vim.list_slice(items, 1, n))
  end
end

function MiniStarter.section_mru_files(n, current_dir, show_path)
  n = n or 5
  current_dir = current_dir == nil and false or current_dir
  show_path = show_path == nil and true or show_path

  if current_dir then
    vim.cmd([[au DirChanged * lua MiniStarter.refresh()]])
  end

  return function()
    local section = string.format([[MRU files%s]], current_dir and ' (current directory)' or '')

    -- Use only actual readable files
    local files = vim.tbl_filter(function(f)
      return vim.fn.filereadable(f) == 1
    end, vim.v.oldfiles or {})

    if #files == 0 then
      return { { name = [[There are no MRU files (`v:oldfiles` is empty)]], action = '', section = section } }
    end

    -- Possibly filter files from current directory
    if current_dir then
      local cwd = vim.loop.cwd()
      local n_cwd = cwd:len()
      files = vim.tbl_filter(function(f)
        return f:sub(1, n_cwd) == cwd
      end, files)
    end

    if #files == 0 then
      return { { name = [[There are no MRU files in current directory]], action = '', section = section } }
    end

    -- Create items
    local items = {}
    local fmodify = vim.fn.fnamemodify
    for _, f in ipairs(vim.list_slice(files, 1, n)) do
      local path = show_path and string.format([[ (%s)]], fmodify(f, ':~:.')) or ''
      local name = string.format([[%s%s]], fmodify(f, ':t'), path)
      table.insert(items, { action = string.format([[edit %s]], fmodify(f, ':p')), name = name, section = section })
    end

    return items
  end
end

-- stylua: ignore start
function MiniStarter.section_telescope()
  return function()
    return {
      {action = 'Telescope file_browser',    name = 'Browser',         section = 'Telescope'},
      {action = 'Telescope command_history', name = 'Command history', section = 'Telescope'},
      {action = 'Telescope find_files',      name = 'Files',           section = 'Telescope'},
      {action = 'Telescope help_tags',       name = 'Help tags',       section = 'Telescope'},
      {action = 'Telescope oldfiles',        name = 'Old files',       section = 'Telescope'},
    }
  end
end
-- stylua: ignore start

function MiniStarter.get_hook_padding(left, top)
  left = math.max(left or 0, 0)
  top = math.max(top or 0, 0)
  return function(content)
    -- Add left padding
    local left_pad = string.rep(' ', left)
    for _, line in ipairs(content) do
      table.insert(line, 1, H.content_unit(left_pad, 'empty', nil))
    end

    -- Add top padding
    local top_lines = {}
    for _ = 1, top do
      table.insert(top_lines, { H.content_unit('', 'empty', nil) })
    end
    content = vim.list_extend(top_lines, content)

    return content
  end
end

function MiniStarter.get_hook_item_bullets(bullet, place_cursor)
  bullet = bullet or '▌ '
  place_cursor = place_cursor == nil and true or place_cursor
  return function(content)
    local coords = MiniStarter.content_coords(content, 'item')
    -- Go backwards to avoid conflict when inserting units
    for i = #coords, 1, -1 do
      local l_num, u_num = coords[i].line, coords[i].unit
      local bullet_unit = {
        string = bullet,
        type = 'item_bullet',
        hl = 'MiniStarterItemBullet',
        -- Use `_item` instead of `item` because it is better to be 'private'
        _item = content[l_num][u_num].item,
        _place_cursor = place_cursor,
      }
      table.insert(content[l_num], u_num, bullet_unit)
    end

    return content
  end
end

function MiniStarter.get_hook_indexing(grouping, exclude_sections)
  grouping = grouping or 'all'
  exclude_sections = exclude_sections or {}
  local per_section = grouping == 'section'

  return function(content)
    local cur_section, n_section, n_item = nil, 0, 0
    local coords = MiniStarter.content_coords(content, 'item')

    for _, c in ipairs(coords) do
      local unit = content[c.line][c.unit]
      local item = unit.item

      if not vim.tbl_contains(exclude_sections, item.section) then
        n_item = n_item + 1
        if cur_section ~= item.section then
          cur_section = item.section
          -- Cycle through lower case letters
          n_section = math.fmod(n_section, 26) + 1
          n_item = per_section and 1 or n_item
        end

        local section_index = per_section and string.char(96 + n_section) or ''
        unit.string = string.format([[%s%s. %s]], section_index, n_item, unit.string)
      end
    end

    return content
  end
end

function MiniStarter.get_hook_aligning(horizontal, vertical)
  horizontal = horizontal == nil and 'left' or horizontal
  vertical = vertical == nil and 'top' or vertical

  local horiz_coef = ({ left = 0, center = 0.5, right = 1.0 })[horizontal]
  local vert_coef = ({ top = 0, center = 0.5, bottom = 1.0 })[vertical]

  return function(content)
    local line_strings = MiniStarter.content_to_lines(content)

    -- Align horizontally
    -- Don't use `string.len()` to account for multibyte characters
    local lines_width = vim.tbl_map(function(l)
      return vim.fn.strdisplaywidth(l)
    end, line_strings)
    local min_right_space = vim.fn.winwidth(0) - math.max(unpack(lines_width))
    local left_pad = math.max(math.floor(horiz_coef * min_right_space), 0)

    -- Align vertically
    local bottom_space = vim.fn.winheight(0) - #line_strings
    local top_pad = math.max(math.floor(vert_coef * bottom_space), 0)

    return MiniStarter.get_hook_padding(left_pad, top_pad)(content)
  end
end

function MiniStarter.content_coords(content, predicate)
  content = content or MiniStarter.content
  if type(predicate) == 'string' then
    local pred_type = predicate
    predicate = function(unit)
      return unit.type == pred_type
    end
  end

  local res = {}
  for l_num, line in ipairs(content) do
    for u_num, unit in ipairs(line) do
      if predicate and predicate(unit) then
        table.insert(res, { line = l_num, unit = u_num })
      end
    end
  end
  return res
end

-- stylua: ignore start
function MiniStarter.content_to_lines(content)
  return vim.tbl_map(
    function(content_line)
      return table.concat(
        vim.tbl_map(function(x) return x.string:gsub('\n', ' ') end, content_line), ''
      )
    end,
    content or MiniStarter.content
  )
end
-- stylua: ignore end

function MiniStarter.content_to_items(content)
  content = content or MiniStarter.content

  -- NOTE: this havily utilizes 'modify by reference' nature of Lua tables
  local items = {}
  for l_num, line in ipairs(content) do
    -- Track 0-based starting column of current unit (using byte length)
    local start_col = 0
    for _, unit in ipairs(line) do
      -- Cursor position is (1, 0)-based
      local cursorpos = { l_num, start_col }

      if unit.type == 'item' then
        local item = unit.item
        -- Take item's name from content string
        item.name = unit.string:gsub('\n', ' ')
        item._line = l_num - 1
        item._start_col = start_col
        item._end_col = start_col + unit.string:len()
        -- Don't overwrite possible cursor position from item's bullet
        item._cursorpos = item._cursorpos or cursorpos

        table.insert(items, item)
      end

      -- Prefer placing cursor at start of item's bullet
      if unit.type == 'item_bullet' and unit._place_cursor then
        -- Item bullet uses 'private' `_item` element instead of `item`
        unit._item._cursorpos = cursorpos
      end

      start_col = start_col + unit.string:len()
    end
  end

  for id, item in ipairs(items) do
    items[id]._nprefix = H.compute_item_nprefix(item, items)
  end

  return items
end

function MiniStarter.eval_current_item()
  H.eval_fun_or_string(H.items[H.current_item_id].action, true)
end

function MiniStarter.update_current_item(direction)
  -- Advance current item
  local prev_current = H.current_item_id
  H.current_item_id = H.next_active_item_id(H.current_item_id, direction)
  if H.current_item_id == prev_current then
    return
  end

  -- Update cursor position
  H.position_cursor_on_current_item()

  -- Highlight current item
  vim.api.nvim_buf_clear_namespace(H.buf_id, H.ns.current_item, 0, -1)
  H.add_hl_current_item()
end

function MiniStarter.add_to_query(char)
  if char == nil then
    H.query = H.query:sub(0, H.query:len() - 1)
  else
    H.query = string.format('%s%s', H.query, char)
  end
  H.make_query()
end

function MiniStarter.on_cursormoved()
  H.position_cursor_on_current_item()
end

-- Helper data
---- Module default config
H.default_config = MiniStarter.config
H.default_items = {
  { action = 'edit $MYVIMRC', name = 'My Init.(lua|vim)', section = 'Builtin actions' },
  { action = 'enew', name = 'Edit new buffer', section = 'Builtin actions' },
  { action = 'qall', name = 'Quit Neovim', section = 'Builtin actions' },
  MiniStarter.section_mru_files(5, false, false),
}
H.default_content_hooks = { MiniStarter.get_hook_item_bullets(), MiniStarter.get_hook_aligning('center', 'center') }

---- Normalized values from config
H.items = {} -- items gathered with `MiniStarter.content_to_items` from final content
H.header = {} -- table of strings
H.footer = {} -- table of strings

---- Identifier of current item
H.current_item_id = nil

---- Buffer identifier where everything is displayed
H.buf_id = nil

---- Namespaces for highlighting
H.ns = {
  activity = vim.api.nvim_create_namespace(''),
  current_item = vim.api.nvim_create_namespace(''),
  general = vim.api.nvim_create_namespace(''),
}

---- Current search query
H.query = ''

-- Helper functions
---- Settings
function H.setup_config(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    autoopen = { config.autoopen, 'boolean' },
    evaluate_single = { config.evaluate_single, 'boolean' },

    items = { config.items, 'table', true },
    header = { config.header, H.is_fun_or_string, 'function or string' },
    footer = { config.footer, H.is_fun_or_string, 'function or string' },

    content_hooks = { config.content_hooks, 'table', true },

    query_updaters = { config.query_updaters, 'string' },
  })

  return config
end

function H.apply_config(config)
  MiniStarter.config = config
end

function H.is_disabled()
  return vim.g.ministarter_disable == true or vim.b.ministarter_disable == true
end

---- Normalize config elements
function H.normalize_items(items)
  local res = H.items_flatten(items)
  if #res == 0 then
    return { { name = '`MiniStarter.config.items` is empty', action = '', section = '' } }
  end
  return H.items_sort(res)
end

function H.normalize_header_footer(x, x_name)
  local res = H.eval_fun_or_string(x)
  if type(res) ~= 'string' then
    H.notify(string.format([[`config.%s` should be evaluated into string.]], x_name))
    return {}
  end
  if res == '' then
    return {}
  end
  return vim.split(res, '\n')
end

---- Work with buffer content
function H.make_initial_content(items)
  MiniStarter.content = {}

  -- Add header lines
  for _, l in ipairs(H.header) do
    H.content_add_line({ H.content_unit(l, 'header', 'MiniStarterHeader') })
  end
  H.content_add_empty_lines(#H.header > 0 and 1 or 0)

  -- Add item lines
  H.content_add_items(items)

  -- Add footer lines
  H.content_add_empty_lines(#H.footer > 0 and 1 or 0)
  for _, l in ipairs(H.footer) do
    H.content_add_line({ H.content_unit(l, 'footer', 'MiniStarterFooter') })
  end
end

function H.content_unit(string, type, hl, extra)
  return vim.tbl_extend('force', { string = string, type = type, hl = hl }, extra or {})
end

function H.content_add_line(content_line)
  table.insert(MiniStarter.content, content_line)
end

function H.content_add_empty_lines(n)
  for _ = 1, n do
    H.content_add_line({ H.content_unit('', 'empty', nil) })
  end
end

function H.content_add_items(items)
  local cur_section
  for _, item in ipairs(items) do
    -- Possibly add section line
    if cur_section ~= item.section then
      -- Don't add empty line before first section line
      H.content_add_empty_lines(cur_section == nil and 0 or 1)
      H.content_add_line({ H.content_unit(item.section, 'section', 'MiniStarterSection') })
      cur_section = item.section
    end

    H.content_add_line({ H.content_unit(item.name, 'item', 'MiniStarterItem', { item = item }) })
  end
end

function H.content_highlight()
  for l_num, content_line in ipairs(MiniStarter.content) do
    -- Track 0-based starting column of current unit (using byte length)
    local start_col = 0
    for _, unit in ipairs(content_line) do
      if unit.hl ~= nil then
        H.buf_hl(H.ns.general, unit.hl, l_num - 1, start_col, start_col + unit.string:len())
      end
      start_col = start_col + unit.string:len()
    end
  end
end

---- Work with items
function H.items_flatten(items)
  local res, f = {}, nil
  f = function(x)
    if H.is_item(x) then
      -- Use deepcopy to allow adding fields to items without changing original
      table.insert(res, vim.deepcopy(x))
      return
    end

    -- Expand functions immediately
    if type(x) == 'function' then
      x = x()
    end
    if type(x) ~= 'table' then
      return
    end
    return vim.tbl_map(f, x)
  end

  f(items)
  return res
end

function H.items_sort(items)
  -- Order first by section and then by item id (both in order of appearence)
  -- Gather items grouped per section in order of their appearence
  local sections, section_order = {}, {}
  for _, item in ipairs(items) do
    local sec = item.section
    if section_order[sec] == nil then
      table.insert(sections, {})
      section_order[sec] = #sections
    end
    table.insert(sections[section_order[sec]], item)
  end

  -- Unroll items in depth-first fashion
  local res = {}
  for _, section_items in ipairs(sections) do
    for _, item in ipairs(section_items) do
      table.insert(res, item)
    end
  end

  return res
end

function H.items_highlight()
  for _, item in ipairs(H.items) do
    H.buf_hl(H.ns.general, 'MiniStarterItemPrefix', item._line, item._start_col, item._start_col + item._nprefix)
  end
end

-- Prefix number is a length of `item.name` unique prefix among all items
-- Uniqueness is checked ignoring case
-- Algorithm can be optimized to not be O(n^2) but currently not worth it
function H.compute_item_nprefix(item, all_items)
  -- Ignore case when computing prefix number
  local name = item.name:lower()

  for n = 1, name:len() do
    local cur_prefix = name:sub(0, n)
    local similar_items = vim.tbl_filter(function(it)
      -- Again use `lower()` to ignore case
      return vim.startswith(it.name:lower(), cur_prefix)
    end, all_items)
    if #similar_items == 1 then
      return n
    end
  end
  return name:len()
end

function H.next_active_item_id(item_id, direction)
  -- Advance in cyclic fashion
  local id = item_id
  local n_items = vim.tbl_count(H.items)
  local increment = direction == 'next' and 1 or (n_items - 1)

  -- Increment modulo `n` but for 1-based indexing
  id = math.fmod(id + increment - 1, n_items) + 1
  while not (H.items[id]._active or id == item_id) do
    id = math.fmod(id + increment - 1, n_items) + 1
  end

  return id
end

function H.position_cursor_on_current_item()
  vim.api.nvim_win_set_cursor(0, H.items[H.current_item_id]._cursorpos)
end

--- Work with queries
function H.make_query(query)
  -- Ignore case
  query = (query or H.query):lower()

  -- Item is active = item's name starts with query (ignoring case) and item's
  -- action is non-empty
  local n_active = 0
  for _, item in ipairs(H.items) do
    item._active = vim.startswith(item.name:lower(), query) and item.action ~= ''
    n_active = n_active + (item._active and 1 or 0)
  end

  -- Move to next active item if current is not active
  if not H.items[H.current_item_id]._active then
    MiniStarter.update_current_item('next')
  end

  -- Update activity highlighting. This should go before `evaluate_single`
  -- check because evaluation might not result into closing Starter buffer
  vim.api.nvim_buf_clear_namespace(H.buf_id, H.ns.activity, 0, -1)
  H.add_hl_activity(query)

  -- Possibly evaluate single active item
  if MiniStarter.config.evaluate_single and n_active == 1 then
    MiniStarter.eval_current_item()
    return
  end

  -- Notify about new query
  local msg = string.format('Query: %s', H.query)
  if n_active == 0 then
    msg = string.format('%s . There is no active items. Use <BS> to delete symbols from query.', msg)
  end
  ---- Use `echo` because it doesn't write to `:messages`
  vim.cmd(string.format([[echo '(mini.starter) %s']], vim.fn.escape(msg, [[']])))
end

---- Work with starter buffer
function H.apply_buffer_options()
  vim.api.nvim_buf_set_name(H.buf_id, 'Starter')
  -- Having `noautocmd` is crucial for performance: ~9ms without it, ~1.6ms with it
  vim.cmd([[noautocmd silent! set filetype=starter]])

  local options = {
    -- Taken from 'vim-startify'
    [[bufhidden=wipe]],
    [[colorcolumn=]],
    [[foldcolumn=0]],
    [[matchpairs=]],
    [[nobuflisted]],
    [[nocursorcolumn]],
    [[nocursorline]],
    [[nolist]],
    [[nonumber]],
    [[noreadonly]],
    [[norelativenumber]],
    [[nospell]],
    [[noswapfile]],
    [[signcolumn=no]],
    [[synmaxcol&]],
    -- Differ from 'vim-startify'
    [[nomodifiable]],
    [[foldlevel=999]],
  }
  ---- Vim's `setlocal` is currently more robust comparing to `opt_local`
  vim.cmd(string.format([[silent! noautocmd setlocal %s]], table.concat(options, ' ')))

  -- Hide tabline (but not statusline as it weirdly feels 'naked' without it)
  vim.cmd(string.format([[au BufLeave <buffer> set showtabline=%s]], vim.o.showtabline))
  vim.o.showtabline = 0
end

function H.apply_buffer_mappings()
  H.buf_keymap('<CR>', [[MiniStarter.eval_current_item()]])

  H.buf_keymap('<Up>', [[MiniStarter.update_current_item('prev')]])
  H.buf_keymap('<M-k>', [[MiniStarter.update_current_item('prev')]])
  H.buf_keymap('<Down>', [[MiniStarter.update_current_item('next')]])
  H.buf_keymap('<M-j>', [[MiniStarter.update_current_item('next')]])

  -- Make all special symbols to update query
  for _, key in ipairs(vim.split(MiniStarter.config.query_updaters, '')) do
    H.buf_keymap(key, string.format([[MiniStarter.add_to_query('%s')]], key))
  end

  H.buf_keymap('<BS>', [[MiniStarter.add_to_query()]])
  H.buf_keymap('<C-c>', [[MiniStarter.close()]])
end

function H.add_hl_activity(query)
  for _, item in ipairs(H.items) do
    local l = item._line
    local s = item._start_col
    local e = item._end_col
    if item._active then
      H.buf_hl(H.ns.activity, 'MiniStarterQuery', l, s, s + query:len())
    else
      H.buf_hl(H.ns.activity, 'MiniStarterInactive', l, s, e)
    end
  end
end

function H.add_hl_current_item()
  local cur_item = H.items[H.current_item_id]
  H.buf_hl(H.ns.current_item, 'MiniStarterCurrent', cur_item._line, cur_item._start_col, cur_item._end_col)
end

---- Predicates
function H.is_fun_or_string(x)
  return type(x) == 'function' or type(x) == 'string'
end

function H.is_item(x)
  return type(x) == 'table'
    and H.is_fun_or_string(x['action'])
    and type(x['name']) == 'string'
    and type(x['section']) == 'string'
end

---- Utilities
function H.eval_fun_or_string(x, string_as_cmd)
  if type(x) == 'function' then
    return x()
  end
  if string_as_cmd then
    vim.cmd(x)
  else
    return x
  end
end

function H.buf_keymap(key, cmd)
  vim.api.nvim_buf_set_keymap(
    H.buf_id,
    'n',
    key,
    string.format([[<Cmd>lua %s<CR>]], cmd),
    { nowait = true, silent = true }
  )
end

function H.buf_hl(ns_id, hl_group, line, col_start, col_end)
  vim.api.nvim_buf_add_highlight(H.buf_id, ns_id, hl_group, line, col_start, col_end)
end

function H.notify(msg)
  vim.notify(string.format([[(mini.starter) %s]], msg))
end

_G.test_items = {
  -- Placeholder section
  { name = 'Should always be inactive', action = '', section = 'Placeholder' },
  -- Section 1 (nested)
  {
    { name = 'G1A1', action = [[echo 'G1A1']], section = 'Section 1' },
  },
  -- Sections 2 and 3 (double nested)
  {
    {
      {
        name = 'G2A1',
        action = function()
          print('Function action is success')
        end,
        section = 'Section 2',
      },
      { name = 'G2B2', action = [[echo 'G2B2']], section = 'Section 2' },
    },
    {
      { name = 'G3A1', action = [[echo 'G3A1']], section = 'Section 3' },
      function()
        return {
          { name = 'G3B2', action = [[echo 'G3B2']], section = 'Section 3' },
          { name = 'G3C3', action = [[echo 'G3C3']], section = 'Section 3' },
        }
      end,
    },
  },
  -- Section 4 (direct)
  { name = 'G4A1', action = [[echo 'G4A1']], section = 'Section 4' },
  { name = 'G4B2', action = [[echo 'G4B2']], section = 'Section 4' },
  { name = 'G4C3', action = [[echo 'G4C3']], section = 'Section 4' },
  { name = 'G4D4', action = [[echo 'G4D4']], section = 'Section 4' },

  -- Without section (should be ignored)
  { name = 'G_A1', action = [[echo 'G_A1']] },
  { name = 'G_B2', action = [[echo 'G_B2']] },

  -- Already present sections to test grouping
  {
    { name = 'G2C3', action = [[echo 'G2C3']], section = 'Section 2' },
    { name = 'G1B2', action = [[echo 'G1B2']], section = 'Section 1' },
    { name = 'G3D4', action = [[echo 'G3D4']], section = 'Section 3' },
    {
      function()
        return { name = 'G4E5', action = [[echo 'G4E5']], section = 'Section 4' }
      end,
    },
  },

  -- Multiline names
  { name = 'G5A1\n\n', action = [[echo 'G5A1']], section = 'Section 5' },
  {
    name = [[G5
    B2]],
    action = [[echo 'G5B2']],
    section = 'Section 5',
  },
}

return MiniStarter
