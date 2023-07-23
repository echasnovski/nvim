-- TODO:
--
-- - Code:
--     - Add `gen_clues` table with callables and preconfigured clues:
--         - 'mini.ai'/'mini.surround'?
--
--     - Autocreate only in listed and help buffers?
--
-- - Docs:
--     - Mostly designed for nested `<Leader>` keymaps.
--
--     - Doesn't have full support for Operator-pending mode triggers:
--         - Doesn't work as part of a command in "temporary Normal mode" (like
--           after |i_CTRL-O|) due to implementation difficulties.
--         - Can have unexpected behavior with custom operators.
--
--     - Has problems with macros:
--         - All triggers are disabled during recording of macro due to
--           technical reasons. Would be good if
--         - The `@` key is specially mapped to temporarily disable triggers.
--
--     - If using |<Leader>| inside config (either as trigger or inside clues),
--       set it prior running |MiniClue.setup()|.
--
--     - If trigger concists from several keys (like `<Leader>f`), it will be
--       treated as single key. Matters for `<BS>`.
--
--     - Trigger will fully override same buffer-local mapping and will have
--       precedence over global mappings. Example:
--
-- - Test:
--     - Should work with multibyte characters.
--     - Should respect `vim.b.miniclue_config` being set in `FileType` event.
--

--- *mini.clue* Show mapping clues
--- *MiniClue*
---
--- MIT License Copyright (c) 2023 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Features:
--- - Enable for some subset of keymaps independence from 'timeoutlen'. That
---   is, mapping input is active until:
---     - Valid mapping is complete: executed it.
---     - Latest key makes current key stack not match any mapping: do nothing.
---     - User presses `<CR>`: execute current key stack.
---     - User presses `<Esc>`/`<C-c>`: cancel mapping.
---
--- - Show window with clues about next available keys.
---
--- - Allow hydra-like submodes via `postkeys`.
---
--- - Stores in-session log of actually used keys which can be used for
---   analysis of your mapping preferences.
---
--- - Basic 'langmap' support during querying.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.clue').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniClue`
--- which you can use for scripting or manually (with `:lua MiniClue.*`).
---
--- See |MiniClue.config| for available config settings.
---
--- You can override runtime config settings (like mappings or window options)
--- locally to buffer inside `vim.b.miniclue_config` which should have same
--- structure as `MiniClue.config`. See |mini.nvim-buffer-local-config| for
--- more details.
---
--- # Comparisons ~
---
--- - 'folke/which-key.nvim':
--- - 'anuvyklack/hydra.nvim':
---
--- # Highlight groups ~
---
--- * `MiniClueBorder` - window border.
--- * `MiniClueGroup` - group description in clue window.
--- * `MiniClueNextKey` - next key label in clue window.
--- * `MiniClueNextKeyWithPostkeys` - next key label with postkeys in clue window.
--- * `MiniClueSeparator` - separator in clue window.
--- * `MiniClueSingle` - single key description in clue window.
--- * `MiniClueTitle` - window title.
---
--- To change any highlight group, modify it directly with |:highlight|.
---
--- # Disabling~
---
--- To disable creating triggers, set `vim.g.miniclue_disable` (globally) or
--- `vim.b.miniclue_disable` (for a buffer) to `true`. Considering high number
--- of different scenarios and customization intentions, writing exact rules
--- for disabling module's functionality is left to user. See
--- |mini.nvim-disabling-recipes| for common recipes.

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local
---@diagnostic disable:cast-local-type

-- Module definition ==========================================================
MiniClue = {}
H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniClue.config|.
---
---@usage `require('mini.clue').setup({})` (replace `{}` with your `config` table).
MiniClue.setup = function(config)
  -- Export module
  _G.MiniClue = MiniClue

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands(config)

  -- Create default highlighting
  H.create_default_hl()
end

--stylua: ignore
--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # Clues ~
---
--- - Submode for moving with 'mini.move': >
---
---   -- Uses `<Leader>M` to initiate "move" submode
---   require('mini.move').setup({
---     mappings = {
---       left       = '<Leader>Mh',
---       right      = '<Leader>Ml',
---       down       = '<Leader>Mj',
---       up         = '<Leader>Mk',
---       line_left  = '<Leader>Mh',
---       line_right = '<Leader>Ml',
---       line_down  = '<Leader>Mj',
---       line_up    = '<Leader>Mk',
---     },
---   })
---
---   require('mini.clue').setup({
---     clues = {
---       { mode = 'n', keys = '<Leader>Mh', postkeys = '<Leader>M' },
---       { mode = 'n', keys = '<Leader>Mj', postkeys = '<Leader>M' },
---       { mode = 'n', keys = '<Leader>Mk', postkeys = '<Leader>M' },
---       { mode = 'n', keys = '<Leader>Ml', postkeys = '<Leader>M' },
---       { mode = 'x', keys = '<Leader>Mh', postkeys = '<Leader>M' },
---       { mode = 'x', keys = '<Leader>Mj', postkeys = '<Leader>M' },
---       { mode = 'x', keys = '<Leader>Mk', postkeys = '<Leader>M' },
---       { mode = 'x', keys = '<Leader>Ml', postkeys = '<Leader>M' },
---     },
---   })
---
--- - Postkeys are literal simulation of keypresses with |nvim_feedkeys()|.
---
--- # Triggers ~
---
--- # Window ~
---
--- - <config.width> can be "auto".
--- - Add example of different anchor: >
---   require('mini.clue').setup({
---     window = { config = { anchor = 'NE', row = 1 } },
---   })
MiniClue.config = {
  clues = {},

  triggers = {},

  window = {
    config = {},
    delay = 1000,
    scroll_down = '<C-d>',
    scroll_up = '<C-u>',
  },
}
--minidoc_afterlines_end

MiniClue.enable_all_triggers = function()
  for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
    H.map_buf_triggers(buf_id)
  end
end

MiniClue.enable_buf_triggers = function(buf_id)
  if not H.is_valid_buf(buf_id) then H.error('`buf_id` should be a valid buffer identifier.') end
  H.map_buf_triggers(buf_id)
end

MiniClue.disable_all_triggers = function()
  for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
    H.unmap_buf_triggers(buf_id)
  end
end

MiniClue.disable_buf_triggers = function(buf_id)
  if not H.is_valid_buf(buf_id) then H.error('`buf_id` should be a valid buffer identifier.') end
  H.unmap_buf_triggers(buf_id)
end

--- Generate pre-configured clues
---
--- This is a table with function elements. Call to actually get timing function.
MiniClue.gen_clues = {}

