-- Code for tweaking new default Neovim color scheme for PR #?????
-- It defines an overall look based on a handful of hyperparameters.
--
-- General goals:
-- - Be "Neovim branded", i.e. follow outlined example from
--   https://github.com/neovim/neovim/issues/14790
--   That generally means to mostly have "green-blue" feel plus at least one
--   reserved for very occasional attention: red for severe, yellow for mild.
-- - Be extra minimal for `notermguicolors` while allowing more shades for
--   when `termguicolors` is set.
-- - Be accessible, i.e. have enough contrast ratios (CR):
--     - Fully passable `Normal` highlight group: CR>=7.
--     - Passable `Visual` highlight group (with `Normal` foreground): CR>=4.5.
--     - Passable comment in current line (foreground from `Comment` and
--       background from `CursorLine`): CR>=4.5.
--     - Passable diff highlight groups: CR>=4.5.
--     - Passable 'Search' highlight group: CR>=4.5.
-- - Have dark and light variants be a simple exchange of dark and light
--   palettes (as this is easier to implement).
-- - Be usable for more than one person.

-- What this script does:
-- - Computes dark and light palettes based on hyperparameters.
-- - Creates a buffer with the following information about palettes:
--     - Dark and light palettes themselves.
--     - Values of target contrast ratios.
--     - Their 8-bit color approximations to be used with `ctermfg`/`ctermbg`.
--     - Copy-pasteable lines defining colors in 'src/nvim/highlight_group.c'.
-- - Enables the currently defined color scheme.

-- NOTE: All manipulation is done in Oklch color space.
-- Get interactive view at https://bottosson.github.io/misc/colorpicker/
-- Install https://github.com/echasnovski/mini.colors to have this working
local colors = require('mini.colors')

-- Hyperparameters ============================================================
-- REFERENCE LIGHTNESS VALUES
-- They are applied both to dark and light pallete, and indicate how far from
-- corresponding edge (0 for dark and 100 for light) it should be.
-- Level meaning for dark color scheme (reverse for light one):
-- - Level 1 is background for floating windows.
-- - Level 2 is basic lightness. Used in `Normal` (both bg and fg).
-- - Level 3 is `CursorLine` background.
-- - Level 4 is `Visual` background and `Comment` foreground.
--
-- Initially value for level 2 was taken from #14790 (as lightness of #1e1e1e).
-- Levels 1 and 2 are adjusted according to request in #26369.
-- Others are the result of experiments to have passable contrast ratios.
local l = { 5, 10, 20, 35 }

-- REFERENCE CHROMA VALUES
-- Chosen experimentally. Darker colors usually need higher chroma to appear
-- visibly different (combined with proper gamut clipping)
local c = { grey = 1, light = 10, dark = 15 }

-- REFERENCE HUE VALUES
-- - Grey is used for UI background and foreground. It is not exactly an
--   achromatic grey, but a "colored grey" (very desaturated colors). It adds
--   at least some character to the color scheme.
--   Choice 270 implements "cold" UI. Tweak to get a different feel. Examples:
--     - 90 for warm.
--     - 180 for neutral cyan.
--     - 0 for neutral pink.
-- - Red hue is taken roughly the same as in reference #D96D6A
-- - Green hue is taken roughly the same as in reference #87FFAF
-- - Cyan hue is taken roughly the same as in reference #00E6E6
-- - Yellow, blue, and magenta are chosen to be visibly different from others.
local h = {
  grey = 270,
  red = 25,
  yellow = 90,
  green = 150,
  cyan = 195,
  blue = 240,
  magenta = 330,
}

-- WHETHER TO OPEN A BUFFER WITH DATA
local show_data_buffer = false

-- WHETHER TO APPLY CURRENT COLOR SCHEME
local apply_colorscheme = true

-- Palettes ===================================================================
local convert = function(L, C, H) return colors.convert({ l = L, c = C, h = H }, 'hex', { gamut_clip = 'cusp' }) end
local round = function(x) return math.floor(10 * x + 0.5) / 10 end

