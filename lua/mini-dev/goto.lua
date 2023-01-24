-- MIT License Copyright (c) 2022 Evgeni Chasnovski

-- TODO
--
-- Code:
-- - Consider renaming to 'mini.next'.
-- - Implement and map `comment()`.
-- - Implement and map `file()` (next/previous/first/last alphabetically file
--   inside current directory, first file in next/prev directory)
-- - Implement and map `indent()` (should respect empty lines).
-- - Implement and map `jump()` (jumplist inside and outside of current buffer)
-- - Think about renaming conflict suffix to 'n' (as in 'unimpaired.vim').
-- - Other todos across code.
--
-- Tests:
--
-- Docs:
-- - Mention that it is ok to not map defaults and use functions manually.

-- Documentation ==============================================================
--- Go to next/previous/first/last target
---
--- Features:
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.goto').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniGoto`
--- which you can use for scripting or manually (with `:lua MiniGoto.*`).
---
--- See |MiniGoto.config| for available config settings.
---
--- # Comparisons ~
---
--- - 'tpope/vim-unimpaired':
---
--- # Disabling~
---
--- To disable, set `g:minigoto_disable` (globally) or `b:minigoto_disable`
--- (for a buffer) to `v:true`. Considering high number of different scenarios
--- and customization intentions, writing exact rules for disabling module's
--- functionality is left to user. See |mini.nvim-disabling-recipes| for common
--- recipes.
---@tag mini.goto
---@tag Minigoto

---@diagnostic disable:undefined-field

-- Module definition ==========================================================
-- TODO: make local after release
MiniGoto = {}
H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniGoto.config|.
---
---@usage `require('mini.goto').setup({})` (replace `{}` with your `config` table)
MiniGoto.setup = function(config)
  -- Export module
  _G.MiniGoto = MiniGoto

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)
end

--stylua: ignore
--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text
MiniGoto.config = {
  mapping_suffixes = {
    buffer     = 'b',
    comment    = 'c',
    conflict   = 'x',
    diagnostic = 'd',
    file       = 'f',
    indent     = 'i',
    jump       = 'j',
    location   = 'l',
    quickfix   = 'q',
    window     = 'w',
  }
}
--minidoc_afterlines_end

MiniGoto.buffer = function(direction, opts)
  if not vim.tbl_contains({ 'first', 'prev', 'next', 'last' }, direction) then
    H.error([[In `buffer()` argument `direction` should be one of 'first', 'prev', 'next', 'last'.]])
  end
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1 }, opts or {})

  if direction == 'first' then vim.cmd('bfirst') end
  if direction == 'prev' then vim.cmd(opts.n_times .. 'bprevious') end
  if direction == 'next' then vim.cmd(opts.n_times .. 'bnext') end
  if direction == 'last' then vim.cmd('blast') end
end

MiniGoto.comment = function(direction, opts)
  if not vim.tbl_contains({ 'first', 'prev', 'next', 'last' }, direction) then
    H.error([[In `comment()` argument `direction` should be one of 'first', 'prev', 'next', 'last'.]])
  end
  opts = vim.tbl_deep_extend('force', { count = vim.v.count1 }, opts or {})

  -- TODO
  H.error('Not implemented')
end

MiniGoto.conflict = function(direction, opts)
  if not vim.tbl_contains({ 'first', 'prev', 'next', 'last', 'next_buf', 'prev_buf' }, direction) then
    H.error(
      [[In `comment()` argument `direction` should be one of 'first', 'prev', 'next', 'last', 'next_buf', 'prev_buf'.]]
    )
  end
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1 }, opts or {})

  -- TODO: Add support for 'next_buf'/'prev_buf' (first actual marker in some
  -- of next/prev buffer)

  -- Compute list of lines as conflict markers
  local marked_lines = {}
  local cur_line, cur_line_ind = vim.fn.line('.'), nil
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, true)
  -- TODO: Optimize to not traverse all lines
  for i, l in ipairs(lines) do
    local l_start = l:sub(1, 8)
    local is_marked = l_start == '<<<<<<< ' or l_start == '=======' or l_start == '>>>>>>> '
    if is_marked then
      table.insert(marked_lines, i)

      -- Track array index of current line (as *index of next marker*)
      if cur_line <= i then cur_line_ind = cur_line_ind or #marked_lines end
    end
  end
  -- - Correct for when current line is after last conflict marker
  cur_line_ind = cur_line_ind or 1

  -- Do nothing if there are no conflict markers
  if #marked_lines == 0 then return end

  -- Compute array index of target marker
  local is_at_marker = cur_line == marked_lines[cur_line_ind]
  local ind = ({
    first = 1,
    prev = cur_line_ind - opts.n_times,
    -- Move by 1 array index less if already at the "next" marker
    next = cur_line_ind + opts.n_times - (is_at_marker and 0 or 1),
    last = #marked_lines,
  })[direction]
  -- - Ensure that index is inside array
  ind = (ind - 1) % #marked_lines + 1

  -- Put cursor on target marker
  vim.api.nvim_win_set_cursor(0, { marked_lines[ind], 0 })
