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
--- - `MiniStatuscolumnDim` - dimmed column. By default is a dimmed |hl-LineNr|.
--- - `MiniStatuscolumnDimCursor` - dimmed column at cursor line.
--- - `MiniStatuscolumnSep` - column and text separator.
--- - `MiniStatuscolumnSepCursor` - column and text separator at cursor line.
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
---@text # Dim inactive windows ~
--- Notes:
--- - Enabling works best with appropriately "dimming" `MiniStatuscolumnDim`
---   and statuscolumn for inactive window being the same as for active.
MiniStatuscolumn.config = {
  content = {
    active = nil,
    inactive = nil,
  },

  -- Whether to dim column text in inactive windows
  dim_inactive = true,
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
--- Notes:
--- - `MiniStatuscolumnSepCursor` is used under the same conditions as described
---   in |hl-CursorLineNr|.
---
--- Examples:
---
--- - Specification for default `content` in |MiniStatuscolumn.config|.
---   Use as a template to adjust/remove added behavior: >lua
---
---   local statuscolumn = require('mini.statuscolumn')
---   local spec = {
---     -- Prefer visible separator with a more efficient order to use
---     -- usually present whitespace to the right of signs
---     { format = '=lfs', sep = '▏' },
---     -- Use custom symbol for virtual lines
---     { ltype = 'virt', lnum = '•' },
---     -- Use custom symbol for wrapped lines
---     { ltype = 'wrap', lnum = '↳' },
---     -- Hide separator to better indicate inactive windows
---     { win = 'inactive', sep = ' ' },
---   }
---   statuscolumn.setup({ content = statuscolumn.gen_content.main(spec) })
--- <
--- - Ways to configure separator:
---
---   - Thicker separator at cursor: `{ pos = 'cursor', sep = '▍' }`.
---
---   - More cell-centered separator: `{ format='=fsl', sep='│' }`
---
--- - Ways to indicate inactive windows:
---
---   - Hide regular non-cursor line: set `MiniStatuscolumnDim` and
---     `MiniStatuscolumnDimCursor` highlight groups to have the same
---     foreground and background.
---
---   - Hide all non-cursor lines: `{ win='inactive', fold='', lnum='', sign='' }`
---
---   - Hide separator: `{ win='inactive', sep='' }`
---
--- - Force highlighting: `{ pos='cursor', ltype='virt', lnum='%#CursorLineNr#•' }`.
---   Has problems that it overrides highlighting from extmarks.
---
---@param spec table[] Specification array.
---@param opts table|nil Options. Possible fields:
---   - <click> `(function)` - action to perform on mouse click in statuscolumn.
---     Will be called with ... TODO:
---     Notes:
---    - It is only possible to split statuscolumn line into "clicking ranges"
---      once per window, including their `minwid` first argument.
---      This is why clicking data only contains data about section and not
---      about line type (text, virt, wrap).
---    - A common (somewhat limiting) pattern to identify what was clicked is
---      to use |screenstring()| with <screenrow> and <screencol> fields of
---      <mousepos>. For example, if wrapped and virtual lines are identified
---      by known symbols, it helps identifying clicking on those cases.
MiniStatuscolumn.gen_content.main = function(spec, opts)
  H.validate_content_spec(spec)
  opts = vim.tbl_extend('force', { click = MiniStatuscolumn.default_click }, opts or {})
  H.check_type('opts.click', opts.click, 'function')

  -- Create content
  local content_map = H.make_content_map(spec, opts.click)

  -- TODO: Remove after doing benchmarks
  _G.n_statuscolumn = 0
  local win_get_cursor = vim.api.nvim_win_get_cursor
  local needs_redraw = {}
  local make = function(win)
    return function(win_data)
      _G.n_statuscolumn = _G.n_statuscolumn + 1

      if win_data.is_empty then return '' end
      local pos = vim.v.relnum == 0 and 'cursor' or (vim.v.lnum < win_get_cursor(0)[1] and 'above' or 'below')
      local ltype = vim.v.virtnum == 0 and 'text' or (vim.v.virtnum < 0 and 'virt' or 'wrap')
      -- Force redraw with cursor on virtual line or manually added cursor sep
      -- highlighting will "stay" there when cursor is moved. It is because
      -- 'statuscolumn' content is not recomputed on cursor move.
      needs_redraw[win_data.win_id] = needs_redraw[win_data.win_id]
        or (win == 'active' and pos == 'cursor' and ltype == 'virt')
      -- Condition on `is_cursorlinenr` for a proper separator hl
      return content_map[win][pos][ltype].content[win_data.is_cursorlinenr]
    end
  end

  -- Fore redraw when needed. Do not do it on every cursor move as it results
  -- into flickering (like with 'mini.cursorword' highlighting word twice)
  local gr = vim.api.nvim_create_augroup('MiniStatuscolumnMain', {})
  local get_current_win, nvim__redraw = vim.api.nvim_get_current_win, vim.api.nvim__redraw
  local redraw_stc = function()
    if not needs_redraw[get_current_win()] then return end
    nvim__redraw({ win = get_current_win(), statuscolumn = true })
    needs_redraw[get_current_win()] = false
  end
  local au_opts = { group = gr, callback = redraw_stc, desc = 'Ensure redraw' }
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, au_opts)

  return { active = make('active'), inactive = make('inactive') }