--stylua: ignore
local palette_dark = {
  grey1   = convert(l[1], c.grey, h.grey),  -- NormalFloat
  grey2   = convert(l[2], c.grey, h.grey),  -- Normal bg
  grey3   = convert(l[3], c.grey, h.grey),  -- CursorLine
  grey4   = convert(l[4], c.grey, h.grey),  -- Visual

  red     = convert(l[2], c.dark, h.red),    -- DiffDelete
  yellow  = convert(l[2], c.dark, h.yellow), -- Search
  green   = convert(l[2], c.dark, h.green),  -- DiffAdd
  cyan    = convert(l[2], c.dark, h.cyan),   -- DiffChange
  blue    = convert(l[2], c.dark, h.blue),
  magenta = convert(l[2], c.dark, h.magenta),
}

--stylua: ignore
local palette_light = {
  grey1   = convert(100 - l[1], c.grey, h.grey),
  grey2   = convert(100 - l[2], c.grey, h.grey),   -- Normal fg
  grey3   = convert(100 - l[3], c.grey, h.grey),
  grey4   = convert(100 - l[4], c.grey, h.grey),   -- Comment

  red     = convert(100 - l[2], c.light, h.red),     -- DiagnosticError
  yellow  = convert(100 - l[2], c.light, h.yellow),  -- DiagnosticWarn
  green   = convert(100 - l[2], c.light, h.green),   -- String,     DiagnosticOk
  cyan    = convert(100 - l[2], c.light, h.cyan),    -- Function,   DiagnosticInfo
  blue    = convert(100 - l[2], c.light, h.blue),    -- Identifier, DiagnosticHint
  magenta = convert(100 - l[2], c.light, h.magenta),
}

-- 8-bit color approximations =================================================
local convert_to_8bit = function(hex) return require('mini.colors').convert(hex, '8-bit') end

local cterm_palette_dark = vim.tbl_map(convert_to_8bit, palette_dark)
local cterm_palette_light = vim.tbl_map(convert_to_8bit, palette_light)

-- Oklch color representations ================================================
local convert_to_oklch = function(hex)
  local res = require('mini.colors').convert(hex, 'oklch')
  return vim.tbl_map(round, res)
end

local oklch_palette_dark = vim.tbl_map(convert_to_oklch, palette_dark)
local oklch_palette_light = vim.tbl_map(convert_to_oklch, palette_light)

-- Contrast ratios ============================================================
local correct_channel = function(x) return x <= 0.04045 and (x / 12.92) or math.pow((x + 0.055) / 1.055, 2.4) end

-- Source: https://www.w3.org/TR/2008/REC-WCAG20-20081211/#relativeluminancedef
local get_luminance = function(hex)
  local rgb = colors.convert(hex, 'rgb')

  -- Convert decimal color to [0; 1]
  local r, g, b = rgb.r / 255, rgb.g / 255, rgb.b / 255

  -- Correct channels
  local R, G, B = correct_channel(r), correct_channel(g), correct_channel(b)

  return 0.2126 * R + 0.7152 * G + 0.0722 * B
end

-- Source: https://www.w3.org/TR/2008/REC-WCAG20-20081211/#contrast-ratiodef
local get_contrast_ratio = function(hex_fg, hex_bg)
  local lum_fg, lum_bg = get_luminance(hex_fg), get_luminance(hex_bg)
  local res = (math.max(lum_bg, lum_fg) + 0.05) / (math.min(lum_bg, lum_fg) + 0.05)
  -- Track only one decimal digit
  return round(res)
end

