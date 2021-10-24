-- MIT License Copyright (c) 2021 Evgeni Chasnovski

---@brief [[
--- Lua module for minimal, fast, and flexible start screen. This is mostly
--- inspired by [mhinz/vim-startify](https://github.com/mhinz/vim-startify).
---
--- Key design ideas:
--- - All available actions are defined by items. Each item should have the
---   following info:
---     - `name` - string which will be displayed and used for choosing.
---     - `action` - function or string for |vim.cmd| which will be executed
---       when item is chosen.
---     - `group` - string representing to which group item belongs.
--- - Choosing of item can be done in two ways:
---     - Choose with Up/Down arrows and hit Enter.
---     - Type start of item's name which uniquely identifies it.
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
--- <pre>
--- {
--- }
--- </pre>
---
--- # Highlight groups
---
--- - `MiniStarterCurrent` - current item.
--- - `MiniStarterFooter` - footer lines.
--- - `MiniStarterGroup` - group lines.
--- - `MiniStarterHeader` - header lines.
--- - `MiniStarterInactive` - inactive item.
--- - `MiniStarterItem` - item name.
--- - `MiniStarterItemQuery` - unique query for item.
--- - `MiniStarterPrefix` - string displayed before item name.
--- - `MiniStarterQuery` - query for active items.
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
  if config.autoopen then
    vim.api.nvim_exec(
      [[augroup MiniStarter
          au!
          au VimEnter * ++nested ++once lua if vim.fn.argc() == 0 then MiniStarter.open() end
        augroup END]],
      false
    )
  end

  -- Create highlighting
  vim.api.nvim_exec(
    [[hi default link MiniStarterCurrent   Visual
      hi default link MiniStarterFooter    Title
      hi default link MiniStarterGroup     Delimiter
      hi default link MiniStarterHeader    Title
      hi default link MiniStarterInactive  Comment
      hi default link MiniStarterItem      Normal
      hi default link MiniStarterItemQuery WarningMsg
      hi default link MiniStarterPrefix    Delimiter
      hi default link MiniStarterQuery     MoreMsg]],
    false
  )
end

-- Module config
MiniStarter.config = {
  -- Whether to open starter buffer if Neovim was called without file arguments
  autoopen = true,

  -- Items to be displayed. Should be a (possibly nested) list with
  -- eventual elements being items. See examples.
  items = {},

  -- Item prefix to be displayed in front of every item
  item_prefix = '│ ',

  -- Whether to prepend item name with unique sequential number
  numerate = false,

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
    'Use <Up>/<Down> or type query to select item',
    '<BS> deletes latest character from query',
    '<C-c> closes this buffer',
  }, '\n'),

  -- Padding from left and top
  padding = { left = 3, top = 2 },

  -- Characters to update query. Each character will have special buffer
  -- mapping overriding your global ones. Be careful to not add `:` as it
  -- allows you to go into command mode.
  query_updaters = [[abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _-.]],
}

-- Module functionality
function MiniStarter.open()
  -- Create and open buffer
  H.buf_id = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(H.buf_id)

  -- Add content
  vim.api.nvim_buf_set_lines(H.buf_id, 0, -1, false, H.buffer_content.lines)

  -- Always position cursor on current item
  H.position_cursor_on_current_item()
  vim.cmd([[au CursorMoved <buffer> lua MiniStarter.on_cursormoved()]])

  -- Setup buffer behavior
  H.apply_buffer_options()
  H.apply_buffer_mappings()
  H.apply_buffer_highlighting()

  -- Apply current query (if reopened, it uses latest query)
  H.make_query()
end

function MiniStarter.close()
  vim.api.nvim_buf_delete(H.buf_id, {})
  H.buf_id = nil
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

function MiniStarter.update_query(char)
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

---- Normalized values from config
H.items = {} -- flattened and sorted items
H.header = {} -- table of strings
H.footer = {} -- table of strings

---- Identifier of current item
H.current_item_id = nil

---- Content of buffer. Table with elements:
---- - `lines` - list of strings to be displayed.
---- - `lines_info` - list with information about each line in `lines`.
H.buffer_content = { lines = {}, lines_info = {} }

---- Buffer identifier where everything is displayed
H.buf_id = nil

---- Namespaces for highlighting
H.ns = {
  activity = vim.api.nvim_create_namespace(''),
  current_item = vim.api.nvim_create_namespace(''),
  general = vim.api.nvim_create_namespace(''),
}

---- Names of highlight groups for content line types (`lines_info[i].type`)
H.hl_group_per_linetype = {
  header = 'MiniStarterHeader',
  footer = 'MiniStarterFooter',
  group = 'MiniStarterGroup',
  item = 'MiniStarterItem',
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

    items = { config.items, 'table' },
    item_prefix = { config.item_prefix, 'string' },
    numerate = { config.numerate, 'boolean' },

    header = { config.header, H.is_fun_or_string, 'function or string' },
    footer = { config.footer, H.is_fun_or_string, 'function or string' },

    padding = { config.padding, 'table' },
    ['padding.left'] = { config.padding.left, 'number' },
    ['padding.top'] = { config.padding.top, 'number' },

    query_updaters = { config.query_updaters, 'string' },
  })

  return config
