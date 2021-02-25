-- Heavily inspired by:
-- https://elianiva.me/post/neovim-lua-statusline (blogpost)
-- https://github.com/elianiva/dotfiles/blob/master/nvim/.config/nvim/lua/modules/_statusline.lua (Github)
-- Suggested dependencies (provide extra functionality, statusline will work without them):
-- - Nerd font (to support git icon).
-- - Plugin 'lewis6991/gitsigns.nvim' for Git info. If missing,
--   'tpope/vim-fugitive'.  If both missing, '<no git plugin>' will be displayed.
-- - Plugin 'kyazdani42/nvim-web-devicons' for filetype icons. If missing, no
--   icons will be used.
has_gitsigns, gitsigns = pcall(require, 'gitsigns')
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

M.modes = {
  ['n']  = {'Normal'   , 'N'  , '%#StatusLineModeNormal#'};
  ['no'] = {'N-Pending', 'N-P', '%#StatusLineModeNormal#'};
  ['v']  = {'Visual'   , 'V'  , '%#StatusLineModeVisual#'};
  ['V']  = {'V-Line'   , 'V-L', '%#StatusLineModeVisual#'};
  [''] = {'V-Block'  , 'V·B', '%#StatusLineModeVisual#'};
  ['s']  = {'Select'   , 'S'  , '%#StatusLineModeVisual#'};
  ['S']  = {'S-Line'   , 'S-L', '%#StatusLineModeVisual#'};
  [''] = {'S-Block'  , 'S-B', '%#StatusLineModeVisual#'};
  ['i']  = {'Insert'   , 'I'  , '%#StatusLineModeInsert#'};
  ['ic'] = {'Insert'   , 'I'  , '%#StatusLineModeInsert#'};
  ['R']  = {'Replace'  , 'R'  , '%#StatusLineModeReplace#'};
  ['Rv'] = {'V-Replace', 'V-R', '%#StatusLineModeReplace#'};
  ['c']  = {'Command'  , 'C'  , '%#StatusLineModeCommand#'};
  ['cv'] = {'Vim-Ex'   , 'V-E', '%#StatusLineModeCommand#'};
  ['ce'] = {'Ex'       , 'E'  , '%#StatusLineModeCommand#'};
  ['r']  = {'Prompt'   , 'P'  , '%#StatusLineModeOther#'};
  ['rm'] = {'More'     , 'M'  , '%#StatusLineModeOther#'};
  ['r?'] = {'Confirm'  , 'C'  , '%#StatusLineModeOther#'};
  ['!']  = {'Shell'    , 'S'  , '%#StatusLineModeOther#'};
  ['t']  = {'Terminal' , 'T'  , '%#StatusLineModeOther#'};
}

-- Information about diagnostics
M.diagnostic_levels = {
  errors = {'Error', 'E', '%#StatusLineDiagnError#'},
  warnings = {'Warning', 'W', '%#StatusLineDiagnWarning#'},
  info = {'Information', 'I', '%#StatusLineDiagnInfo#'},
  hints = {'Hint', 'H', '%#StatusLineDiagnHint#'}
}

-- Window width at which section becomes truncated
M.trunc_width = {
  mode = 120,
  filename = 140,
  fileinfo = 120,
  git = 90,
  diagnostics = 75,
}

M.is_truncated = function(self, section)
  -- Get section width (default to 80 if there is no section)
  local ok, width = pcall(function() return self.trunc_width[section] end)
  width = ok and width or 80
  return api.nvim_win_get_width(0) < width
end

local isnt_normal_buffer = function()
  -- For more information see ":h buftype"
  return vim.bo.buftype ~= ''
end

M.get_current_mode = function(self)
  local current_mode = api.nvim_get_mode().mode
  local mode_info = self.modes[current_mode]
  local mode_color = mode_info[3]
  local mode_string = self:is_truncated('mode') and mode_info[2] or mode_info[1]

  return string.format('%s %s ', mode_color, mode_string):upper()
end

M.get_spelling = function(self)
  if not vim.wo.spell then return '' end

  -- NOTE: this section will inherit highliting of the previous section
  return string.format(' SPELL(%s) ', vim.bo.spelllang)
end

M.get_git_status = function(self)
  if isnt_normal_buffer() then return '' end

  if not has_gitsigns then
    if fn.exists('*FugitiveHead') == 0 then return ' <no git plugin> ' end

    local branch = fn.FugitiveHead()
    if branch == '' then return ' <no git> ' end
    return string.format('  %s ', branch)
  end

  local branch = vim.b.gitsigns_head
  if not branch then
    return ' <no git> '
  end

  if self.is_truncated('git') then
    return string.format('  %s ', branch)
  else
    local status = vim.b.gitsigns_status
    if status == "" then
      return string.format('  %s ', branch)
    else
      return string.format(' %s |  %s ', status, branch)
    end
  end

  -- -- use fallback because it doesn't set this variable on the initial `BufEnter`
  -- local signs = vim.b.gitsigns_status_dict or {head = '', added = 0, changed = 0, removed = 0}

  -- if signs.head == '' then
  --   return ' <no git> '
  -- end

  -- if self:is_truncated('git') then
  --   return string.format('  %s ', signs.head or '') or ''
  -- end

  -- return string.format(
  --   ' +%s ~%s -%s |  %s ',
  --   signs.added, signs.changed, signs.removed, signs.head
  -- ) or ''
end

M.get_filename = function(self)
  -- File name with 'modified' and 'readonly' flags
  -- Use relative path if truncted
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

M.get_fileinfo = function(self)
  local filetype = vim.bo.filetype

  -- Don't show anything if can't detect file type or not inside a "normal
  -- buffer"
  if ((filetype == '') or isnt_normal_buffer()) then return '' end

  -- Add filetype icon
  if has_devicons then
    local file_name, file_ext = fn.expand('%:t'), fn.expand('%:e')
    local icon = devicons.get_icon(file_name, file_ext) or
      -- Fallback for some extensions (like '.R' and '.r')
      devicons.get_icon(string.lower(file_name), string.lower(file_ext), { default = true })

    filetype = string.format('%s %s', icon, filetype)
  end

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