--- Generate clues for `g` key
---
--- Contains clues for the following triggers: >
---
---   { mode = 'n', keys = 'g' }
---   { mode = 'x', keys = 'g' }
---
---@return table Array of clues.
MiniClue.gen_clues.g = function()
  --stylua: ignore
  return {
    { mode = 'n', keys = 'g0',     desc = 'Go to leftmost visible column' },
    { mode = 'n', keys = 'g8',     desc = 'Print hex value of char under cursor' },
    { mode = 'n', keys = 'ga',     desc = 'Print ascii value' },
    { mode = 'n', keys = 'gD',     desc = 'Go to definition in file' },
    { mode = 'n', keys = 'gd',     desc = 'Go to definition in function' },
    { mode = 'n', keys = 'gE',     desc = 'Go backwards to end of previous WORD' },
    { mode = 'n', keys = 'ge',     desc = 'Go backwards to end of previous word' },
    { mode = 'n', keys = 'gF',     desc = 'Edit file under cursor + jump line' },
    { mode = 'n', keys = 'gf',     desc = 'Edit file under cursor' },
    { mode = 'n', keys = 'gg',     desc = 'Go to line (def: first)' },
    { mode = 'n', keys = 'gH',     desc = 'Start Select line mode' },
    { mode = 'n', keys = 'gh',     desc = 'Start Select mode' },
    { mode = 'n', keys = 'gI',     desc = 'Start Insert at column 1' },
    { mode = 'n', keys = 'gi',     desc = 'Start Insert where it stopped' },
    { mode = 'n', keys = 'gJ',     desc = 'Join lines without extra spaces' },
    { mode = 'n', keys = 'gj',     desc = 'Go down by screen lines' },
    { mode = 'n', keys = 'gk',     desc = 'Go up by screen lines' },
    { mode = 'n', keys = 'gM',     desc = 'Go to middle of text line' },
    { mode = 'n', keys = 'gm',     desc = 'Go to middle of screen line' },
    { mode = 'n', keys = 'gN',     desc = 'Select previous search match' },
    { mode = 'n', keys = 'gn',     desc = 'Select next search match' },
    { mode = 'n', keys = 'go',     desc = 'Go to byte' },
    { mode = 'n', keys = 'gP',     desc = 'Put text before cursor + stay after it' },
    { mode = 'n', keys = 'gp',     desc = 'Put text after cursor + stay after it' },
    { mode = 'n', keys = 'gQ',     desc = 'Switch to "Ex" mode' },
    { mode = 'n', keys = 'gq',     desc = 'Format text (operator)' },
    { mode = 'n', keys = 'gR',     desc = 'Enter Virtual Replace mode' },
    { mode = 'n', keys = 'gr',     desc = 'Virtual replace with character' },
    { mode = 'n', keys = 'gs',     desc = 'Sleep' },
    { mode = 'n', keys = 'gT',     desc = 'Go to previous tabpage' },
    { mode = 'n', keys = 'gt',     desc = 'Go to next tabpage' },
    { mode = 'n', keys = 'gU',     desc = 'Make uppercase (operator)' },
    { mode = 'n', keys = 'gu',     desc = 'Make lowercase (operator)' },
    { mode = 'n', keys = 'gV',     desc = 'Avoid reselect' },
    { mode = 'n', keys = 'gv',     desc = 'Reselect previous Visual area' },
    { mode = 'n', keys = 'gw',     desc = 'Format text + keep cursor (operator)' },
    { mode = 'n', keys = 'g<C-]>', desc = '`:tjump` to tag under cursor' },
    { mode = 'n', keys = 'g<C-a>', desc = 'Dump a memory profile' },
    { mode = 'n', keys = 'g<C-g>', desc = 'Show information about cursor' },
    { mode = 'n', keys = 'g<C-h>', desc = 'Start Select block mode' },
    { mode = 'n', keys = 'g<Tab>', desc = 'Go to last accessed tabpage' },
    { mode = 'n', keys = "g'",     desc = "Jump to mark (don't affect jumplist)" },
    { mode = 'n', keys = 'g#',     desc = 'Search backwards word under cursor' },
    { mode = 'n', keys = 'g$',     desc = 'Go to rightmost visible column' },
    { mode = 'n', keys = 'g%',     desc = 'Cycle through matching groups' },
    { mode = 'n', keys = 'g&',     desc = 'Repeat last `:s` on all lines' },
    { mode = 'n', keys = 'g*',     desc = 'Search word under cursor' },
    { mode = 'n', keys = 'g+',     desc = 'Go to newer text state' },
    { mode = 'n', keys = 'g,',     desc = 'Go to newer position in change list' },
    { mode = 'n', keys = 'g-',     desc = 'Go to older text state' },
    { mode = 'n', keys = 'g;',     desc = 'Go to older position in change list' },
    { mode = 'n', keys = 'g<',     desc = 'Display previous command output' },
    { mode = 'n', keys = 'g?',     desc = 'Rot13 encode (operator)' },
    { mode = 'n', keys = 'g@',     desc = "Call 'operatorfunc' (operator)" },
    { mode = 'n', keys = 'g]',     desc = '`:tselect` tag under cursor' },
    { mode = 'n', keys = 'g^',     desc = 'Go to leftmost visible non-whitespace' },
    { mode = 'n', keys = 'g_',     desc = 'Go to lower line' },
    { mode = 'n', keys = 'g`',     desc = "Jump to mark (don't affect jumplist)" },
    { mode = 'n', keys = 'g~',     desc = 'Swap case (operator)' },

    { mode = 'x', keys = 'gf',     desc = 'Edit selected file' },
    { mode = 'x', keys = 'gJ',     desc = 'Join selected lines without extra spaces' },
    { mode = 'x', keys = 'gq',     desc = 'Format selection' },
    { mode = 'x', keys = 'gV',     desc = 'Avoid reselect' },
    { mode = 'x', keys = 'gw',     desc = 'Format selection + keep cursor' },
    { mode = 'x', keys = 'g<C-]>', desc = '`:tjump` to selected tag' },
    { mode = 'x', keys = 'g<C-a>', desc = 'Increment with compound' },
    { mode = 'x', keys = 'g<C-g>', desc = 'Show information about selection' },
    { mode = 'x', keys = 'g<C-x>', desc = 'Decrement with compound' },
    { mode = 'x', keys = 'g]',     desc = '`:tselect` selected tag' },
    { mode = 'x', keys = 'g?',     desc = 'Rot13 encode selection' },
  }
end

--- Generate clues for `z` key
---
--- Contains clues for the following triggers: >
---
---   { mode = 'n', keys = 'z' }
---   { mode = 'x', keys = 'z' }
---
---@return table Array of clues.
MiniClue.gen_clues.z = function()
  --stylua: ignore
  return {
    { mode = 'n', keys = 'zA',   desc = 'Toggle folds recursively' },
    { mode = 'n', keys = 'za',   desc = 'Toggle fold' },
    { mode = 'n', keys = 'zb',   desc = 'Redraw at bottom' },
    { mode = 'n', keys = 'zC',   desc = 'Close folds recursively' },
    { mode = 'n', keys = 'zc',   desc = 'Close fold' },
    { mode = 'n', keys = 'zD',   desc = 'Delete folds recursively' },
    { mode = 'n', keys = 'zd',   desc = 'Delete fold' },
    { mode = 'n', keys = 'zE',   desc = 'Eliminate all folds' },
    { mode = 'n', keys = 'ze',   desc = 'Scroll to cursor on right screen side' },
    { mode = 'n', keys = 'zF',   desc = 'Create fold' },
    { mode = 'n', keys = 'zf',   desc = 'Create fold (operator)' },
    { mode = 'n', keys = 'zG',   desc = 'Temporarily mark as correctly spelled' },
    { mode = 'n', keys = 'zg',   desc = 'Permanently mark as correctly spelled' },
    { mode = 'n', keys = 'zH',   desc = 'Scroll left half screen' },
    { mode = 'n', keys = 'zh',   desc = 'Scroll left' },
    { mode = 'n', keys = 'zi',   desc = "Toggle 'foldenable'" },
    { mode = 'n', keys = 'zj',   desc = 'Move to start of next fold' },
    { mode = 'n', keys = 'zk',   desc = 'Move to end of previous fold' },
    { mode = 'n', keys = 'zL',   desc = 'Scroll right half screen' },
    { mode = 'n', keys = 'zl',   desc = 'Scroll right' },
    { mode = 'n', keys = 'zM',   desc = 'Close all folds' },
    { mode = 'n', keys = 'zm',   desc = 'Fold more' },
    { mode = 'n', keys = 'zN',   desc = "Set 'foldenable'" },
    { mode = 'n', keys = 'zn',   desc = "Reset 'foldenable'" },
    { mode = 'n', keys = 'zO',   desc = 'Open folds recursively' },
    { mode = 'n', keys = 'zo',   desc = 'Open fold' },
    { mode = 'n', keys = 'zP',   desc = 'Paste without trailspace' },
    { mode = 'n', keys = 'zp',   desc = 'Paste without trailspace' },
    { mode = 'n', keys = 'zR',   desc = 'Open all folds' },
    { mode = 'n', keys = 'zr',   desc = 'Fold less' },
    { mode = 'n', keys = 'zs',   desc = 'Scroll to cursor on left screen side' },
    { mode = 'n', keys = 'zt',   desc = 'Redraw at top' },
    { mode = 'n', keys = 'zu',   desc = '+Undo spelling commands' },
    { mode = 'n', keys = 'zug',  desc = 'Undo `zg`' },
    { mode = 'n', keys = 'zuG',  desc = 'Undo `zG`' },
    { mode = 'n', keys = 'zuw',  desc = 'Undo `zw`' },
    { mode = 'n', keys = 'zuW',  desc = 'Undo `zW`' },
    { mode = 'n', keys = 'zv',   desc = 'Open enough folds' },
    { mode = 'n', keys = 'zW',   desc = 'Temporarily mark as incorrectly spelled' },
    { mode = 'n', keys = 'zw',   desc = 'Permanently mark as incorrectly spelled' },
    { mode = 'n', keys = 'zX',   desc = 'Update folds' },
    { mode = 'n', keys = 'zx',   desc = 'Update folds + open enough folds' },
    { mode = 'n', keys = 'zy',   desc = 'Yank without trailing spaces (operator)' },
    { mode = 'n', keys = 'zz',   desc = 'Redraw at center' },
    { mode = 'n', keys = 'z+',   desc = 'Redraw under bottom at top' },
    { mode = 'n', keys = 'z-',   desc = 'Redraw at bottom + cursor on first non-blank' },
    { mode = 'n', keys = 'z.',   desc = 'Redraw at center + cursor on first non-blank' },
    { mode = 'n', keys = 'z=',   desc = 'Show spelling suggestions' },
    { mode = 'n', keys = 'z^',   desc = 'Redraw above top at bottom' },

    { mode = 'x', keys = 'zf',   desc = 'Create fold from selection' },
  }
