-- Code for tweaking new default Neovim color scheme for PR #?????
-- It defines an overall look based on a handful of hyperparameters.
--
-- General goals:
-- - Be "Neovim branded", i.e. follow outlined example from
--   https://github.com/neovim/neovim/issues/14790
--   That generally means to have two main hues (green and cyan) plus at least
--   one reserved for very occasional attention (red/error and yellow/warning).
-- - Be accessible, i.e. have enough contrast ratios (CR):
--     - Fully passable `Normal` highlight group: CR>=7.
--     - Passable `Visual` highlight group (with `Normal` foreground): CR>=4.5.
--     - Passable comment in current line (foreground from `Comment` and
--       background from `CursorLine`): CR>=4.5.
--     - Passable diff highlight groups: CR>=4.5.
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
-- Reference values for lightness, chroma and hue in Oklch color space.
-- All of them result into passable accessibility requirements.
-- Use "colored greys" (very desaturated colors) as main UI colors. It adds at
-- least some character to the color scheme.

-- Dark lightness is taken from #14790 (as lightness of #1e1e1e).
-- Light lightness is taken so that to have passable contrast ratios but not
-- have too much contrast.
local l = { dark = 13, light = 85 }

-- Chroma values are chosen experimentally
local c = { grey = 1, low = 3, mid = 10, high = 15 }

-- Grey is taken to generally have "cold" UI. Tweak to get a different feel:
-- 90 for warm, 180 for neutral green, 0 for neutral pink.
-- Red hue is taken roughly the same as in reference #D96D6A
-- Green hue is taken roughly the same as in reference #87FFAF
-- Cyan hue is taken roughly the same as in reference #00E6E6
local h = { grey = 225, red = 25, yellow = 90, green = 150, cyan = 195 }

-- Palettes ===================================================================
local convert = function(L, C, H) return colors.convert({ l = L, c = C, h = H }, 'hex', { gamut_clip = 'cusp' }) end

--stylua: ignore
local palette_dark = {
  grey1      = convert(0.5  * l.dark + 0.5  * 0,       c.grey, h.grey),  -- NormalFloat
  grey2      = convert(1.0  * l.dark + 0.0  * l.light, c.grey, h.grey),  -- Normal bg
  grey3      = convert(0.9 * l.dark + 0.1 * l.light, c.grey, h.grey),  -- CursorLine
  grey4      = convert(0.7  * l.dark + 0.3  * l.light, c.grey, h.grey),  -- Visual

  red        = convert(l.dark, c.high, h.red),    -- DiffDelete
  red_dim    = convert(l.dark, c.mid,  h.red),
  yellow     = convert(l.dark, c.high, h.yellow), -- Search
  yellow_dim = convert(l.dark, c.mid,  h.yellow),
  green      = convert(l.dark, c.high, h.green),  -- DiffAdd
  green_dim  = convert(l.dark, c.mid,  h.green),
  cyan       = convert(l.dark, c.high, h.cyan),   -- DiffChange
  cyan_dim   = convert(l.dark, c.mid,  h.cyan),
}

--stylua: ignore
local palette_light = {
  grey1      = convert(0.5  * l.light + 0.5  * 100,    c.grey, h.grey),
  grey2      = convert(1.0  * l.light + 0.0  * l.dark, c.grey, h.grey), -- Normal fg
  grey3      = convert(0.9  * l.light + 0.1 * l.dark, c.grey, h.grey),
  grey4      = convert(0.7  * l.light + 0.3  * l.dark, c.grey, h.grey), -- Comment

  red        = convert(l.light, c.mid, h.red),    -- DiagnosticError
  red_dim    = convert(l.light, c.low, h.red),
  yellow     = convert(l.light, c.mid, h.yellow), -- DiagnosticWarn
  yellow_dim = convert(l.light, c.low, h.yellow),
  green      = convert(l.light, c.mid, h.green),  -- String,     DiagnosticOk
  green_dim  = convert(l.light, c.low, h.green),  -- Identifier, DiagnosticHint
  cyan       = convert(l.light, c.mid, h.cyan),   -- Function,   DiagnosticInfo
  cyan_dim   = convert(l.light, c.low, h.cyan),   -- Special
}

-- 8-bit color approximations =================================================
local convert_to_8bit = function(hex) return require('mini.colors').convert(hex, '8-bit') end

local cterm_palette_dark = vim.tbl_map(convert_to_8bit, palette_dark)
local cterm_palette_light = vim.tbl_map(convert_to_8bit, palette_light)

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
  return math.floor(10 * res + 0.5) / 10