end

function H.apply_config(config)
  MiniStarter.config = config

  -- Normalize certain config values
  H.items = H.items_enhance(H.items_sort(H.items_flatten(config.items)))
  H.header = H.normalize_header_footer(config.header, 'header')
  H.footer = H.normalize_header_footer(config.footer, 'footer')

  -- Precompute helper information
  H.current_item_id = 1
  H.make_buffer_content()
end

function H.is_disabled()
  return vim.g.ministarter_disable == true or vim.b.ministarter_disable == true
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
function H.make_buffer_content(left_pad, top_pad)
  left_pad = left_pad or math.max(MiniStarter.config.padding.left, 0)
  top_pad = top_pad or math.max(MiniStarter.config.padding.top, 0)

  H.buffer_content = { lines = {}, lines_info = {} }

  H.content_add_empty(top_pad)

  H.content_add(H.header, { type = 'header', start_col = left_pad + 1 }, left_pad)
  if vim.tbl_count(H.header) > 0 then
    H.content_add_empty(1)
  end

  H.content_add_items(H.items, left_pad)

  if vim.tbl_count(H.footer) > 0 then
    H.content_add_empty(1)
  end
  H.content_add(H.footer, { type = 'footer', start_col = left_pad + 1 }, left_pad)
end

function H.content_add(lines, info, left_pad)
  local pad_string = string.rep(' ', left_pad or 0)

  for _, l in ipairs(lines) do
    table.insert(H.buffer_content.lines, string.format('%s%s', pad_string, l))
    table.insert(H.buffer_content.lines_info, info)
  end
end

function H.content_add_empty(n)
  local t = {}
  for _ = 1, n do
    table.insert(t, '')
  end

  H.content_add(t, { type = 'empty', start_col = 0 })
end

function H.content_add_items(items, left_pad)
  local cur_group
  for _, item in ipairs(items) do
    -- Possibly start new group
    if cur_group ~= item.group then
      -- Don't add empty line for the first group header
      if cur_group ~= nil then
        H.content_add_empty(1)
      end
      H.content_add({ item.group }, { type = 'group', start_col = left_pad + 1 }, left_pad)
      cur_group = item.group
    end
    H.content_add(
      { string.format('%s%s', MiniStarter.config.item_prefix, item.name) },
      { type = 'item', start_col = left_pad + MiniStarter.config.item_prefix:len() + 1, item_id = item.id },
      left_pad
    )

    -- Add (by reference) tracking information to items
    item.line_num = #H.buffer_content.lines
  end
end