end

--- Generate clues for window commands
---
--- Contains clues for the following triggers: >
---
---   { mode = 'n', keys = '<C-w>' }
---
--- Note: only non-duplicated commands are included. For full list see |CTRL-W|.
---
---@param opts table|nil Options. Possible keys:
---   - <submode_focus> `(boolean)` - whether to make focus commands a submode
---     by using `postkeys` field. Default: `false`.
---   - <submode_move> `(boolean)` - whether to make move commands a submode
---     by using `postkeys` field. Default: `false`.
---   - <submode_resize> `(boolean)` - whether to make resize commands a submode
---     by using `postkeys` field. Default: `false`.
---
---@return table Array of clues.
MiniClue.gen_clues.windows = function(opts)
  local default_opts = { submode_focus = false, submode_move = false, submode_resize = false }
  opts = vim.tbl_deep_extend('force', default_opts, opts or {})

  local postkeys_focus, postkeys_move, postkeys_resize = nil, nil, nil
  if opts.submode_focus then postkeys_focus = '<C-w>' end
  if opts.submode_move then postkeys_move = '<C-w>' end
  if opts.submode_resize then postkeys_resize = '<C-w>' end

  --stylua: ignore
  return {
    { mode = 'n', keys = '<C-w>+',      desc = 'Increase height',         postkeys = postkeys_resize },
    { mode = 'n', keys = '<C-w>-',      desc = 'Decrease height',         postkeys = postkeys_resize },
    { mode = 'n', keys = '<C-w><',      desc = 'Decrease width',          postkeys = postkeys_resize },
    { mode = 'n', keys = '<C-w>>',      desc = 'Increase width',          postkeys = postkeys_resize },
    { mode = 'n', keys = '<C-w>=',      desc = 'Make windows same dimensions' },
    { mode = 'n', keys = '<C-w>]',      desc = 'Split + jump to tag' },
    { mode = 'n', keys = '<C-w>^',      desc = 'Split + edit alternate file' },
    { mode = 'n', keys = '<C-w>_',      desc = 'Set height (def: very high)' },
    { mode = 'n', keys = '<C-w>|',      desc = 'Set width (def: very wide)' },
    { mode = 'n', keys = '<C-w>}',      desc = 'Show tag in preview' },
    { mode = 'n', keys = '<C-w>b',      desc = 'Focus bottom',            postkeys = postkeys_focus },
    { mode = 'n', keys = '<C-w>c',      desc = 'Close' },
    { mode = 'n', keys = '<C-w>d',      desc = 'Split + jump to definition' },
    { mode = 'n', keys = '<C-w>F',      desc = 'Split + edit file name + jump' },
    { mode = 'n', keys = '<C-w>f',      desc = 'Split + edit file name' },
    { mode = 'n', keys = '<C-w>g',      desc = '+Extra actions' },
    { mode = 'n', keys = '<C-w>g]',     desc = 'Split + list tags' },
    { mode = 'n', keys = '<C-w>g}',     desc = 'Do `:ptjump`' },
    { mode = 'n', keys = '<C-w>g<C-]>', desc = 'Split + jump to tag with `:tjump`' },
    { mode = 'n', keys = '<C-w>g<Tab>', desc = 'Focus last accessed tab', postkeys = postkeys_focus },
    { mode = 'n', keys = '<C-w>gF',     desc = 'New tabpage + edit file name + jump' },
    { mode = 'n', keys = '<C-w>gf',     desc = 'New tabpage + edit file name' },
    { mode = 'n', keys = '<C-w>gT',     desc = 'Focus previous tabpage',  postkeys = postkeys_focus },
    { mode = 'n', keys = '<C-w>gt',     desc = 'Focus next tabpage',      postkeys = postkeys_focus },
    { mode = 'n', keys = '<C-w>H',      desc = 'Move to the far left',    postkeys = postkeys_move },
    { mode = 'n', keys = '<C-w>h',      desc = 'Focus left',              postkeys = postkeys_focus },
    { mode = 'n', keys = '<C-w>i',      desc = 'Split + jump to declaration' },
    { mode = 'n', keys = '<C-w>J',      desc = 'Move to the very bottom', postkeys = postkeys_move },
    { mode = 'n', keys = '<C-w>j',      desc = 'Focus down',              postkeys = postkeys_focus },
    { mode = 'n', keys = '<C-w>K',      desc = 'Move to the very top',    postkeys = postkeys_move },
    { mode = 'n', keys = '<C-w>k',      desc = 'Focus up',                postkeys = postkeys_focus },
    { mode = 'n', keys = '<C-w>L',      desc = 'Move to the far right',   postkeys = postkeys_move },
    { mode = 'n', keys = '<C-w>l',      desc = 'Focus right',             postkeys = postkeys_focus },
    { mode = 'n', keys = '<C-w>n',      desc = 'Open new' },
    { mode = 'n', keys = '<C-w>o',      desc = 'Close all but current' },
    { mode = 'n', keys = '<C-w>P',      desc = 'Focus preview',           postkeys = postkeys_focus },
    { mode = 'n', keys = '<C-w>p',      desc = 'Focus previous',          postkeys = postkeys_focus },
    { mode = 'n', keys = '<C-w>q',      desc = 'Quit current' },
    { mode = 'n', keys = '<C-w>R',      desc = 'Rotate upwards',          postkeys = postkeys_move },
    { mode = 'n', keys = '<C-w>r',      desc = 'Rotate downwards',        postkeys = postkeys_move },
    { mode = 'n', keys = '<C-w>s',      desc = 'Split horizontally' },
    { mode = 'n', keys = '<C-w>T',      desc = 'Move to a new tab page',  postkeys = postkeys_move },
    { mode = 'n', keys = '<C-w>t',      desc = 'Focus top',               postkeys = postkeys_focus },
    { mode = 'n', keys = '<C-w>v',      desc = 'Split vertically' },
    { mode = 'n', keys = '<C-w>W',      desc = 'Focus previous',          postkeys = postkeys_focus },
    { mode = 'n', keys = '<C-w>w',      desc = 'Focus next',              postkeys = postkeys_focus },
    { mode = 'n', keys = '<C-w>x',      desc = 'Exchange windows',        postkeys = postkeys_move },
    { mode = 'n', keys = '<C-w>z',      desc = 'Close preview' },
  }