end

--stylua: ignore
local contrast_ratios = {
  dark_normal   = get_contrast_ratio(palette_light.grey2, palette_dark.grey2),
  dark_cur_line = get_contrast_ratio(palette_light.grey2, palette_dark.grey3),
  dark_visual   = get_contrast_ratio(palette_light.grey2, palette_dark.grey4),

  dark_comment     = get_contrast_ratio(palette_light.grey4, palette_dark.grey2),
  dark_comment_cur = get_contrast_ratio(palette_light.grey4, palette_dark.grey3),
  dark_comment_vis = get_contrast_ratio(palette_light.grey4, palette_dark.grey4),

  light_normal   = get_contrast_ratio(palette_dark.grey2, palette_light.grey2),
  light_cur_line = get_contrast_ratio(palette_dark.grey2, palette_light.grey3),
  light_visual   = get_contrast_ratio(palette_dark.grey2, palette_light.grey4),

  light_comment     = get_contrast_ratio(palette_dark.grey4, palette_light.grey2),
  light_comment_cur = get_contrast_ratio(palette_dark.grey4, palette_light.grey3),
  light_comment_vis = get_contrast_ratio(palette_dark.grey4, palette_light.grey4),

  red    = get_contrast_ratio(palette_light.red, palette_dark.grey2),
  red_bg = get_contrast_ratio(palette_light.grey2, palette_dark.red),

  yellow    = get_contrast_ratio(palette_light.yellow, palette_dark.grey2),
  yellow_bg = get_contrast_ratio(palette_light.grey2, palette_dark.yellow),

  green    = get_contrast_ratio(palette_light.green, palette_dark.grey2),
  green_bg = get_contrast_ratio(palette_light.grey2, palette_dark.green),

  cyan    = get_contrast_ratio(palette_light.cyan, palette_dark.grey2),
  cyan_bg = get_contrast_ratio(palette_light.grey2, palette_dark.cyan),
}

-- Buffer with data ===========================================================
-- Create buffer lines
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
    table.insert(res, string.format(formatstring, key, vim.inspect(tbl[key])))
  end

  return res
end

local make_src_definition_lines = function(p_dark, p_light)
  -- TODO
  return {}
end

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

vim.list_extend(lines, { "--- 'src/nvim/highlight_group.c' code ---" })
vim.list_extend(lines, make_src_definition_lines(palette_dark, palette_light))

