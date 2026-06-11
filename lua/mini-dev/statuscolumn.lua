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
--- - `MiniStatuscolumnInactive` - highlighting of not current window.
--- - `MiniStatuscolumnSep` - separator between column and buffer text.
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
  -- Whether to autohighlight whole column in active windows
  hl_inactive = false,

  -- TODO: Decide on config. Like:
  -- - Whether to allow callable (active/inactive) content that will be called
  --   with efficiently cached window data?
  -- - Or just support "specs array"? Mixing the two feels problematic.
  --   Unless via some combination of `default_content` that returns
  --   `{ active = function()  end, inactive = function()  end }`. But that
  --   should not result in a very deep nesting.
}
--minidoc_afterlines_end

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

  H.check_type('config.hl_inactive', config.hl_inactive, 'boolean')

  return config
end

H.apply_config = function(config)
  MiniStatuscolumn.config = config

  H.make_content(config)
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

  hi('MiniStatuscolumnInactive', { link = 'StatusLineNC' })
  hi('MiniStatuscolumnSep', { link = 'LineNr' })
end

-- Autocommands ---------------------------------------------------------------
H.make_hl_inactive = function()
  -- Set automatic inactive highlight
  local inactive_winhl = {
    'CursorLineFold:MiniStatuscolumnInactive',
    'CursorLineNr:MiniStatuscolumnInactive',
    'CursorLineSign:MiniStatuscolumnInactive',
    'FoldColumn:MiniStatuscolumnInactive',
    'LineNr:MiniStatuscolumnInactive',
    'LineNrAbove:MiniStatuscolumnInactive',
    'LineNrBelow:MiniStatuscolumnInactive',
    'SignColumn:MiniStatuscolumnInactive',
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
H.make_content = function(config)
  -- TODO: Remove after doing benchmarks
  _G.n_statuscolumn = 0

  -- Local helpers to not do extra `vim.api` table lookups
  local get_cur_win = vim.api.nvim_get_current_win
  local win_get_cursor = vim.api.nvim_win_get_cursor
  local eval_stl = vim.api.nvim_eval_statusline

  -- Set up window data caching
  local gr = vim.api.nvim_create_augroup('MiniStatuscolumnWinCache', {})
  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = gr, pattern = pattern, callback = callback, desc = desc })
  end

  local win_cache = {}
  -- TODO: Maybe a more granular update (for performance)?
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
      -- NOTE: This shows whether line number for the cursor position should be
      -- `CursorLineNr` or `LineNr`
      cache.is_cursorlinenr = cache.cursorline
        and (cache.cursorlineopt:find('number') ~= nil or cache.cursorlineopt:find('both') ~= nil)

      win_cache[win_id] = cache
    end
  end
  au({ 'WinNew', 'WinClosed' }, '*', update_win_cache, 'Update window cache')
  local options = { 'cursorline', 'cursorlineopt', 'foldcolumn', 'number', 'relativenumber', 'signcolumn' }
  au('OptionSet', options, update_win_cache, 'Update window cache')

  local get_from_cache = function(win_id)
    if win_cache[win_id] then return win_cache[win_id] end
    update_win_cache()
    return win_cache[win_id]
  end

  -- TODO: Decide how to allow users to customize this
  local spec = {
    { format = '=lfs', sep = '▏' },
    { ltype = 'virt', lnum = '•' },
    { ltype = 'wrap', lnum = '↳' },
    -- TODO: Decide if somehow automatically adding this is worth it.
    -- Maybe a thick or differently highlighted `sep` at cursor is enough?
    -- { pos = 'cursor', ltype = 'virt', lnum = '%#CursorLineNr#•' },
    -- { pos = 'cursor', ltype = 'wrap', lnum = '%#CursorLineNr#↳' },

    -- TODO: Maybe add `MiniStatuscolumnCursorLineSep`?
    { pos = 'cursor', sep = '%#CursorLineNr#▏' },
    -- Or a thicker default `sep`?
    -- { pos = 'cursor', sep = '▍' },

    { win = 'inactive', pos = 'above', fold = '', lnum = '', sign = '' },
    { win = 'inactive', pos = 'below', fold = '', lnum = '', sign = '' },
  }
  local content_map = H.make_content_map(spec)

  local make = function(win)
    return function()
      _G.n_statuscolumn = _G.n_statuscolumn + 1
      local cache = get_from_cache(get_cur_win())
      if cache.is_empty then return '' end
      local pos = vim.v.relnum == 0 and 'cursor' or (vim.v.lnum < win_get_cursor(0)[1] and 'above' or 'below')
      local ltype = vim.v.virtnum == 0 and 'text' or (vim.v.virtnum < 0 and 'virt' or 'wrap')
      local res = content_map[win][pos][ltype].content[cache.relativenumber][cache.cursorline][cache.is_cursorlinenr]
      return res
    end
  end

  MiniStatuscolumn.active = make('active')
  MiniStatuscolumn.inactive = make('inactive')
