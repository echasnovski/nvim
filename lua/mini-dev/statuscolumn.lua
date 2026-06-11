--- *mini.statuscolumn* Statuscolumn
---
--- MIT License Copyright (c) 2026 Evgeni Chasnovski

--- Features:
---
--- - Configurable and performant |'statuscolumn'|.
---
--- Notes:
--- - Works best on Neovim>=0.11.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.statuscolumn').setup({})`
--- (replace `{}` with your `config` table). It will create global Lua table
--- `MiniStatuscolumn` which you can use for scripting or manually (with
--- `:lua MiniStatuscolumn.*`).
---
--- See |MiniStatuscolumn.config| for `config` structure and default values.
---
--- # Suggested option values ~
---
--- - Depending on how distinctive |hl-FoldColumn| is from |hl-LineNr|, it might
---   be a good idea to use minimal fold column characters in  |'fillchars'|.
---   Like `foldopen:🯘,foldclose:🮥,foldsep: ,foldinner: `.
---
--- # Comparisons ~
---
--- - [luukvball/statuscol.nvim](https://github.com/luukvball/statuscol.nvim):
---     - ...
---
--- - [folke/snacks.nvim#statuscolumn](https://github.com/folke/snacks.nvim):
---     - ...
---
--- # Highlight groups ~
--- *MiniStatuscolumn-hl-groups*
---
--- - `MiniStatuscolumnCursorLineSep` - column and text separator at cursor line.
--- - `MiniStatuscolumnInactive` - column highlighting of not current window.
--- - `MiniStatuscolumnSep` - column and text separator.
---@tag MiniStatuscolumn

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local

-- Module definition ==========================================================
local MiniStatuscolumn = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniStatuscolumn.config|.
---
---@usage >lua
---   require('mini.statuscolumn').setup() -- use default config
---   -- OR
---   require('mini.statuscolumn').setup({}) -- replace {} with your config table
--- <
MiniStatuscolumn.setup = function(config)
  -- Export module
  _G.MiniStatuscolumn = MiniStatuscolumn

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands(config)

  -- Create default highlighting
  H.create_default_hl()
end

--- Defaults ~
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # Highlight inactive windows ~
--- Notes:
--- - Enabling works best with appropriately "dimming" `MiniStatuscolumnInactive`
---   and statuscolumn for inactive window being the same as for active.
MiniStatuscolumn.config = {
  content = {
    active = nil,
    inactive = nil,
  },

  click = {
    -- TODO: should it be in config or enough in `gen_content.precomputed` spec?
  },

  -- Whether to autohighlight whole column in active windows
  hl_inactive = false,
}
--minidoc_afterlines_end

--- Content generators
---
--- This is a table with function elements. Call to actually get a content table.
MiniStatuscolumn.gen_content = {}

--- Default content generator
---
--- TODO: How spec array normalization works, defaults are the same as
--- default |'statuscolumn'|.
---
--- Examples:
---
--- - Specification for default `content` in |MiniStatuscolumn.config|.
---   Use as a template to adjust/remove added behavior: >lua
---
---   local statuscolumn = require('mini.statuscolumn')
---   local spec = {
---     -- Prefer more efficient order and visible separator
---     { format = '=lfs', sep = '▏' },
---     -- Use custom symbol for virtual lines
---     { ltype = 'virt', lnum = '•' },
---     -- Use custom symbol for wrapped lines
---     { ltype = 'wrap', lnum = '↳' },
---     -- Highlight only cursor line in inactive windows
---     { win = 'inactive', pos = 'above', fold = '', lnum = '', sign = '' },
---     { win = 'inactive', pos = 'below', fold = '', lnum = '', sign = '' },
---   }
---   statuscolumn.setup({ content = statuscolumn.gen_content.precomputed(spec) })
--- <
--- - Thicker default `sep`: `{ pos = 'cursor', sep = '▍' }`.
---
--- - Forced highlighting: `{ pos = 'cursor', lnum = '%#CursorLineNr#•' }`.
---   Has problems that it overrides highlighting from extmarks.
MiniStatuscolumn.gen_content.precomputed = function(spec)
  H.validate_content_spec(spec)
  -- TODO: Add mouse click support
  local content_map = H.make_content_map(spec)

  -- TODO: Remove after doing benchmarks
  _G.n_statuscolumn = 0
  local win_get_cursor = vim.api.nvim_win_get_cursor
  local make = function(win)
    return function(win_data)
      _G.n_statuscolumn = _G.n_statuscolumn + 1
      if win_data.is_empty then return '' end
      local pos = vim.v.relnum == 0 and 'cursor' or (vim.v.lnum < win_get_cursor(0)[1] and 'above' or 'below')
      local ltype = vim.v.virtnum == 0 and 'text' or (vim.v.virtnum < 0 and 'virt' or 'wrap')
      local res = content_map[win][pos][ltype].content
      return res
    end
  end

  return { active = make('active'), inactive = make('inactive') }
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniStatuscolumn.config)

-- Namespaces
H.ns_id = {
  decor = vim.api.nvim_create_namespace('MiniStatuscolumnDecor'),
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('config.content', config.content, 'table')
  H.check_type('config.content.active', config.content.active, 'function', true)
  H.check_type('config.content.inactive', config.content.inactive, 'function', true)

  H.check_type('config.click', config.click, 'table')

  H.check_type('config.hl_inactive', config.hl_inactive, 'boolean')

  return config
end

H.apply_config = function(config)
  MiniStatuscolumn.config = config

  -- Ensure proper content
  local content = config.content
  if content.active == nil and content.inactive == nil then
    local default_spec = {
      { format = '=lfs', sep = '▏' },
      { ltype = 'virt', lnum = '•' },
      { ltype = 'wrap', lnum = '↳' },
      { win = 'inactive', pos = 'above', fold = '', lnum = '', sign = '' },
      { win = 'inactive', pos = 'below', fold = '', lnum = '', sign = '' },
    }
    content = MiniStatuscolumn.gen_content.precomputed(default_spec)
  end

  -- Make and set statuscolumn
  H.make_statuscolumn_functions(content.active or content.inactive, content.inactive or content.active)
  vim.o.statuscolumn =
    '%{%nvim_get_current_win()==#g:actual_curwin ? v:lua.MiniStatuscolumn.active() : v:lua.MiniStatuscolumn.inactive()%}'
end

H.create_autocommands = function(config)
  local gr = vim.api.nvim_create_augroup('MiniStatuscolumn', {})
  vim.api.nvim_create_autocmd('ColorScheme', { group = gr, callback = H.create_default_hl, desc = 'Ensure colors' })

  if config.hl_inactive then H.make_hl_inactive() end
end

H.create_default_hl = function()
  local hi = function(name, opts)
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end

  hi('MiniStatuscolumnCursorLineSep', { link = 'MiniStatuscolumnSep' })
  hi('MiniStatuscolumnInactive', { link = 'StatusLineNC' })
  hi('MiniStatuscolumnSep', { link = 'LineNr' })
end

-- Autocommands ---------------------------------------------------------------
H.make_hl_inactive = function()
  -- Set automatic inactive highlight
  local inactive_winhl = {
    -- TODO: Decide maybe to not dim cursorline groups?
    'CursorLineFold:MiniStatuscolumnInactive',
    'CursorLineNr:MiniStatuscolumnInactive',
    'CursorLineSign:MiniStatuscolumnInactive',
    'FoldColumn:MiniStatuscolumnInactive',
    'LineNr:MiniStatuscolumnInactive',
    'LineNrAbove:MiniStatuscolumnInactive',
    'LineNrBelow:MiniStatuscolumnInactive',
    'SignColumn:MiniStatuscolumnInactive',

    'MiniStatuscolumnCursorLineSep:MiniStatuscolumnInactive',
    'MiniStatuscolumnSep:MiniStatuscolumnInactive',
  }
  local inactive_winhl_str = table.concat(inactive_winhl, ',')
  local inactive_winhl_map = {}
  for _, hl_pair in ipairs(inactive_winhl) do
    inactive_winhl_map[hl_pair] = true
  end

  local add = function()
    local winhl = vim.wo.winhighlight
    local new_winhl = winhl .. (winhl == '' and '' or ',') .. inactive_winhl_str
    vim.wo.winhighlight = new_winhl
  end

  local remove = function()
    local winhl = vim.split(vim.wo.winhighlight, ',')
    winhl = vim.tbl_filter(function(hl_pair) return not inactive_winhl_map[hl_pair] end, winhl)
    vim.wo.winhighlight = table.concat(winhl, ',')
  end

  local gr = vim.api.nvim_create_augroup('MiniStatuscolumn', { clear = false })
  vim.api.nvim_create_autocmd('WinLeave', { group = gr, callback = add, desc = 'Add inactive highlight' })
  vim.api.nvim_create_autocmd('WinEnter', { group = gr, callback = remove, desc = 'Remove inactive highlight' })
end

-- Content --------------------------------------------------------------------
H.make_statuscolumn_functions = function(active, inactive)
  -- Local helpers to not do extra `vim.api` table lookups
  local get_cur_win = vim.api.nvim_get_current_win
  local eval_stl = vim.api.nvim_eval_statusline

  -- Set up window data caching
  local gr = vim.api.nvim_create_augroup('MiniStatuscolumnWinCache', {})
  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = gr, pattern = pattern, callback = callback, desc = desc })
  end

  -- TODO: Maybe a more granular update (for performance)?
  local win_cache = {}
  local update_win_cache = function()
    win_cache = {}
    for _, win_id in ipairs(vim.api.nvim_list_wins()) do
      local cache = { buf_id = vim.api.nvim_win_get_buf(win_id), win_id = win_id }

      -- Relevant options
      cache.cursorline = vim.wo[win_id].cursorline
      cache.cursorlineopt = vim.wo[win_id].cursorlineopt
      cache.foldcolumn = vim.wo[win_id].foldcolumn
      cache.number = vim.wo[win_id].number
      cache.relativenumber = vim.wo[win_id].relativenumber
      cache.signcolumn = vim.wo[win_id].signcolumn

      -- Helpful indicators
      cache.is_empty = eval_stl('%l%C%s', { winid = win_id, use_statuscol_lnum = 1 }).str == ''
      -- TODO: Maybe rename to `is_cursorline_hl` if https://github.com/vim/vim/issues/20480
      -- is closed as expected behavior
      cache.is_cursorlinenr = cache.cursorline
        and (cache.cursorlineopt:find('number') ~= nil or cache.cursorlineopt:find('both') ~= nil)

      win_cache[win_id] = cache
    end
  end
  au({ 'WinNew', 'WinClosed' }, '*', update_win_cache, 'Update window cache')
  local options = { 'cursorline', 'cursorlineopt', 'foldcolumn', 'number', 'relativenumber', 'signcolumn' }
  au('OptionSet', options, update_win_cache, 'Update window cache')

  -- Define exported functions for active and inactive windows
  local get_curwin_cache = function()
    local win_id = get_cur_win()
    if win_cache[win_id] then return win_cache[win_id] end
    update_win_cache()
    return win_cache[win_id]
  end

  MiniStatuscolumn.active = function() return active(get_curwin_cache()) end
  MiniStatuscolumn.inactive = function() return inactive(get_curwin_cache()) end
