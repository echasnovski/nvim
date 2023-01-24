-- MIT License Copyright (c) 2023 Evgeni Chasnovski

-- TODO
--
-- Code:
-- - Consider renaming to 'mini.next'.
-- - Think about renaming conflict suffix to 'n' (as in 'unimpaired.vim').
-- - Other todos across code.
-- - Ensure the following meaning of `n_times` is followed as much as possible:
--     - For 'first' - it is `n_times - 1` forward starting from first one.
--     - For 'prev' - it is `n_times` backward starting from current one.
--     - For 'next' - it is `n_times` forward starting from current one.
--     - For 'last' - it is `n_times - 1` backward starting from last one.
-- - Ensure that moves guaranteed to be inside current buffer have mappings in
--   Normal, Visual, and Operator-pending modes.
-- - Consider modifying *all* code to have three parts:
--     - Construct array plus current index (with possible flag `exact_index`);
--     - Compute target index (with or without wrapping around edges).
--     - Perform action on entry with target index.
-- - Refactor and clean up with possible abstractions.
--
-- Tests:
--
-- Docs:
-- - Mention that it is ok to not map defaults and use functions manually.
-- - General implementation idea is usually as follows:
--     - Construct array of valid targets and the current index in this array.
--     - Depending on `direction`:
--         - For 'first' - it is `n_times - 1` forward starting from first one.
--         - For 'prev' - it is `n_times` backward starting from current one.
--         - For 'next' - it is `n_times` forward starting from current one.
--         - For 'last' - it is `n_times - 1` backward starting from last one.
--     - Walking along array is usually done with wrapping around edges
--       (`buffer`, `window`, `quickfix`), but may be not (`jump`, `indent`).

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
  if direction == 'last' then vim.cmd('blast') end

  local n_times = opts.n_times - ((direction == 'first' or direction == 'last') and 1 or 0)
  if n_times <= 0 then return end

  local command = (direction == 'first' or direction == 'next') and 'bnext' or 'bprevious'
  vim.cmd(n_times .. command)
end

MiniGoto.comment = function(direction, opts)
  if not vim.tbl_contains({ 'first', 'prev', 'next', 'last' }, direction) then
    H.error([[In `comment()` argument `direction` should be one of 'first', 'prev', 'next', 'last'.]])
  end
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1 }, opts or {})

  -- Make checker for if string is commented.
  local left, right = unpack(vim.fn.split(vim.o.commentstring, '%s'))
  right = right or ''

  -- - String is commented if it has structure:
  --   <space> <left> <anything> <right> <space>
  local regex = string.format('^%%s-%s.*%s%%s-$', vim.pesc(vim.trim(left)), vim.pesc(vim.trim(right)))
  local is_commented = function(line) return line:find(regex) ~= nil end

  -- Construct array of comment block starting lines
  local cur_line, lines = vim.fn.line('.'), vim.api.nvim_buf_get_lines(0, 0, -1, true)
  local comment_starts, prev_is_commented = {}, false
  local cur_line_ind
  for i, l in ipairs(lines) do
    local is_comment = is_commented(l)
    if is_comment and not prev_is_commented then table.insert(comment_starts, i) end
    prev_is_commented = is_comment

    -- Track array index of current line (as *index of previous comment*)
    if cur_line == i then cur_line_ind = #comment_starts end
  end

  -- Do nothing if there is no comments
  if #comment_starts == 0 then return end

  -- Compute array index of target comment start
  local is_at_marker = cur_line == comment_starts[cur_line_ind]
  local ind = ({
    first = opts.n_times,
    -- Move by 1 array index less if already at the "previous" marker
    prev = cur_line_ind - opts.n_times + (is_at_marker and 0 or 1),
    next = cur_line_ind + opts.n_times,
    last = #comment_starts - (opts.n_times - 1),
  })[direction]
  -- - Ensure that index is inside array
  ind = (ind - 1) % #comment_starts + 1

  -- Put cursor on first non-blank character of target comment start
  vim.api.nvim_win_set_cursor(0, { comment_starts[ind], 0 })
  vim.cmd('normal! ^')