---- Work with items
function H.items_flatten(items)
  local res, f = {}, nil
  f = function(x)
    if H.is_item(x) then
      -- Add some helper fields to items
      -- Use deepcopy to allow adding fields to items without them changing
      local t = vim.deepcopy(x)
      t.active = true

      table.insert(res, t)
      return
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
  -- Order first by group and then by item id (both in order of appearence)
  -- Gather grouped items in order of their appearence
  local grouped, group_order = {}, {}
  for _, item in ipairs(items) do
    local gr = item.group
    if group_order[gr] == nil then
      table.insert(grouped, {})
      group_order[gr] = #grouped
    end
    table.insert(grouped[group_order[gr]], item)
  end

  -- Unroll items in depth-first fashion
  local res = {}
  for _, group_items in ipairs(grouped) do
    for _, item in ipairs(group_items) do
      table.insert(res, item)
    end
  end

  return res
end

function H.items_enhance(items)
  -- Add data by reference
  for i, item in ipairs(items) do
    item.id = i
    -- Ensure single line name
    item.name = item.name:gsub('\n', ' ')
    if MiniStarter.config.numerate then
      item.name = string.format('%s. %s', i, item.name)
    end
  end

  -- Compute item queries *after* all names are enhanced
  for _, item in ipairs(items) do
    item.query = H.compute_item_query(item, items)
  end

  return items
end

function H.compute_item_query(item, all_items)
  for len = 1, item.name:len() do
    local cur_res = item.name:sub(0, len)
    local similar_items = vim.tbl_filter(function(it)
      return it.name:sub(0, len) == cur_res
    end, all_items)
    if #similar_items == 1 then
      return cur_res
    end
  end
  return item.name
end

function H.next_active_item_id(item_id, direction)
  -- Advance in cyclic fashion
  local id = item_id
  local n_items = vim.tbl_count(H.items)
  local increment = direction == 'next' and 1 or (n_items - 1)

  id = math.fmod(id + increment - 1, n_items) + 1
  while not (H.items[id].active or id == item_id) do
    id = math.fmod(id + increment - 1, n_items) + 1
  end

  return id
end

function H.position_cursor_on_current_item()
  local current_line = H.items[H.current_item_id].line_num
  local start_col = H.buffer_content.lines_info[current_line].start_col
  vim.api.nvim_win_set_cursor(0, { current_line, start_col - 1 - MiniStarter.config.item_prefix:len() })
end

--- Work with queries
function H.make_query(query)
  query = query or H.query

  -- Active is active = item's name starts with query
  local query_n_string = query:len()
  for _, item in ipairs(H.items) do
    item.active = item.name:sub(0, query_n_string) == query
  end

  -- Update activity highlighting
  vim.api.nvim_buf_clear_namespace(H.buf_id, H.ns.activity, 0, -1)
  H.add_hl_activity(query)

  -- Move to next active item if current is not active
  local no_active = false
  if not H.items[H.current_item_id].active then
    local prev_current = H.current_item_id
    MiniStarter.update_current_item('next')
    if prev_current == H.current_item_id then
      no_active = true
    end
  end

  -- Notify about new query
  local msg = string.format('Query: %s', H.query)
  if no_active then
    msg = string.format('%s . There is no active items. Use <BS> to delete symbols from query.', msg)
  end
  H.notify(msg)
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
  -- Using Vim's `setlocal` is currently more robust comparing to `opt_local`
  vim.cmd(string.format([[silent! noautocmd setlocal %s]], table.concat(options, ' ')))
end

function H.apply_buffer_mappings()
  H.buf_keymap('<CR>', [[MiniStarter.eval_current_item()]])
  H.buf_keymap('<Up>', [[MiniStarter.update_current_item('prev')]])
  H.buf_keymap('<Down>', [[MiniStarter.update_current_item('next')]])

  -- Make all special symbols to update query
  for _, key in ipairs(vim.split(MiniStarter.config.query_updaters, '')) do
    H.buf_keymap(key, string.format([[MiniStarter.update_query('%s')]], key))
  end

  H.buf_keymap('<BS>', [[MiniStarter.update_query()]])
  H.buf_keymap('<C-c>', [[MiniStarter.close()]])