-- -- Create and set buffer
-- local buf_id = vim.api.nvim_create_buf(true, true)
-- vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
-- vim.api.nvim_set_current_buf(buf_id)

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
  hi('ColorColumn',          { fg=nil,          bg=bg.grey4 })
  hi('Conceal',              { fg=fg.cyan,      bg=nil })
  hi('CurSearch',            { link='Search' })
  hi('Cursor',               { fg=bg.grey2,     bg=fg.grey2 })
  hi('CursorColumn',         { fg=nil,          bg=bg.grey3 })
  hi('CursorIM',             { fg=bg.grey2,     bg=fg.grey2 })
  hi('CursorLine',           { fg=nil,          bg=bg.grey3 })
  hi('CursorLineFold',       { fg=bg.grey4,     bg=nil })
  hi('CursorLineNr',         { fg=nil,          bg=nil,      bold=true })
  hi('CursorLineSign',       { fg=bg.grey4,     bg=nil })
  hi('DiffAdd',              { fg=nil,          bg=bg.green })
  hi('DiffChange',           { fg=nil,          bg=bg.grey4 })
  hi('DiffDelete',           { fg=nil,          bg=bg.red })
  hi('DiffText',             { fg=nil,          bg=bg.cyan })
  hi('Directory',            { fg=fg.cyan,      bg=nil })
  hi('EndOfBuffer',          { fg=bg.grey4,     bg=nil })
  hi('ErrorMsg',             { fg=fg.red,       bg=nil })
  hi('FloatBorder',          { fg=nil,          bg=bg.grey1 })
  hi('FloatTitle',           { link='Title' })
  hi('FloatShadow',          { fg=bg.grey1,     bg=nil,      blend=80 })
  hi('FloatShadowThrough',   { fg=bg.grey1,     bg=nil,      blend=100 })
  hi('FloatTitle',           { link='Title' })
  hi('FoldColumn',           { fg=bg.grey33,    bg=nil })
  hi('Folded',               { fg=fg.grey4,     bg=bg.grey3 })
  hi('IncSearch',            { link='Search' })
  hi('lCursor',              { fg=bg.grey2,     bg=fg.grey2 })
  hi('LineNr',               { fg=bg.grey4,     bg=nil })
  hi('LineNrAbove',          { link='LineNr' })
  hi('LineNrBelow',          { link='LineNr' })
  hi('MatchParen',           { fg=nil,          bg=bg.grey4, bold=true })
  hi('ModeMsg',              { fg=fg.green,     bg=nil })
  hi('MoreMsg',              { fg=fg.cyan,      bg=nil })
  hi('MsgArea',              { link='Normal' })
  hi('MsgSeparator',         { fg=fg.grey4,     bg=bg.grey4 })
  hi('NonText',              { fg=bg.grey4,     bg=nil })
  hi('Normal',               { fg=fg.grey2,     bg=bg.grey2 })
  hi('NormalFloat',          { fg=fg.grey2,     bg=bg.grey1 })
  hi('NormalNC',             { link='Normal' })
  hi('PMenu',                { fg=fg.grey2,     bg=bg.grey3 })
  hi('PMenuExtra',           { link='PMenu' })
  hi('PMenuExtraSel',        { link='PMenuSel' })
  hi('PMenuKind',            { link='PMenu' })
  hi('PMenuKindSel',         { link='PMenuSel' })
  hi('PMenuSbar',            { link='PMenu' })
  hi('PMenuSel',             { fg=bg.grey2,     bg=fg.grey2, blend=0 })
  hi('PMenuThumb',           { fg=nil,          bg=bg.grey4 })
  hi('Question',             { fg=fg.cyan,      bg=nil })
  hi('QuickFixLine',         { fg=nil,          bg=bg.grey3 })
  hi('RedrawDebugNormal',    { fg=nil,          bg=nil,      reverse=true })
  hi('RedrawDebugClear',     { fg=nil,          bg=bg.cyan })
  hi('RedrawDebugComposed',  { fg=nil,          bg=bg.green })
  hi('RedrawDebugRecompose', { fg=nil,          bg=bg.red })
  hi('Search',               { fg=bg.grey2,     bg=fg.yellow })
  hi('SignColumn',           { fg=bg.grey33,    bg=nil })
  hi('SpecialKey',           { fg=bg.grey4,     bg=nil })
  hi('SpellBad',             { fg=nil,          bg=nil,      sp=fg.red,    undercurl=true })
  hi('SpellCap',             { fg=nil,          bg=nil,      sp=fg.yellow, undercurl=true })
  hi('SpellLocal',           { fg=nil,          bg=nil,      sp=fg.green,  undercurl=true })
  hi('SpellRare',            { fg=nil,          bg=nil,      sp=fg.cyan,   undercurl=true })
  hi('StatusLine',           { fg=fg.grey3,     bg=bg.grey1 })
  hi('StatusLineNC',         { fg=fg.grey4,     bg=bg.grey1 })
  hi('Substitute',           { fg=bg.grey2,     bg=fg.cyan })
  hi('TabLine',              { fg=fg.grey3,     bg=bg.grey1 })
  hi('TabLineFill',          { link='Tabline' })
  hi('TabLineSel',           { fg=fg.grey3,     bg=bg.grey1, bold = true })
  hi('TermCursor',           { fg=nil,          bg=nil,      reverse=true })
  hi('TermCursorNC',         { fg=nil,          bg=nil,      reverse=true })
  hi('Title',                { fg=fg.green_dim, bg=nil })
  hi('VertSplit',            { link='Normal' })
  hi('Visual',               { fg=nil,          bg=bg.grey4 })
  hi('VisualNOS',            { fg=nil,          bg=bg.grey3 })
  hi('WarningMsg',           { fg=fg.yellow,    bg=nil })
  hi('Whitespace',           { fg=bg.grey4,     bg=nil })
  hi('WildMenu',             { link='PMenuSel' })
  hi('WinBar',               { link='StatusLine' })
  hi('WinBarNC',             { link='StatusLineNC' })
  hi('WinSeparator',         { link='Normal' })

  -- Syntax (`:h group-name`)
  hi('Comment', { fg=fg.grey4, bg=nil })

  hi('Constant',  { fg=nil,      bg=nil })
  hi('String',    { fg=fg.green, bg=nil })
  hi('Character', { link='Constant' })
  hi('Number',    { link='Constant' })
  hi('Boolean',   { link='Constant' })
  hi('Float',     { link='Constant' })

  hi('Identifier', { fg=fg.green_dim, bg=nil }) -- frequent but important to get "main" branded color
  hi('Function',   { fg=fg.cyan,      bg=nil }) -- not so frequent but important to get "main" branded color

  hi('Statement',   { fg=nil,      bg=nil, bold=true }) -- bold choice (get it?) for accessibility
  hi('Conditional', { link='Statement' })
  hi('Repeat',      { link='Statement' })
  hi('Label',       { link='Statement' })
  hi('Operator',    { fg=fg.grey2, bg=nil }) -- seems too much to be bold for mostly singl-character words
  hi('Keyword',     { link='Statement' })
  hi('Exception',   { link='Statement' })

  hi('PreProc',   { fg=nil, bg=nil })
  hi('Include',   { link='PreProc' })
  hi('Define',    { link='PreProc' })
  hi('Macro',     { link='PreProc' })
  hi('PreCondit', { link='PreProc' })

  hi('Type',         { fg=fg.grey2, bg=nil })
  hi('StorageClass', { link='Type' })
  hi('Structure',    { link='Type' })
  hi('Typedef',      { link='Type' })

  hi('Special',        { fg=fg.cyan_dim, bg=nil }) -- frequent but important to get "main" branded color
  hi('SpecialChar',    { link='Special' })
  hi('Tag',            { link='Special' })
  hi('Delimiter',      { fg=nil,         bg=nil })
  hi('SpecialComment', { link='Special' })
  hi('Debug',          { link='Special' })

  hi('Underlined', { fg=nil,      bg=nil, underline=true })
  hi('Ignore',     { link='Normal' })
  hi('Error',      { fg=bg.grey2, bg=fg.red })
  hi('Todo',       { fg=fg.grey1, bg=nil, bold=true })

  hi('diffAdded',   { fg=fg.green, bg=nil })
  hi('diffRemoved', { fg=fg.red,   bg=nil })

  -- Built-in diagnostic
  hi('DiagnosticError', { fg=fg.red,       bg=nil })
  hi('DiagnosticWarn',  { fg=fg.yellow,    bg=nil })
  hi('DiagnosticInfo',  { fg=fg.cyan,      bg=nil })
  hi('DiagnosticHint',  { fg=fg.green_dim, bg=nil })
  hi('DiagnosticOk',    { fg=fg.green,     bg=nil })

  hi('DiagnosticUnderlineError', { fg=nil, bg=nil, sp=fg.red,       underline=true })
  hi('DiagnosticUnderlineWarn',  { fg=nil, bg=nil, sp=fg.yellow,    underline=true })
  hi('DiagnosticUnderlineInfo',  { fg=nil, bg=nil, sp=fg.cyan,      underline=true })
  hi('DiagnosticUnderlineHint',  { fg=nil, bg=nil, sp=fg.green_dim, underline=true })
  hi('DiagnosticUnderlineOk',    { fg=nil, bg=nil, sp=fg.green,     underline=true })

  hi('DiagnosticFloatingError', { fg=fg.red,       bg=bg.grey1 })
  hi('DiagnosticFloatingWarn',  { fg=fg.yellow,    bg=bg.grey1 })
  hi('DiagnosticFloatingInfo',  { fg=fg.cyan,      bg=bg.grey1 })
  hi('DiagnosticFloatingHint',  { fg=fg.green_dim, bg=bg.grey1 })
  hi('DiagnosticFloatingOk',    { fg=fg.green,     bg=bg.grey1 })

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

  hi('@variable',        { fg=fg.grey2, bg=nil }) -- using default foreground reduces visual overload
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
  vim.g.terminal_color_1  = fg.red -- red
  vim.g.terminal_color_2  = fg.green -- green
  vim.g.terminal_color_3  = fg.yellow -- yellow
  vim.g.terminal_color_4  = fg.cyan_dim -- blue
  vim.g.terminal_color_5  = fg.red_dim -- magenta
  vim.g.terminal_color_6  = fg.cyan -- cyan
  vim.g.terminal_color_7  = fg.grey2
  vim.g.terminal_color_8  = bg.grey2
  vim.g.terminal_color_9  = fg.red
  vim.g.terminal_color_10 = fg.green
  vim.g.terminal_color_11 = fg.yellow
  vim.g.terminal_color_12 = fg.cyan_dim
  vim.g.terminal_color_13 = fg.red_dim
  vim.g.terminal_color_14 = fg.cyan
  vim.g.terminal_color_15 = fg.grey2
  --stylua: ignore end
end

-- Comment this to not enable color scheme
enable_colorscheme()
