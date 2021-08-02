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
--   -- Whether to set Vim's settings for statusline (make it always shown)
--   set_vim_settings = true
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
-- - Built-in `active`
--
-- Suggested dependencies (provide extra functionality, statusline will work
-- without them):
-- - Nerd font (to support extra icons).
-- - Plugin 'airblade/vim-gitgutter' for Git signs. If missing, no git signs
--   will be shown.
-- - Plugin 'tpope/vim-fugitive' for Git branch. If missing, '<no fugitive>'
--   will be displayed instead of a branch.
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
--     - Plugin 'vim-gitgutter' processes buffer on 'CursorHold' events.
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
  vim.api.nvim_exec([[
    augroup MiniStatusline
      au!
      au WinEnter,BufEnter * setlocal statusline=%!v:lua.MiniStatusline.active()
      au WinLeave,BufLeave * setlocal statusline=%!v:lua.MiniStatusline.inactive()
    augroup END
  ]], false)

  -- Update git branch on every buffer enter and after Neovim gained focus
  -- (detect outside change).  Also update git branch before leaving command
  -- line (detect fugitive change). Defer update to actually make it **after**
  -- leaving command line.  Otherwise this will be evaluated too soon and give
  -- "previous" branch.
  vim.api.nvim_exec([[
    augroup MiniStatusline
      au BufEnter,FocusGained * lua MiniStatusline.update_git_branch({defer = false})
      au CmdlineLeave         * lua MiniStatusline.update_git_branch({defer = true})
    augroup END
  ]], false)

  -- Update git signs on every buffer enter (detect signs for buffer) and every
  -- time 'gitgutter' says that change occured
  vim.api.nvim_exec([[
    augroup MiniStatusline
      au BufEnter *         lua MiniStatusline.update_git_signs()
      au User     GitGutter lua MiniStatusline.update_git_signs()
    augroup END
  ]], false)

  -- Create highlighting
  vim.api.nvim_exec([[
    hi link MiniStatuslineModeNormal  Cursor
    hi link MiniStatuslineModeInsert  DiffChange
    hi link MiniStatuslineModeVisual  DiffAdd
    hi link MiniStatuslineModeReplace DiffDelete
    hi link MiniStatuslineModeCommand DiffText
    hi link MiniStatuslineModeOther   IncSearch

    hi link MiniStatuslineDevinfo  StatusLine
    hi link MiniStatuslineFilename StatusLineNC
    hi link MiniStatuslineFileinfo StatusLine
    hi link MiniStatuslineInactive StatusLineNC
  ]], false)
end

-- Module settings
-- Whether to set Vim's settings for statusline
MiniStatusline.set_vim_settings = true

-- Module functionality
function MiniStatusline.active()
  local mode_info = MiniStatusline.modes[vim.fn.mode()]

  local mode        = MiniStatusline.section_mode{mode_info = mode_info, trunc_width = 120}
  local spell       = MiniStatusline.section_spell{trunc_width = 120}
  local wrap        = MiniStatusline.section_wrap{}
  local git         = MiniStatusline.section_git{trunc_width = 75}
  local diagnostics = MiniStatusline.section_diagnostics{trunc_width = 75}
  local filename    = MiniStatusline.section_filename{trunc_width = 140}
  local fileinfo    = MiniStatusline.section_fileinfo{trunc_width = 120}
  local location    = MiniStatusline.section_location{}

  -- Usage of `H.combine_sections()` ensures correct padding with spaces between
  -- sections (accounts for 'missing' sections, etc.)
  return H.combine_sections({
    {string = mode,        hl = mode_info.hl},
    {string = spell,       hl = nil}, -- Copy highliting from previous section
    {string = wrap,        hl = nil}, -- Copy highliting from previous section
    {string = git,         hl = '%#MiniStatuslineDevinfo#'},
    {string = diagnostics, hl = nil}, -- Copy highliting from previous section
    '%<', -- Mark general truncate point
    {string = filename,    hl = '%#MiniStatuslineFilename#'},
    '%=', -- End left alignment
    {string = fileinfo,    hl = '%#MiniStatuslineFileinfo#'},
    {string = location,    hl = mode_info.hl},
  })
end

function MiniStatusline.inactive()
  return '%#MiniStatuslineInactive#%F%='
end

-- Statusline sections. Should return output text without whitespace on sides
-- or empty string to omit section.
---- Mode
---- Custom `^V` and `^S` symbols to make this file appropriate for copy-paste
---- (otherwise those symbols are not displayed).
local CTRL_S = vim.api.nvim_replace_termcodes('<C-S>', true, true, true)
local CTRL_V = vim.api.nvim_replace_termcodes('<C-V>', true, true, true)