end

function H.apply_buffer_highlighting()
  H.add_hl_general()
  H.add_hl_current_item()
end

function H.add_hl_general()
  local n_prefix = MiniStarter.config.item_prefix:len()
  for i, info in ipairs(H.buffer_content.lines_info) do
    local s = info.start_col
    if info.type == 'item' and n_prefix > 0 then
      H.buf_hl(H.ns.general, 'MiniStarterPrefix', i - 1, s - n_prefix - 1, s - 2)
    end
    if info.type ~= 'empty' then
      H.buf_hl(H.ns.general, H.hl_group_per_linetype[info.type], i - 1, s - 1, -1)
    end
    if info.type == 'item' then
      local n_item_query = H.items[info.item_id].query:len()
      H.buf_hl(H.ns.general, 'MiniStarterItemQuery', i - 1, s - 1, s + n_item_query - 1)
    end
  end
end

function H.add_hl_activity(query)
  for _, item in ipairs(H.items) do
    local line_num = item.line_num
    local s = H.buffer_content.lines_info[line_num].start_col
    if item.active then
      H.buf_hl(H.ns.activity, 'MiniStarterQuery', line_num - 1, s - 1, s + query:len() - 1)
    else
      H.buf_hl(H.ns.activity, 'MiniStarterInactive', line_num - 1, s - 1, -1)
    end
  end
end

function H.add_hl_current_item()
  local line = H.items[H.current_item_id].line_num
  local start_col = H.buffer_content.lines_info[line].start_col
  H.buf_hl(H.ns.current_item, 'MiniStarterCurrent', line - 1, start_col - 1, -1)
end

---- Predicates
function H.is_fun_or_string(x)
  return type(x) == 'function' or type(x) == 'string'
end

function H.is_item(x)
  return type(x) == 'table'
    and type(x['name']) == 'string'
    and H.is_fun_or_string(x['action'])
    and type(x['group']) == 'string'
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
  { name = [[Load 'nvim-config']], action = [[lua MiniSessions.load('nvim-config')]], group = 'Sessions' },

  -- Group 1 (nested)
  {
    { name = 'G1A1', action = [[echo 'G1A1']], group = 'Group 1' },
  },
  -- Groups 2 and 3 (double nested)
  {
    {
      { name = 'G2A1', action = [[echo 'G2A1']], group = 'Group 2' },
      { name = 'G2B2', action = [[echo 'G2B2']], group = 'Group 2' },
    },
    {
      { name = 'G3A1', action = [[echo 'G3A1']], group = 'Group 3' },
      { name = 'G3B2', action = [[echo 'G3B2']], group = 'Group 3' },
      { name = 'G3C3', action = [[echo 'G3C3']], group = 'Group 3' },
    },
  },
  -- Group 4 (direct)
  { name = 'G4A1', action = [[echo 'G4A1']], group = 'Group 4' },
  { name = 'G4B2', action = [[echo 'G4B2']], group = 'Group 4' },
  { name = 'G4C3', action = [[echo 'G4C3']], group = 'Group 4' },
  { name = 'G4D4', action = [[echo 'G4D4']], group = 'Group 4' },

  -- Ungrouped (should be ignored)
  { name = 'G_A1', action = [[echo 'G_A1']] },
  { name = 'G_B2', action = [[echo 'G_B2']] },

  -- Already present groups to test grouping
  { name = 'G2C3', action = [[echo 'G2C3']], group = 'Group 2' },
  { name = 'G1B2', action = [[echo 'G1B2']], group = 'Group 1' },
  { name = 'G3D4', action = [[echo 'G3D4']], group = 'Group 3' },
  { name = 'G4E5', action = [[echo 'G4E5']], group = 'Group 4' },

  -- Multiline names
  { name = 'G5A1\n\n', action = [[echo 'G5A1']], group = 'Group 5' },
  {
    name = [[G5
    B2]],
    action = [[echo 'G5B2']],
    group = 'Group 5',
  },
}

return MiniStarter
