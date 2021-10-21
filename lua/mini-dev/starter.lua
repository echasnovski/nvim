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
--- - `MiniStarterHeader` - header lines.
--- - `MiniStarterFooter` - footer lines.
--- - `MiniStarterGroup` - group lines.
--- - `MiniStarterCurrent` - current item.
--- - `MiniStarterInactive` - inactive item.
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

  -- Create highlighting
  vim.api.nvim_exec(
    [[hi default link MiniStarterHeader    Title
      hi default link MiniStarterFooter    Title
      hi default link MiniStarterGroup     Statement
      hi default link MiniStarterCurrent   Visual
      hi default link MiniStarterInactive  Comment]],
    false
  )
end

-- Module config
MiniStarter.config = {
  -- Items to be displayed. Should be a (possibly nested) list with
  -- eventual elements being items. See examples.
  items = {},

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
  footer = '',
}

-- Module functionality
function MiniStarter.on_enter()
  local current_item = H.get_item(H.current_item_id)
  H.eval_fun_or_string(current_item.action, true)
end

function MiniStarter.on_arrow(arrow)
  -- Advance current item
  local direction = arrow == 'down' and 'next' or 'previous'
  H.current_item_id = H.advance_item_id(H.current_item_id, direction)

  -- Highlight current item
  vim.api.nvim_buf_clear_namespace(H.buf_id, H.ns.current_item, 0, -1)
  H.add_hl_current()
end

-- Helper data
---- Module default config
H.default_config = MiniStarter.config

---- Normalized values from config
H.norm_items = {} -- flattened and grouped items
H.header = {} -- table of strings
H.footer = {} -- table of strings

---- Mapping of item identifier to its coordinate (group_id, item_id) in
---- `H.norm_items`. Useful for iterating through items.
H.id_to_coord = {}

---- Identifier of current item
H.current_item_id = nil

---- Buffer identifier where everything is displayed
H.buf_id = nil

---- Namespaces for highlighting
H.ns = {
  general = vim.api.nvim_create_namespace(''),
  active_items = vim.api.nvim_create_namespace(''),
  current_item = vim.api.nvim_create_namespace(''),
}

-- Helper functions
---- Settings
function H.setup_config(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    items = { config.items, 'table' },
    header = { config.header, H.is_fun_or_string, 'function or string' },
    footer = { config.footer, H.is_fun_or_string, 'function or string' },
  })

  return config
end

function H.apply_config(config)
  MiniStarter.config = config

  -- Normalize certain config values
  H.norm_items = H.items_group(H.items_flatten(config.items))
  H.header = H.normalize_header_footer(config.header, 'header')
  H.footer = H.normalize_header_footer(config.footer, 'footer')

  -- Precompute helper information
  H.id_to_coord = H.items_get_id_to_coord(H.norm_items)
  H.current_item_id = 1
  H.buffer_lines = H.make_buffer_lines()
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

function H.make_buffer_lines()
  local lines = {}

  -- Add header
  vim.list_extend(lines, H.header)
  table.insert(lines, '')

  -- Add grouped items. Track source of every added line (modify by reference).
  for _, gr in pairs(H.norm_items) do
    table.insert(lines, gr.group)
    gr.line = #lines
    for _, item in pairs(gr.items) do
      -- Indent items relative to group lines
      table.insert(lines, string.format('│ %s', item.name))
      item.line = #lines
    end

    table.insert(lines, '')
  end

  -- Add footer
  vim.list_extend(lines, H.footer)

  return lines
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

-- Group flattened items. Output is a list where each element is a table:
-- - `group` - name of group.
-- - `items` - list of items of this group.
-- Order of groups and items within group - whichever appeared first in
-- flattened items.
function H.items_group(items)
  local grouped_items, group_id = {}, {}
  for _, item in ipairs(items) do
    local gr = item.group
    if group_id[gr] == nil then
      group_id[gr] = #grouped_items + 1
      grouped_items[group_id[gr]] = { group = gr, items = {} }
    end

    item.group = nil
    table.insert(grouped_items[group_id[gr]].items, item)
  end

  return grouped_items