MiniStatusline.modes = setmetatable({
  ['n']    = {long = 'Normal',   short = 'N' ,  hl = '%#MiniStatuslineModeNormal#'};
  ['v']    = {long = 'Visual',   short = 'V' ,  hl = '%#MiniStatuslineModeVisual#'};
  ['V']    = {long = 'V-Line',   short = 'V-L', hl = '%#MiniStatuslineModeVisual#'};
  [CTRL_V] = {long = 'V-Block',  short = 'V-B', hl = '%#MiniStatuslineModeVisual#'};
  ['s']    = {long = 'Select',   short = 'S' ,  hl = '%#MiniStatuslineModeVisual#'};
  ['S']    = {long = 'S-Line',   short = 'S-L', hl = '%#MiniStatuslineModeVisual#'};
  [CTRL_S] = {long = 'S-Block',  short = 'S-B', hl = '%#MiniStatuslineModeVisual#'};
  ['i']    = {long = 'Insert',   short = 'I' ,  hl = '%#MiniStatuslineModeInsert#'};
  ['R']    = {long = 'Replace',  short = 'R' ,  hl = '%#MiniStatuslineModeReplace#'};
  ['c']    = {long = 'Command',  short = 'C' ,  hl = '%#MiniStatuslineModeCommand#'};
  ['r']    = {long = 'Prompt',   short = 'P' ,  hl = '%#MiniStatuslineModeOther#'};
  ['!']    = {long = 'Shell',    short = 'Sh' , hl = '%#MiniStatuslineModeOther#'};
  ['t']    = {long = 'Terminal', short = 'T' ,  hl = '%#MiniStatuslineModeOther#'};
}, {
  -- By default return 'Unknown' but this shouldn't be needed
  __index = function()
    return {long = 'Unknown', short = 'U', hl = '%#MiniStatuslineModeOther#'}
  end
})

function MiniStatusline.section_mode(arg)
  local mode = H.is_truncated(arg.trunc_width) and
    arg.mode_info.short or
    arg.mode_info.long

  return mode
end

---- Spell
function MiniStatusline.section_spell(arg)
  if not vim.wo.spell then return '' end

  if H.is_truncated(arg.trunc_width) then return 'SPELL' end

  return string.format('SPELL(%s)', vim.bo.spelllang)
end

---- Wrap
function MiniStatusline.section_wrap()
  if not vim.wo.wrap then return '' end

  return 'WRAP'
end

---- Git
---- NOTE: Everything is implemented through updating some custom variable to
---- increase performance because certain actions are only done when needed and
---- not on every statusline update. For comparison: if called on every
---- statusline update, total statusline execution time is ~1.1ms; with current
---- approach it drops to ~0.2ms.
------ Git branch
MiniStatusline.git_branch = nil

function MiniStatusline.update_git_branch(arg)
  if vim.fn.exists('*FugitiveHead') == 0 then
    MiniStatusline.git_branch = '<no fugitive>'
    return
  end

  update_fun = function()
    -- Use commit hash truncated to 7 characters in case of detached HEAD
    local branch = vim.fn.FugitiveHead(7)
    if branch == '' then branch = '<no branch>' end

    local old_val = MiniStatusline.git_branch
    MiniStatusline.git_branch = branch
    -- Force statusline redraw if it is not first update (otherwise there is a
    -- flicker at Neovim start) and if new value differs from the current one
    if (old_val ~= nil) and (old_val ~= branch) then
      vim.cmd [[noautocmd redrawstatus]]
    end
  end

  if arg.defer then
    vim.defer_fn(update_fun, 50)
  else
    update_fun()
  end
end

------ Git diff signs
MiniStatusline.git_signs = nil

