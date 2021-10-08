-- MIT License Copyright (c) 2021 Evgeni Chasnovski
--
-- Custom *minimal* and *fast* statusline module with opinionated look. Special
-- features: change color depending on current mode and compact version of
-- sections activated when window width is small enough. Inspired by:
-- https://elianiva.me/post/neovim-lua-statusline (blogpost)
-- https://github.com/elianiva/dotfiles/blob/master/nvim/.config/nvim/lua/modules/_statusline.lua (Github)
--
-- To activate, put this file somewhere into 'lua' folder and call module's
-- `setup()`. For example, put as 'lua/mini/statusline.lua' and execute
-- `require('mini.statusline').setup()` Lua code. It may have `config` argument
-- which should be a table overwriting default values using same structure.
--
-- Default `config`:
-- {
--   -- Content of statusline as functions which return statusline string. See `:h
--   -- statusline` and code of default contents (used when `nil` is supplied).
--   content = {
--     -- Content for active window
--     active = nil,
--     -- Content for inactive window(s)
--     inactive = nil,
--   },
--
--   -- Whether to set Vim's settings for statusline (make it always shown)
--   set_vim_settings = true,
-- }
--
-- Defined highlight groups:
-- - Highlighting depending on mode:
--     - MiniStatuslineModeNormal - normal mode
--     - MiniStatuslineModeInsert - insert mode
--     - MiniStatuslineModeVisual - visual mode
--     - MiniStatuslineModeReplace - replace mode
--     - MiniStatuslineModeCommand - command mode
--     - MiniStatuslineModeOther - other mode (like terminal, etc.)
-- - MiniStatuslineDevinfo - highlighting of "dev info" section
-- - MiniStatuslineFilename - highliting of "file name" section
-- - MiniStatuslineFileinfo - highliting of "file info" section
-- - MiniStatuslineInactive - highliting in not focused window
--
-- Features:
-- - Built-in active mode indicator with colors.
-- - Sections hide information when window is too narrow (specific width is
--   configurable per section).
-- - Define own custom statusline structure by overwriting (even after calling
--   `setup()`) `MiniStatusline.active()` or `MiniStatusline.inactive()`. Code
--   should be similar to default method with rough structure:
--     - Compute string data for every section you want to display.
--     - Combine them in groups with `MiniStatusline.combine_groups()`. Each
--       group has own highlighting. Strings within group are separated by one
--       space. Groups are separated by two spaces (one for each highlighting).
--
-- Suggested dependencies (provide extra functionality, statusline will work
-- without them):
-- - Nerd font (to support extra icons).
-- - Plugin 'lewis6991/gitsigns.nvim' for Git information. If missing, '-' will
--   be shown.
-- - Plugin 'kyazdani42/nvim-web-devicons' or 'ryanoasis/vim-devicons' for
--   filetype icons. If missing, no icons will be used.
--
-- Notes about structure:
-- - Main statusline object is `MiniStatusline`. It has two different "states":
--   active and inactive.
-- - In active mode `MiniStatusline.active()` is called. Its code defines
--   high-level structure of statusline. From there go to respective section
--   functions. Override it to create custom statusline layout.
--
-- Note about performance:
-- - Currently statusline gets evaluated on every call inside a timer (see
--   https://github.com/neovim/neovim/issues/14303). In current setup this
--   means that update is made periodically in insert mode due to
--   'completion-nvim' plugin and its `g:completion_timer_cycle` setting.
-- - MiniStatusline might get evaluated on every 'CursorHold' event (indicator
--   is an update happening in `&updatetime` time after cursor stopped; set
--   different `&updatetime` to verify that is a reason). In current setup this
--   is happening due to following reasons:
--     - Plugin 'vim-polyglot' has 'polyglot-sensible' autogroup which checks
--     on 'CursorHold' events if file was updated (see `:h checktime`).
--   As these actions are useful, one can only live with the fact that
--   'statusline' option gets reevaluated on 'CursorHold'.

-- Possible Lua dependencies
local has_devicons, devicons = pcall(require, 'nvim-web-devicons')

-- Module and its helper
local MiniStatusline = {}
local H = {}

-- Module setup
function MiniStatusline.setup(config)
  -- Export module
  _G.MiniStatusline = MiniStatusline

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Module behavior
  vim.api.nvim_exec(
    [[augroup MiniStatusline
        au!
        au WinEnter,BufEnter * setlocal statusline=%!v:lua.MiniStatusline.active()
        au WinLeave,BufLeave * setlocal statusline=%!v:lua.MiniStatusline.inactive()
      augroup END]],
    false
  )

  -- Create highlighting
  vim.api.nvim_exec(
    [[hi link MiniStatuslineModeNormal  Cursor
      hi link MiniStatuslineModeInsert  DiffChange
      hi link MiniStatuslineModeVisual  DiffAdd
      hi link MiniStatuslineModeReplace DiffDelete
      hi link MiniStatuslineModeCommand DiffText
      hi link MiniStatuslineModeOther   IncSearch

      hi link MiniStatuslineDevinfo  StatusLine
      hi link MiniStatuslineFilename StatusLineNC
      hi link MiniStatuslineFileinfo StatusLine
      hi link MiniStatuslineInactive StatusLineNC]],
    false
  )
end

-- Module config
MiniStatusline.config = {
  -- Content of statusline as functions which return statusline string. See `:h
  -- statusline` and code of default contents (used when `nil` is supplied).
  content = {
    -- Content for active window
    active = nil,
    -- Content for inactive window(s)
    inactive = nil,
  },

  -- Whether to set Vim's settings for statusline
  set_vim_settings = true,
}

-- Module functionality
function MiniStatusline.active()
  return (MiniStatusline.config.content.active or H.default_content_active)()
end

function MiniStatusline.inactive()
  return (MiniStatusline.config.content.inactive or H.default_content_inactive)()
end

function MiniStatusline.combine_groups(groups)
  local t = vim.tbl_map(function(s)
    if not s then
      return ''
    end
    if type(s) == 'string' then
      return s
    end
    local t = vim.tbl_filter(function(x)
      return not (x == nil or x == '')
    end, s.strings)
    -- Return highlighting group to allow inheritance from later sections
    if vim.tbl_count(t) == 0 then
      return s.hl or ''
    end
    return string.format('%s %s ', s.hl or '', table.concat(t, ' '))
  end, groups)
  return table.concat(t, '')
end

-- Statusline sections. Should return output text without whitespace on sides
-- or empty string to omit section.
---- Mode
---- Custom `^V` and `^S` symbols to make this file appropriate for copy-paste
---- (otherwise those symbols are not displayed).
local CTRL_S = vim.api.nvim_replace_termcodes('<C-S>', true, true, true)
local CTRL_V = vim.api.nvim_replace_termcodes('<C-V>', true, true, true)

-- stylua: ignore start
MiniStatusline.modes = setmetatable({
  ['n']    = { long = 'Normal',   short = 'N',   hl = '%#MiniStatuslineModeNormal#' },
  ['v']    = { long = 'Visual',   short = 'V',   hl = '%#MiniStatuslineModeVisual#' },
  ['V']    = { long = 'V-Line',   short = 'V-L', hl = '%#MiniStatuslineModeVisual#' },
  [CTRL_V] = { long = 'V-Block',  short = 'V-B', hl = '%#MiniStatuslineModeVisual#' },
  ['s']    = { long = 'Select',   short = 'S',   hl = '%#MiniStatuslineModeVisual#' },
  ['S']    = { long = 'S-Line',   short = 'S-L', hl = '%#MiniStatuslineModeVisual#' },
  [CTRL_S] = { long = 'S-Block',  short = 'S-B', hl = '%#MiniStatuslineModeVisual#' },
  ['i']    = { long = 'Insert',   short = 'I',   hl = '%#MiniStatuslineModeInsert#' },
  ['R']    = { long = 'Replace',  short = 'R',   hl = '%#MiniStatuslineModeReplace#' },
  ['c']    = { long = 'Command',  short = 'C',   hl = '%#MiniStatuslineModeCommand#' },
  ['r']    = { long = 'Prompt',   short = 'P',   hl = '%#MiniStatuslineModeOther#' },
  ['!']    = { long = 'Shell',    short = 'Sh',  hl = '%#MiniStatuslineModeOther#' },
  ['t']    = { long = 'Terminal', short = 'T',   hl = '%#MiniStatuslineModeOther#' },
}, {
  -- By default return 'Unknown' but this shouldn't be needed
  __index = function()
    return   { long = 'Unknown',  short = 'U',   hl = '%#MiniStatuslineModeOther#' }
  end,
})
-- stylua: ignore end

function MiniStatusline.section_mode(args)
  local mode_info = MiniStatusline.modes[vim.fn.mode()]

  local mode = H.is_truncated(args.trunc_width) and mode_info.short or mode_info.long

  return mode, mode_info.hl
end

---- Spell
function MiniStatusline.section_spell(args)
  if not vim.wo.spell then
    return ''
  end

  if H.is_truncated(args.trunc_width) then
    return 'SP'
  end

  return string.format('SPELL(%s)', vim.bo.spelllang)
end

---- Wrap
function MiniStatusline.section_wrap(args)
  if not vim.wo.wrap then
    return ''
  end

  if H.is_truncated(args.trunc_width) then
    return 'WR'
  end

  return 'WRAP'
end

---- Git
function MiniStatusline.section_git(args)
  if H.isnt_normal_buffer() then
    return ''
  end

  local head = vim.b.gitsigns_head or '-'
  local signs = H.is_truncated(args.trunc_width) and '' or (vim.b.gitsigns_status or '')

  if signs == '' then
    if head == '-' then
      return ''
    end
    return string.format(' %s', head)
  end
  return string.format(' %s %s', head, signs)
end

---- Diagnostics
function MiniStatusline.section_diagnostics(args)
  -- Assumption: there are no attached clients if table
  -- `vim.lsp.buf_get_clients()` is empty
  local hasnt_attached_client = next(vim.lsp.buf_get_clients()) == nil
  local dont_show_lsp = H.is_truncated(args.trunc_width) or H.isnt_normal_buffer() or hasnt_attached_client
  if dont_show_lsp then
    return ''
  end

  -- Construct diagnostic info using predefined order
  local t = {}
  for _, level in ipairs(H.diagnostic_levels) do
    local n = vim.lsp.diagnostic.get_count(0, level.name)
    -- Add level info only if diagnostic is present
    if n > 0 then
      table.insert(t, string.format(' %s%s', level.sign, n))
    end
  end

  if vim.tbl_count(t) == 0 then
    return 'ﯭ  -'
  end
  return string.format('ﯭ %s', table.concat(t, ''))
end

---- File name
function MiniStatusline.section_filename(args)
  -- In terminal always use plain name
  if vim.bo.buftype == 'terminal' then
    return '%t'
  elseif H.is_truncated(args.trunc_width) then
    -- File name with 'truncate', 'modified', 'readonly' flags
    -- Use relative path if truncated
    return '%f%m%r'
  else
    -- Use fullpath if not truncated
    return '%F%m%r'
  end
end

---- File information
function MiniStatusline.section_fileinfo(args)
  local filetype = vim.bo.filetype

  -- Don't show anything if can't detect file type or not inside a "normal
  -- buffer"
  if (filetype == '') or H.isnt_normal_buffer() then
    return ''
  end

  -- Add filetype icon
  local icon = H.get_filetype_icon()
  if icon ~= '' then
    filetype = string.format('%s %s', icon, filetype)
  end

  -- Construct output string if truncated
  if H.is_truncated(args.trunc_width) then
    return filetype
  end

  -- Construct output string with extra file info
  local encoding = vim.bo.fileencoding or vim.bo.encoding
  local format = vim.bo.fileformat
  local size = H.get_filesize()

  return string.format('%s %s[%s] %s', filetype, encoding, format, size)
end

---- Location inside buffer
function MiniStatusline.section_location(args)
  -- Use virtual column number to allow update when paste last column
  if H.is_truncated(args.trunc_width) then
    return '%l│%2v'
  end

  return '%l|%L│%2v|%-2{col("$") - 1}'
end

-- Helpers
---- Module default config
H.default_config = MiniStatusline.config

function H.default_content_active()
  -- stylua: ignore start
  local mode, mode_hl = MiniStatusline.section_mode({ trunc_width = 120 })
  local spell         = MiniStatusline.section_spell({ trunc_width = 120 })
  local wrap          = MiniStatusline.section_wrap({ trunc_width = 120 })
  local git           = MiniStatusline.section_git({ trunc_width = 75 })
  local diagnostics   = MiniStatusline.section_diagnostics({ trunc_width = 75 })
  local filename      = MiniStatusline.section_filename({ trunc_width = 140 })
  local fileinfo      = MiniStatusline.section_fileinfo({ trunc_width = 120 })
  local location      = MiniStatusline.section_location({ trunc_width = 75 })

  -- Usage of `MiniStatusline.combine_groups()` ensures highlighting and
  -- correct padding with spaces between groups (accounts for 'missing'
  -- sections, etc.)
  return MiniStatusline.combine_groups({
    { hl = mode_hl,                     strings = { mode, spell, wrap } },
    { hl = '%#MiniStatuslineDevinfo#',  strings = { git, diagnostics } },
    '%<', -- Mark general truncate point
    { hl = '%#MiniStatuslineFilename#', strings = { filename } },
    '%=', -- End left alignment
    { hl = '%#MiniStatuslineFileinfo#', strings = { fileinfo } },
    { hl = mode_hl,                     strings = { location } },
  })
  -- stylua: ignore end
end

function H.default_content_inactive()
  return '%#MiniStatuslineInactive#%F%='
end

---- Settings
function H.setup_config(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    content = { config.content, 'table' },
    ['content.active'] = { config.content.active, 'function', true },
    ['content.inactive'] = { config.content.inactive, 'function', true },

    set_vim_settings = { config.set_vim_settings, 'boolean' },
  })

  return config