end

H.validate_content_spec = function(x)
  H.check_array_of('spec', x, 'table')
  for i, s in ipairs(x) do
    local item = string.format('spec[%d]', i)
    if s.win ~= nil then H.check_one_of(item .. '.win', s.win, { 'active', 'inactive' }) end
    if s.pos ~= nil then H.check_one_of(item .. '.pos', s.pos, { 'above', 'cursor', 'below' }) end
    if s.ltype ~= nil then H.check_one_of(item .. '.ltype', s.ltype, { 'text', 'virt', 'wrap' }) end

    H.check_type(item .. '.format', s.format, 'string', true)
    if s.format ~= nil and s.format:find('[^=lfs]') ~= nil then
      H.error('`' .. item .. '`.format should contain only `=fls` characters')
    end
    H.check_type(item .. '.fold', s.fold, 'string', true)
    H.check_type(item .. '.lnum', s.lnum, 'string', true)
    H.check_type(item .. '.sign', s.sign, 'string', true)
    H.check_type(item .. '.sep', s.sep, 'string', true)

    local at_least_one_info = s.format or s.fold or s.lnum or s.sign or s.sep
    if not at_least_one_info then H.error('`' .. item .. '`should contain at least one info field') end
  end
end

H.make_content_map = function(spec)
  -- Gather array spec into a map ensuring default values
  spec = vim.deepcopy(spec)
  table.insert(spec, 1, { format = '=fsl', fold = '%C', lnum = '%l', sign = '%s', sep = ' ' })

  local map = {}
  for _, s in ipairs(spec) do
    local win_values = s.win == nil and { 'active', 'inactive' } or { s.win }
    local pos_values = s.pos == nil and { 'above', 'cursor', 'below' } or { s.pos }
    local ltype_values = s.ltype == nil and { 'text', 'virt', 'wrap' } or { s.ltype }

    for _, win in ipairs(win_values) do
      s.win = win
      local win_map = map[win] or {}
      for _, pos in ipairs(pos_values) do
        s.pos = pos
        local pos_map = win_map[pos] or {}
        for _, ltype in ipairs(ltype_values) do
          s.ltype = ltype
          pos_map[ltype] = vim.tbl_extend('force', pos_map[ltype] or {}, s)
        end
        win_map[pos] = pos_map
      end
      map[win] = win_map
    end
  end

  -- Compute content for each scope
  local format_repl = { ['='] = '%=' }
  for _, win_map in pairs(map) do
    for _, pos_map in pairs(win_map) do
      for _, ltype_map in pairs(pos_map) do
        local hl_sep = '%#MiniStatuscolumn' .. (ltype_map.pos == 'cursor' and 'CursorLine' or '') .. 'Sep#'
        local sep = ltype_map.sep == '' and '' or (hl_sep .. ltype_map.sep)

        format_repl.f, format_repl.l, format_repl.s = ltype_map.fold, ltype_map.lnum, ltype_map.sign
        ltype_map.content = ltype_map.format:gsub('[=fls]', format_repl) .. sep
      end
    end
  end

  return map
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.statuscolumn) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.check_one_of = function(name, x, choices)
  if vim.tbl_contains(choices, x) then return end
  local choices_string = table.concat(vim.tbl_map(vim.inspect, choices), ', ')
  local msg = string.format('`%s` should be one of %s', name, choices_string)
  H.error(msg)
end

H.check_array_of = function(name, x, ref_type)
  if not H.islist(x) then H.error('`' .. name .. '` should be array') end
  for i, k in ipairs(x) do
    if type(k) ~= ref_type then H.error('Every `' .. name .. '` item should be ' .. ref_type) end
  end
end

H.notify = function(msg, level_name) vim.notify('(mini.statuscolumn) ' .. msg, vim.log.levels[level_name]) end

-- TODO: Remove after compatibility with Neovim=0.9 is dropped
H.islist = vim.fn.has('nvim-0.10') == 1 and vim.islist or vim.tbl_islist

return MiniStatuscolumn