end

function H.items_get_id_to_coord(norm_items)
  local res = {}
  for i, gr in ipairs(norm_items) do
    for j, _ in ipairs(gr.items) do
      table.insert(res, { group = i, item = j })
    end
  end
  return res
end

-- Compute item id of next/previous active item
function H.advance_item_id(item_id, direction)
  local id = item_id
  local n_items = vim.tbl_count(H.id_to_coord)
  local increment = direction == 'next' and 1 or (n_items - 1)

  -- Advance in cyclic fashion
  id = math.fmod(id + increment - 1, n_items) + 1
  while not (H.get_item(id).active or id == item_id) do
    id = math.fmod(id + increment - 1, n_items) + 1
  end

  return id
end

function H.get_item(item_id)
  local coord = H.id_to_coord[item_id]
  return H.norm_items[coord.group].items[coord.item]
end

---- Work with starter buffer
function H.open_starter_buffer()
  H.buf_id = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(H.buf_id, 0, -1, false, H.buffer_lines)

  H.apply_buffer_options()
  H.apply_buffer_mappings()
  H.apply_buffer_highlighting()

  vim.api.nvim_set_current_buf(H.buf_id)
  vim.cmd([[%foldopen!]])
end

function H.close_starter_buffer()
  vim.api.nvim_buf_delete(H.buf_id, {})
  H.buf_id = nil
end

function H.apply_buffer_options()
  vim.api.nvim_buf_set_name(H.buf_id, 'Starter')
  vim.api.nvim_buf_set_option(H.buf_id, 'filetype', 'starter')
  vim.api.nvim_buf_set_option(H.buf_id, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(H.buf_id, 'bufhidden', 'wipe')
end

function H.apply_buffer_mappings()
  H.buf_keymap('<CR>', [[MiniStarter.on_enter()]])
  H.buf_keymap('<Up>', [[MiniStarter.on_arrow('up')]])
  H.buf_keymap('<Down>', [[MiniStarter.on_arrow('down')]])
end

function H.apply_buffer_highlighting()
  H.add_hl_current()
end

function H.add_hl_current()
  local line = H.get_item(H.current_item_id).line
  vim.api.nvim_buf_add_highlight(H.buf_id, H.ns.current_item, 'MiniStarterCurrent', line - 1, 4, -1)
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

function H.notify(msg)
  vim.notify(string.format([[(mini.starter) %s]], msg))
end

_G.test_items = {
  -- Group 1 (nested)
  {
    { name = 'G1N1', action = [[echo 'G1N1']], group = 'G1' },
  },
  -- Groups 2 and 3 (double nested)
  {
    {
      { name = 'G2N1', action = [[echo 'G2N1']], group = 'G2' },
      { name = 'G2N2', action = [[echo 'G2N2']], group = 'G2' },
    },
    {
      { name = 'G3N1', action = [[echo 'G3N1']], group = 'G3' },
      { name = 'G3N2', action = [[echo 'G3N2']], group = 'G3' },
      { name = 'G3N3', action = [[echo 'G3N3']], group = 'G3' },
    },
  },
  -- Group 4 (direct)
  { name = 'G4N1', action = [[echo 'G4N1']], group = 'G4' },
  { name = 'G4N2', action = [[echo 'G4N2']], group = 'G4' },
  { name = 'G4N3', action = [[echo 'G4N3']], group = 'G4' },
  { name = 'G4N4', action = [[echo 'G4N4']], group = 'G4' },

  -- Ungrouped (should be ignored)
  { name = 'G_N1', action = [[echo 'G_N1']] },
  { name = 'G_N2', action = [[echo 'G_N2']] },

  -- Already present groups to test grouping
  { name = 'G2N3', action = [[echo 'G2N3']], group = 'G2' },
  { name = 'G1N2', action = [[echo 'G1N2']], group = 'G1' },
  { name = 'G3N4', action = [[echo 'G3N4']], group = 'G3' },
  { name = 'G4N5', action = [[echo 'G4N5']], group = 'G4' },
}

return MiniStarter