end

function H.apply_config(config)
  MiniStatusline.config = config

  -- Set settings to ensure statusline is displayed properly
  if config.set_vim_settings then
    vim.o.laststatus = 2 -- Always show statusline
  end
end

---- Various helpers
function H.is_truncated(width)
  return vim.api.nvim_win_get_width(0) < width
end

function H.isnt_normal_buffer()
  -- For more information see ":h buftype"
  return vim.bo.buftype ~= ''
end

H.diagnostic_levels = {
  { name = 'Error', sign = 'E' },
  { name = 'Warning', sign = 'W' },
  { name = 'Information', sign = 'I' },
  { name = 'Hint', sign = 'H' },
}

function H.get_filesize()
  local size = vim.fn.getfsize(vim.fn.getreg('%'))
  if size < 1024 then
    return string.format('%dB', size)
  elseif size < 1048576 then
    return string.format('%.2fKiB', size / 1024)
  else
    return string.format('%.2fMiB', size / 1048576)
  end
end

function H.get_filetype_icon()
  -- By default use 'nvim-web-devicons', fallback to 'vim-devicons'
  if has_devicons then
    local file_name, file_ext = vim.fn.expand('%:t'), vim.fn.expand('%:e')
    return devicons.get_icon(file_name, file_ext, { default = true })
  elseif vim.fn.exists('*WebDevIconsGetFileTypeSymbol') ~= 0 then
    return vim.fn.WebDevIconsGetFileTypeSymbol()
  end

  return ''
end

return MiniStatusline