end

MiniGoto.conflict = function(direction, opts)
  if not vim.tbl_contains({ 'first', 'prev', 'next', 'last' }, direction) then
    H.error([[In `comment()` argument `direction` should be one of 'first', 'prev', 'next', 'last'.]])
  end
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1 }, opts or {})

  -- Compute list of lines as conflict markers
  local marked_lines = {}
  local cur_line, cur_line_ind = vim.fn.line('.'), nil
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, true)
  for i, l in ipairs(lines) do
    if H.is_conflict_mark(l) then table.insert(marked_lines, i) end

    -- Track array index of current line (as *index of previous marker*)
    if cur_line <= i then cur_line_ind = cur_line_ind or #marked_lines end
  end

  -- Do nothing if there are no conflict markers
  if #marked_lines == 0 then return end

  -- Compute array index of target marker
  local is_at_marker = cur_line == marked_lines[cur_line_ind]
  local ind = ({
    first = opts.n_times,
    -- Move by 1 array index less if already at the "previous" marker
    prev = cur_line_ind - opts.n_times + (is_at_marker and 0 or 1),
    next = cur_line_ind + opts.n_times,
    last = #marked_lines - (opts.n_times - 1),
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
  -- next/prev buffer) and `opts.n_times`.

  if direction == 'first' then vim.diagnostic.goto_next({ cursor_position = { 1, 0 } }) end
  if direction == 'prev' then vim.diagnostic.goto_prev() end
  if direction == 'next' then vim.diagnostic.goto_next() end
  if direction == 'last' then vim.diagnostic.goto_prev({ cursor_position = { 1, 0 } }) end
end

MiniGoto.file = function(direction, opts)
  if not vim.tbl_contains({ 'first', 'prev', 'next', 'last' }, direction) then
    H.error([[In `file()` argument `direction` should be one of 'first', 'prev', 'next', 'last'.]])
  end
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1 }, opts or {})

  -- Compute target directory
  local cur_file_path = vim.api.nvim_buf_get_name(0)
  local dir_path = cur_file_path ~= '' and vim.fn.fnamemodify(cur_file_path, ':p:h') or vim.fn.getcwd()

  -- Compute sorted array of all files in target directory
  local dir_handle = vim.loop.fs_scandir(dir_path)
  local iterator = function() return vim.loop.fs_scandir_next(dir_handle) end

  local files = {}
  for path, path_type in iterator do
    if path_type == 'file' then table.insert(files, path) end
  end

  if #files == 0 then return end
  -- - Sort files ignoring case
  table.sort(files, function(x, y) return x:lower() < y:lower() end)

  -- Compute array index of current buffer file
  local cur_file_ind = 1
  if cur_file_path ~= '' then
    local cur_file_basename = vim.fn.fnamemodify(cur_file_path, ':t')
    for i, file_name in ipairs(files) do
      if cur_file_basename == file_name then
        cur_file_ind = i
        break
      end
    end
  end

  -- Compute array index of target file
  local ind = ({
    first = opts.n_times,
    prev = cur_file_ind - opts.n_times,
    next = cur_file_ind + opts.n_times,
    last = #files - (opts.n_times - 1),
  })[direction]
  -- - Ensure that index is inside array
  ind = (ind - 1) % #files + 1

  -- Open target file
  local path_sep = package.config:sub(1, 1)
  local target_path = dir_path .. path_sep .. files[ind]
  vim.cmd('edit ' .. target_path)
end

