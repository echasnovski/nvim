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
has_devicons, devicons = pcall(require, 'nvim-web-devicons')

local fn = vim.fn
local api = vim.api

local M = {}

M.colors = {
  active      = '%#StatusLineActive#',
  inactive    = '%#StatuslineInactive#',
  mode        = '%#StatusLineModeNormal#',
  git         = '%#StatusLineGit#',
  fileinfo    = '%#StatusLineFileinfo#',
  line_col    = '%#StatusLineLineCol#',
  diagnostics = '%#StatusLineDiagn#',
}

M.modes = setmetatable({
  ['n']  = {'Normal'   , 'N'  , '%#StatusLineModeNormal#'};
  ['v']  = {'Visual'   , 'V'  , '%#StatusLineModeVisual#'};
  ['V']  = {'V-Line'   , 'V-L', '%#StatusLineModeVisual#'};
  [''] = {'V-Block'  , 'V·B', '%#StatusLineModeVisual#'};
  ['s']  = {'Select'   , 'S'  , '%#StatusLineModeVisual#'};
  ['S']  = {'S-Line'   , 'S-L', '%#StatusLineModeVisual#'};
  [''] = {'S-Block'  , 'S-B', '%#StatusLineModeVisual#'};
  ['i']  = {'Insert'   , 'I'  , '%#StatusLineModeInsert#'};
  ['R']  = {'Replace'  , 'R'  , '%#StatusLineModeReplace#'};
  ['c']  = {'Command'  , 'C'  , '%#StatusLineModeCommand#'};
  ['r']  = {'Prompt'   , 'P'  , '%#StatusLineModeOther#'};
  ['!']  = {'Shell'    , 'Sh' , '%#StatusLineModeOther#'};
  ['t']  = {'Terminal' , 'T'  , '%#StatusLineModeOther#'};
}, {
  -- By default return 'Unknown' but this shouldn't be needed
  __index = function() return {'Unknown', 'U', '%#StatusLineModeOther#'} end
})

-- Information about diagnostics
M.diagnostic_levels = {
  errors   = {'Error'      , 'E', '%#StatusLineDiagnError#'},
  warnings = {'Warning'    , 'W', '%#StatusLineDiagnWarning#'},
  info     = {'Information', 'I', '%#StatusLineDiagnInfo#'},
  hints    = {'Hint'       , 'H', '%#StatusLineDiagnHint#'}
}

-- Window width at which section becomes truncated (default to 80)
M.trunc_width = setmetatable({
  mode        = 120,
  filename    = 140,
  fileinfo    = 120,
  git         = 80,
  diagnostics = 75,
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

M.get_current_mode = function(self)
  -- Usage of `fn.mode()` allows getting single letter description of mode
  -- which greatly reduces number of needed entries in `modes` table.
  -- For bigger flexibility, use `api.nvim_get_mode().mode`.
  local mode_info = self.modes[fn.mode()]
  local mode_color = mode_info[3]
  local mode_string = self:is_truncated('mode') and mode_info[2] or mode_info[1]

  return string.format('%s %s ', mode_color, mode_string):upper()
end

M.get_spelling = function(self)
  if not vim.wo.spell then return '' end

  -- NOTE: this section will inherit highliting of the previous section
  return string.format(' SPELL(%s) ', vim.bo.spelllang)
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

local get_git_branch = function()
  if fn.exists('*FugitiveHead') == 0 then return '<no fugitive>' end

  -- Use commit hash truncated to 7 characters in case of detached HEAD
  local branch = fn.FugitiveHead(7)
  if branch == '' then return '<no branch>' end
  return string.format(' %s', branch)
end

M.get_git_status = function(self)
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

  if self:is_truncated('git') then
    return string.format(' %s ', branch)
  else
    local signs = get_git_signs()

    if signs == '' then
      return string.format(' %s ', branch)
    else
      return string.format(' %s %s ', branch, signs)
    end
  end
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

M.get_lsp_diagnostic = function(self)
  if (self:is_truncated('diagnostics') or isnt_normal_buffer()) then return '' end

  local result = {}

  for k, level in pairs(self.diagnostic_levels) do
    n = vim.lsp.diagnostic.get_count(0, level[1])
    -- Add string only if diagnostic is present
    if n > 0 then
      table.insert(result, string.format('%s%s:%s', level[3], level[2], n))
    end
  end

  if #result == 0 then return '' end

  return ' ' .. table.concat(result, ' ')
end

M.set_active = function(self)
  local colors = self.colors

  local mode = self:get_current_mode()
  local spelling = self:get_spelling()
  local git = colors.git .. self:get_git_status()
  local filename = colors.inactive .. self:get_filename()
  local fileinfo = colors.fileinfo .. self:get_fileinfo()
  local line_col = colors.line_col .. self:get_line_col()
  local diagnostics = colors.diagnostics .. self:get_lsp_diagnostic()

  return table.concat({
    colors.active, mode, spelling, git, filename,
    "%=",
    fileinfo, line_col, diagnostics
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