--stylua: ignore
local contrast_ratios = {
  dark_normal   = get_contrast_ratio(palette_light.grey2, palette_dark.grey2),
  dark_cur_line = get_contrast_ratio(palette_light.grey2, palette_dark.grey3),
  dark_visual   = get_contrast_ratio(palette_light.grey2, palette_dark.grey4),

  light_normal   = get_contrast_ratio(palette_dark.grey2, palette_light.grey2),
  light_cur_line = get_contrast_ratio(palette_dark.grey2, palette_light.grey3),
  light_visual   = get_contrast_ratio(palette_dark.grey2, palette_light.grey4),

  dark_comment     = get_contrast_ratio(palette_light.grey4, palette_dark.grey2),
  dark_comment_cur = get_contrast_ratio(palette_light.grey4, palette_dark.grey3),
  dark_comment_vis = get_contrast_ratio(palette_light.grey4, palette_dark.grey4),

  light_comment     = get_contrast_ratio(palette_dark.grey4, palette_light.grey2),
  light_comment_cur = get_contrast_ratio(palette_dark.grey4, palette_light.grey3),
  light_comment_vis = get_contrast_ratio(palette_dark.grey4, palette_light.grey4),

  dark_red  = get_contrast_ratio(palette_light.red, palette_dark.grey2),
  light_red = get_contrast_ratio(palette_dark.red, palette_light.grey2),

  dark_yellow  = get_contrast_ratio(palette_light.yellow, palette_dark.grey2),
  light_yellow = get_contrast_ratio(palette_dark.yellow, palette_light.grey2),

  dark_green  = get_contrast_ratio(palette_light.green, palette_dark.grey2),
  light_green = get_contrast_ratio(palette_dark.green, palette_light.grey2),

  dark_cyan  = get_contrast_ratio(palette_light.cyan, palette_dark.grey2),
  light_cyan = get_contrast_ratio(palette_dark.cyan, palette_light.grey2),

  dark_blue  = get_contrast_ratio(palette_light.blue, palette_dark.grey2),
  light_blue = get_contrast_ratio(palette_dark.blue, palette_light.grey2),

  dark_magenta  = get_contrast_ratio(palette_light.magenta, palette_dark.grey2),
  light_magenta = get_contrast_ratio(palette_dark.magenta, palette_light.grey2),
}

-- Buffer with data ===========================================================
local table_to_lines = function(tbl)
  local keys = vim.tbl_keys(tbl)
  table.sort(keys)

  -- Compute key_width for a pretty alignment
  local key_width = 0
  for _, key in ipairs(keys) do
    key_width = math.max(key_width, key:len())
  end

  local formatstring = '%-' .. key_width .. 's = %s'
  local res = {}
  for _, key in ipairs(keys) do
    local value_str = vim.inspect(tbl[key], { newline = ' ', indent = '' })
    table.insert(res, string.format(formatstring, key, value_str))
  end

  return res
end

--stylua: ignore
local color_src_names = {
  blue    = 'Blue',
  cyan    = 'Cyan',
  green   = 'Green',
  grey1   = 'Grey1',
  grey2   = 'Grey2',
  grey3   = 'Grey3',
  grey4   = 'Grey4',
  magenta = 'Magenta',
  red     = 'Red',
  yellow  = 'Yellow',
}
local color_names = vim.tbl_keys(color_src_names)
table.sort(color_names)

local make_color_def_lines = function(bg, palette, palette_8bit)
  local prefix = bg == 'dark' and 'NvimDark' or 'NvimLight'
  local res = {}
  for _, color in ipairs(color_names) do
    local r, g, b = palette[color]:match('^#(..)(..)(..)$')
    local cterm_color = palette_8bit[color]
    --stylua: ignore
    local src_l = string.format(
      '{ "%s%s", RGB_(0x%s, 0x%s, 0x%s) }, // cterm=%d',
      prefix, color_src_names[color], r, g, b, cterm_color
    )
    table.insert(res, src_l)
  end

  return res
end

local make_color_use_lines = function(bg, palette_8bit)
  local res = {}
  for _, color in ipairs(color_names) do
    -- Produce color usage for dark background
    local src_name = (bg == 'dark' and 'NvimDark' or 'NvimLight') .. color_src_names[color]
    local suffix = bg == 'dark' and 'bg' or 'fg'
    local gui = string.format('gui%s=%s', suffix, src_name)
    local cterm = string.format('cterm%s=%s', suffix, palette_8bit[color])
    table.insert(res, gui .. ' ' .. cterm)
  end

  return res
end