end

MiniGoto.diagnostic = function(direction, opts)
  if not vim.tbl_contains({ 'first', 'prev', 'next', 'last', 'next_buf', 'prev_buf' }, direction) then
    H.error(
      [[In `diagnostic()` argument `direction` should be one of 'first', 'prev', 'next', 'last', 'next_buf', 'prev_buf'.]]
    )
  end
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1 }, opts or {})

  -- TODO: Add support for 'next_buf'/'prev_buf' (first diagnostic in some of
  -- next/prev buffer)

  if direction == 'first' then vim.diagnostic.goto_next({ cursor_position = { 1, 0 } }) end
  if direction == 'prev' then vim.diagnostic.goto_prev() end
  if direction == 'next' then vim.diagnostic.goto_next() end
  if direction == 'last' then vim.diagnostic.goto_prev({ cursor_position = { 1, 0 } }) end
end

MiniGoto.file = function(direction, opts)
  if not vim.tbl_contains({ 'first', 'prev', 'next', 'last', 'next_dir', 'prev_dir' }, direction) then
    H.error(
      [[In `file()` argument `direction` should be one of 'first', 'prev', 'next', 'last', 'next_dir', 'prev_dir'.]]
    )
  end
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1 }, opts or {})

  -- TODO
  H.error('Not implemented')
end

MiniGoto.indent = function(direction, opts)
  if not vim.tbl_contains({ 'prev_zero', 'prev', 'next', 'next_zero' }, direction) then
    H.error([[In `file()` argument `direction` should be one of 'prev_zero', 'prev', 'next', 'next_zero'.]])
  end
  opts = vim.tbl_deep_extend('force', { count = vim.v.count1 }, opts or {})

  -- TODO
  H.error('Not implemented')
end

MiniGoto.jump = function(direction, opts)
  if not vim.tbl_contains({ 'first', 'prev', 'next', 'last', 'next_buf', 'prev_buf' }, direction) then
    H.error(
      [[In `jump()` argument `direction` should be one of 'first', 'prev', 'next', 'last', 'next_buf', 'prev_buf'.]]
    )
  end
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1 }, opts or {})

  -- TODO
  H.error('Not implemented')
end

MiniGoto.location = function(direction, opts)
  if not vim.tbl_contains({ 'first', 'prev', 'next', 'last', 'prev_buf', 'next_buf' }, direction) then
    H.error(
      [[In `location()` argument `direction` should be one of 'first', 'prev', 'next', 'last', 'prev_buf', 'next_buf'.]]
    )
  end
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1 }, opts or {})

  if direction == 'first' then vim.cmd('lfirst | normal! zvzz') end
  if direction == 'last' then vim.cmd('llast | normal! zvzz') end

  -- TODO: should wrap around (possibly behind option)
  if direction == 'prev' then vim.cmd(opts.n_times .. 'lprevious | normal! zvzz') end
  if direction == 'next' then vim.cmd(opts.n_times .. 'lnext | normal! zvzz') end

  -- TODO
  -- if direction == 'prev_next' then  end
  -- if direction == 'next_next' then  end
end