end

H.validate_content_spec = function(x)
  H.check_array_of('spec', x, 'table')
  for i, h in ipairs(x) do
    local item = string.format('spec[%d]', i)
    if item.win ~= nil then H.check_one_of(item .. '.win', h.win, { 'active', 'inactive' }) end
    if item.pos ~= nil then H.check_one_of(item .. '.pos', h.pos, { 'above', 'cursor', 'below' }) end
    if item.ltype ~= nil then H.check_one_of(item .. '.ltype', h.ltype, { 'text', 'virt', 'wrap' }) end

    H.check_type(item .. '.format', h.format, 'string', true)
    if item.format ~= nil and item.format:find('[^=lfs]') ~= nil then
      H.error('`' .. item .. '`.format should contain only `=fls` characters')
    end
    H.check_type(item .. '.fold', h.fold, 'string', true)
    H.check_type(item .. '.lnum', h.lnum, 'string', true)
    H.check_type(item .. '.sign', h.sign, 'string', true)
    H.check_type(item .. '.sep', h.sep, 'string', true)

    local at_least_one_info = x.format or x.fold or x.lnum or x.sign or x.sep
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
  for _, win_map in pairs(map) do
    for _, pos_map in pairs(win_map) do
      for _, ltype_map in pairs(pos_map) do
        ltype_map.content = H.construct_content_string(ltype_map)
      end
    end
  end

  return map
end

H.construct_content_string = function(spec)
  local single = function(rnu, cul, is_culnr)
    local repl = { ['='] = '%=' }

    -- TODO: Now `CursorLineFold` needs `is_culnr`, but that is not documented
    local hl_fold = (spec.pos == 'cursor' and cul) and '%#CursorLineFold#' or '%#FoldColumn#'
    -- if spec.fold:find('%%') ~= nil then hl_fold = '' end

    local hl_lnum = '%#LineNr#'
    if spec.pos == 'above' and rnu then hl_lnum = '%#LineNrAbove#' end
    if spec.pos == 'below' and rnu then hl_lnum = '%#LineNrBelow#' end
    if spec.pos == 'cursor' and is_culnr then hl_lnum = '%#CursorLineNr#' end
    -- if spec.lnum:find('%%') ~= nil then hl_lnum = '' end

    -- TODO: Now `CursorLineSign` needs `is_culnr`, but that is not documented
    local hl_sign = (spec.pos == 'cursor' and cul) and '%#CursorLineSign#' or '%#SignColumn#'
    -- if spec.sign:find('%%') ~= nil then hl_sign = '' end

    -- !!!TODO!!! Explicitly added highlight groups override extra highlighting
    -- from %l/%C/%s. Like from `{number,sign}_hl_group` in extmarks.
    -- The explicit highlighting here is added only for a "clean" solution of
    -- fixed character section (like `lnum='•'` for virtual lines) not having
    -- the same highlighting as if it was `%l` for the "real" text line.
    -- **However**, it only looks like a problem for `CusrorLine{Nr,Fold,Sign}`
    -- cases. `LineNr`/`LineNrAbove`/`LineNrBelow` and extmark highlighting
    -- seem to work okay (at least for the firxed `lnum` case).
    --
    -- Maybe it is a better idea to just drop this extra forcing and suggest
    -- to manually use specs like
    -- `{ pos = 'cursor', ltype = 'virt', lnum = '%#CursorLineNr#•' }`?
    -- The downside is no cool highlighting of `•` and `↳` at cursor, but in
    -- return this simplifies code a lot while thick-ish `sep` serves the same
    -- purpose.

    hl_fold, hl_lnum, hl_sign = '', '', ''
    repl.f = spec.fold == '' and '' or (hl_fold .. spec.fold)
    repl.l = spec.lnum == '' and '' or (hl_lnum .. spec.lnum)
    repl.s = spec.sign == '' and '' or (hl_sign .. spec.sign)

    local format = vim.split(spec.format, '')
    for i = 1, #format do
      format[i] = repl[format[i]] or format[i]
    end

    -- TODO: Add mouse click support
    local sep = spec.sep == '' and '' or ('%#MiniStatuscolumnSep#' .. spec.sep)
    return table.concat(format, '') .. sep
  end

  -- Nested key values are relativenumber-cursorline-is_cursorlinenr
  return {
    [false] = {
      [false] = { [false] = single(false, false, false), [true] = single(false, false, true) },
      [true] = { [false] = single(false, true, false), [true] = single(false, true, true) },
    },
    [true] = {
      [false] = { [false] = single(true, false, false), [true] = single(true, false, true) },
      [true] = { [false] = single(true, true, false), [true] = single(true, true, true) },
    },
  }
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

return MiniStatuscolumn