local create_data_buffer = function()
  -- Create buffer lines
  local lines = {}

  vim.list_extend(lines, { '--- Hex palettes ---' })
  vim.list_extend(lines, { 'Dark:' })
  vim.list_extend(lines, table_to_lines(palette_dark))
  vim.list_extend(lines, { '' })
  vim.list_extend(lines, { 'Light:' })
  vim.list_extend(lines, table_to_lines(palette_light))
  vim.list_extend(lines, { '', '' })

  vim.list_extend(lines, { '--- Contrast ratios ---' })
  vim.list_extend(lines, table_to_lines(contrast_ratios))
  vim.list_extend(lines, { '', '' })

  vim.list_extend(lines, { '--- 8-bit palettes ---' })
  vim.list_extend(lines, { 'Dark:' })
  vim.list_extend(lines, table_to_lines(cterm_palette_dark))
  vim.list_extend(lines, { '' })
  vim.list_extend(lines, { 'Light:' })
  vim.list_extend(lines, table_to_lines(cterm_palette_light))
  vim.list_extend(lines, { '', '' })

  vim.list_extend(lines, { '--- Oklch palettes ---' })
  vim.list_extend(lines, { 'Dark:' })
  vim.list_extend(lines, table_to_lines(oklch_palette_dark))
  vim.list_extend(lines, { '' })
  vim.list_extend(lines, { 'Light:' })
  vim.list_extend(lines, table_to_lines(oklch_palette_light))
  vim.list_extend(lines, { '', '' })

  vim.list_extend(lines, { "--- 'src/nvim/highlight_group.c' code ---" })
  vim.list_extend(lines, make_color_def_lines('dark', palette_dark, cterm_palette_dark))
  vim.list_extend(lines, make_color_def_lines('light', palette_light, cterm_palette_light))
  vim.list_extend(lines, { '' })
  vim.list_extend(lines, make_color_use_lines('dark', cterm_palette_dark))
  vim.list_extend(lines, make_color_use_lines('light', cterm_palette_light))

  -- Create and set buffer
  local buf_id = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(buf_id)
end

if show_data_buffer then create_data_buffer() end

-- Highlight groups ===========================================================
-- A function which defines highlight groups same way as the PR.
-- Uncomment later call to this function for quick prototyping.