MiniGoto.quickfix = function(direction, opts)
  if not vim.tbl_contains({ 'first', 'prev', 'next', 'last', 'prev_buf', 'next_buf' }, direction) then
    H.error(
      [[In `quickfix()` argument `direction` should be one of 'first', 'prev', 'next', 'last', 'prev_buf', 'next_buf'.]]
    )
  end
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1 }, opts or {})

  if direction == 'first' then vim.cmd('cfirst | normal! zvzz') end
  if direction == 'last' then vim.cmd('clast | normal! zvzz') end

  -- TODO: should wrap around (possibly behind option)
  if direction == 'prev' then vim.cmd(opts.n_times .. 'cprevious | normal! zvzz') end
  if direction == 'next' then vim.cmd(opts.n_times .. 'cnext | normal! zvzz') end

  -- TODO
  -- if direction == 'prev_next' then  end
  -- if direction == 'next_next' then  end
end

MiniGoto.window = function(direction, opts)
  -- NOTE: these solutions are easier, but have drawbacks:
  -- - Repeat `<C-w>w` / `<C-w>W` `opts.count` times. This causes occasional
  --   flickering due to `WinLeave/WinEnter` events.
  -- - Use `<C-w>{count}w` / `<C-w>{count}W` with correctly computed `{count}`.
  --   This doesn't work well with floating windows (may focus when shouldn't).

  if not vim.tbl_contains({ 'first', 'prev', 'next', 'last' }, direction) then
    H.error([[In `window()` argument `direction` should be one of 'first', 'prev', 'next', 'last'.]])
  end
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1 }, opts or {})

  -- Compute list of normal windows in "natural" order.
  local cur_winnr, cur_winnr_ind = vim.fn.winnr(), nil
  local normal_windows = {}
  -- TODO: Optimize to not traverse all windows
  for i = 1, vim.fn.winnr('$') do
    local win_id = vim.fn.win_getid(i)
    local is_normal = vim.api.nvim_win_get_config(win_id).relative == ''
    if is_normal then
      table.insert(normal_windows, win_id)

      -- Track array index of current window
      if cur_winnr == i then cur_winnr_ind = #normal_windows end
    end
  end
  -- - Correct for when current window is not found (like in float)
  cur_winnr_ind = cur_winnr_ind or 1

  -- Compute array index of target window
  local ind = ({
    first = 1,
    prev = cur_winnr_ind - opts.n_times,
    next = cur_winnr_ind + opts.n_times,
    last = #normal_windows,
  })[direction]
  -- - Ensure that index is inside array
  ind = (ind - 1) % #normal_windows + 1

  -- Focus target window
  vim.api.nvim_set_current_win(normal_windows[ind])
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniGoto.config

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    mapping_suffixes = { config.mapping_suffixes, 'table' },
  })

  vim.validate({
    ['mapping_suffixes.buffer'] = { config.mapping_suffixes.buffer, 'string' },
    ['mapping_suffixes.comment'] = { config.mapping_suffixes.comment, 'string' },
    ['mapping_suffixes.conflict'] = { config.mapping_suffixes.conflict, 'string' },
    ['mapping_suffixes.diagnostic'] = { config.mapping_suffixes.diagnostic, 'string' },
    ['mapping_suffixes.file'] = { config.mapping_suffixes.file, 'string' },
    ['mapping_suffixes.indent'] = { config.mapping_suffixes.indent, 'string' },
    ['mapping_suffixes.jump'] = { config.mapping_suffixes.jump, 'string' },
    ['mapping_suffixes.location'] = { config.mapping_suffixes.location, 'string' },
    ['mapping_suffixes.quickfix'] = { config.mapping_suffixes.quickfix, 'string' },
    ['mapping_suffixes.window'] = { config.mapping_suffixes.window, 'string' },
  })

  return config
end

