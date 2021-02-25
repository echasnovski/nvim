local ok, lualine = pcall(require, 'lualine')

if not ok then return end

-- Set color theme
lualine.options.theme = 'gruvbox'

-- Don't use separators
lualine.options.section_separators = nil
lualine.options.component_separators = nil

-- Custom sections

-- Show current location as "<line>:<column>" and overall info as "(<number of
-- lines>:<number of columns in current line>)"
local function my_location()
  -- For magical formatting values see ':h statusline'
  local data = [[%3l:%-2c (%L:%-2{col("$") - 1})]]
  return data
end

-- Spelling information
local function spell()
  local data = ""

  if vim.wo.spell then
    data = "SPELL(" .. vim.bo.spelllang .. ")"
  end

  return data
end

-- File size
local function filesize()
  local size = vim.fn.getfsize(vim.fn.getreg('%'))
  local data = nil
  if size < 1024 then
    data = size .. "B"
  elseif size < 1048576 then
    data = string.format('%.2f', size / 1024) .. "KiB"
  else
    data = string.format('%.2f', size / 1048576) .. "MiB"
  end

  return "(" .. data .. ")"
end

-- Fixed filetype section (icon actually updates and looking for lowercase
-- extension is supported)
local function my_filetype()
  local data = vim.bo.filetype

  if #data > 0 then
    local icon = nil
    local ok, devicons = pcall(require,'nvim-web-devicons')
    if ok then
      local f_name, f_extension = vim.fn.expand('%:t'), vim.fn.expand('%:e')

      -- Look for icon based on file name and extension (try lowercase in
      -- case of a fail)
      icon = devicons.get_icon(f_name, f_extension) or
        devicons.get_icon(string.lower(f_name), string.lower(f_extension))
    else
      ok = vim.fn.exists('*WebDevIconsGetFileTypeSymbol')
      if ok ~= 0 then
        icon = vim.fn.WebDevIconsGetFileTypeSymbol()
      end
    end

    if icon then
      data = icon .. " " .. data
    end
    return data
  end

  return ''
end

-- Define sections
lualine.sections = {
  lualine_a = { 'mode', spell },
  lualine_b = {
    -- Don't show diff symbols with colors because it currently chenges color
    -- of 'branch' section
    { 'diff', colored = false },
    'branch'
  },
  lualine_c = {
    -- Show full file path relative to current working directory
    { 'filename', shorten = true, full_path = true},
    filesize
  },
  lualine_x = { 'encoding', 'fileformat', my_filetype },
  lualine_y = { my_location },
  lualine_z = {
    {'diagnostics', sources = { 'nvim_lsp' }}
  },
}

-- Start statusline
lualine.status()