MiniGoto.indent = function(direction, opts)
  if not vim.tbl_contains({ 'prev_zero', 'prev', 'next', 'next_zero' }, direction) then
    H.error([[In `file()` argument `direction` should be one of 'prev_zero', 'prev', 'next', 'next_zero'.]])
  end
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1 }, opts or {})

  -- Compute loop data
  local is_up = direction == 'prev_zero' or direction == 'prev'
  local start_line = vim.fn.line('.')
  local iter_line_fun = is_up and vim.fn.prevnonblank or vim.fn.nextnonblank
  -- - Make it work for empty start line
  local start_indent = vim.fn.indent(iter_line_fun(start_line))

  -- Don't move if already on minimum indent
  if start_indent == 0 then return end

  -- Loop until indent is decreased `n_times` times
  local cur_line, step = start_line, is_up and -1 or 1
  local n_times, cur_n_times = opts.n_times, 0
  local target_max_indent = (direction == 'prev_zero' or direction == 'next_zero') and 0 or (start_indent - 1)
  local target_line
  while cur_line > 0 do
    cur_line = iter_line_fun(cur_line + step)
    local new_indent = vim.fn.indent(cur_line)

    -- New indent can be negative only if line is outside of present range.
    -- Don't accept those also.
    if 0 <= new_indent and new_indent <= target_max_indent then
      -- Accept result even if can't jump exactly `n_times` times
      target_line = cur_line
      target_max_indent = new_indent - 1
      cur_n_times = cur_n_times + 1
    end

    -- Stop if reached target `n_times` or can't reduce current indent
    if n_times <= cur_n_times or target_max_indent < 0 then break end
  end

  -- Place cursor at first non-blank of target line
  if target_line == nil then return end
  vim.api.nvim_win_set_cursor(0, { target_line, 0 })
  vim.cmd('normal! ^')
end

