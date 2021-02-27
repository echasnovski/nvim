-- Heavily inspired by:
-- https://elianiva.me/post/neovim-lua-statusline (blogpost)
-- https://github.com/elianiva/dotfiles/blob/master/nvim/.config/nvim/lua/modules/_statusline.lua (Github)
-- Suggested dependencies (provide extra functionality, statusline will work without them):
-- - Nerd font (to support git icon).
-- - Plugin 'airblade/vim-gitgutter' for Git signs. If missing, no git signs
--   will be shown.
-- - Plugin 'tpope/vim-fugitive' for Git branch. If missing, '<no fugitive>'
--   will be displayed instead of a branch.
-- - Plugin 'kyazdani42/nvim-web-devicons' or 'ryanoasis/vim-devicons' for
--   filetype icons. If missing, no icons will be used.
--
-- Notes about structure:
-- - Main statusline object is `Statusline`. It has three different "states":
--   active, inactive, explorer.
-- - In active mode `M.set_active()` is called. Its code defines high-level
--   structure of statusline. From there go to respective functions.
has_devicons, devicons = pcall(require, 'nvim-web-devicons')

local fn = vim.fn
local api = vim.api

local M = {}

M.colors = {
  active   = '%#StatusLineActive#',
  inactive = '%#StatuslineInactive#',
  mode     = '%#StatusLineModeNormal#',
  devinfo  = '%#StatusLineDevinfo#', -- gitinfo and lspinfo
  filename = '%#StatusLineFilename#',
  fileinfo = '%#StatusLineFileinfo#',
}

