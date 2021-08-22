-- MIT License Copyright (c) 2021 Evgeni Chasnovski
--
-- Custom *minimal* and *fast* Lua module which implements
-- [base16](http://chriskempson.com/projects/base16/) color scheme (with
-- Copyright (C) 2012 Chris Kempson)
--
-- This module doesn't need to get activated. Call to `setup()` will create
-- global `MiniBase16` object. Use its functions as with normal Lua modules.
--
-- Default `config`: {} (currently nothing to configure)
--
-- Features:
-- - `apply(palette, name)` applies base16 `palette` by creating Neovim's
--   highlight groups and sets `g:colors_name` to `name` ('base16-custom' by
--   default). Highlight groups make an extended set from original
--   [base16-vim](https://github.com/chriskempson/base16-vim/) plugin. It is a
--   good idea to have `palette` respect the original [styling
--   principles](https://github.com/chriskempson/base16/blob/master/styling.md).
--   Currently it only supports 'gui colors' (see `:h 'termguicolors'`).
-- - `mini_palette(background, foreground, accent_chroma)` creates base16
--   palette based on the HEX (string '#RRGGBB') colors of main background and
--   foreground with optional setting of accent chroma (see details). Exact
--   algorithm is based on certain heuristics:
--     - Main operating color space is
--       [CIELCh(uv)](https://en.wikipedia.org/wiki/CIELUV#Cylindrical_representation_(CIELCh))
--       which is a cylindrical representation of a perceptually uniform CIELUV
--       color space. It defines color by three values: lightness L (values
--       from 0 to 100), chroma (positive values), and hue (circular values
--       from 0 to 360 degress). Useful converting tool:
--       https://www.easyrgb.com/en/convert.php
--     - There are four important lightness values: background, foreground,
--       focus (around the middle of background and foreground, leaning towards
--       foreground), and edge (extreme lightness closest to foreground).
--     - First four colors have the same chroma and hue as `background` but
--       lightness progresses from background towards focus.
--     - Second four colors have the same chroma and hue as `foreground` but
--       lightness progresses from foreground towards edge in such a way that
--       'base05' color is main text color.
--     - The rest eight colors are accent colors which are created in pairs
--         - Each pair has same hue from set of hues 'most different' to
--           background and foreground hues (if respective chorma is positive).
--         - All colors have the same chroma equal to `accent_chroma` (if not
--           provided, chroma of foreground is used, as they will appear next
--           to each other). NOTE: this means that in case of low foreground
--           chroma, it is a good idea to set `accent_chroma` manually.
--           Values from 30 (low chorma) to 80 (high chroma) are common.
--         - Within pair there is base lightness (equal to foreground
--           lightness) and alternative (equal to focus lightness). Base
--           lightness goes to colors which will be used more frequently in
--           code: base08 (variables), base0B (strings), base0D (functions),
--           base0E (keywords).
--       How exactly accent colors are mapped to 'base16' colors is a result of
--       trial and error. One rule of thumb was: colors within one hue pair
--       should be more often seen next to each other. This is because it is
--       easier to distinguish them and seems to be more visually appealing.
--       That is why `base0D` (14) and `base0F` (16) have same hues because
--       they usually represent functions and delimiter (brackets included).

-- Module and its helper
local MiniBase16 = {}
local H = {}

-- Module setup
function MiniBase16.setup(config)
  -- Export module
  _G.MiniBase16 = MiniBase16
end

MiniBase16.palette = nil

function MiniBase16.apply(palette, name)
  -- Validate arguments
  H.validate_base16_palette(palette)
  if type(name) ~= 'string' then error('(mini.base16): `name` should be string') end

  -- Store palette
  MiniBase16.palette = palette

  -- Prepare highlighting application. Notes:
  -- - Clear current highlight only if other theme was loaded previously.
  -- - No need to `syntax reset` because *all* syntax groups are defined later.
  if vim.g.colors_name then vim.cmd([[highlight clear]]) end
  vim.g.colors_name = name or 'base16-custom'

  local p = palette

  -- Builtin highlighting groups. Some groups which are missing in 'base16=vim'
  -- are added based on groups to which they are linked.
  H.hi('ColorColumn',  {guifg=nil,      guibg=p.base01, gui=nil,         guisp=nil})
  H.hi('Conceal',      {guifg=p.base0D, guibg=p.base00, gui=nil,         guisp=nil})
  H.hi('Cursor',       {guifg=p.base00, guibg=p.base05, gui=nil,         guisp=nil})
  H.hi('CursorColumn', {guifg=nil,      guibg=p.base01, gui=nil,         guisp=nil})
  H.hi('CursorIM',     {guifg=p.base00, guibg=p.base05, gui=nil,         guisp=nil})
  H.hi('CursorLine',   {guifg=nil,      guibg=p.base01, gui=nil,         guisp=nil})
  H.hi('CursorLineNr', {guifg=p.base04, guibg=p.base01, gui=nil,         guisp=nil})
  H.hi('DiffAdd',      {guifg=p.base0B, guibg=p.base01, gui=nil,         guisp=nil})
  H.hi('DiffChange',   {guifg=p.base03, guibg=p.base01, gui=nil,         guisp=nil})
  H.hi('DiffDelete',   {guifg=p.base08, guibg=p.base01, gui=nil,         guisp=nil})
  H.hi('DiffText',     {guifg=p.base0D, guibg=p.base01, gui=nil,         guisp=nil})
  H.hi('Directory',    {guifg=p.base0D, guibg=nil,      gui=nil,         guisp=nil})
  H.hi('EndOfBuffer',  {guifg=p.base03, guibg=nil,      gui=nil,         guisp=nil})
  H.hi('ErrorMsg',     {guifg=p.base08, guibg=p.base00, gui=nil,         guisp=nil})
  H.hi('FoldColumn',   {guifg=p.base0C, guibg=p.base01, gui=nil,         guisp=nil})
  H.hi('Folded',       {guifg=p.base03, guibg=p.base01, gui=nil,         guisp=nil})
  H.hi('IncSearch',    {guifg=p.base01, guibg=p.base09, gui=nil,         guisp=nil})
  H.hi('LineNr',       {guifg=p.base03, guibg=p.base01, gui=nil,         guisp=nil})
  ---- Slight difference from base16, where `guibg=base03` is used. This makes
  ---- it possible to comfortably see this highlighting in comments.
  H.hi('MatchParen',   {guifg=nil,      guibg=p.base02, gui=nil,         guisp=nil})
  H.hi('ModeMsg',      {guifg=p.base0B, guibg=nil,      gui=nil,         guisp=nil})
  H.hi('MoreMsg',      {guifg=p.base0B, guibg=nil,      gui=nil,         guisp=nil})
  H.hi('MsgArea',      {guifg=p.base05, guibg=p.base00, gui=nil,         guisp=nil})
  H.hi('MsgSeparator', {guifg=p.base04, guibg=p.base02, gui=nil,         guisp=nil})
  H.hi('NonText',      {guifg=p.base03, guibg=nil,      gui=nil,         guisp=nil})
  H.hi('Normal',       {guifg=p.base05, guibg=p.base00, gui=nil,         guisp=nil})
  H.hi('NormalFloat',  {guifg=p.base05, guibg=p.base01, gui=nil,         guisp=nil})
  H.hi('NormalNC',     {guifg=p.base05, guibg=p.base00, gui=nil,         guisp=nil})
  H.hi('PMenu',        {guifg=p.base05, guibg=p.base01, gui=nil,         guisp=nil})
  H.hi('PMenuSbar',    {guifg=nil,      guibg=p.base02, gui=nil,         guisp=nil})
  H.hi('PMenuSel',     {guifg=p.base01, guibg=p.base05, gui=nil,         guisp=nil})
  H.hi('PMenuThumb',   {guifg=nil,      guibg=p.base07, gui=nil,         guisp=nil})
  H.hi('Question',     {guifg=p.base0D, guibg=nil,      gui=nil,         guisp=nil})
  H.hi('QuickFixLine', {guifg=nil,      guibg=p.base01, gui=nil,         guisp=nil})
  H.hi('Search',       {guifg=p.base01, guibg=p.base0A, gui=nil,         guisp=nil})
  H.hi('SignColumn',   {guifg=p.base03, guibg=p.base01, gui=nil,         guisp=nil})
  H.hi('SpecialKey',   {guifg=p.base03, guibg=nil,      gui=nil,         guisp=nil})
  H.hi('SpellBad',     {guifg=nil,      guibg=nil,      gui='undercurl', guisp=p.base08})
  H.hi('SpellCap',     {guifg=nil,      guibg=nil,      gui='undercurl', guisp=p.base0D})
  H.hi('SpellLocal',   {guifg=nil,      guibg=nil,      gui='undercurl', guisp=p.base0C})
  H.hi('SpellRare',    {guifg=nil,      guibg=nil,      gui='undercurl', guisp=p.base0E})
  H.hi('StatusLine',   {guifg=p.base04, guibg=p.base02, gui=nil,         guisp=nil})
  H.hi('StatusLineNC', {guifg=p.base03, guibg=p.base01, gui=nil,         guisp=nil})
  H.hi('Substitute',   {guifg=p.base01, guibg=p.base0A, gui=nil,         guisp=nil})
  H.hi('TabLine',      {guifg=p.base03, guibg=p.base01, gui=nil,         guisp=nil})
  H.hi('TabLineFill',  {guifg=p.base03, guibg=p.base01, gui=nil,         guisp=nil})
  H.hi('TabLineSel',   {guifg=p.base0B, guibg=p.base01, gui=nil,         guisp=nil})
  H.hi('TermCursor',   {guifg=nil,      guibg=nil,      gui='reverse',   guisp=nil})
  H.hi('TermCursorNC', {guifg=nil,      guibg=nil,      gui='reverse',   guisp=nil})
  H.hi('Title',        {guifg=p.base0D, guibg=nil,      gui=nil,         guisp=nil})
  H.hi('VertSplit',    {guifg=p.base02, guibg=p.base02, gui=nil,         guisp=nil})
  H.hi('Visual',       {guifg=nil,      guibg=p.base02, gui=nil,         guisp=nil})
  H.hi('VisualNOS',    {guifg=p.base08, guibg=nil,      gui=nil,         guisp=nil})
  H.hi('WarningMsg',   {guifg=p.base08, guibg=nil,      gui=nil,         guisp=nil})
  H.hi('Whitespace',   {guifg=p.base03, guibg=nil,      gui=nil,         guisp=nil})
  H.hi('WildMenu',     {guifg=p.base08, guibg=p.base0A, gui=nil,         guisp=nil})
  H.hi('lCursor',      {guifg=p.base00, guibg=p.base05, gui=nil,         guisp=nil})

  -- Standard syntax (affects treesitter)
  H.hi('Boolean',        {guifg=p.base09, guibg=nil,      gui=nil, guisp=nil})
  H.hi('Character',      {guifg=p.base08, guibg=nil,      gui=nil, guisp=nil})
  H.hi('Comment',        {guifg=p.base03, guibg=nil,      gui=nil, guisp=nil})
  H.hi('Conditional',    {guifg=p.base0E, guibg=nil,      gui=nil, guisp=nil})
  H.hi('Constant',       {guifg=p.base09, guibg=nil,      gui=nil, guisp=nil})
  H.hi('Debug',          {guifg=p.base08, guibg=nil,      gui=nil, guisp=nil})
  H.hi('Define',         {guifg=p.base0E, guibg=nil,      gui=nil, guisp=nil})
  H.hi('Delimiter',      {guifg=p.base0F, guibg=nil,      gui=nil, guisp=nil})
  H.hi('Error',          {guifg=p.base00, guibg=p.base08, gui=nil, guisp=nil})
  H.hi('Exception',      {guifg=p.base08, guibg=nil,      gui=nil, guisp=nil})
  H.hi('Float',          {guifg=p.base09, guibg=nil,      gui=nil, guisp=nil})
  H.hi('Function',       {guifg=p.base0D, guibg=nil,      gui=nil, guisp=nil})
  H.hi('Identifier',     {guifg=p.base08, guibg=nil,      gui=nil, guisp=nil})
  H.hi('Ignore',         {guifg=p.base0C, guibg=nil,      gui=nil, guisp=nil})
  H.hi('Include',        {guifg=p.base0D, guibg=nil,      gui=nil, guisp=nil})
  H.hi('Keyword',        {guifg=p.base0E, guibg=nil,      gui=nil, guisp=nil})
  H.hi('Label',          {guifg=p.base0A, guibg=nil,      gui=nil, guisp=nil})
  H.hi('Macro',          {guifg=p.base08, guibg=nil,      gui=nil, guisp=nil})
  H.hi('Number',         {guifg=p.base09, guibg=nil,      gui=nil, guisp=nil})
  H.hi('Operator',       {guifg=p.base05, guibg=nil,      gui=nil, guisp=nil})
  H.hi('PreCondit',      {guifg=p.base0A, guibg=nil,      gui=nil, guisp=nil})
  H.hi('PreProc',        {guifg=p.base0A, guibg=nil,      gui=nil, guisp=nil})
  H.hi('Repeat',         {guifg=p.base0A, guibg=nil,      gui=nil, guisp=nil})
  H.hi('Special',        {guifg=p.base0C, guibg=nil,      gui=nil, guisp=nil})
  H.hi('SpecialChar',    {guifg=p.base0F, guibg=nil,      gui=nil, guisp=nil})
  H.hi('SpecialComment', {guifg=p.base0C, guibg=nil,      gui=nil, guisp=nil})
  H.hi('Statement',      {guifg=p.base08, guibg=nil,      gui=nil, guisp=nil})
  H.hi('StorageClass',   {guifg=p.base0A, guibg=nil,      gui=nil, guisp=nil})
  H.hi('String',         {guifg=p.base0B, guibg=nil,      gui=nil, guisp=nil})
  H.hi('Structure',      {guifg=p.base0E, guibg=nil,      gui=nil, guisp=nil})
  H.hi('Tag',            {guifg=p.base0A, guibg=nil,      gui=nil, guisp=nil})
  H.hi('Todo',           {guifg=p.base0A, guibg=p.base01, gui=nil, guisp=nil})
  H.hi('Type',           {guifg=p.base0A, guibg=nil,      gui=nil, guisp=nil})
  H.hi('Typedef',        {guifg=p.base0A, guibg=nil,      gui=nil, guisp=nil})
  H.hi('Underlined',     {guifg=p.base08, guibg=nil,      gui=nil, guisp=nil})

  -- Other from 'base16-vim'
  H.hi('Bold',       {guifg=nil,      guibg=nil, gui='bold', guisp=nil})
  H.hi('Italic',     {guifg=nil,      guibg=nil, gui=nil,    guisp=nil})
  H.hi('TooLong',    {guifg=p.base08, guibg=nil, gui=nil,    guisp=nil})
  H.hi('Underlined', {guifg=p.base08, guibg=nil, gui=nil,    guisp=nil})

  -- Git diff
  H.hi("DiffAdded",   {guifg=p.base0B, guibg=p.base00, gui=nil, guisp=nil})
  H.hi("DiffFile",    {guifg=p.base08, guibg=p.base00, gui=nil, guisp=nil})
  H.hi("DiffLine",    {guifg=p.base0D, guibg=p.base00, gui=nil, guisp=nil})
  H.hi("DiffNewFile", {guifg=p.base0B, guibg=p.base00, gui=nil, guisp=nil})
  H.hi("DiffRemoved", {guifg=p.base08, guibg=p.base00, gui=nil, guisp=nil})

  -- Git commit
  H.hi("gitcommitBranch",        {guifg=p.base09, guibg=nil, gui="bold", guisp=nil})
  H.hi("gitcommitComment",       {guifg=p.base03, guibg=nil, gui=nil,    guisp=nil})
  H.hi("gitcommitDiscarded",     {guifg=p.base03, guibg=nil, gui=nil,    guisp=nil})
  H.hi("gitcommitDiscardedFile", {guifg=p.base08, guibg=nil, gui="bold", guisp=nil})
  H.hi("gitcommitDiscardedType", {guifg=p.base0D, guibg=nil, gui=nil,    guisp=nil})
  H.hi("gitcommitHeader",        {guifg=p.base0E, guibg=nil, gui=nil,    guisp=nil})
  H.hi("gitcommitOverflow",      {guifg=p.base08, guibg=nil, gui=nil,    guisp=nil})
  H.hi("gitcommitSelected",      {guifg=p.base03, guibg=nil, gui=nil,    guisp=nil})
  H.hi("gitcommitSelectedFile",  {guifg=p.base0B, guibg=nil, gui="bold", guisp=nil})
  H.hi("gitcommitSelectedType",  {guifg=p.base0D, guibg=nil, gui=nil,    guisp=nil})
  H.hi("gitcommitSummary",       {guifg=p.base0B, guibg=nil, gui=nil,    guisp=nil})
  H.hi("gitcommitUnmergedFile",  {guifg=p.base08, guibg=nil, gui="bold", guisp=nil})
  H.hi("gitcommitUnmergedType",  {guifg=p.base0D, guibg=nil, gui=nil,    guisp=nil})
  H.hi("gitcommitUntracked",     {guifg=p.base03, guibg=nil, gui=nil,    guisp=nil})
  H.hi("gitcommitUntrackedFile", {guifg=p.base0A, guibg=nil, gui=nil,    guisp=nil})

  -- Built-in LSP (similar to spelling)
  H.hi('LspDiagnosticsDefaultError',       {guifg=p.base08, guibg=p.base00, gui=nil, guisp=nil})
  H.hi('LspDiagnosticsDefaultHint',        {guifg=p.base0D, guibg=p.base00, gui=nil, guisp=nil})
  H.hi('LspDiagnosticsDefaultInformation', {guifg=p.base0C, guibg=p.base00, gui=nil, guisp=nil})
  H.hi('LspDiagnosticsDefaultWarning',     {guifg=p.base0E, guibg=p.base00, gui=nil, guisp=nil})

  H.hi('LspDiagnosticsUnderlineError',       {guifg=nil, guibg=nil, gui='underline', guisp=p.base08})
  H.hi('LspDiagnosticsUnderlineHint',        {guifg=nil, guibg=nil, gui='underline', guisp=p.base0D})
  H.hi('LspDiagnosticsUnderlineInformation', {guifg=nil, guibg=nil, gui='underline', guisp=p.base0C})
  H.hi('LspDiagnosticsUnderlineWarning',     {guifg=nil, guibg=nil, gui='underline', guisp=p.base0E})

  -- Plugins
  ---- 'mini'
  H.hi('MiniTablineCurrent',         {guifg=p.base05, guibg=p.base02, gui='bold', guisp=nil})
  H.hi('MiniTablineFill',            {guifg=nil,      guibg=nil,      gui=nil,    guisp=nil})
  H.hi('MiniTablineHidden',          {guifg=p.base04, guibg=p.base01, gui=nil,    guisp=nil})
  H.hi('MiniTablineModifiedCurrent', {guifg=p.base02, guibg=p.base05, gui='bold', guisp=nil})
  H.hi('MiniTablineModifiedHidden',  {guifg=p.base01, guibg=p.base04, gui=nil,    guisp=nil})
  H.hi('MiniTablineModifiedVisible', {guifg=p.base02, guibg=p.base04, gui='bold', guisp=nil})
  H.hi('MiniTablineVisible',         {guifg=p.base05, guibg=p.base01, gui='bold', guisp=nil})

  H.hi('MiniStatuslineDevinfo',     {guifg=p.base04, guibg=p.base02, gui=nil,    guisp=nil})
  H.hi('MiniStatuslineFileinfo',    {guifg=p.base04, guibg=p.base02, gui=nil,    guisp=nil})
  H.hi('MiniStatuslineFilename',    {guifg=p.base03, guibg=p.base01, gui=nil,    guisp=nil})
  H.hi('MiniStatuslineInactive',    {guifg=p.base03, guibg=p.base01, gui=nil,    guisp=nil})
  H.hi('MiniStatuslineModeCommand', {guifg=p.base00, guibg=p.base08, gui='bold', guisp=nil})
  H.hi('MiniStatuslineModeInsert',  {guifg=p.base00, guibg=p.base0D, gui='bold', guisp=nil})
  H.hi('MiniStatuslineModeNormal',  {guifg=p.base00, guibg=p.base05, gui='bold', guisp=nil})
  H.hi('MiniStatuslineModeOther',   {guifg=p.base00, guibg=p.base03, gui='bold', guisp=nil})
  H.hi('MiniStatuslineModeReplace', {guifg=p.base00, guibg=p.base0E, gui='bold', guisp=nil})
  H.hi('MiniStatuslineModeVisual',  {guifg=p.base00, guibg=p.base0B, gui='bold', guisp=nil})

  H.hi('MiniTrailspace', {guifg=p.base00, guibg=p.base08})
end

function MiniBase16.mini_palette(background, foreground, accent_chroma)
  H.validate_hex(background, 'background')
  H.validate_hex(foreground, 'foreground')
  if accent_chroma and not (type(accent_chroma) == 'number' and accent_chroma >= 0) then
    error('(mini.base16) `accent_chroma` should be a positive number or `nil`')
  end
  local bg, fg = H.hex2lch(background), H.hex2lch(foreground)
  accent_chroma = accent_chroma or fg.c

  local palette = {}

  -- Target lightness values
  -- Justification for skewness towards foreground in focus is mainly because
  -- it will be paired with foreground lightness and used for text.
  local focus_l = 0.4 * bg.l + 0.6 * fg.l
  local edge_l = fg.l > 50 and 99 or 1

  -- Background colors
  local bg_step = (focus_l - bg.l) / 3
  palette[1] = {l = bg.l + 0 * bg_step, c = bg.c, h = bg.h}
  palette[2] = {l = bg.l + 1 * bg_step, c = bg.c, h = bg.h}
  palette[3] = {l = bg.l + 2 * bg_step, c = bg.c, h = bg.h}
  palette[4] = {l = bg.l + 3 * bg_step, c = bg.c, h = bg.h}

  -- Foreground colors Possible negative value of `palette[5].l` will be
  -- handled in future conversion to hex.
  local fg_step = (edge_l - fg.l) / 2
  palette[5] = {l = fg.l - 1 * fg_step, c = fg.c, h = fg.h}
  palette[6] = {l = fg.l + 0 * fg_step, c = fg.c, h = fg.h}
  palette[7] = {l = fg.l + 1 * fg_step, c = fg.c, h = fg.h}
  palette[8] = {l = fg.l + 2 * fg_step, c = fg.c, h = fg.h}

  -- Accent colors
  ---- Only try to avoid color if it has positive chroma, because with zero
  ---- chroma hue is meaningless (as in polar coordinates)
  local present_hues = {}
  if bg.c > 0 then table.insert(present_hues, bg.h) end
  if fg.c > 0 then table.insert(present_hues, fg.h) end
  local hues = H.make_different_hues(present_hues, 4)

  palette[9]  = {l = fg.l,    c = accent_chroma, h = hues[1]}
  palette[10] = {l = focus_l, c = accent_chroma, h = hues[1]}
  palette[11] = {l = focus_l, c = accent_chroma, h = hues[2]}
  palette[12] = {l = fg.l,    c = accent_chroma, h = hues[2]}
  palette[13] = {l = focus_l, c = accent_chroma, h = hues[4]}
  palette[14] = {l = fg.l,    c = accent_chroma, h = hues[3]}
  palette[15] = {l = fg.l,    c = accent_chroma, h = hues[4]}
  palette[16] = {l = focus_l, c = accent_chroma, h = hues[3]}

  -- Convert to base16 palette
  local base16_palette = {}
  for i, lch in ipairs(palette) do
    local name = H.base16_names[i]
    -- It is ensured in `lch2hex` that only valid HEX values are produced
    base16_palette[name] = H.lch2hex(lch)
  end

  return base16_palette
end

-- Helpers
---- Highlighting
function H.hi(group, args)
  -- NOTE: using `string.format` instead of gradually growing string with `..`
  -- is faster. Crude estimate for this particular case: whole colorscheme
  -- loading decreased from ~3.6ms to ~3.0ms, i.e. by about 20%.
  local command = string.format(
    [[highlight %s guifg=%s guibg=%s gui=%s guisp=%s]],
    group,
    args.guifg or 'NONE',
    args.guibg or 'NONE',
    args.gui   or 'NONE',
    args.guisp or 'NONE'
  )
  vim.cmd(command)
end

---- Optimal scales
---- Make a set of equally spaced hues which are as different to present hues
---- as possible
function H.make_different_hues(present_hues, n)
  local max_offset = math.floor(360 / n + 0.5)

  local dist, best_dist = nil, -math.huge
  local best_hues, new_hues

  for offset=0,max_offset-1,1 do
    new_hues = H.make_hue_scale(n, offset)

    -- Compute distance as usual 'minimum distance' between two sets
    dist = H.dist_circle_set(new_hues, present_hues)

    -- Decide if it is the best
    if dist > best_dist then
      best_hues, best_dist = new_hues, dist
    end
  end

  return best_hues
end

function H.make_hue_scale(n, offset)
  local step = math.floor(360 / n + 0.5)
  local res = {}
  for i=0,n-1,1 do table.insert(res, (offset + i * step) % 360) end
  return res
end

---- Validators
H.base16_names = {
  'base00', 'base01', 'base02', 'base03', 'base04', 'base05', 'base06', 'base07',
  'base08', 'base09', 'base0A', 'base0B', 'base0C', 'base0D', 'base0E', 'base0F'
}

function H.validate_hex(x, name)
  local is_hex = type(x) == 'string' and x:len() == 7 and
    x:sub(1, 1) == '#' and (tonumber(x:sub(2), 16) ~= nil)

  if not is_hex then
    local msg = string.format(
      '(mini.base16): `%s` is not a HEX color (string "#RRGGBB")', name
    )
    error(msg)
  end
  return true
end

function H.validate_base16_palette(x)
  if type(x) ~= 'table' then error("(mini.base16): `palette` is not a table.") end
  for _, name in pairs(H.base16_names) do
    local c = x[name]
    if c == nil then
      local msg = string.format(
        '(mini.base16): `palette` does not have value %s', name
      )
      error(msg)
    end
    H.validate_hex(c, string.format('palette[%s]', name))
  end
  return true
end

---- Terminal colors
---- Sources:
---- - https://github.com/shawncplus/Vim-toCterm/blob/master/lib/Xterm.php
---- - https://gist.github.com/MicahElliott/719710
H.cterm_first16 = {
  {r = 0, g = 0, b = 0},
  {r = 205, g = 0, b = 0},
  {r = 0, g = 205, b = 0},
  {r = 205, g = 205, b = 0},
  {r = 0, g = 0, b = 238},
  {r = 205, g = 0, b = 205},
  {r = 0, g = 205, b = 205},
  {r = 229, g = 229, b = 229},
  {r = 127, g = 127, b = 127},
  {r = 255, g = 0, b = 0},
  {r = 0, g = 255, b = 0},
  {r = 255, g = 255, b = 0},
  {r = 92, g = 92, b = 255},
  {r = 255, g = 0, b = 255},
  {r = 0, g = 255, b = 255},
  {r = 255, g = 255, b = 255}
}

H.cterm_basis = {0, 95, 135, 175, 215, 255}

function H.cterm2rgb(i)
  if i < 16 then return H.cterm_first16[i + 1] end
  if 16 <= i and i <= 231 then
    i = i - 16
    local r = H.cterm_basis[math.floor(i / 36) % 6 + 1]
    local g = H.cterm_basis[math.floor(i / 6) % 6 + 1]
    local b = H.cterm_basis[i % 6 + 1]
    return {r = r, g = g, b = b}
  end
  if 232 <= i and i <= 255 then
    local c = 8 + (i - 232) * 10
    return {r = c, g = c, b = c}
  end
end

function H.ensure_cterm_palette()
  if H.cterm_palette then return end
  H.cterm_palette = {}
  for i=0,255 do H.cterm_palette[i] = H.cterm2rgb(i) end
end

---- Color conversion
---- Source: https://www.easyrgb.com/en/math.php
---- Accuracy is usually around 2-3 decimal digits, which should be fine
------ HEX <-> CIELCh(uv)
function H.hex2lch(hex)
  local res = hex
  for _, f in pairs({H.hex2rgb, H.rgb2xyz, H.xyz2luv, H.luv2lch}) do
    res = f(res)
  end
  return res
end

function H.lch2hex(lch)
  local res = lch
  for _, f in pairs({H.lch2luv, H.luv2xyz, H.xyz2rgb, H.rgb2hex}) do
    res = f(res)
  end
  return res
end

------ HEX <-> RGB
function H.hex2rgb(hex)
  local dec = tonumber(hex:sub(2), 16)

  local b = math.fmod(dec, 256)
  local g = math.fmod((dec - b) / 256, 256)
  local r = math.floor(dec / 65536)

  return {r = r, g = g, b = b}
end

function H.rgb2hex(rgb)
  -- Round and trim values
  local t = vim.tbl_map(
    function(x)
      x = math.min(math.max(x, 0), 255)
      return math.floor(x + 0.5)
    end,
    rgb
  )

  return '#' .. string.format('%02x', t.r) ..
    string.format('%02x', t.g) ..
    string.format('%02x', t.b)
end

------ RGB <-> XYZ
function H.rgb2xyz(rgb)
  local t = vim.tbl_map(
    function(c)
      c = c / 255
      if c > 0.04045 then
        c = ((c + 0.055) / 1.055)^2.4
      else
        c = c / 12.92
      end
      return 100 * c
    end,
    rgb
  )

  -- Source of better matrix: http://brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
  local x = 0.41246 * t.r + 0.35757 * t.g + 0.18043 * t.b
  local y = 0.21267 * t.r + 0.71515 * t.g + 0.07217 * t.b
  local z = 0.01933 * t.r + 0.11919 * t.g + 0.95030 * t.b
  return {x = x, y = y, z = z}
end

function H.xyz2rgb(xyz)
  -- Source of better matrix: http://brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
  r =  3.24045 * xyz.x - 1.53713 * xyz.y - 0.49853 * xyz.z
  g = -0.96927 * xyz.x + 1.87601 * xyz.y + 0.04155 * xyz.z
  b =  0.05564 * xyz.x - 0.20403 * xyz.y + 1.05722 * xyz.z

  return vim.tbl_map(
    function(c)
      c = c / 100
      if c > 0.0031308 then
        c = 1.055 * (c^(1 / 2.4)) - 0.055
      else
        c = 12.92 * c
      end
      return 255 * c
    end,
    {r = r, g = g, b = b}
  )
end

------ XYZ <-> CIELuv
-------- Using white reference for D65 and 2 degress
H.ref_u = (4 * 95.047) / (95.047 + (15 * 100) + (3 * 108.883))
H.ref_v = (9 * 100) / (95.047 + (15 * 100) + (3 * 108.883))

function H.xyz2luv(xyz)
  local x, y, z = xyz.x, xyz.y, xyz.z
  if x + y + z == 0 then return {l = 0, u = 0, v = 0} end

  local var_u = 4 * x / (x + 15 * y + 3 * z)
  local var_v = 9 * y / (x + 15 * y + 3 * z)
  local var_y = y / 100
  if var_y > 0.008856 then
    var_y = var_y^(1 / 3)
  else
    var_y = (7.787 * var_y) + (16 / 116)
  end

  local l = (116 * var_y) - 16
  local u = 13 * l * (var_u - H.ref_u)
  local v = 13 * l * (var_v - H.ref_v)
  return {l = l, u = u, v = v}
end

function H.luv2xyz(luv)
  if luv.l == 0 then return {x = 0, y = 0, z = 0} end

  local var_y = (luv.l + 16) / 116
  if (var_y^3  > 0.008856) then
    var_y = var_y^3
  else
    var_y = (var_y - 16 / 116) / 7.787
  end

  local var_u = luv.u / (13 * luv.l) + H.ref_u
  local var_v = luv.v / (13 * luv.l) + H.ref_v

  local y = var_y * 100
  local x = -(9 * y * var_u) / ((var_u - 4) * var_v - var_u * var_v)
  local z = (9 * y - 15 * var_v * y - var_v * x) / (3 * var_v)
  return {x = x, y = y, z = z}
end

------ CIELuv <-> CIELCh(uv)
H.tau = 2 * math.pi

function H.luv2lch(luv)
  local c = math.sqrt(luv.u^2 + luv.v^2)
  local h
  if c == 0 then
    h = 0
  else
    -- Convert [-pi, pi] radians to [0, 360] degrees
    h = (math.atan2(luv.v, luv.u) % H.tau) * 360 / H.tau
  end
  return {l = luv.l, c = c, h = h}
end

function H.lch2luv(lch)
  local angle = lch.h * H.tau / 360
  local u = lch.c * math.cos(angle)
  local v = lch.c * math.sin(angle)
  return {l = lch.l, u = u, v = v}
end

---- Distances
function H.dist_circle(x, y)
  local d = math.abs(x - y) % 360
  return d > math.pi and (360 - d) or d
end

function H.dist_circle_set(set1, set2)
  -- Minimum distance between all pairs
  local dist = math.huge
  local d
  for _, x in pairs(set1) do
    for _, y in pairs(set2) do
      d = H.dist_circle(x, y)
      if dist > d then dist = d end
    end
  end
  return dist
end

function H.nearest_rgb_id(rgb_target, rgb_palette)
  local best_dist = math.huge
  local best_id, dist
  for id, rgb in pairs(rgb_palette) do
    dist = math.abs(rgb_target.r - rgb.r) +
      math.abs(rgb_target.g - rgb.g) +
      math.abs(rgb_target.b - rgb.b)
    if dist < best_dist then best_id, best_dist = id, dist end
  end

  return best_id
end

return MiniBase16