-- Notes:
-- - Doesn't wrap around edges.
MiniGoto.jump = function(direction, opts)
  if not vim.tbl_contains({ 'first', 'prev', 'next', 'last', 'next_buf', 'prev_buf' }, direction) then
    H.error(
      [[In `jump()` argument `direction` should be one of 'first', 'prev', 'next', 'last', 'next_buf', 'prev_buf'.]]
    )
  end
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1 }, opts or {})

  -- Get jumplist data and ensure it is non-empty
  local jump_list, cur_ind = unpack(vim.fn.getjumplist())
  if #jump_list == 0 then return end
  -- - Correct for zero-indexing
  cur_ind = cur_ind + 1

  -- Construct a predicate to tell if jump entry is appropriate
  local cur_buf_id = vim.api.nvim_get_current_buf()
  local is_good_entry = function(jump_entry) return jump_entry.bufnr == cur_buf_id end
  if direction == 'next_buf' or direction == 'prev_buf' then
    is_good_entry = function(jump_entry) return jump_entry.bufnr ~= cur_buf_id end
  end

  -- Construct loop data. This approach is more efficient than constructing
  -- array of valid jumps and computing index, but is only applicable if there
  -- is no wrapping around edges.
  --stylua: ignore
  local loop_data = ({
    first    = { from = 1,           to = #jump_list, by =  1 },
    prev     = { from = cur_ind - 1, to = 1,          by = -1 },
    prev_buf = { from = cur_ind - 1, to = 1,          by = -1 },
    next     = { from = cur_ind + 1, to = #jump_list, by =  1 },
    next_buf = { from = cur_ind + 1, to = #jump_list, by =  1 },
    last     = { from = #jump_list,  to = 1,          by = -1 },
  })[direction]

  local n_times, cur_n_times = opts.n_times, 0
  local target_ind
  for ind = loop_data.from, loop_data.to, loop_data.by do
    if is_good_entry(jump_list[ind]) then
      -- Accept result even if can't jump exactly `n_times` times
      target_ind = ind
      cur_n_times = cur_n_times + 1
    end
    if n_times <= cur_n_times then break end
  end

  -- Make jump. Use builtin mappings to also update current jump entry.
  if target_ind == nil or target_ind == cur_ind then return end

  local ind_diff = target_ind - cur_ind
  local key = ind_diff > 0 and '\t' or '\15'
  vim.cmd('normal! ' .. math.abs(ind_diff) .. key)
end

MiniGoto.location = function(direction, opts)
  if not vim.tbl_contains({ 'first', 'prev', 'next', 'last' }, direction) then
    H.error([[In `location()` argument `direction` should be one of 'first', 'prev', 'next', 'last'.]])
  end
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1 }, opts or {})

  H.goto_qf_loc('location', direction, opts)
end

MiniGoto.quickfix = function(direction, opts)
  if not vim.tbl_contains({ 'first', 'prev', 'next', 'last' }, direction) then
    H.error([[In `quickfix()` argument `direction` should be one of 'first', 'prev', 'next', 'last'.]])
  end
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1 }, opts or {})

  H.goto_qf_loc('quickfix', direction, opts)
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

  -- Compute list of normal windows in "natural" order. Can not be optimized to
  -- not traverse all windows because it has to know how many **normal**
  -- windows there are to correctly handle wrapping around edges.
  local cur_winnr, cur_winnr_ind = vim.fn.winnr(), nil
  local normal_windows = {}
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
    first = opts.n_times,
    prev = cur_winnr_ind - opts.n_times,
    next = cur_winnr_ind + opts.n_times,
    last = #normal_windows - (opts.n_times - 1),
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
    H.map('x', '[' .. low, "<Cmd>lua MiniGoto.comment('prev')<CR>",  { desc = 'Go to previous comment' })
    H.map('o', '[' .. low, "V<Cmd>lua MiniGoto.comment('prev')<CR>", { desc = 'Go to previous comment' })
    H.map('n', ']' .. low, "<Cmd>lua MiniGoto.comment('next')<CR>",  { desc = 'Go to next comment' })
    H.map('x', ']' .. low, "<Cmd>lua MiniGoto.comment('next')<CR>",  { desc = 'Go to next comment' })
    H.map('o', ']' .. low, "V<Cmd>lua MiniGoto.comment('next')<CR>", { desc = 'Go to next comment' })

    H.map('n', '[' .. up, "<Cmd>lua MiniGoto.comment('first')<CR>",  { desc = 'Go to first comment' })
    H.map('x', '[' .. up, "<Cmd>lua MiniGoto.comment('first')<CR>",  { desc = 'Go to first comment' })
    H.map('o', '[' .. up, "V<Cmd>lua MiniGoto.comment('first')<CR>", { desc = 'Go to first comment' })
    H.map('n', ']' .. up, "<Cmd>lua MiniGoto.comment('last')<CR>",   { desc = 'Go to last comment' })
    H.map('x', ']' .. up, "<Cmd>lua MiniGoto.comment('last')<CR>",   { desc = 'Go to last comment' })
    H.map('o', ']' .. up, "V<Cmd>lua MiniGoto.comment('last')<CR>",  { desc = 'Go to last comment' })
  end

  if suffixes.conflict ~= '' then
    local low, up, _ = H.get_suffix_variants(suffixes.conflict)
    H.map('n', '[' .. low, "<Cmd>lua MiniGoto.conflict('prev')<CR>",  { desc = 'Go to previous conflict' })
    H.map('x', '[' .. low, "<Cmd>lua MiniGoto.conflict('prev')<CR>",  { desc = 'Go to previous conflict' })
    H.map('o', '[' .. low, "V<Cmd>lua MiniGoto.conflict('prev')<CR>", { desc = 'Go to previous conflict' })
    H.map('n', ']' .. low, "<Cmd>lua MiniGoto.conflict('next')<CR>",  { desc = 'Go to next conflict' })
    H.map('x', ']' .. low, "<Cmd>lua MiniGoto.conflict('next')<CR>",  { desc = 'Go to next conflict' })
    H.map('o', ']' .. low, "V<Cmd>lua MiniGoto.conflict('next')<CR>", { desc = 'Go to next conflict' })

    H.map('n', '[' .. up, "<Cmd>lua MiniGoto.conflict('first')<CR>",  { desc = 'Go to first conflict' })
    H.map('x', '[' .. up, "<Cmd>lua MiniGoto.conflict('first')<CR>",  { desc = 'Go to first conflict' })
    H.map('o', '[' .. up, "V<Cmd>lua MiniGoto.conflict('first')<CR>", { desc = 'Go to first conflict' })
    H.map('n', ']' .. up, "<Cmd>lua MiniGoto.conflict('last')<CR>",   { desc = 'Go to last conflict' })
    H.map('x', ']' .. up, "<Cmd>lua MiniGoto.conflict('last')<CR>",   { desc = 'Go to last conflict' })
    H.map('o', ']' .. up, "V<Cmd>lua MiniGoto.conflict('last')<CR>",  { desc = 'Go to last conflict' })
  end

  if suffixes.diagnostic ~= '' then
    local low, up, ctrl = H.get_suffix_variants(suffixes.diagnostic)
    H.map('n', '[' .. low, "<Cmd>lua MiniGoto.diagnostic('prev')<CR>",  { desc = 'Go to previous diagnostic' })
    H.map('x', '[' .. low, "<Cmd>lua MiniGoto.diagnostic('prev')<CR>",  { desc = 'Go to previous diagnostic' })
    H.map('o', '[' .. low, "V<Cmd>lua MiniGoto.diagnostic('prev')<CR>", { desc = 'Go to previous diagnostic' })
    H.map('n', ']' .. low, "<Cmd>lua MiniGoto.diagnostic('next')<CR>",  { desc = 'Go to next diagnostic' })
    H.map('x', ']' .. low, "<Cmd>lua MiniGoto.diagnostic('next')<CR>",  { desc = 'Go to next diagnostic' })
    H.map('o', ']' .. low, "V<Cmd>lua MiniGoto.diagnostic('next')<CR>", { desc = 'Go to next diagnostic' })

    H.map('n', '[' .. up, "<Cmd>lua MiniGoto.diagnostic('first')<CR>",  { desc = 'Go to first diagnostic' })
    H.map('x', '[' .. up, "<Cmd>lua MiniGoto.diagnostic('first')<CR>",  { desc = 'Go to first diagnostic' })
    H.map('o', '[' .. up, "V<Cmd>lua MiniGoto.diagnostic('first')<CR>", { desc = 'Go to first diagnostic' })
    H.map('n', ']' .. up, "<Cmd>lua MiniGoto.diagnostic('last')<CR>",   { desc = 'Go to last diagnostic' })
    H.map('x', ']' .. up, "<Cmd>lua MiniGoto.diagnostic('last')<CR>",   { desc = 'Go to last diagnostic' })
    H.map('o', ']' .. up, "V<Cmd>lua MiniGoto.diagnostic('last')<CR>",  { desc = 'Go to last diagnostic' })

    H.map('n', '[' .. ctrl, "<Cmd>lua MiniGoto.diagnostic('prev_buf')<CR>", { desc = 'Go to diagnostic in previous buffer' })
    H.map('n', ']' .. ctrl, "<Cmd>lua MiniGoto.diagnostic('next_buf')<CR>", { desc = 'Go to diagnostic in next buffer' })
  end

  if suffixes.file ~= '' then
    local low, up, _ = H.get_suffix_variants(suffixes.file)
    H.map('n', '[' .. low,  "<Cmd>lua MiniGoto.file('prev')<CR>",     { desc = 'Go to previous file' })
    H.map('n', ']' .. low,  "<Cmd>lua MiniGoto.file('next')<CR>",     { desc = 'Go to next file' })
    H.map('n', '[' .. up,   "<Cmd>lua MiniGoto.file('first')<CR>",    { desc = 'Go to first file' })
    H.map('n', ']' .. up,   "<Cmd>lua MiniGoto.file('last')<CR>",     { desc = 'Go to last file' })
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

    H.map('n', '[' .. up, "<Cmd>lua MiniGoto.jump('first')<CR>",  { desc = 'Go to first jump' })
    H.map('x', '[' .. up, "<Cmd>lua MiniGoto.jump('first')<CR>",  { desc = 'Go to first jump' })
    H.map('o', '[' .. up, "v<Cmd>lua MiniGoto.jump('first')<CR>", { desc = 'Go to first jump' })
    H.map('n', ']' .. up, "<Cmd>lua MiniGoto.jump('last')<CR>",   { desc = 'Go to last jump' })
    H.map('x', ']' .. up, "<Cmd>lua MiniGoto.jump('last')<CR>",   { desc = 'Go to last jump' })
    H.map('o', ']' .. up, "v<Cmd>lua MiniGoto.jump('last')<CR>",  { desc = 'Go to last jump' })

    H.map('n', '[' .. ctrl, "<Cmd>lua MiniGoto.jump('prev_buf')<CR>", { desc = 'Go to jump in previous buffer' })
    H.map('n', ']' .. ctrl, "<Cmd>lua MiniGoto.jump('next_buf')<CR>", { desc = 'Go to jump in next buffer' })
  end

  if suffixes.location ~= '' then
    local low, up, _ = H.get_suffix_variants(suffixes.location)
    H.map('n', '[' .. low, "<Cmd>lua MiniGoto.location('prev')<CR>",  { desc = 'Go to previous location' })
    H.map('n', ']' .. low, "<Cmd>lua MiniGoto.location('next')<CR>",  { desc = 'Go to next location' })
    H.map('n', '[' .. up,  "<Cmd>lua MiniGoto.location('first')<CR>", { desc = 'Go to first location' })
    H.map('n', ']' .. up,  "<Cmd>lua MiniGoto.location('last')<CR>",  { desc = 'Go to last location' })
  end

  if suffixes.quickfix ~= '' then
    local low, up, _ = H.get_suffix_variants(suffixes.quickfix)
    H.map('n', '[' .. low, "<Cmd>lua MiniGoto.quickfix('prev')<CR>",  { desc = 'Go to previous quickfix' })
    H.map('n', ']' .. low, "<Cmd>lua MiniGoto.quickfix('next')<CR>",  { desc = 'Go to next quickfix' })
    H.map('n', '[' .. up,  "<Cmd>lua MiniGoto.quickfix('first')<CR>", { desc = 'Go to first quickfix' })
    H.map('n', ']' .. up,  "<Cmd>lua MiniGoto.quickfix('last')<CR>",  { desc = 'Go to last quickfix' })
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

-- Conflicts ------------------------------------------------------------------
H.is_conflict_mark = function(line)
  local l_start = line:sub(1, 8)
  return l_start == '<<<<<<< ' or l_start == '=======' or l_start == '>>>>>>> '
end

-- Quickfix/Location lists ----------------------------------------------------
H.goto_qf_loc = function(list_type, direction, opts)
  local get_list, goto_command = vim.fn.getqflist, 'cc'
  if list_type == 'location' then
    get_list, goto_command = function(...) return vim.fn.getloclist(0, ...) end, 'll'
  end

  -- Get quickfix list and ensure it is not empty
  local qf_list = get_list()
  if #qf_list == 0 then return end

  -- Compute array index of target quickfix entry (wrapping around edges)
  local n_list, cur_ind = #qf_list, get_list({ idx = 0 }).idx
  local ind = ({
    first = opts.n_times,
    prev = cur_ind - opts.n_times,
    next = cur_ind + opts.n_times,
    last = n_list - (opts.n_times - 1),
  })[direction]
  -- - Ensure that index is inside array
  ind = (ind - 1) % n_list + 1

  -- Focus target entry, open enough folds and center
  local command = string.format('%s %d | normal! zvzz', goto_command, ind)
  vim.cmd(command)
end

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