end

--- Generate clues for built-in completion
---
--- Contains clues for the following triggers: >
---
---   { mode = 'i', keys = '<C-x>' }
---
---@return table Array of clues.
MiniClue.gen_clues.builtin_completion = function()
  --stylua: ignore
  return {
    { mode = 'i', keys = '<C-x><C-d>', desc = 'Complete defined identifiers' },
    { mode = 'i', keys = '<C-x><C-e>', desc = 'Scroll up' },
    { mode = 'i', keys = '<C-x><C-f>', desc = 'Complete file names' },
    { mode = 'i', keys = '<C-x><C-i>', desc = 'Complete identifiers' },
    { mode = 'i', keys = '<C-x><C-k>', desc = 'Complete identifiers from dictionary' },
    { mode = 'i', keys = '<C-x><C-l>', desc = 'Complete whole lines' },
    { mode = 'i', keys = '<C-x><C-n>', desc = 'Next completion' },
    { mode = 'i', keys = '<C-x><C-o>', desc = 'Omni completion' },
    { mode = 'i', keys = '<C-x><C-p>', desc = 'Previous completion' },
    { mode = 'i', keys = '<C-x><C-s>', desc = 'Spelling suggestions' },
    { mode = 'i', keys = '<C-x><C-t>', desc = 'Complete identifiers from thesaurus' },
    { mode = 'i', keys = '<C-x><C-y>', desc = 'Scroll down' },
    { mode = 'i', keys = '<C-x><C-u>', desc = "Complete with 'completefunc'" },
    { mode = 'i', keys = '<C-x><C-v>', desc = 'Complete like in : command line' },
    { mode = 'i', keys = '<C-x><C-z>', desc = 'Stop completion, keeping the text as-is' },
    { mode = 'i', keys = '<C-x><C-]>', desc = 'Complete tags' },
    { mode = 'i', keys = '<C-x>s',     desc = 'Spelling suggestions' },
  }
end

--- Generate clues for marks
---
--- Contains clues for the following triggers: >
---
---   { mode = 'n', keys = "'" }
---   { mode = 'n', keys = "g'" }
---   { mode = 'n', keys = '`' }
---   { mode = 'n', keys = 'g`' }
---   { mode = 'x', keys = "'" }
---   { mode = 'x', keys = "g'" }
---   { mode = 'x', keys = '`' }
---   { mode = 'x', keys = 'g`' }
---
---@return table Array of clues.
---
---@seealso |mark-motions|
MiniClue.gen_clues.marks = function(opts)
  local describe_marks = function(mode, prefix)
    local make_clue = function(register, desc) return { mode = mode, keys = prefix .. register, desc = desc } end

    return {
      make_clue('^', 'Latest insert position'),
      make_clue('.', 'Latest change'),
      make_clue('"', 'Latest exited position'),
      make_clue("'", 'Line before jump'),
      make_clue('`', 'Position before jump'),
      make_clue('[', 'Start of latest changed or yanked text'),
      make_clue(']', 'End of latest changed or yanked text'),
      make_clue('(', 'Start of sentence'),
      make_clue(')', 'End of sentence'),
      make_clue('{', 'Start of paragraph'),
      make_clue('}', 'End of paragraph'),
      make_clue('<', 'Start of lastest visual selection'),
      make_clue('>', 'End of lastest visual selection'),
    }
  end

  --stylua: ignore
  return {
    -- Normal mode
    describe_marks('n', "'"),
    describe_marks('n', "g'"),
    describe_marks('n', "`"),
    describe_marks('n', "g`"),

    -- Visual mode
    describe_marks('x', "'"),
    describe_marks('x', "g'"),
    describe_marks('x', "`"),
    describe_marks('x', "g`"),
  }
end

--- Generate clues for registers
---
--- Contains clues for the following triggers: >
---
---   { mode = 'n', keys = '"' }
---   { mode = 'x', keys = '"' }
---   { mode = 'i', keys = '<C-r>' }
---   { mode = 'c', keys = '<C-r>' }
---
---@param opts table|nil Options. Possible keys:
---   - <show_contents> `(boolean)` - whether to show contents of all possible
---     registers. If `false`, only description of special registers is shown.
---     Default: `false`.
---
---@return table Array of clues.
---
---@seealso |registers|
MiniClue.gen_clues.registers = function(opts)
  opts = vim.tbl_deep_extend('force', { show_contents = false }, opts or {})

  local describe_registers
  if opts.show_contents then
    describe_registers = H.make_clues_with_register_contents
  else
    describe_registers = function(mode, prefix)
      local make_clue = function(register, desc) return { mode = mode, keys = prefix .. register, desc = desc } end
      return {
        make_clue('0', 'Latest yank'),
        make_clue('1', 'Latest big delete'),
        make_clue('"', 'Default register'),
        make_clue('#', 'Alternate buffer'),
        make_clue('%', 'Name of the current file'),
        make_clue('*', 'Selection clipboard'),
        make_clue('+', 'System clipboard'),
        make_clue('-', 'Latest small delete'),
        make_clue('.', 'Latest inserted text'),
        make_clue('/', 'Latest search pattern'),
        make_clue(':', 'Latest executed command'),
        make_clue('=', 'Result of expression'),
        make_clue('_', 'Black hole'),
      }
    end
  end

  --stylua: ignore
  return {
    -- Normal mode
    describe_registers('n', '"'),

    -- Visual mode
    describe_registers('x', '"'),

    -- Insert mode
    describe_registers('i', '<C-r>'),

    { mode = 'i', keys = '<C-r><C-r>', desc = '+Insert register literally' },
    describe_registers('i', '<C-r><C-r>'),

    { mode = 'i', keys = '<C-r><C-o>', desc = '+Insert register literally + not auto-indent' },
    describe_registers('i', '<C-r><C-o>'),

    { mode = 'i', keys = '<C-r><C-p>', desc = '+Insert register + fix indent' },
    describe_registers('i', '<C-r><C-p>'),

    -- Command-line mode
    describe_registers('c', '<C-r>'),

    { mode = 'c', keys = '<C-r><C-r>', desc = '+Insert register literally' },
    describe_registers('c', '<C-r><C-r>'),

    { mode = 'c', keys = '<C-r><C-o>', desc = '+Insert register literally + not auto-indent' },
    describe_registers('c', '<C-r><C-o>'),

    { mode = 'c', keys = '<C-r><C-p>', desc = '+Insert register + fix indent' },
    describe_registers('c', '<C-r><C-p>'),
  }
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniClue.config

-- Namespaces
H.ns_id = {
  highlight = vim.api.nvim_create_namespace('MiniClueHighlight'),
}

-- State of user input
H.state = {
  trigger = nil,
  -- Array of raw keys
  query = {},
  clues = {},
  timer = vim.loop.new_timer(),
  buf_id = nil,
  win_id = nil,
  is_after_postkeys = false,
}

-- Default window config
H.default_win_config = {
  anchor = 'SE',
  border = 'single',
  focusable = false,
  relative = 'editor',
  style = 'minimal',
  width = 30,
  zindex = 99,
}