function MiniStatusline.update_git_signs()
  if vim.fn.exists('*GitGutterGetHunkSummary') == 0 then
    MiniStatusline.git_signs = nil
    return
  end

  local signs = vim.fn.GitGutterGetHunkSummary()
  local res = {}
  if signs[1] > 0 then res[#res + 1] = '+' .. signs[1] end
  if signs[2] > 0 then res[#res + 1] = '~' .. signs[2] end
  if signs[3] > 0 then res[#res + 1] = '-' .. signs[3] end

  local old_val = MiniStatusline.git_signs
  if next(res) == nil then
    MiniStatusline.git_signs = nil
  else
    MiniStatusline.git_signs = table.concat(res, ' ')
  end

  -- Force statusline redraw if it is not first update (otherwise there is a
  -- flicker at Neovim start) and if new value differs from the current one
  if (old_val ~= nil) and (old_val ~= MiniStatusline.git_signs) then
    vim.cmd [[noautocmd redrawstatus]]
  end
end

function MiniStatusline.section_git(arg)
  if H.isnt_normal_buffer() then return '' end

  local res
  if H.is_truncated(arg.trunc_width) then
    res = MiniStatusline.git_branch
  else
    res = table.concat({MiniStatusline.git_branch, MiniStatusline.git_signs}, ' ')
  end

  if (res == nil) or res == '' then res = '-' end

  return string.format(' %s', res)
end

---- Diagnostics
function MiniStatusline.section_diagnostics(arg)
  -- Assumption: there are no attached clients if table
  -- `vim.lsp.buf_get_clients()` is empty
  local hasnt_attached_client = next(vim.lsp.buf_get_clients()) == nil
  local dont_show_lsp = H.is_truncated(arg.trunc_width) or
    H.isnt_normal_buffer() or
    hasnt_attached_client
  if dont_show_lsp then return '' end

  -- Gradual growing of string ensures preferred order
  local result = ''

  for _, level in ipairs(H.diagnostic_levels) do
    n = vim.lsp.diagnostic.get_count(0, level.name)
    -- Add string only if diagnostic is present
    if n > 0 then
      result = result .. string.format(' %s%s', level.sign, n)
    end
  end

  if result == '' then result = ' -' end

  return 'ﯭ ' .. result
end

---- File name
function MiniStatusline.section_filename(arg)
  -- In terminal always use plain name
  if vim.bo.buftype == 'terminal' then
    return '%t'
  -- File name with 'truncate', 'modified', 'readonly' flags
  elseif H.is_truncated(arg.trunc_width) then
    -- Use relative path if truncated
    return '%f%m%r'
  else
    -- Use fullpath if not truncated
    return '%F%m%r'
  end
end

---- File information
function MiniStatusline.section_fileinfo(arg)
  local filetype = vim.bo.filetype

  -- Don't show anything if can't detect file type or not inside a "normal
  -- buffer"
  if ((filetype == '') or H.isnt_normal_buffer()) then return '' end

  -- Add filetype icon
  local icon = H.get_filetype_icon()
  if icon ~= '' then filetype = icon .. ' ' .. filetype end

  -- Construct output string if truncated
  if H.is_truncated(arg.trunc_width) then return filetype end

  -- Construct output string with extra file info
  local encoding = vim.bo.fileencoding or vim.bo.encoding
  local format = vim.bo.fileformat
  local size = H.get_filesize()

  return string.format('%s %s[%s] %s', filetype, encoding, format, size)
end

---- Location inside buffer
function MiniStatusline.section_location(arg)
  -- Use virtual column number to allow update when paste last column
  return '%l|%L│%2v|%-2{col("$") - 1}'
end

-- Helpers
---- Module default config
H.config = {set_vim_settings = MiniStatusline.set_vim_settings}

---- Settings
function H.setup_config(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({config = {config, 'table', true}})
  config = vim.tbl_deep_extend('force', H.config, config or {})

  vim.validate({set_vim_settings = {config.set_vim_settings, 'boolean'}})

  return config
end

function H.apply_config(config)
  MiniStatusline.set_vim_settings = config.set_vim_settings

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

function H.combine_sections(sections)
  local t = {}
  for _, s in ipairs(sections) do
    if type(s) == 'string' then
      t[#t + 1] = s
    elseif s.string ~= '' then
      if s.hl then
        t[#t + 1] = string.format('%s %s ', s.hl, s.string)
      else
        t[#t + 1] = string.format('%s ', s.string)
      end
    end
  end
  return table.concat(t, '')
end

H.diagnostic_levels = {
  {name = 'Error'      , sign = 'E'},
  {name = 'Warning'    , sign = 'W'},
  {name = 'Information', sign = 'I'},
  {name = 'Hint'       , sign = 'H'},
}

function H.get_filesize()
  local size = vim.fn.getfsize(vim.fn.getreg('%'))
  local data
  if size < 1024 then
    data = size .. 'B'
  elseif size < 1048576 then
    data = string.format('%.2fKiB', size / 1024)
  else
    data = string.format('%.2fMiB', size / 1048576)
  end

  return data
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
