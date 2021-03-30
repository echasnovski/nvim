-- Custom statusline. Heavily inspired by:
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
-- - Main statusline object is `Statusline`. It has two different "states":
--   active and inactive.
-- - In active mode `Statusline.set_active()` is called. Its code defines high-level
--   structure of statusline. From there go to respective section functions.
has_devicons, devicons = pcall(require, 'nvim-web-devicons')

local fn = vim.fn
local api = vim.api

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

-- Statusline object
Statusline = setmetatable({}, {
  __call = function(statusline, mode)
    if mode == 'active' then return statusline:set_active() end
    if mode == 'inactive' then return statusline:set_inactive() end
  end
})

-- Statusline behavior
vim.api.nvim_exec([[
  augroup Statusline
  au!
  au WinEnter,BufEnter * setlocal statusline=%!v:lua.Statusline('active')
  au WinLeave,BufLeave * setlocal statusline=%!v:lua.Statusline('inactive')
  augroup END
]], false)

-- High-level definition of statusline content
function Statusline:set_active()
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
    {string = git,         hl = '%#StatusLineDevinfo#'},
    {string = diagnostics, hl = nil}, -- Copy highliting from previous section
    '%<', -- Mark general truncate point
    {string = filename,    hl = '%#StatusLineFilename#'},
    '%=', -- End left alignment
    {string = fileinfo,    hl = '%#StatusLineFileinfo#'},
    {string = location,    hl = mode_info.hl},
  })
end

function Statusline:set_inactive()
  return '%#StatuslineInactive#%F%='
end

-- Mode
Statusline.modes = setmetatable({
  ['n']  = {long = 'Normal'  , short = 'N'  , hl = '%#StatusLineModeNormal#'};
  ['v']  = {long = 'Visual'  , short = 'V'  , hl = '%#StatusLineModeVisual#'};
  ['V']  = {long = 'V-Line'  , short = 'V-L', hl = '%#StatusLineModeVisual#'};
  [''] = {long = 'V-Block' , short = 'V-B', hl = '%#StatusLineModeVisual#'};
  ['s']  = {long = 'Select'  , short = 'S'  , hl = '%#StatusLineModeVisual#'};
  ['S']  = {long = 'S-Line'  , short = 'S-L', hl = '%#StatusLineModeVisual#'};
  [''] = {long = 'S-Block' , short = 'S-B', hl = '%#StatusLineModeVisual#'};
  ['i']  = {long = 'Insert'  , short = 'I'  , hl = '%#StatusLineModeInsert#'};
  ['R']  = {long = 'Replace' , short = 'R'  , hl = '%#StatusLineModeReplace#'};
  ['c']  = {long = 'Command' , short = 'C'  , hl = '%#StatusLineModeCommand#'};
  ['r']  = {long = 'Prompt'  , short = 'P'  , hl = '%#StatusLineModeOther#'};
  ['!']  = {long = 'Shell'   , short = 'Sh' , hl = '%#StatusLineModeOther#'};
  ['t']  = {long = 'Terminal', short = 'T'  , hl = '%#StatusLineModeOther#'};
}, {
  -- By default return 'Unknown' but this shouldn't be needed
  __index = function()
    return {long = 'Unknown', short = 'U', hl = '%#StatusLineModeOther#'}
  end
})

function Statusline:section_mode(arg)
  local mode = is_truncated(arg.trunc_width) and
    arg.mode_info.short or
    arg.mode_info.long

  return mode
end

-- Spell
function Statusline:section_spell(arg)
  if not vim.wo.spell then return '' end

  if is_truncated(arg.trunc_width) then return 'SPELL' end

  return string.format('SPELL(%s)', vim.bo.spelllang)
end

-- Wrap
function Statusline:section_wrap()
  if not vim.wo.wrap then return '' end

  return 'WRAP'
end

-- Git
local function get_git_branch()
  if fn.exists('*FugitiveHead') == 0 then return '<no fugitive>' end

  -- Use commit hash truncated to 7 characters in case of detached HEAD
  local branch = fn.FugitiveHead(7)
  if branch == '' then return '<no branch>' end
  return branch
end

local function get_git_signs()
  if fn.exists('*GitGutterGetHunkSummary') == 0 then return nil end

  local signs = fn.GitGutterGetHunkSummary()
  local res = {}
  if signs[1] > 0 then table.insert(res, '+' .. signs[1]) end
  if signs[2] > 0 then table.insert(res, '~' .. signs[2]) end
  if signs[3] > 0 then table.insert(res, '-' .. signs[3]) end

  if next(res) == nil then
    return nil
  end
  return table.concat(res, ' ')
end

function Statusline:section_git(arg)
  if isnt_normal_buffer() then return '' end

  -- NOTE: this information doesn't change on every entry but these functions
  -- are called on every statusline update (which is **very** often). Currently
  -- this doesn't introduce noticeable overhead because of a smart way used
  -- functions of 'vim-gitgutter' and 'vim-fugitive' are written (seems like
  -- they just take value of certain buffer variable, which is quick).
  -- If ever encounter overhead, write 'update_val()' wrapper which updates
  -- module's certain variable and call it only on certain event. Example:
  -- ```lua
  -- Statusline.git_signs_str = ''
  -- Statusline.update_git_signs = function(self)
  --   self.git_signs_str = get_git_signs()
  -- end
  -- vim.api.nvim_exec([[
  --   au BufEnter,User GitGutter lua Statusline:update_git_signs()
  -- ]], false)
  -- ```
  local res
  local branch = get_git_branch()

  if is_truncated(arg.trunc_width) then
    res = branch
  else
    local signs = get_git_signs()

    res = table.concat({branch, signs}, ' ')
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

function Statusline:section_diagnostics(arg)
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
function Statusline:section_filename(arg)
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

function Statusline:section_fileinfo(arg)
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
function Statusline:section_location(arg)
  -- Use virtual column number to allow update when paste last column
  return '%l|%L│%2v|%-2{col("$") - 1}'
end