-- Precomputed raw keys
H.keys = {
  bs = vim.api.nvim_replace_termcodes('<BS>', true, true, true),
  cr = vim.api.nvim_replace_termcodes('<CR>', true, true, true),
  exit = vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true),
  ctrl_d = vim.api.nvim_replace_termcodes('<C-d>', true, true, true),
  ctrl_u = vim.api.nvim_replace_termcodes('<C-u>', true, true, true),
}

-- Undo command which depends on Neovim version
H.undo_autocommand = 'au ModeChanged * ++once undo' .. (vim.fn.has('nvim-0.8') == 1 and '!' or '')

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    clues = { config.clues, 'table' },
    triggers = { config.triggers, 'table' },
    window = { config.window, 'table' },
  })

  vim.validate({
    ['window.delay'] = { config.window.delay, 'number' },
    ['window.config'] = { config.window.config, 'table' },
    ['window.scroll_down'] = { config.window.scroll_down, 'string' },
    ['window.scroll_up'] = { config.window.scroll_up, 'string' },
  })

  return config
end

H.apply_config = function(config)
  MiniClue.config = config

  -- Create trigger keymaps for all existing buffers
  MiniClue.enable_all_triggers()

  -- Tweak macro execution
  local macro_keymap_opts = { nowait = true, desc = "Execute macro without 'mini.clue' triggers" }
  local exec_macro = function(keys)
    local register = H.getcharstr()
    if register == nil then return end
    MiniClue.disable_all_triggers()
    vim.schedule(MiniClue.enable_all_triggers)
    pcall(vim.api.nvim_feedkeys, vim.v.count1 .. '@' .. register, 'nx', false)
  end
  vim.keymap.set('n', '@', exec_macro, macro_keymap_opts)

  local exec_latest_macro = function(keys)
    MiniClue.disable_all_triggers()
    vim.schedule(MiniClue.enable_all_triggers)
    vim.api.nvim_feedkeys(vim.v.count1 .. 'Q', 'nx', false)
  end
  vim.keymap.set('n', 'Q', exec_latest_macro, macro_keymap_opts)
end

H.is_disabled = function(buf_id)
  local buf_disable = H.get_buf_var(buf_id, 'miniclue_disable')
  return vim.g.miniclue_disable == true or buf_disable == true
end

H.create_autocommands = function(config)
  local augroup = vim.api.nvim_create_augroup('MiniClue', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = augroup, pattern = pattern, callback = callback, desc = desc })
  end

  -- Create buffer-local mappings for triggers to fully utilize `<nowait>`
  -- Use `vim.schedule_wrap` to allow other events to create
  -- `vim.b.miniclue_config` and `vim.b.miniclue_disable`
  local map_buf = vim.schedule_wrap(function(data) H.map_buf_triggers(data.buf) end)
  au('BufAdd', '*', map_buf, 'Create buffer-local trigger keymaps')

  -- Disable all triggers when recording macro as they interfer with what is
  -- actually recorded
  au('RecordingEnter', '*', MiniClue.disable_all_triggers, 'Disable all triggers')
  au('RecordingLeave', '*', MiniClue.enable_all_triggers, 'Enable all triggers')

  au('VimResized', '*', H.window_update, 'Update window on resize')
end

--stylua: ignore
H.create_default_hl = function()
  local hi = function(name, opts)
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end

  hi('MiniClueBorder',              { link = 'FloatBorder' })
  hi('MiniClueGroup',               { link = 'DiagnosticFloatingWarn' })
  hi('MiniClueNextKey',             { link = 'DiagnosticFloatingHint' })
  hi('MiniClueNextKeyWithPostkeys', { link = 'DiagnosticFloatingError' })
  hi('MiniClueSeparator',           { link = 'DiagnosticFloatingInfo' })
  hi('MiniClueSingle',              { link = 'NormalFloat' })
  hi('MiniClueTitle',               { link = 'FloatTitle' })
end

H.get_config = function(config, buf_id)
  config = config or {}
  local buf_config = H.get_buf_var(buf_id, 'miniclue_config') or {}
  local global_config = MiniClue.config

  -- Manually reconstruct to allow array elements to be concatenated
  local res = {
    clues = H.list_concat(global_config.clues, buf_config.clues, config.clues),
    triggers = H.list_concat(global_config.triggers, buf_config.triggers, config.triggers),
    window = vim.tbl_deep_extend('force', global_config.window, buf_config.window or {}, config.window or {}),
  }
  return res
end

H.get_buf_var = function(buf_id, name)
  if not H.is_valid_buf(buf_id) then return nil end
  return vim.b[buf_id or 0][name]
end

-- Triggers -------------------------------------------------------------------
H.map_buf_triggers = function(buf_id)
  if not H.is_valid_buf(buf_id) then return end

  if H.is_disabled(buf_id) then return end

  for _, trigger in ipairs(H.get_config(nil, buf_id).triggers) do
    H.map_trigger(buf_id, trigger)
  end
end

H.unmap_buf_triggers = function(buf_id)
  if not H.is_valid_buf(buf_id) then return end

  for _, trigger in ipairs(H.get_config(nil, buf_id).triggers) do
    H.unmap_trigger(buf_id, trigger)
  end
end

H.map_trigger = function(buf_id, trigger)
  if not H.is_valid_buf(buf_id) then return end

  -- Compute mapping RHS
  trigger.keys = H.replace_termcodes(trigger.keys)

  local rhs = function()
    -- Don't act if for some reason entered the same trigger during state exec
    local is_in_exec = type(H.exec_trigger) == 'table'
      and H.exec_trigger.mode == trigger.mode
      and H.exec_trigger.keys == trigger.keys
    if is_in_exec then
      H.exec_trigger = nil
      return
    end

    -- Start user query
    H.state_set(trigger, { trigger.keys })

    -- Do not advance if no other clues to query. NOTE: it is `<= 1` and not
    -- `<= 0` because the "init query" mapping should match.
    if vim.tbl_count(H.state.clues) <= 1 then return H.state_exec() end

    H.state_advance()
  end

  -- Use buffer-local mappings and `nowait` to make it a primary source of
  -- keymap execution
  local desc = string.format('Query clues after "%s"', H.keytrans(trigger.keys))
  local opts = { buffer = buf_id, nowait = true, desc = desc }

  -- Create mapping
  vim.keymap.set(trigger.mode, trigger.keys, rhs, opts)
end

H.unmap_trigger = function(buf_id, trigger)
  if not H.is_valid_buf(buf_id) then return end

  trigger.keys = H.replace_termcodes(trigger.keys)

  -- Delete mapping
  pcall(vim.keymap.del, trigger.mode, trigger.keys, { buffer = buf_id })
end

-- State ----------------------------------------------------------------------
H.state_advance = function(opts)
  opts = opts or {}
  local config_window = H.get_config().window

  -- Show clues: delay (debounce) first show; update immediately if shown or
  -- after postkeys (for visual feedback that extra key is needed to stop)
  H.state.timer:stop()
  local show_immediately = H.is_valid_win(H.state.win_id) or H.state.is_after_postkeys
  local delay = show_immediately and 0 or config_window.delay
  H.state.timer:start(delay, 0, function() H.window_update(opts.scroll_to_start) end)

  -- Reset postkeys right now to not flicker when trying to close window during
  -- "not querying" check
  H.state.is_after_postkeys = false

  -- Query user for new key
  local key = H.getcharstr()

  -- Handle key
  if key == nil then return H.state_reset() end

  if key == H.keys.cr then return H.state_exec() end

  local is_scroll_down = key == H.replace_termcodes(config_window.scroll_down)
  local is_scroll_up = key == H.replace_termcodes(config_window.scroll_up)
  if is_scroll_down or is_scroll_up then
    H.window_scroll(is_scroll_down and H.keys.ctrl_d or H.keys.ctrl_u)
    return H.state_advance({ scroll_to_start = false })
  end

  if key == H.keys.bs then
    H.state_pop()
  else
    H.state_push(key)
  end

  -- Advance state
  -- - Execute if reached single target keymap
  if H.state_is_at_target() then return H.state_exec() end

  -- - Reset if there are no keys (like after `<BS>`)
  if #H.state.query == 0 then return H.state_reset() end

  -- - Query user for more information if there is not enough
  --   NOTE: still advance even if there is single clue because it is still not
  --   a target but can be one.
  if vim.tbl_count(H.state.clues) >= 1 then return H.state_advance() end

  -- - Fall back for executing what user typed
  H.state_exec()