end

--- Default mouse click handler
MiniStatuscolumn.default_click = function(data)
  local mousepos = data.mousepos
  local ok = pcall(vim.api.nvim_set_current_win, mousepos.winid)
  if not ok then return end
  ok = pcall(vim.api.nvim_win_set_cursor, mousepos.winid, { mousepos.line, mousepos.column - 1 })
  if not ok then return end

  if data.n_clicks == 2 then vim.cmd('normal! zz') end

  -- TODO: Maybe act differently on folds (open/close), etc.
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

  H.check_type('config.dim_inactive', config.dim_inactive, 'boolean')

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
      { win = 'inactive', sep = ' ' },
    }
    content = MiniStatuscolumn.gen_content.main(default_spec)
  end

  -- Make and set statuscolumn
  H.make_statuscolumn_functions(content.active or content.inactive, content.inactive or content.active)
  vim.o.statuscolumn =
    '%{%nvim_get_current_win()==#g:actual_curwin ? v:lua.MiniStatuscolumn.active() : v:lua.MiniStatuscolumn.inactive()%}'
end

H.create_autocommands = function(config)
  local gr = vim.api.nvim_create_augroup('MiniStatuscolumn', {})
  vim.api.nvim_create_autocmd('ColorScheme', { group = gr, callback = H.create_default_hl, desc = 'Ensure colors' })

  if config.dim_inactive then H.make_dim_inactive() end
end

H.create_default_hl = function()
  local hi = function(name, opts)
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end

  -- Make sure that `MiniStatuscolumnDim` is dimming out of the box
  local linenr = vim.api.nvim_get_hl(0, { name = 'LineNr', link = false })
  local normal = vim.api.nvim_get_hl(0, { name = 'Normal', link = false })
  local fg, bg = linenr.fg or normal.fg, linenr.bg or normal.bg
  if type(fg) == 'number' and type(bg) == 'number' then
    local fg_b, bg_b = math.fmod(fg, 256), math.fmod(bg, 256)
    local fg_g, bg_g = math.fmod((fg - fg_b) / 256, 256), math.fmod((bg - bg_b) / 256, 256)
    local fg_r, bg_r = math.floor(fg / 65536), math.floor(bg / 65536)

    local bl = 0.382
    local bl_b = string.format('%02x', math.floor((bl * fg_b + (1 - bl) * bg_b)))
    local bl_g = string.format('%02x', math.floor((bl * fg_g + (1 - bl) * bg_g)))
    local bl_r = string.format('%02x', math.floor((bl * fg_r + (1 - bl) * bg_r)))
    hi('MiniStatuscolumnDim', { fg = '#' .. bl_r .. bl_g .. bl_b, bg = bg })
  else
    hi('MiniStatuscolumnDim', { link = 'LineNr' })
  end

  hi('MiniStatuscolumnDimCursor', { link = 'MiniStatuscolumnDim' })
  hi('MiniStatuscolumnSep', { link = 'LineNr' })
  hi('MiniStatuscolumnSepCursor', { link = 'CursorLineNr' })
end