--stylua: ignore
H.apply_config = function(config)
  MiniGoto.config = config

  -- Make mappings
  local suffixes = config.mapping_suffixes

  if suffixes.buffer ~= '' then
    local low, up, _ = H.get_suffix_variants(suffixes.buffer)
    H.map('n', '[' .. low, "<Cmd>lua MiniGoto.buffer('prev')<CR>",  { desc = 'Go to previous buffer' })
    H.map('n', ']' .. low, "<Cmd>lua MiniGoto.buffer('next')<CR>",  { desc = 'Go to next buffer' })
    H.map('n', '[' .. up,  "<Cmd>lua MiniGoto.buffer('first')<CR>", { desc = 'Go to first buffer' })
    H.map('n', ']' .. up,  "<Cmd>lua MiniGoto.buffer('last')<CR>",  { desc = 'Go to last buffer' })
  end

  if suffixes.comment ~= '' then
    local low, up, _ = H.get_suffix_variants(suffixes.comment)
    H.map('n', '[' .. low, "<Cmd>lua MiniGoto.comment('prev')<CR>",  { desc = 'Go to previous comment' })
    H.map('n', ']' .. low, "<Cmd>lua MiniGoto.comment('next')<CR>",  { desc = 'Go to next comment' })
    H.map('n', '[' .. up,  "<Cmd>lua MiniGoto.comment('first')<CR>", { desc = 'Go to first comment' })
    H.map('n', ']' .. up,  "<Cmd>lua MiniGoto.comment('last')<CR>",  { desc = 'Go to last comment' })
  end

  if suffixes.conflict ~= '' then
    local low, up, ctrl = H.get_suffix_variants(suffixes.conflict)
    H.map('n', '[' .. low, "<Cmd>lua MiniGoto.conflict('prev')<CR>",  { desc = 'Go to previous conflict' })
    H.map('x', '[' .. low, "<Cmd>lua MiniGoto.conflict('prev')<CR>",  { desc = 'Go to previous conflict' })
    H.map('o', '[' .. low, "V<Cmd>lua MiniGoto.conflict('prev')<CR>", { desc = 'Go to previous conflict' })
    H.map('n', ']' .. low, "<Cmd>lua MiniGoto.conflict('next')<CR>",  { desc = 'Go to next conflict' })
    H.map('x', ']' .. low, "<Cmd>lua MiniGoto.conflict('next')<CR>",  { desc = 'Go to next conflict' })
    H.map('o', ']' .. low, "V<Cmd>lua MiniGoto.conflict('next')<CR>", { desc = 'Go to next conflict' })

    H.map('n', '[' .. up,   "<Cmd>lua MiniGoto.conflict('first')<CR>",    { desc = 'Go to first conflict' })
    H.map('n', ']' .. up,   "<Cmd>lua MiniGoto.conflict('last')<CR>",     { desc = 'Go to last conflict' })
    H.map('n', '[' .. ctrl, "<Cmd>lua MiniGoto.conflict('prev_buf')<CR>", { desc = 'Go to conflict in previous buffer' })
    H.map('n', ']' .. ctrl, "<Cmd>lua MiniGoto.conflict('next_buf')<CR>", { desc = 'Go to conflict in next buffer' })
  end

  if suffixes.diagnostic ~= '' then
    local low, up, ctrl = H.get_suffix_variants(suffixes.diagnostic)
    H.map('n', '[' .. low, "<Cmd>lua MiniGoto.diagnostic('prev')<CR>",  { desc = 'Go to previous diagnostic' })
    H.map('x', '[' .. low, "<Cmd>lua MiniGoto.diagnostic('prev')<CR>",  { desc = 'Go to previous diagnostic' })
    H.map('o', '[' .. low, "V<Cmd>lua MiniGoto.diagnostic('prev')<CR>", { desc = 'Go to previous diagnostic' })
    H.map('n', ']' .. low, "<Cmd>lua MiniGoto.diagnostic('next')<CR>",  { desc = 'Go to next diagnostic' })
    H.map('x', ']' .. low, "<Cmd>lua MiniGoto.diagnostic('next')<CR>",  { desc = 'Go to next diagnostic' })
    H.map('o', ']' .. low, "V<Cmd>lua MiniGoto.diagnostic('next')<CR>", { desc = 'Go to next diagnostic' })

    H.map('n', '[' .. up,   "<Cmd>lua MiniGoto.diagnostic('first')<CR>",    { desc = 'Go to first diagnostic' })
    H.map('n', ']' .. up,   "<Cmd>lua MiniGoto.diagnostic('last')<CR>",     { desc = 'Go to last diagnostic' })
    H.map('n', '[' .. ctrl, "<Cmd>lua MiniGoto.diagnostic('prev_buf')<CR>", { desc = 'Go to diagnostic in previous buffer' })
    H.map('n', ']' .. ctrl, "<Cmd>lua MiniGoto.diagnostic('next_buf')<CR>", { desc = 'Go to diagnostic in next buffer' })
  end

  if suffixes.file ~= '' then
    local low, up, ctrl = H.get_suffix_variants(suffixes.file)
    H.map('n', '[' .. low,  "<Cmd>lua MiniGoto.file('prev')<CR>",     { desc = 'Go to previous file' })
    H.map('n', ']' .. low,  "<Cmd>lua MiniGoto.file('next')<CR>",     { desc = 'Go to next file' })
    H.map('n', '[' .. up,   "<Cmd>lua MiniGoto.file('first')<CR>",    { desc = 'Go to first file' })
    H.map('n', ']' .. up,   "<Cmd>lua MiniGoto.file('last')<CR>",     { desc = 'Go to last file' })
    H.map('n', '[' .. ctrl, "<Cmd>lua MiniGoto.file('prev_dir')<CR>", { desc = 'Go to file in previous directory' })
    H.map('n', ']' .. ctrl, "<Cmd>lua MiniGoto.file('next_dir')<CR>", { desc = 'Go to file in next directory' })
  end

  if suffixes.indent ~= '' then
    local low, up, _ = H.get_suffix_variants(suffixes.indent)
    H.map('n', '[' .. low, "<Cmd>lua MiniGoto.indent('prev')<CR>",  { desc = 'Go to previous indent' })
    H.map('x', '[' .. low, "<Cmd>lua MiniGoto.indent('prev')<CR>",  { desc = 'Go to previous indent' })
    H.map('o', '[' .. low, "V<Cmd>lua MiniGoto.indent('prev')<CR>", { desc = 'Go to previous indent' })
    H.map('n', ']' .. low, "<Cmd>lua MiniGoto.indent('next')<CR>",  { desc = 'Go to next indent' })
    H.map('x', ']' .. low, "<Cmd>lua MiniGoto.indent('next')<CR>",  { desc = 'Go to next indent' })
    H.map('o', ']' .. low, "V<Cmd>lua MiniGoto.indent('next')<CR>", { desc = 'Go to next indent' })

    H.map('n', '[' .. up, "<Cmd>lua MiniGoto.indent('prev_zero')<CR>",  { desc = 'Go to previous zero indent' })
    H.map('x', '[' .. up, "<Cmd>lua MiniGoto.indent('prev_zero')<CR>",  { desc = 'Go to previous zero indent' })
    H.map('o', '[' .. up, "V<Cmd>lua MiniGoto.indent('prev_zero')<CR>", { desc = 'Go to previous zero indent' })
    H.map('n', ']' .. up, "<Cmd>lua MiniGoto.indent('next_zero')<CR>",  { desc = 'Go to next zero indent' })
    H.map('x', ']' .. up, "<Cmd>lua MiniGoto.indent('next_zero')<CR>",  { desc = 'Go to next zero indent' })
    H.map('o', ']' .. up, "V<Cmd>lua MiniGoto.indent('next_zero')<CR>", { desc = 'Go to next zero indent' })
  end

  if suffixes.jump ~= '' then
    local low, up, ctrl = H.get_suffix_variants(suffixes.jump)
    H.map('n', '[' .. low, "<Cmd>lua MiniGoto.jump('prev')<CR>",  { desc = 'Go to previous jump' })
    H.map('x', '[' .. low, "<Cmd>lua MiniGoto.jump('prev')<CR>",  { desc = 'Go to previous jump' })
    H.map('o', '[' .. low, "V<Cmd>lua MiniGoto.jump('prev')<CR>", { desc = 'Go to previous jump' })
    H.map('n', ']' .. low, "<Cmd>lua MiniGoto.jump('next')<CR>",  { desc = 'Go to next jump' })
    H.map('x', ']' .. low, "<Cmd>lua MiniGoto.jump('next')<CR>",  { desc = 'Go to next jump' })
    H.map('o', ']' .. low, "V<Cmd>lua MiniGoto.jump('next')<CR>", { desc = 'Go to next jump' })

    H.map('n', '[' .. up,   "<Cmd>lua MiniGoto.jump('first')<CR>",    { desc = 'Go to first jump' })
    H.map('n', ']' .. up,   "<Cmd>lua MiniGoto.jump('last')<CR>",     { desc = 'Go to last jump' })
    H.map('n', '[' .. ctrl, "<Cmd>lua MiniGoto.jump('prev_buf')<CR>", { desc = 'Go to jump in previous buffer' })
    H.map('n', ']' .. ctrl, "<Cmd>lua MiniGoto.jump('next_buf')<CR>", { desc = 'Go to jump in next buffer' })
  end

  if suffixes.location ~= '' then
    local low, up, ctrl = H.get_suffix_variants(suffixes.location)
    H.map('n', '[' .. low,  "<Cmd>lua MiniGoto.location('prev')<CR>",     { desc = 'Go to previous location' })
    H.map('n', ']' .. low,  "<Cmd>lua MiniGoto.location('next')<CR>",     { desc = 'Go to next location' })
    H.map('n', '[' .. up,   "<Cmd>lua MiniGoto.location('first')<CR>",    { desc = 'Go to first location' })
    H.map('n', ']' .. up,   "<Cmd>lua MiniGoto.location('last')<CR>",     { desc = 'Go to last location' })
    H.map('n', '[' .. ctrl, "<Cmd>lua MiniGoto.location('prev_buf')<CR>", { desc = 'Go to previous location in another buffer' })
    H.map('n', ']' .. ctrl, "<Cmd>lua MiniGoto.location('next_buf')<CR>", { desc = 'Go to next location in another buffer' })
  end

  if suffixes.quickfix ~= '' then
    local low, up, ctrl = H.get_suffix_variants(suffixes.quickfix)
    H.map('n', '[' .. low,  "<Cmd>lua MiniGoto.quickfix('prev')<CR>",     { desc = 'Go to previous quickfix' })
    H.map('n', ']' .. low,  "<Cmd>lua MiniGoto.quickfix('next')<CR>",     { desc = 'Go to next quickfix' })
    H.map('n', '[' .. up,   "<Cmd>lua MiniGoto.quickfix('first')<CR>",    { desc = 'Go to first quickfix' })
    H.map('n', ']' .. up,   "<Cmd>lua MiniGoto.quickfix('last')<CR>",     { desc = 'Go to last quickfix' })
    H.map('n', '[' .. ctrl, "<Cmd>lua MiniGoto.quickfix('prev_buf')<CR>", { desc = 'Go to previous quickfix in another buffer' })
    H.map('n', ']' .. ctrl, "<Cmd>lua MiniGoto.quickfix('next_buf')<CR>", { desc = 'Go to next quickfix in another buffer' })
  end

  if suffixes.window ~= '' then
    local low, up, _ = H.get_suffix_variants(suffixes.window)
    H.map('n', '[' .. low, "<Cmd>lua MiniGoto.window('prev')<CR>",  { desc = 'Go to previous window' })
    H.map('n', ']' .. low, "<Cmd>lua MiniGoto.window('next')<CR>",  { desc = 'Go to next window' })
    H.map('n', '[' .. up,  "<Cmd>lua MiniGoto.window('first')<CR>", { desc = 'Go to first window' })
    H.map('n', ']' .. up,  "<Cmd>lua MiniGoto.window('last')<CR>",  { desc = 'Go to last window' })
  end
end

H.get_suffix_variants = function(char)
  local lower, upper = char:lower(), char:upper()
  return lower, upper, string.format('<C-%s>', lower)
end

H.is_disabled = function() return vim.g.minigoto_disable == true or vim.b.minigoto_disable == true end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.goto) %s', msg), 0) end

H.validate_if = function(predicate, x, x_name)
  local is_valid, msg = predicate(x, x_name)
  if not is_valid then H.error(msg) end
end

H.map = function(mode, key, rhs, opts)
  if key == '' then return end

  opts = vim.tbl_deep_extend('force', { noremap = true, silent = true }, opts or {})

  -- Use mapping description only in Neovim>=0.7
  if vim.fn.has('nvim-0.7') == 0 then opts.desc = nil end

  vim.api.nvim_set_keymap(mode, key, rhs, opts)
end

return MiniGoto
