local ok, lualine = pcall(require, 'lualine')

if not ok then
  return
end

lualine.options.theme = 'gruvbox'

lualine.options.section_separators = nil
lualine.options.component_separators = nil

lualine.sections = {
  lualine_a = { 'mode' },
  lualine_b = {
    -- Don't show diff symbols with colors because it currently chenges color
    -- of 'branch' section
    { 'diff', colored = false },
    'branch'
  },
  lualine_c = {
    -- Show full file path relative to current working directory
    { 'filename', shorten = true, full_path = true}
  },
  lualine_x = { 'encoding', 'fileformat', 'filetype' },
  lualine_y = { 'progress', 'location' },
  lualine_z = {
    {'diagnostics', sources = { 'nvim_lsp' }}
  },
}

lualine.status()