end

H.state_set = function(trigger, query)
  H.state.trigger = trigger
  H.state.query = query
  H.state.clues = H.clues_filter(H.clues_get_all(trigger.mode), query)
end

H.state_reset = function(keep_window)
  H.state.trigger = nil
  H.state.query = {}
  H.state.clues = {}
  H.state.is_after_postkeys = false

  H.state.timer:stop()
  if not keep_window then H.window_close() end
end

H.state_exec = function()
  -- Compute keys to type
  local keys_to_type = H.compute_exec_keys()

  -- Add extra (redundant) safety flag to try to avoid inifinite recursion
  local trigger, clue = H.state.trigger, H.state_get_query_clue()
  H.exec_trigger = trigger
  vim.schedule(function() H.exec_trigger = nil end)

  -- Reset state
  local has_postkeys = (clue or {}).postkeys ~= nil
  H.state_reset(has_postkeys)

  -- Disable trigger !!!VERY IMPORTANT!!!
  -- This is a workaround against infinite recursion (like if `g` is trigger
  -- then typing `gg`/`g~` would introduce infinite recursion).
  local buf_id = vim.api.nvim_get_current_buf()
  H.unmap_trigger(buf_id, trigger)

  -- Execute keys. The `i` flag is used to fully support Operator-pending mode.
  -- Flag `t` imitates keys as if user typed, which is reasonable but has small
  -- downside with edge cases of 'langmap' (like ':\;;\;:') as it "inverts" key
  -- meaning second time (at least in Normal mode).
  vim.api.nvim_feedkeys(keys_to_type, 'mit', false)

  -- Enable trigger back after it can no longer harm
  vim.schedule(function() H.map_trigger(buf_id, trigger) end)

  -- Apply postkeys (in scheduled fashion)
  if has_postkeys then H.state_apply_postkeys(clue.postkeys) end
end

H.state_push = function(keys)
  table.insert(H.state.query, keys)
  H.state.clues = H.clues_filter(H.state.clues, H.state.query)
end

H.state_pop = function()
  H.state.query[#H.state.query] = nil
  H.state.clues = H.clues_filter(H.clues_get_all(H.state.trigger.mode), H.state.query)
end

H.state_apply_postkeys = vim.schedule_wrap(function(postkeys)
  -- Register that possible future querying is a result of postkeys.
  -- This enables (keep) showing window immediately.
  H.state.is_after_postkeys = true

  -- Use `nvim_feedkeys()` because using `state_set()` and
  -- `state_advance()` directly does not work: it doesn't guarantee to be
  -- executed **after** keys from `nvim_feedkeys()`.
  vim.api.nvim_feedkeys(postkeys, 'mit', false)

  -- Defer check of whether postkeys resulted into window.
  -- Could not find proper way to check this which guarantees to be executed
  -- after `nvim_feedkeys()` takes effect **end** doesn't result into flicker
  -- when consecutively applying "submode" keys.
  vim.defer_fn(function()
    if #H.state.query == 0 then H.window_close() end
  end, 50)
end)

H.state_is_at_target =
  function() return vim.tbl_count(H.state.clues) == 1 and H.state.clues[H.query_to_keys(H.state.query)] ~= nil end

H.state_get_query_clue = function()
  local keys = H.query_to_keys(H.state.query)
  return H.state.clues[keys]
end

H.compute_exec_keys = function()
  local keys_count = vim.v.count > 0 and vim.v.count or ''
  local keys_query = H.query_to_keys(H.state.query)
  local res = keys_count .. keys_query

  local cur_mode = vim.fn.mode(1)

  -- Using `feedkeys()` inside Operator-pending mode leads to its cancel into
  -- Normal/Insert mode so extra work should be done to rebuild all keys
  if cur_mode:find('^no') ~= nil then
    local operator_tweak = H.operator_tweaks[vim.v.operator] or function(x) return x end
    res = operator_tweak(vim.v.operator .. H.get_forced_submode() .. res)
  end

  -- `feedkeys()` inside "temporary" Normal mode is executed **after** it is
  -- already back from Normal mode. Go into it again with `<C-o>` ('\15').
  -- NOTE: This only works when Normal mode trigger is triggered in
  -- "temporary" Normal mode. Still doesn't work when Operator-pending mode is
  -- triggered afterwards (like in `<C-o>gUiw` with 'i' as trigger).
  if cur_mode:find('^ni') ~= nil then res = '\15' .. res end

  return res
end

-- Some operators needs special tweaking due to their nature:
-- - Some operators perform on register. Solution: add register explicitly.
-- - Some operators end up changing mode which affects `feedkeys()`.
--   Solution: explicitly exit to Normal mode with '<C-\><C-n>'.
-- - Some operators still perform some redundant operation before `feedkeys()`
--   takes effect. Solution: add one-shot autocommand undoing that.
H.operator_tweaks = {
  ['c'] = function(keys)
    -- Doing '<C-\><C-n>' moves cursor one space to left (same as `i<Esc>`).
    -- Solution: add one-shot autocommand correcting cursor position.
    vim.cmd('au InsertLeave * ++once normal! l')
    return H.keys.exit .. '"' .. vim.v.register .. keys
  end,
  ['d'] = function(keys) return '"' .. vim.v.register .. keys end,
  ['y'] = function(keys) return '"' .. vim.v.register .. keys end,
  ['~'] = function(keys)
    if vim.fn.col('.') == 1 then vim.cmd(H.undo_autocommand) end
    return keys
  end,
  ['g~'] = function(keys)
    if vim.fn.col('.') == 1 then vim.cmd(H.undo_autocommand) end
    return keys
  end,
  ['g?'] = function(keys)
    if vim.fn.col('.') == 1 then vim.cmd(H.undo_autocommand) end
    return keys
  end,
  ['!'] = function(keys) return H.keys.exit .. keys end,
  ['>'] = function(keys)
    vim.cmd(H.undo_autocommand)
    return keys
  end,
  ['<'] = function(keys)
    vim.cmd(H.undo_autocommand)
    return keys
  end,
  ['g@'] = function(keys)
    -- Cancelling in-process `g@` operator seems to be particularly hard.
    -- Not even sure why specifically this combination works, but having `x`
    -- flag in `feedkeys()` is crucial.
    vim.api.nvim_feedkeys(H.keys.exit, 'nx', false)
    return H.keys.exit .. keys
  end,
}

H.query_to_keys = function(query) return table.concat(query, '') end

H.query_to_title = function(query) return H.keytrans(H.query_to_keys(query)) end

-- Window ---------------------------------------------------------------------
H.window_update = vim.schedule_wrap(function(scroll_to_start)
  -- Don't allow showing windows when Command-line window is active.
  -- It is possible to open them on Neovim<0.10, but not close.
  -- On Neovim=0.10 it is not possible to even open at the moment.
  -- See https://github.com/neovim/neovim/issues/24452
  --
  -- If only opening would be possible, update `H.window_close()` to create
  -- one-shot autocommand to close on 'CmdwinLeave'.
  if vim.fn.getcmdwintype() ~= '' then return end

  -- Make sure that outdated windows are not shown
  if #H.state.query == 0 then return H.window_close() end

  -- Close window if it is not in current tabpage (as only window is tracked)
  local is_different_tabpage = H.is_valid_win(H.state.win_id)
    and vim.api.nvim_win_get_tabpage(H.state.win_id) ~= vim.api.nvim_get_current_tabpage()
  if is_different_tabpage then H.window_close() end

  -- Create-update buffer showing clues
  H.state.buf_id = H.buffer_update()

  -- Create-update window showing buffer
  local win_config = H.window_get_config()
  if not H.is_valid_win(H.state.win_id) then
    H.state.win_id = H.window_open(win_config)
  else
    vim.api.nvim_win_set_config(H.state.win_id, win_config)
  end

  -- Make scroll not persist
  if scroll_to_start == nil then scroll_to_start = true end
  if scroll_to_start then vim.api.nvim_win_call(H.state.win_id, function() vim.cmd('normal! gg') end) end

  -- Add redraw because Neovim won't do it when `getcharstr()` is active
  vim.cmd('redraw')
end)

H.window_scroll = function(scroll_key)
  pcall(vim.api.nvim_win_call, H.state.win_id, function() vim.cmd('normal! ' .. scroll_key) end)
end

H.window_open = function(config)
  local win_id = vim.api.nvim_open_win(H.state.buf_id, false, config)

  vim.wo[win_id].foldenable = false
  vim.wo[win_id].wrap = false

  -- Neovim=0.7 doesn't support invalid highlight groups in 'winhighlight'
  local win_hl = 'FloatBorder:MiniClueBorder' .. (vim.fn.has('nvim-0.8') == 1 and ',FloatTitle:MiniClueTitle' or '')
  vim.wo[win_id].winhighlight = win_hl

  return win_id
end

H.window_close = function()
  pcall(vim.api.nvim_win_close, H.state.win_id, true)
  H.state.win_id = nil
end

H.window_get_config = function()
  local has_statusline = vim.o.laststatus > 0
  local has_tabline = vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)
  -- Remove 2 from maximum height to account for top and bottom borders
  local max_height = vim.o.lines - vim.o.cmdheight - (has_tabline and 1 or 0) - (has_statusline and 1 or 0) - 2

  local cur_config_fields = {
    row = vim.o.lines - vim.o.cmdheight - (has_statusline and 1 or 0),
    col = vim.o.columns,
    height = math.min(vim.api.nvim_buf_line_count(H.state.buf_id), max_height),
    title = H.query_to_title(H.state.query),
  }
  local res = vim.tbl_deep_extend('force', H.default_win_config, cur_config_fields, H.get_config().window.config)

  -- Tweak "auto" fields
  if res.width == 'auto' then res.width = H.buffer_get_width() + 1 end
  res.width = math.min(res.width, vim.o.columns)

  if res.row == 'auto' then
    local is_on_top = res.anchor == 'NW' or res.anchor == 'NE'
    res.row = is_on_top and (has_tabline and 1 or 0) or cur_config_fields.row
  end

  if res.col == 'auto' then
    local is_on_left = res.anchor == 'NW' or res.anchor == 'SW'
    res.col = is_on_left and 0 or cur_config_fields.col
  end

  -- Ensure it works on Neovim<0.9
  if vim.fn.has('nvim-0.9') == 0 then res.title = nil end

  return res