-- Autocommands ---------------------------------------------------------------
H.make_dim_inactive = function()
  -- Set automatic inactive highlight
  local inactive_winhl = {
    'CursorLineFold:MiniStatuscolumnDimCursor',
    'CursorLineNr:MiniStatuscolumnDimCursor',
    'CursorLineSign:MiniStatuscolumnDimCursor',
    'FoldColumn:MiniStatuscolumnDim',
    'LineNr:MiniStatuscolumnDim',
    'LineNrAbove:MiniStatuscolumnDim',
    'LineNrBelow:MiniStatuscolumnDim',
    'SignColumn:MiniStatuscolumnDim',

    'MiniStatuscolumnSep:MiniStatuscolumnDim',
    'MiniStatuscolumnSepCursor:MiniStatuscolumnDimCursor',
  }
  local inactive_winhl_str = table.concat(inactive_winhl, ',')
  local inactive_winhl_map = {}
  for _, hl_pair in ipairs(inactive_winhl) do
    inactive_winhl_map[hl_pair] = true
  end

  local not_inactive_winhl = function(hl_pair) return not inactive_winhl_map[hl_pair] end

  local ensure_dimmed = function()
    local cur_win_id = vim.api.nvim_get_current_win()
    -- NOTE: Working with all visible windows instead of precisely per event
    -- is more robust due to window-local options and window events nature
    for _, win_id in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local winhl_split = vim.split(vim.wo[win_id].winhighlight, ',')
      local new_winhl = table.concat(vim.tbl_filter(not_inactive_winhl, winhl_split), ',')
      if win_id ~= cur_win_id then new_winhl = new_winhl .. ((new_winhl == '' and '' or ',') .. inactive_winhl_str) end
      vim.wo[win_id].winhighlight = new_winhl
    end
  end

  local gr = vim.api.nvim_create_augroup('MiniStatuscolumn', { clear = false })

  -- NOTE: The `BufWinEnter` callback is executed with shown buffer is current
  -- (even if it is not). This means that showing that buffer without visibly
  -- changing windows can result in it highlighted as "active", when it is not.
  -- So schedule in hope that this will not result in flickering.
  vim.api.nvim_create_autocmd('WinEnter', { group = gr, callback = ensure_dimmed, desc = 'Ensure dimmed' })
  local ensure_dimmed_scheduled = vim.schedule_wrap(ensure_dimmed)
  vim.api.nvim_create_autocmd('BufWinEnter', { group = gr, callback = ensure_dimmed_scheduled, desc = 'Ensure dimmed' })
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
  au({ 'BufWinEnter', 'WinNew', 'TermOpen' }, '*', update_win_cache, 'Update window cache')
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

H.make_content_map = function(spec, click)
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

  -- Prepare clicking data
  local make_click = function(ltype, section)
    return function(_, n_clicks, button, modifiers)
      -- NOTE: `ltype` has proper values only on Neovim>=0.13
      -- See: https://github.com/neovim/neovim/issues/40210
      local data = { n_clicks = n_clicks, button = button, modifiers = modifiers, section = section, ltype = ltype }
      data.mousepos = vim.fn.getmousepos()
      click(data)
    end
  end

  local with_click = function(ltype, section, section_content)
    if section_content == '' then return '' end
    local click_name = '_click_' .. ltype .. '_' .. section
    MiniStatuscolumn[click_name] = MiniStatuscolumn[click_name] or make_click(ltype, section)

    return string.format('%%@v:lua.MiniStatuscolumn.%s@%s%%T', click_name, section_content)
  end

  -- Compute content for each scope
  local format_repl = { ['='] = '%=' }
  for _, win_map in pairs(map) do
    for pos, pos_map in pairs(win_map) do
      for ltype, ltype_map in pairs(pos_map) do
        format_repl.f = with_click(ltype, 'fold', ltype_map.fold)
        format_repl.l = with_click(ltype, 'lnum', ltype_map.lnum)
        format_repl.s = with_click(ltype, 'sign', ltype_map.sign)
        local content_str = ltype_map.format:gsub('[=fls]', format_repl)

        local content = {}
        -- NOTE: show separator hl based on whether it is configured to show
        -- "CursorLine" highlighting in the column (`:h hl-CursorLineNr`, but
        -- it works for fold and sign: https://github.com/vim/vim/issues/20480)
        -- It also helps with drawing issues, since statuscolumn is not redrawn
        -- on cursor movement with 'nocursorline', which makes cursor separator
        -- not update also.
        for _, show_cur in ipairs({ false, true }) do
          local sep_hl = (pos == 'cursor' and show_cur) and '%#MiniStatuscolumnSepCursor#' or '%#MiniStatuscolumnSep#'
          local sep = ltype_map.sep == '' and '' or (sep_hl .. ltype_map.sep)
          content[show_cur] = content_str .. with_click(ltype, 'sep', sep)
        end
        ltype_map.content = content
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
