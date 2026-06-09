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
  local eval_stl = vim.api.nvim_eval_statusline

  -- Set up window cache
  local win_cache = {}

  local gr = vim.api.nvim_create_augroup('MiniStatuscolumnWinCache', {})
  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = gr, pattern = pattern, callback = callback, desc = desc })
  end

  local update_win_cache = function()
    win_cache = {}
    for _, win_id in ipairs(vim.api.nvim_list_wins()) do
      win_cache[win_id] = {
        win_id = win_id,
        buf_id = vim.api.nvim_win_get_buf(win_id),
        foldcolumn = vim.wo[win_id].foldcolumn,
        number = vim.wo[win_id].number,
        relativenumber = vim.wo[win_id].relativenumber,
        signcolumn = vim.wo[win_id].signcolumn,
        is_empty = eval_stl('%l%C%s', { winid = win_id, use_statuscol_lnum = 1 }).str == '',
      }
    end
  end
  au({ 'WinNew', 'WinClosed' }, '*', update_win_cache, 'Update window cache')
  au('OptionSet', { 'foldcolumn', 'number', 'relativenumber', 'signcolumn' }, update_win_cache, 'Update window cache')

  local get_from_cache = function(win_id)
    if win_cache[win_id] then return win_cache[win_id] end
    update_win_cache()
    return win_cache[win_id]
  end

  -- TODO: Figure out a better way to customize it with just enough flexibility
  -- Use cases:
  -- - Easily customize `format` once and maybe selectively adjust it for
  --   certain combinations.
  -- - Special symbols for `virt` and `wrap` should be highlighted as
  --   approriately to position and section. Like `CursorLineNr` / `CursorLineSign`
  --   or `LineNrAbove`. This probably requires adding extra `fold`, `lnum`, `sign`
  --   fields and have `format` be more limited. Like "contains only `=lfsS`
  --   (align, line number, fold, sign, separator) and whitespace".
  --
  -- An idea is to
  -- - Allow partial entries which are populated via a cross product of missing
  --   "scope" fields. But not defaults for "info" fields (as it makes it
  --   a hassle to "override" for narrow scopes).
  -- - Have the normalization of an array in some form. Like "later overrides
  --   previous ones with the same 'scope' fields".
  -- - The result is 18 (2 for `win` times 3 for `pos` times 3 for `ltype`) specs
  --   each defining `format`, `fold`, `lnum`, `sign`, `sep`. Missing fields are
  --   inferred from defaults.
  --
  -- For example, the following should be noremalized to the below default:
  -- ```
  -- {
  --   { format = '=lfsS' },
  --   { ltype = 'virt', lnum = '•' },
  --   { ltype = 'wrap', lnum = '↳' },
  --   { pos = 'cursor', sep = '▎' },
  --   { win = 'inactive', pos = 'above', fold = '', lnum = '', sign = '' },
  --   { win = 'inactive', pos = 'below', fold = '', lnum = '', sign = '' },
  -- }
  -- ```

  --stylua: ignore
  local sections = {
    { win = 'active',   pos = 'above',  ltype = 'text', format = '=lCs', sep = '▏' },
    { win = 'active',   pos = 'above',  ltype = 'virt', format = '=•Cs', sep = '▏' },
    { win = 'active',   pos = 'above',  ltype = 'wrap', format = '=↳Cs', sep = '▏' },

    { win = 'active',   pos = 'cursor', ltype = 'text', format = '=lCs', sep = '▎' },
    { win = 'active',   pos = 'cursor', ltype = 'virt', format = '=•Cs', sep = '▎' },
    { win = 'active',   pos = 'cursor', ltype = 'wrap', format = '=↳Cs', sep = '▎' },

    { win = 'active',   pos = 'below',  ltype = 'text', format = '=lCs', sep = '▏' },
    { win = 'active',   pos = 'below',  ltype = 'virt', format = '=•Cs', sep = '▏' },
    { win = 'active',   pos = 'below',  ltype = 'wrap', format = '=↳Cs', sep = '▏' },

    { win = 'inactive', pos = 'above',  ltype = 'text', format = '=',    sep = '▏' },
    { win = 'inactive', pos = 'above',  ltype = 'virt', format = '=',    sep = '▏' },
    { win = 'inactive', pos = 'above',  ltype = 'wrap', format = '=',    sep = '▏' },

    { win = 'inactive', pos = 'cursor', ltype = 'text', format = '=lCs', sep = '▎' },
    { win = 'inactive', pos = 'cursor', ltype = 'virt', format = '=•Cs', sep = '▎' },
    { win = 'inactive', pos = 'cursor', ltype = 'wrap', format = '=↳Cs', sep = '▎' },

    { win = 'inactive', pos = 'below',  ltype = 'text', format = '=',    sep = '▏' },
    { win = 'inactive', pos = 'below',  ltype = 'virt', format = '=',    sep = '▏' },
    { win = 'inactive', pos = 'below',  ltype = 'wrap', format = '=',    sep = '▏' },
  }

  local stc_map = {
    active = { above = {}, cursor = {}, below = {} },
    inactive = { above = {}, cursor = {}, below = {} },
  }
  for _, s in ipairs(sections) do
    local value = s.format:gsub('([=lCs])', '%%%1') .. '%#MiniStatuscolumnSep#' .. s.sep
    stc_map[s.win][s.pos][s.ltype] = value
  end

  local make = function(win)
    return function()
      local cache = get_from_cache(get_cur_win())
      if cache.is_empty then return '' end
      local pos = vim.v.relnum == 0 and 'cursor' or (vim.v.relnum < 0 and 'above' or 'below')
      local ltype = vim.v.virtnum == 0 and 'text' or (vim.v.virtnum < 0 and 'virt' or 'wrap')
      return stc_map[win][pos][ltype]
    end
  end

  MiniStatuscolumn.active = make('active')
  MiniStatuscolumn.inactive = make('inactive')
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