end

-- Buffer ---------------------------------------------------------------------
H.buffer_update = function()
  local buf_id = H.state.buf_id
  if not H.is_valid_buf(buf_id) then buf_id = vim.api.nvim_create_buf(false, true) end

  -- Compute content data
  local keys = H.query_to_keys(H.state.query)
  local content = H.clues_to_buffer_content(H.state.clues, keys)

  -- Add lines
  local lines = {}
  for _, line_content in ipairs(content) do
    table.insert(lines, string.format(' %s │ %s', line_content.next_key, line_content.desc))
  end
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)

  -- Add highlighting
  local ns_id = H.ns_id.highlight
  vim.api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)

  local set_hl = function(hl_group, line_from, col_from, line_to, col_to)
    local opts = { end_row = line_to, end_col = col_to, hl_group = hl_group, hl_eol = true }
    vim.api.nvim_buf_set_extmark(buf_id, ns_id, line_from, col_from, opts)
  end

  for i, line_content in ipairs(content) do
    local sep_start = line_content.next_key:len() + 3
    local next_key_hl_group = line_content.has_postkeys and 'MiniClueNextKeyWithPostkeys' or 'MiniClueNextKey'
    set_hl(next_key_hl_group, i - 1, 0, i - 1, sep_start - 1)

    -- NOTE: Separator '│' is 3 bytes long
    set_hl('MiniClueSeparator', i - 1, sep_start - 1, i - 1, sep_start + 2)

    local desc_hl_group = line_content.is_group and 'MiniClueGroup' or 'MiniClueSingle'
    set_hl(desc_hl_group, i - 1, sep_start + 2, i, 0)
  end

  return buf_id
end

H.buffer_get_width = function()
  if not H.is_valid_buf(H.state.buf_id) then return end
  local lines = vim.api.nvim_buf_get_lines(H.state.buf_id, 0, -1, false)
  local res = 0
  for _, l in ipairs(lines) do
    res = math.max(res, vim.fn.strdisplaywidth(l))
  end
  return res
end

-- Clues ----------------------------------------------------------------------
H.clues_get_all = function(mode)
  local res = {}

  -- Order of clue precedence: config clues < buffer mappings < global mappings
  local config_clues = H.clues_normalize(H.get_config().clues) or {}
  local mode_clues = vim.tbl_filter(function(x) return x.mode == mode end, config_clues)
  for _, clue in ipairs(mode_clues) do
    local lhsraw = H.replace_termcodes(clue.keys)
    local desc = clue.desc
    if vim.is_callable(desc) then desc = desc() end
    res[lhsraw] = {
      -- Allows callable clue description
      desc = desc,
      postkeys = H.replace_termcodes(clue.postkeys),
    }
  end

  for _, map_data in ipairs(vim.api.nvim_get_keymap(mode)) do
    local lhsraw = H.replace_termcodes(map_data.lhs)
    local res_data = res[lhsraw] or {}
    res_data.desc = map_data.desc or ''
    res[lhsraw] = res_data
  end

  for _, map_data in ipairs(vim.api.nvim_buf_get_keymap(0, mode)) do
    local lhsraw = H.replace_termcodes(map_data.lhs)
    local res_data = res[lhsraw] or {}
    res_data.desc = map_data.desc or ''
    res[lhsraw] = res_data
  end

  return res
end

H.clues_normalize = function(clues)
  local res = {}
  local process
  process = function(x)
    if vim.is_callable(x) then x = x() end
    if H.is_clue(x) then return table.insert(res, x) end
    if not vim.tbl_islist(x) then return nil end
    for _, y in ipairs(x) do
      process(y)
    end
  end

  process(clues)
  return res
end

H.clues_filter = function(clues, query)
  local keys = H.query_to_keys(query)
  for clue_keys, _ in pairs(clues) do
    if not vim.startswith(clue_keys, keys) then clues[clue_keys] = nil end
  end
  return clues
end