M.modes = setmetatable({
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

-- Keep track of current mode. This is so that all section would rely on the
-- same mode value. !!!Important to keep it updated!!!
M.current_mode_info = M.modes['n']

-- Information about diagnostics
M.diagnostic_levels = {
  {name = 'Error'      , sign = 'E'},
  {name = 'Warning'    , sign = 'W'},
  {name = 'Information', sign = 'I'},
  {name = 'Hint'       , sign = 'H'},
}

-- Window width at which section becomes truncated (default to 80)
M.trunc_width = setmetatable({
  mode     = 120,
  devinfo  = 75, -- gitinfo and lspinfo
  filename = 140,
  fileinfo = 120,
}, {
  __index = function() return 80 end
})

M.is_truncated = function(self, section)
  return api.nvim_win_get_width(0) < self.trunc_width[section]
end

local isnt_normal_buffer = function()
  -- For more information see ":h buftype"
  return vim.bo.buftype ~= ''
end

M.update_current_mode_info = function(self)
  -- Usage of `fn.mode()` allows getting single letter description of mode
  -- which greatly reduces number of needed entries in `modes` table.
  -- For bigger flexibility, use `api.nvim_get_mode().mode`.
  self.current_mode_info = self.modes[fn.mode()]
end

M.get_current_mode = function(self)
  local mode_info = self.current_mode_info
  local mode_string = self:is_truncated('mode') and mode_info.short or mode_info.long

  return string.format(' %s ', mode_string)
end

M.get_spelling = function(self)
  if not vim.wo.spell then return '' end

  -- NOTE: this section will inherit highliting of the previous section
  return string.format('SPELL(%s) ', vim.bo.spelllang)
end

local get_git_branch = function()
  if fn.exists('*FugitiveHead') == 0 then return '<no fugitive>' end

  -- Use commit hash truncated to 7 characters in case of detached HEAD
  local branch = fn.FugitiveHead(7)
  if branch == '' then return '<no branch>' end
  return string.format(' %s', branch)
end

local get_git_signs = function()
  if fn.exists('*GitGutterGetHunkSummary') == 0 then return '' end

  local signs = fn.GitGutterGetHunkSummary()
  local res = {}
  if signs[1] > 0 then table.insert(res, '+' .. signs[1]) end
  if signs[2] > 0 then table.insert(res, '~' .. signs[2]) end
  if signs[3] > 0 then table.insert(res, '-' .. signs[3]) end

  return table.concat(res, ' ')
end

M.get_gitinfo = function(self)
  if isnt_normal_buffer() then return '' end

  -- NOTE: this information doesn't change on every entry but these functions
  -- are called on every statusline update (which is **very** often). Currently
  -- this doesn't introduce noticeable overhead because of a smart way used
  -- functions of 'vim-gitgutter' and 'vim-fugitive' are written (seems like
  -- they just take value of certain buffer variable, which is quick).
  -- If ever encounter overhead, write 'update_val()' wrapper which updates
  -- module's certain variable and call it only on certain event. Example:
  -- ```lua
  -- M.git_signs_str = ''
  -- M.update_git_signs = function(self)
  --   self.git_signs_str = get_git_signs()
  -- end
  -- vim.api.nvim_exec([[
  --   au BufEnter,User GitGutter lua Statusline.update_git_signs(Statusline)
  -- ]], false)
  -- ```
  local branch = get_git_branch()

  if self:is_truncated('devinfo') then
    return string.format('%s', branch)
  else
    local signs = get_git_signs()

    if signs == '' then
      return string.format('%s', branch)
    else
      return string.format('%s %s', branch, signs)
    end
  end
end

M.get_lspinfo = function(self)
  -- Assumption: there are no attached clients if table
  -- `vim.lsp.buf_get_clients()` is empty
  local hasnt_attached_client = next(vim.lsp.buf_get_clients()) == nil
  local dont_show_lsp = self:is_truncated('devinfo') or
    isnt_normal_buffer() or
    hasnt_attached_client
  if dont_show_lsp then return '' end

  -- Gradual growing of string ensures preferred order
  local result = ''

  for _, level in ipairs(self.diagnostic_levels) do
    n = vim.lsp.diagnostic.get_count(0, level.name)
    -- Add string only if diagnostic is present
    if n > 0 then
      result = result .. string.format(' %s%s', level.sign, n)
    end
  end

  if result == '' then result = ' -' end

  return 'LSP:' .. result
end

M.get_devinfo = function(self)
  local result = ''
  -- Not using `table.concat()` because it seems to be a good idea for
  -- `get_gitinfo()` and `get_lspinfo()` to return empty string ('') in case
  -- there is nothing to show (instead of `nil`). But in the case when both of
  -- them are '' (like in terminal buffer) the output of `table.concat()` will
  -- be '  '.
  for _, s in ipairs({self:get_gitinfo(), self:get_lspinfo()}) do
    if s ~= '' then result = result .. ' ' .. s end
  end
  if result ~= '' then result = result .. ' ' end
  return result
end

M.get_filename = function(self)
  -- File name with 'modified' and 'readonly' flags
  -- Use relative path if truncated
  if self:is_truncated('filename') then return " %<%f%m%r " end
  -- Use fullpath if not truncated
  return " %<%F%m%r "
end

local get_filesize = function()
  local size = vim.fn.getfsize(vim.fn.getreg('%'))
  local data
  if size < 1024 then
    data = size .. "B"
  elseif size < 1048576 then
    data = string.format('%.2f', size / 1024) .. 'KiB'
  else
    data = string.format('%.2f', size / 1048576) .. 'MiB'
  end

  return data
end

local get_filetype_icon = function()
  -- By default use 'nvim-web-devicons', fallback to 'vim-devicons'
  if has_devicons then
    local file_name, file_ext = fn.expand('%:t'), fn.expand('%:e')
    return devicons.get_icon(file_name, file_ext) or
      -- Fallback for some extensions (like '.R' and '.r')
      devicons.get_icon(string.lower(file_name), string.lower(file_ext), { default = true })
  elseif fn.exists("*WebDevIconsGetFileTypeSymbol") ~= 0 then
    return fn.WebDevIconsGetFileTypeSymbol()
  end

  return ''
end

M.get_fileinfo = function(self)
  local filetype = vim.bo.filetype

  -- Don't show anything if can't detect file type or not inside a "normal
  -- buffer"
  if ((filetype == '') or isnt_normal_buffer()) then return '' end

  -- Add filetype icon
  local icon = get_filetype_icon()
  if icon ~= "" then filetype = icon .. ' ' .. filetype end

  -- Construct output string if truncated
  if self:is_truncated('fileinfo') then
    return string.format(' %s ', filetype)
  end

  -- Construct output string with extra file info
  local encoding = vim.bo.fileencoding or vim.bo.encoding
  local format = vim.bo.fileformat
  local size = get_filesize()

  return string.format(' %s %s[%s] %s ', filetype, encoding, format, size)
end

M.get_line_col = function(self)
  -- Use virtual column number to allow update when paste last column
  return ' (%3l|%L):(%2v|%-2{col("$") - 1}) '
end

M.set_active = function(self)
  self:update_current_mode_info()
  local mode_info = self.current_mode_info

  local colors = self.colors

  local mode     = mode_info.hl    .. self:get_current_mode()
  local spelling = mode_info.hl    .. self:get_spelling()
  local devinfo  = colors.devinfo  .. self:get_devinfo()
  local filename = colors.filename .. self:get_filename()
  local fileinfo = colors.fileinfo .. self:get_fileinfo()
  local line_col = mode_info.hl    .. self:get_line_col()

  return table.concat({
    mode, spelling, devinfo, filename,
    "%=",
    fileinfo, line_col
  })
end

M.set_inactive = function(self)
  return self.colors.inactive .. '%F %='
end

M.set_explorer = function(self)
  local title = self.colors.mode .. '   '

  return table.concat({ self.colors.active, title })
end

Statusline = setmetatable(M, {
  __call = function(statusline, mode)
    if mode == "active" then return statusline:set_active() end
    if mode == "inactive" then return statusline:set_inactive() end
    if mode == "explorer" then return statusline:set_explorer() end
  end
})

-- set statusline
-- TODO: replace this once we can define autocmd using lua
vim.api.nvim_exec([[
  augroup Statusline
  au!
  au WinEnter,BufEnter * setlocal statusline=%!v:lua.Statusline('active')
  au WinLeave,BufLeave * setlocal statusline=%!v:lua.Statusline('inactive')
  au WinEnter,BufEnter,FileType NvimTree setlocal statusline=%!v:lua.Statusline('explorer')
  augroup END
]], false)
