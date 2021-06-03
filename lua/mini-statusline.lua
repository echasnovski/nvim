-- Custom minimal **fast** statusline. This is meant to be a standalone file
-- which when sourced in 'init.*' file provides a working minimal statusline.
-- Inspired by:
-- https://elianiva.me/post/neovim-lua-statusline (blogpost)
-- https://github.com/elianiva/dotfiles/blob/master/nvim/.config/nvim/lua/modules/_statusline.lua (Github)
--
-- Suggested dependencies (provide extra functionality, statusline will work without them):
-- - Nerd font (to support git and diagnostics icon).
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
-- - In active mode `MiniStatusline.set_active()` is called. Its code defines
--   high-level structure of statusline. From there go to respective section
--   functions.
--
-- Note about performance:
-- - Currently statusline gets evaluated on every call inside a timer (see
--   https://github.com/neovim/neovim/issues/14303). In current setup this
--   means that update is made periodically in insert mode due to
--   'completion-nvim' plugin and its `g:completion_timer_cycle` setting.
-- - MiniStatusline might get evaluated on every 'CursorHold' event (indicator
--   is an updated happening in `&updatetime` time after cursor stopped; set
--   different `&updatetime` to verify that is a reason). In current setup this
--   is happening due to following reasons:
--     - Plugin 'vim-polyglot' has 'polyglot-sensible' autogroup which checks
--     on 'CursorHold' events if file was updated (see `:h checktime`).
--     - Plugin 'vim-gitgutter' processes buffer on 'CursorHold' events.
--   As these actions are useful, one can only live with the fact that
--   'statusline' option gets reevaluated on 'CursorHold'.
has_devicons, devicons = pcall(require, 'nvim-web-devicons')

local fn = vim.fn
local api = vim.api

-- Create custom `^V` and `^S` symbols to make this file appropriate for
-- copy-paste (otherwise those symbols are not displayed).
local CTRL_S = vim.api.nvim_replace_termcodes('<C-S>', true, true, true)
local CTRL_V = vim.api.nvim_replace_termcodes('<C-V>', true, true, true)

-- Local helpers
local is_truncated = function(width)
  return api.nvim_win_get_width(0) < width
end

local isnt_normal_buffer = function()
  -- For more information see ":h buftype"
  return vim.bo.buftype ~= ''
end

local combine_sections = function(sections)
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

-- MiniStatusline object
MiniStatusline = setmetatable({}, {
  __call = function(statusline, mode)
    if mode == 'active' then return statusline:set_active() end
    if mode == 'inactive' then return statusline:set_inactive() end
  end
})

-- MiniStatusline behavior
vim.api.nvim_exec([[
  augroup MiniStatusline
    au!
    au WinEnter,BufEnter * setlocal statusline=%!v:lua.MiniStatusline('active')
    au WinLeave,BufLeave * setlocal statusline=%!v:lua.MiniStatusline('inactive')
  augroup END
]], false)

-- MiniStatusline colors (from Gruvbox bright palette)
vim.api.nvim_exec([[
  hi MiniStatuslineModeNormal  guibg=#BDAE93 guifg=#1D2021 gui=bold ctermbg=7 ctermfg=0
  hi MiniStatuslineModeInsert  guibg=#83A598 guifg=#1D2021 gui=bold ctermbg=4 ctermfg=0
  hi MiniStatuslineModeVisual  guibg=#B8BB26 guifg=#1D2021 gui=bold ctermbg=2 ctermfg=0
  hi MiniStatuslineModeReplace guibg=#FB4934 guifg=#1D2021 gui=bold ctermbg=1 ctermfg=0
  hi MiniStatuslineModeCommand guibg=#FABD2F guifg=#1D2021 gui=bold ctermbg=3 ctermfg=0
  hi MiniStatuslineModeOther   guibg=#8EC07C guifg=#1D2021 gui=bold ctermbg=6 ctermfg=0

  hi link MiniStatuslineInactive StatusLineNC
  hi link MiniStatuslineDevinfo  StatusLine
  hi link MiniStatuslineFilename StatusLineNC
  hi link MiniStatuslineFileinfo StatusLine
]], false)

-- High-level definition of statusline content
function MiniStatusline:set_active()
  local mode_info = self.modes[fn.mode()]

  local mode        = self:section_mode{mode_info = mode_info, trunc_width = 120}
  local spell       = self:section_spell{trunc_width = 120}
  local wrap        = self:section_wrap{}
  local git         = self:section_git{trunc_width = 75}
  local diagnostics = self:section_diagnostics{trunc_width = 75}
  local filename    = self:section_filename{trunc_width = 140}
  local fileinfo    = self:section_fileinfo{trunc_width = 120}
  local location    = self:section_location{}

  -- Usage of `combine_sections()` ensures correct padding with spaces between
  -- sections (accounts for 'missing' sections, etc.)
  return combine_sections({
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

function MiniStatusline:set_inactive()
  return '%#MiniStatuslineInactive#%F%='
end

-- Mode
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

function MiniStatusline:section_mode(arg)
  local mode = is_truncated(arg.trunc_width) and
    arg.mode_info.short or
    arg.mode_info.long

  return mode
end

-- Spell
function MiniStatusline:section_spell(arg)
  if not vim.wo.spell then return '' end

  if is_truncated(arg.trunc_width) then return 'SPELL' end

  return string.format('SPELL(%s)', vim.bo.spelllang)
end

-- Wrap
function MiniStatusline:section_wrap()
  if not vim.wo.wrap then return '' end

  return 'WRAP'
end

-- Git
-- NOTE: Everything is implemented through updating some custom variable to
-- increase performance because certain actions are only done when needed and
-- not on every statusline update. For comparison: if called on every
-- statusline update, total statusline execution time is ~1.1ms; with current
-- approach it drops to ~0.2ms.
---- Git branch
---- Update git branch on every buffer enter and after Neovim gained focus
---- (detect outside change).
---- Also update git branch before leaving command line (detect fugitive
---- change). Defer update to actually make it **after** leaving command line.
---- Otherwise this will be evaluated too soon and give "previous" branch.
---- NOTE: this adds autocommands to 'MiniStatusline' autogroup
vim.api.nvim_exec([[
  augroup MiniStatusline
    au BufEnter,FocusGained * lua MiniStatusline:update_git_branch({defer = false})
    au CmdlineLeave         * lua MiniStatusline:update_git_branch({defer = true})
  augroup END
]], false)

MiniStatusline.git_branch = nil

function MiniStatusline:update_git_branch(arg)
  if fn.exists('*FugitiveHead') == 0 then
    self.git_branch = '<no fugitive>'
    return
  end

  update_fun = function()
    -- Use commit hash truncated to 7 characters in case of detached HEAD
    local branch = fn.FugitiveHead(7)
    if branch == '' then branch = '<no branch>' end

    local old_val = self.git_branch
    self.git_branch = branch
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

---- Git diff signs
---- Update git signs on every buffer enter (detect signs for buffer) and every
---- time 'gitgutter' says that change occured
---- NOTE: this adds autocommands to 'MiniStatusline' autogroup
vim.api.nvim_exec([[
  augroup MiniStatusline
    au BufEnter *         lua MiniStatusline:update_git_signs()
    au User     GitGutter lua MiniStatusline:update_git_signs()
  augroup END
]], false)

MiniStatusline.git_signs = nil

function MiniStatusline:update_git_signs()
  if fn.exists('*GitGutterGetHunkSummary') == 0 then
    self.git_signs = nil
    return
  end

  local signs = fn.GitGutterGetHunkSummary()
  local res = {}
  if signs[1] > 0 then res[#res + 1] = '+' .. signs[1] end
  if signs[2] > 0 then res[#res + 1] = '~' .. signs[2] end
  if signs[3] > 0 then res[#res + 1] = '-' .. signs[3] end

  local old_val = self.git_signs
  if next(res) == nil then
    self.git_signs = nil
  else
    self.git_signs = table.concat(res, ' ')
  end

  -- Force statusline redraw if it is not first update (otherwise there is a
  -- flicker at Neovim start) and if new value differs from the current one
  if (old_val ~= nil) and (old_val ~= self.git_signs) then
    vim.cmd [[noautocmd redrawstatus]]
  end
end

function MiniStatusline:section_git(arg)
  if isnt_normal_buffer() then return '' end

  local res
  if is_truncated(arg.trunc_width) then
    res = self.git_branch
  else
    res = table.concat({self.git_branch, self.git_signs}, ' ')
  end

  if (res == nil) or res == '' then res = '-' end

  return string.format(' %s', res)
end

-- Diagnostics
local diagnostic_levels = {
  {name = 'Error'      , sign = 'E'},
  {name = 'Warning'    , sign = 'W'},
  {name = 'Information', sign = 'I'},
  {name = 'Hint'       , sign = 'H'},
}

function MiniStatusline:section_diagnostics(arg)
  -- Assumption: there are no attached clients if table
  -- `vim.lsp.buf_get_clients()` is empty
  local hasnt_attached_client = next(vim.lsp.buf_get_clients()) == nil
  local dont_show_lsp = is_truncated(arg.trunc_width) or
    isnt_normal_buffer() or
    hasnt_attached_client
  if dont_show_lsp then return '' end

  -- Gradual growing of string ensures preferred order
  local result = ''

  for _, level in ipairs(diagnostic_levels) do
    n = vim.lsp.diagnostic.get_count(0, level.name)
    -- Add string only if diagnostic is present
    if n > 0 then
      result = result .. string.format(' %s%s', level.sign, n)
    end
  end

  if result == '' then result = ' -' end

  return 'ﯭ ' .. result
end

-- File name
function MiniStatusline:section_filename(arg)
  -- In terminal always use plain name
  if vim.bo.buftype == 'terminal' then
    return '%t'
  -- File name with 'truncate', 'modified', 'readonly' flags
  elseif is_truncated(arg.trunc_width) then
    -- Use relative path if truncated
    return '%f%m%r'
  else
    -- Use fullpath if not truncated
    return '%F%m%r'
  end
end

-- File information
local get_filesize = function()
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

local get_filetype_icon = function()
  -- By default use 'nvim-web-devicons', fallback to 'vim-devicons'
  if has_devicons then
    local file_name, file_ext = fn.expand('%:t'), fn.expand('%:e')
    return devicons.get_icon(file_name, file_ext, { default = true })
  elseif fn.exists('*WebDevIconsGetFileTypeSymbol') ~= 0 then
    return fn.WebDevIconsGetFileTypeSymbol()
  end

  return ''
end

function MiniStatusline:section_fileinfo(arg)
  local filetype = vim.bo.filetype

  -- Don't show anything if can't detect file type or not inside a "normal
  -- buffer"
  if ((filetype == '') or isnt_normal_buffer()) then return '' end

  -- Add filetype icon
  local icon = get_filetype_icon()
  if icon ~= '' then filetype = icon .. ' ' .. filetype end

  -- Construct output string if truncated
  if is_truncated(arg.trunc_width) then return filetype end

  -- Construct output string with extra file info
  local encoding = vim.bo.fileencoding or vim.bo.encoding
  local format = vim.bo.fileformat
  local size = get_filesize()

  return string.format('%s %s[%s] %s', filetype, encoding, format, size)
end

-- Location inside buffer
function MiniStatusline:section_location(arg)
  -- Use virtual column number to allow update when paste last column
  return '%l|%L│%2v|%-2{col("$") - 1}'
end

return MiniStatusline