H.clues_to_buffer_content = function(clues, keys)
  -- Gather clue data
  local n_chars = vim.fn.strchars(keys)
  local keys_pattern = string.format('^%s.', vim.pesc(keys))
  local next_key_data, next_key_max_width = {}, 0
  for clue_keys, clue_data in pairs(clues) do
    -- `strcharpart()` has 0-based index
    local next_key = H.keytrans(vim.fn.strcharpart(clue_keys, n_chars, 1))

    -- Add non-trivial next key data only if clue matches current keys
    if next_key ~= '' and clue_keys:find(keys_pattern) ~= nil then
      -- Update description data
      local data = next_key_data[next_key] or {}
      data.n_choices = (data.n_choices or 0) + 1

      -- - Add description directly if it is group clue with description or
      --   a non-group clue
      if vim.fn.strchars(clue_keys) == (n_chars + 1) then
        data.desc = clue_data.desc or ''
        data.has_postkeys = clue_data.postkeys ~= nil
      end

      next_key_data[next_key] = data

      -- Update width data
      local next_key_width = vim.fn.strchars(next_key)
      data.next_key_width = next_key_width
      next_key_max_width = math.max(next_key_max_width, next_key_width)
    end
  end

  -- Convert to array sorted by keys and finalize content
  local next_keys_extra = vim.tbl_map(
    function(x) return { key = x, keytype = H.clues_get_next_key_type(x) } end,
    vim.tbl_keys(next_key_data)
  )
  table.sort(next_keys_extra, H.clues_compare_next_key)
  local next_keys = vim.tbl_map(function(x) return x.key end, next_keys_extra)

  local res = {}
  for _, key in ipairs(next_keys) do
    local data = next_key_data[key]
    local is_group = data.n_choices > 1
    local desc = data.desc or string.format('+%d choice%s', data.n_choices, is_group and 's' or '')
    local next_key = key .. string.rep(' ', next_key_max_width - data.next_key_width)
    table.insert(res, { next_key = next_key, desc = desc, is_group = is_group, has_postkeys = data.has_postkeys })
  end

  return res
end

H.clues_get_next_key_type = function(x)
  if x:find('^%w$') ~= nil then return 'alphanum' end
  if x:find('^<.*>$') ~= nil then return 'mod' end
  return 'other'
end

H.clues_compare_next_key = function(a, b)
  local a_type, b_type = a.keytype, b.keytype
  if a_type == b_type then
    local cmp = vim.stricmp(a.key, b.key)
    return cmp == -1 or (cmp == 0 and a.key < b.key)
  end

  if a_type == 'alphanum' then return true end
  if b_type == 'alphanum' then return false end

  if a_type == 'mod' then return true end
  if b_type == 'mod' then return false end
end

-- Clue generators ------------------------------------------------------------
H.make_clues_with_register_contents = function(mode, prefix)
  local get_register_desc = function(register)
    return function()
      local ok, value = pcall(vim.fn.getreg, register, 1)
      if not ok or value == '' then return nil end
      return vim.inspect(value)
    end
  end

  local all_registers = vim.split('0123456789abcdefghijklmnopqrstuvwxyz*+"-:.%/#', '')

  local res = {}
  for _, register in ipairs(all_registers) do
    table.insert(res, { mode = mode, keys = prefix .. register, desc = get_register_desc(register) })
  end
  table.insert(res, { mode = mode, keys = prefix .. '=', desc = 'Result of expression' })

  return res
end

-- Predicates -----------------------------------------------------------------
H.is_trigger = function(x) return type(x) == 'table' and type(x.mode) == 'string' and type(x.keys) == 'string' end

H.is_clue = function(x)
  if type(x) ~= 'table' then return false end
  local mandatory = type(x.mode) == 'string' and type(x.keys) == 'string'
  local extra = (x.desc == nil or type(x.desc) == 'string' or vim.is_callable(x.desc))
    and (x.postkeys == nil or type(x.postkeys) == 'string')
  return mandatory and extra
end

H.is_array_of = function(x, predicate)
  if not vim.tbl_islist(x) then return false end
  for _, v in ipairs(x) do
    if not predicate(v) then return false end
  end
  return true
end

-- Utilities ------------------------------------------------------------------
H.echo = function(msg, is_important)
  -- Construct message chunks
  msg = type(msg) == 'string' and { { msg } } or msg
  table.insert(msg, 1, { '(mini.clue) ', 'WarningMsg' })

  -- Avoid hit-enter-prompt
  local max_width = vim.o.columns * math.max(vim.o.cmdheight - 1, 0) + vim.v.echospace
  local chunks, tot_width = {}, 0
  for _, ch in ipairs(msg) do
    local new_ch = { vim.fn.strcharpart(ch[1], 0, max_width - tot_width), ch[2] }
    table.insert(chunks, new_ch)
    tot_width = tot_width + vim.fn.strdisplaywidth(new_ch[1])
    if tot_width >= max_width then break end
  end

  -- Echo. Force redraw to ensure that it is effective (`:h echo-redraw`)
  vim.cmd([[echo '' | redraw]])
  vim.api.nvim_echo(chunks, is_important, {})
end

H.unecho = function() vim.cmd([[echo '' | redraw]]) end

H.message = function(msg) H.echo(msg, true) end

H.error = function(msg) error(string.format('(mini.clue) %s', msg), 0) end

H.map = function(mode, lhs, rhs, opts)
  if lhs == '' then return end
  opts = vim.tbl_deep_extend('force', { silent = true }, opts or {})
  vim.keymap.set(mode, lhs, rhs, opts)
end

H.replace_termcodes = function(x)
  if x == nil then return nil end
  return vim.api.nvim_replace_termcodes(x, true, true, true)
end

-- TODO: Remove after compatibility with Neovim=0.7 is dropped
if vim.fn.has('nvim-0.8') == 1 then
  H.keytrans = function(x)
    local res = vim.fn.keytrans(x):gsub('<lt>', '<')
    return res
  end
else
  H.keytrans = function(x)
    local res = x:gsub('<lt>', '<')
    return res
  end
end

H.get_forced_submode = function()
  local mode = vim.fn.mode(1)
  if not mode:sub(1, 2) == 'no' then return '' end
  return mode:sub(3)
end

H.is_valid_buf = function(buf_id) return type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id) end

H.is_valid_win = function(win_id) return type(win_id) == 'number' and vim.api.nvim_win_is_valid(win_id) end

H.getcharstr = function()
  local ok, char = pcall(vim.fn.getcharstr)
  -- Terminate if couldn't get input (like with <C-c>) or it is `<Esc>`
  if not ok or char == '\27' or char == '' then return end
  return H.get_langmap()[char] or char
end

H.get_langmap = function()
  if vim.o.langmap == '' then return {} end

  -- Get langmap parts by splitting at "," not preceded by "\"
  local langmap_parts = vim.fn.split(vim.o.langmap, '[^\\\\]\\zs,')

  -- Process each langmap part
  local res = {}
  for _, part in ipairs(langmap_parts) do
    H.process_langmap_part(res, part)
  end
  return res
end

H.process_langmap_part = function(res, part)
  local semicolon_byte_ind = vim.fn.match(part, '[^\\\\]\\zs;') + 1

  -- Part is without ';', like 'aAbB'
  if semicolon_byte_ind == 0 then
    -- Drop backslash escapes
    part = part:gsub('\\([^\\])', '%1')

    for i = 1, vim.fn.strchars(part), 2 do
      -- `strcharpart()` has 0-based indexes
      local from, to = vim.fn.strcharpart(part, i - 1, 1), vim.fn.strcharpart(part, i, 1)
      if from ~= '' and to ~= '' then res[from] = to end
    end

    return
  end

  -- Part is with ';', like 'ab;AB'
  -- - Drop backslash escape
  local left = part:sub(1, semicolon_byte_ind - 1):gsub('\\([^\\])', '%1')
  local right = part:sub(semicolon_byte_ind + 1):gsub('\\([^\\])', '%1')

  for i = 1, vim.fn.strchars(left) do
    local from, to = vim.fn.strcharpart(left, i - 1, 1), vim.fn.strcharpart(right, i - 1, 1)
    if from ~= '' and to ~= '' then res[from] = to end
  end
end

H.list_concat = function(...)
  local res = {}
  for i = 1, select('#', ...) do
    for _, x in ipairs(select(i, ...) or {}) do
      table.insert(res, x)
    end
  end
  return res
end

return MiniClue