local enable_colorscheme = function()
  vim.cmd('hi clear')
  vim.g.colors_name = 'neovim_colors'

  -- In 'background=dark' dark colors are used for background and light - for
  -- foreground. In 'background=light' they reverse.
  -- Inline comments show basic highlight group assuming dark background

  local is_dark = vim.o.background == 'dark'
  local bg = is_dark and palette_dark or palette_light
  local fg = is_dark and palette_light or palette_dark

  -- Source for actual groups: 'src/nvim/highlight_group.c' in Neovim source code
  --stylua: ignore start
  local hi = function(name, data) vim.api.nvim_set_hl(0, name, data) end

  -- General UI
  hi('ColorColumn',          { fg=nil,       bg=bg.grey4 })
  hi('Conceal',              { fg=bg.grey4,  bg=nil })
  hi('CurSearch',            { fg=bg.grey1,  bg=fg.yellow })
  hi('Cursor',               { fg=nil,       bg=nil })
  hi('CursorColumn',         { fg=nil,       bg=bg.grey3 })
  hi('CursorIM',             { link='Cursor' })
  hi('CursorLine',           { fg=nil,       bg=bg.grey3 })
  hi('CursorLineFold',       { link='FoldColumn' })
  hi('CursorLineNr',         { fg=nil,       bg=nil,      bold=true })
  hi('CursorLineSign',       { link='SignColumn' })
  hi('DiffAdd',              { fg=fg.grey1,  bg=bg.green })
  hi('DiffChange',           { fg=fg.grey1,  bg=bg.grey4 })
  hi('DiffDelete',           { fg=fg.red,    bg=nil,      bold=true })
  hi('DiffText',             { fg=fg.grey1,  bg=bg.cyan })
  hi('Directory',            { fg=fg.cyan,   bg=nil })
  hi('EndOfBuffer',          { link='NonText' })
  hi('ErrorMsg',             { fg=fg.red,    bg=nil })
  hi('FloatBorder',          { link='NormalFloat' })
  hi('FloatFooter',          { link='FloatTitle' })
  hi('FloatShadow',          { fg=nil,       bg=bg.grey4, blend=80 })
  hi('FloatShadowThrough',   { fg=nil,       bg=bg.grey4, blend=100 })
  hi('FloatTitle',           { link='Title' })
  hi('FoldColumn',           { link='SignColumn' })
  hi('Folded',               { fg=fg.grey4,  bg=bg.grey3 })
  hi('IncSearch',            { link='CurSearch' })
  hi('lCursor',              { fg=bg.grey2,  bg=fg.grey2 })
  hi('LineNr',               { fg=bg.grey4,  bg=nil })
  hi('LineNrAbove',          { link='LineNr' })
  hi('LineNrBelow',          { link='LineNr' })
  hi('MatchParen',           { fg=nil,       bg=bg.grey4, bold=true })
  hi('ModeMsg',              { fg=fg.green,  bg=nil })
  hi('MoreMsg',              { fg=fg.cyan,   bg=nil })
  hi('MsgArea',              { fg=nil,       bg=nil })
  hi('MsgSeparator',         { link='StatusLine' })
  hi('NonText',              { fg=bg.grey4,  bg=nil })
  hi('Normal',               { fg=fg.grey2,  bg=bg.grey2 })
  hi('NormalFloat',          { fg=nil,  bg=bg.grey1 })
  hi('NormalNC',             { fg=nil,       bg=nil })
  hi('PMenu',                { fg=nil,  bg=bg.grey3 })
  hi('PMenuExtra',           { link='PMenu' })
  hi('PMenuExtraSel',        { link='PMenuSel' })
  hi('PMenuKind',            { link='PMenu' })
  hi('PMenuKindSel',         { link='PMenuSel' })
  hi('PMenuSbar',            { link='PMenu' })
  hi('PMenuSel',             { fg=bg.grey3,  bg=fg.grey2, blend=0 })
  hi('PMenuThumb',           { fg=nil,       bg=bg.grey4 })
  hi('Question',             { fg=fg.cyan,   bg=nil })
  hi('QuickFixLine',         { fg=fg.cyan,   bg=nil })
  hi('RedrawDebugNormal',    { fg=nil,       bg=nil,      reverse=true })
  hi('RedrawDebugClear',     { fg=nil,       bg=bg.cyan })
  hi('RedrawDebugComposed',  { fg=nil,       bg=bg.green })
  hi('RedrawDebugRecompose', { fg=nil,       bg=bg.red })
  hi('Search',               { fg=fg.grey1,  bg=bg.yellow})
  hi('SignColumn',           { fg=bg.grey4,  bg=nil })
  hi('SpecialKey',           { fg=bg.grey4,  bg=nil })
  hi('SpellBad',             { fg=nil,       bg=nil,      sp=fg.red,    undercurl=true })
  hi('SpellCap',             { fg=nil,       bg=nil,      sp=fg.yellow, undercurl=true })
  hi('SpellLocal',           { fg=nil,       bg=nil,      sp=fg.green,  undercurl=true })
  hi('SpellRare',            { fg=nil,       bg=nil,      sp=fg.cyan,   undercurl=true })
  hi('StatusLine',           { fg=fg.grey3,  bg=bg.grey1 })
  hi('StatusLineNC',         { fg=fg.grey4,  bg=bg.grey1 })
  hi('Substitute',           { link='Search' })
  hi('TabLine',              { fg=fg.grey3,  bg=bg.grey1 })
  hi('TabLineFill',          { link='Tabline' })
  hi('TabLineSel',           { fg=nil,       bg=nil,      bold = true })
  hi('TermCursor',           { fg=nil,       bg=nil,      reverse=true })
  hi('TermCursorNC',         { fg=nil,       bg=nil })
  hi('Title',                { fg=nil,       bg=nil,      bold=true })
  hi('VertSplit',            { link='WinSeparator' })
  hi('Visual',               { fg=nil,       bg=bg.grey4 })
  hi('VisualNOS',            { link='Visual' })
  hi('WarningMsg',           { fg=fg.yellow, bg=nil })
  hi('Whitespace',           { link='NonText' })
  hi('WildMenu',             { link='PMenuSel' })
  hi('WinBar',               { link='StatusLine' })
  hi('WinBarNC',             { link='StatusLineNC' })
  hi('WinSeparator',         { link='Normal' })

  -- Syntax (`:h group-name`)
  hi('Comment', { fg=fg.grey4, bg=nil })

  hi('Constant',  { fg=nil, bg=nil })
  hi('String',    { fg=fg.green, bg=nil })
  hi('Character', { link='Constant' })
  hi('Number',    { link='Constant' })
  hi('Boolean',   { link='Constant' })
  hi('Float',     { link='Number' })

  hi('Identifier', { fg=fg.blue, bg=nil }) -- frequent but important to get "main" branded color
  hi('Function',   { fg=fg.cyan, bg=nil }) -- not so frequent but important to get "main" branded color

  hi('Statement',   { fg=nil, bg=nil, bold=true }) -- bold choice (get it?) for accessibility
  hi('Conditional', { link='Statement' })
  hi('Repeat',      { link='Statement' })
  hi('Label',       { link='Statement' })
  hi('Operator',    { fg=nil, bg=nil }) -- seems too much to be bold for mostly singl-character words
  hi('Keyword',     { link='Statement' })
  hi('Exception',   { link='Statement' })

  hi('PreProc',   { fg=nil, bg=nil })
  hi('Include',   { link='PreProc' })
  hi('Define',    { link='PreProc' })
  hi('Macro',     { link='PreProc' })
  hi('PreCondit', { link='PreProc' })

  hi('Type',         { fg=nil, bg=nil })
  hi('StorageClass', { link='Type' })
  hi('Structure',    { link='Type' })
  hi('Typedef',      { link='Type' })

  hi('Special',        { fg=fg.cyan, bg=nil }) -- not so frequent but important to get "main" branded color
  hi('Tag',            { link='Special' })
  hi('SpecialChar',    { link='Special' })
  hi('Delimiter',      { fg=nil,     bg=nil })
  hi('SpecialComment', { link='Special' })
  hi('Debug',          { link='Special' })

  hi('LspInlayHint',   { link='NonText' })
  hi('SnippetTabstop', { link='Visual'  })

  hi('Underlined', { fg=nil,      bg=nil, underline=true })
  hi('Ignore',     { link='Normal' })
  hi('Error',      { fg=bg.grey1, bg=fg.red })
  hi('Todo',       { fg=fg.grey1, bg=nil, bold=true })

  hi('diffAdded',   { fg=fg.green, bg=nil })
  hi('diffRemoved', { fg=fg.red,   bg=nil })

  -- Built-in diagnostic
  hi('DiagnosticError', { fg=fg.red,    bg=nil })
  hi('DiagnosticWarn',  { fg=fg.yellow, bg=nil })
  hi('DiagnosticInfo',  { fg=fg.cyan,   bg=nil })
  hi('DiagnosticHint',  { fg=fg.blue,   bg=nil })
  hi('DiagnosticOk',    { fg=fg.green,  bg=nil })

  hi('DiagnosticUnderlineError', { fg=nil, bg=nil, sp=fg.red,    underline=true })
  hi('DiagnosticUnderlineWarn',  { fg=nil, bg=nil, sp=fg.yellow, underline=true })
  hi('DiagnosticUnderlineInfo',  { fg=nil, bg=nil, sp=fg.cyan,   underline=true })
  hi('DiagnosticUnderlineHint',  { fg=nil, bg=nil, sp=fg.blue,   underline=true })
  hi('DiagnosticUnderlineOk',    { fg=nil, bg=nil, sp=fg.green,  underline=true })

  hi('DiagnosticFloatingError', { fg=fg.red,    bg=bg.grey1 })
  hi('DiagnosticFloatingWarn',  { fg=fg.yellow, bg=bg.grey1 })
  hi('DiagnosticFloatingInfo',  { fg=fg.cyan,   bg=bg.grey1 })
  hi('DiagnosticFloatingHint',  { fg=fg.blue,   bg=bg.grey1 })
  hi('DiagnosticFloatingOk',    { fg=fg.green,  bg=bg.grey1 })

  hi('DiagnosticVirtualTextError', { link='DiagnosticError' })
  hi('DiagnosticVirtualTextWarn',  { link='DiagnosticWarn' })
  hi('DiagnosticVirtualTextInfo',  { link='DiagnosticInfo' })
  hi('DiagnosticVirtualTextHint',  { link='DiagnosticHint' })
  hi('DiagnosticVirtualTextOk',    { link='DiagnosticOk' })

  hi('DiagnosticSignError', { link='DiagnosticError' })
  hi('DiagnosticSignWarn',  { link='DiagnosticWarn' })
  hi('DiagnosticSignInfo',  { link='DiagnosticInfo' })
  hi('DiagnosticSignHint',  { link='DiagnosticHint' })
  hi('DiagnosticSignOk',    { link='DiagnosticOk' })

  hi('DiagnosticDeprecated',  { fg=nil, bg=nil, sp=fg.red, strikethrough=true })
  hi('DiagnosticUnnecessary', { link='Comment' })

  -- Tree-sitter
  -- - Text
  hi('@text.literal',   { link='Comment' })
  hi('@text.reference', { link='Identifier' })
  hi('@text.title',     { link='Title' })
  hi('@text.uri',       { link='Underlined' })
  hi('@text.underline', { link='Underlined' })
  hi('@text.todo',      { link='Todo' })

  -- - Miscs
  hi('@comment',     { link='Comment' })
  hi('@punctuation', { link='Delimiter' })

  -- - Constants
  hi('@constant',          { link='Constant' })
  hi('@constant.builtin',  { link='Special' })
  hi('@constant.macro',    { link='Define' })
  hi('@define',            { link='Define' })
  hi('@macro',             { link='Macro' })
  hi('@string',            { link='String' })
  hi('@string.escape',     { link='SpecialChar' })
  hi('@string.special',    { link='SpecialChar' })
  hi('@character',         { link='Character' })
  hi('@character.special', { link='SpecialChar' })
  hi('@number',            { link='Number' })
  hi('@boolean',           { link='Boolean' })
  hi('@float',             { link='Float' })

  -- - Functions
  hi('@function',         { link='Function' })
  hi('@function.builtin', { link='Special' })
  hi('@function.macro',   { link='Macro' })
  hi('@parameter',        { link='Identifier' })
  hi('@method',           { link='Function' })
  hi('@field',            { link='Identifier' })
  hi('@property',         { link='Identifier' })
  hi('@constructor',      { link='Special' })

  -- - Keywords
  hi('@conditional', { link='Conditional' })
  hi('@repeat',      { link='Repeat' })
  hi('@label',       { link='Label' })
  hi('@operator',    { link='Operator' })
  hi('@keyword',     { link='Keyword' })
  hi('@exception',   { link='Exception' })

  hi('@variable',        { fg=nil, bg=nil }) -- using default foreground reduces visual overload
  hi('@type',            { link='Type' })
  hi('@type.definition', { link='Typedef' })
  hi('@storageclass',    { link='StorageClass' })
  hi('@namespace',       { link='Identifier' })
  hi('@include',         { link='Include' })
  hi('@preproc',         { link='PreProc' })
  hi('@debug',           { link='Debug' })
  hi('@tag',             { link='Tag' })

  -- - LSP semantic tokens
  hi('@lsp.type.class',         { link='Structure' })
  hi('@lsp.type.comment',       { link='Comment' })
  hi('@lsp.type.decorator',     { link='Function' })
  hi('@lsp.type.enum',          { link='Structure' })
  hi('@lsp.type.enumMember',    { link='Constant' })
  hi('@lsp.type.function',      { link='Function' })
  hi('@lsp.type.interface',     { link='Structure' })
  hi('@lsp.type.macro',         { link='Macro' })
  hi('@lsp.type.method',        { link='Function' })
  hi('@lsp.type.namespace',     { link='Structure' })
  hi('@lsp.type.parameter',     { link='Identifier' })
  hi('@lsp.type.property',      { link='Identifier' })
  hi('@lsp.type.struct',        { link='Structure' })
  hi('@lsp.type.type',          { link='Type' })
  hi('@lsp.type.typeParameter', { link='TypeDef' })
  hi('@lsp.type.variable',      { link='@variable' }) -- links to tree-sitter group to reduce overload

  -- Terminal colors (not ideal)
  vim.g.terminal_color_0  = bg.grey2
  vim.g.terminal_color_1  = fg.red
  vim.g.terminal_color_2  = fg.green
  vim.g.terminal_color_3  = fg.yellow
  vim.g.terminal_color_4  = fg.blue
  vim.g.terminal_color_5  = fg.magenta
  vim.g.terminal_color_6  = fg.cyan
  vim.g.terminal_color_7  = fg.grey2
  vim.g.terminal_color_8  = bg.grey2
  vim.g.terminal_color_9  = fg.red
  vim.g.terminal_color_10 = fg.green
  vim.g.terminal_color_11 = fg.yellow
  vim.g.terminal_color_12 = fg.blue
  vim.g.terminal_color_13 = fg.magenta
  vim.g.terminal_color_14 = fg.cyan
  vim.g.terminal_color_15 = fg.grey2
  --stylua: ignore end
end

-- Comment this to not enable color scheme
if apply_colorscheme then enable_colorscheme() end
