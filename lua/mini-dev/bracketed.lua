-- MIT License Copyright (c) 2023 Evgeni Chasnovski

-- TODO
--
-- Code:
-- - Other todos across code.
-- - Refactor and clean up to increase naming and structure consistency.
--
-- Tests:
-- - Ensure moves that guaranteed to be inside current buffer have mappings in
--   Normal, Visual, and Operator-pending modes (linewise if source is
--   linewise, charwise otherwise).
-- - Refactor common validators for 'works', 'respects `opts.n_times`', and
--   'respects `opts.wrap`'. This should save quite some lines of code.
--
-- Docs:
-- - Mention that it is ok to not map defaults and use functions manually.
-- - Mention in `conflict` about possibility of resolving merge conflicts by
--   placing cursor on `===` line and executing one of these:
--   `d]x[xdd` (choose upper part), `d[x]xdd` (choose lower part).
-- - Directions 'first' and 'last' work differently in `indent()` for
--   performance reasons.
-- - General implementation idea is usually as follows:
--     - Construct target iterator:
--         - Has idea about current state.
--         - Can go forward and backward from the state (once without wrap).
--           Returns `nil` if can't iterate.
--         - Has optional idea about edges (enables wrap and 'first'/'last'):
--             - Start edge: `forward(start_edge)` is first target state
--             - End edge: `backward(end_edge)` is last target state.
--       Like with quickfix list:
--         - State: index of current quickfix entry. 1, and number of quickfix entries.
--         - Forward and backward: add or subtract 1 if result is inside range;
--           `nil` otherwise.
--         - Edges: left - 0, right - number of quickfix entries plus 1.
--       This idea is better of computing whole array of possible targets for
--       at least two reasons:
--         - It is usually more efficient for common use cases (doesn't compute
--           whole array for relatively low `n_times`; matters in cases like
--           `comment`, `indent`).
--         - Current state is not always a part of target state (like current
--           line is not always a comment; current position is not on
--           a jumplist, etc.).
--     - Iterate target amount of times from current state in target direction.
--       This can respect wrapping around edges, etc.
--     - Apply current state.

-- Documentation ==============================================================
--- Go forward/backward with square brackets
---
--- Features:
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.bracketed').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniBracketed`
--- which you can use for scripting or manually (with `:lua MiniBracketed.*`).
---
--- See |MiniBracketed.config| for available config settings.
---
--- You can override runtime config settings (like options of sources) locally
--- to buffer inside `vim.b.minibracketed_config` which should have same structure
--- as `MiniBracketed.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons ~
---
--- - 'tpope/vim-unimpaired':
---
--- # Disabling~
---
--- To disable, set `g:minibracketed_disable` (globally) or `b:minibracketed_disable`
--- (for a buffer) to `v:true`. Considering high number of different scenarios
--- and customization intentions, writing exact rules for disabling module's
--- functionality is left to user. See |mini.nvim-disabling-recipes| for common
--- recipes.
---@tag mini.bracketed
---@tag MiniBracketed

---@diagnostic disable:undefined-field

-- Module definition ==========================================================
-- TODO: make local after release
MiniBracketed = {}
H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniBracketed.config|.
---
---@usage `require('mini.bracketed').setup({})` (replace `{}` with your `config` table)
MiniBracketed.setup = function(config)
  -- Export module
  _G.MiniBracketed = MiniBracketed

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Module behavior
  vim.api.nvim_exec(
    [[augroup MiniBracketed
        au!
        au BufEnter * lua MiniBracketed.track_oldfile()
        au TextYankPost * lua MiniBracketed.track_yank()
      augroup END]],
    false
  )
end

--stylua: ignore
--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text
MiniBracketed.config = {
  -- First-level elements are tables describing behavior of targets sources:
  -- - <suffix> - single character suffix. Used after `[` / `]` in mappings.
  --   For example, with `b` creates `[b`, `]b`, `[B`, `]B` mappings.
  --   Supply empty string `''` to not create mappings.
  -- - <opts> - table overriding source options.
  -- See `:h MiniBracketed.config` for more info.
  buffer     = { suffix = 'b', options = {} },
  comment    = { suffix = 'c', options = {} },
  conflict   = { suffix = 'x', options = {} },
  diagnostic = { suffix = 'd', options = {} },
  file       = { suffix = 'f', options = {} },
  indent     = { suffix = 'i', options = {} },
  jump       = { suffix = 'j', options = {} },
  location   = { suffix = 'l', options = {} },
  oldfile    = { suffix = 'o', options = {} },
  quickfix   = { suffix = 'q', options = {} },
  undo       = { suffix = 'u', options = {} },
  window     = { suffix = 'w', options = {} },
  yank       = { suffix = 'y', options = {} },
}
--minidoc_afterlines_end

MiniBracketed.buffer = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'backward', 'forward', 'last' }, 'buffer')
  opts =
    vim.tbl_deep_extend('force', { n_times = vim.v.count1, wrap = true }, H.get_config().buffer.options, opts or {})

  -- Define iterator that traverses all valid listed buffers
  -- (should be same as `:bnext` / `:bprev`)
  local buf_list = vim.api.nvim_list_bufs()
  local is_listed = function(buf_id) return vim.api.nvim_buf_is_valid(buf_id) and vim.bo[buf_id].buflisted end

  local iterator = {}

  iterator.next = function(buf_id)
    for id = buf_id + 1, buf_list[#buf_list] do
      if is_listed(id) then return id end
    end
  end

  iterator.prev = function(buf_id)
    for id = buf_id - 1, buf_list[1], -1 do
      if is_listed(id) then return id end
    end
  end

  iterator.state = vim.api.nvim_get_current_buf()
  iterator.start_edge = buf_list[1] - 1
  iterator.end_edge = buf_list[#buf_list] + 1

  -- Iterate
  local res_buf_id = MiniBracketed.advance(iterator, direction, opts)
  if res_buf_id == iterator.state then return end

  -- Apply
  vim.api.nvim_set_current_buf(res_buf_id)
end

MiniBracketed.comment = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'backward', 'forward', 'last' }, 'comment')
  opts = vim.tbl_deep_extend(
    'force',
    { block_side = 'near', n_times = vim.v.count1, wrap = true },
    H.get_config().comment.options,
    opts or {}
  )

  -- Compute loop data to traverse target commented lines in current buffer
  local is_commented = H.make_comment_checker()
  if is_commented == nil then return end

  local predicate = ({
    start = function(above, cur, _, _) return cur and not above end,
    ['end'] = function(_, cur, below, _) return cur and not below end,
    both = function(above, cur, below, _) return cur and not (above and below) end,
    near = function(_, cur, _, recent) return cur and not recent end,
  })[opts.block_side]
  if predicate == nil then return end

  -- Define iterator
  local iterator = {}

  local n_lines = vim.api.nvim_buf_line_count(0)
  iterator.next = function(line_num)
    local above, cur = is_commented(line_num), is_commented(line_num + 1)
    for lnum = line_num + 1, n_lines do
      local below = is_commented(lnum + 1)
      if predicate(above, cur, below, above) then return lnum end
      above, cur = cur, below
    end
  end

  iterator.prev = function(line_num)
    local cur, below = is_commented(line_num - 1), is_commented(line_num)
    for lnum = line_num - 1, 1, -1 do
      local above = is_commented(lnum - 1)
      if predicate(above, cur, below, below) then return lnum end
      below, cur = cur, above
    end
  end

  iterator.state = vim.fn.line('.')
  iterator.start_edge = 0
  iterator.end_edge = n_lines + 1

  -- Iterate
  local res_line_num = MiniBracketed.advance(iterator, direction, opts)
  local is_outside = res_line_num <= 0 or n_lines < res_line_num
  if res_line_num == nil or res_line_num == iterator.state or is_outside then return end

  -- Apply. Open just enough folds and put cursor on first non-blank.
  vim.api.nvim_win_set_cursor(0, { res_line_num, 0 })
  vim.cmd('normal! zv^')
end

MiniBracketed.conflict = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'backward', 'forward', 'last' }, 'conflict')
  opts =
    vim.tbl_deep_extend('force', { n_times = vim.v.count1, wrap = true }, H.get_config().conflict.options, opts or {})

  -- Define iterator that traverses all conflict markers in current buffer
  local n_lines = vim.api.nvim_buf_line_count(0)

  local iterator = {}

  iterator.next = function(line_num)
    for lnum = line_num + 1, n_lines do
      if H.is_conflict_mark(lnum) then return lnum end
    end
  end

  iterator.prev = function(line_num)
    for lnum = line_num - 1, 1, -1 do
      if H.is_conflict_mark(lnum) then return lnum end
    end
  end

  iterator.state = vim.fn.line('.')
  iterator.start_edge = 0
  iterator.end_edge = n_lines + 1

  -- Iterate
  local res_line_num = MiniBracketed.advance(iterator, direction, opts)
  local is_outside = res_line_num <= 0 or n_lines < res_line_num
  if res_line_num == nil or res_line_num == iterator.state or is_outside then return end

  -- Apply. Open just enough folds and put cursor on first non-blank.
  vim.api.nvim_win_set_cursor(0, { res_line_num, 0 })
  vim.cmd('normal! zv^')
end

MiniBracketed.diagnostic = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'backward', 'forward', 'last' }, 'diagnostic')
  opts = vim.tbl_deep_extend(
    'force',
    { n_times = vim.v.count1, severity = nil, wrap = true },
    H.get_config().diagnostic.options,
    opts or {}
  )

  -- Define iterator that traverses all diagnostic entries in current buffer
  local is_position = function(x) return type(x) == 'table' and #x == 2 end
  local diag_pos_to_cursor_pos = function(pos) return { pos[1] + 1, pos[2] } end
  local iterator = {}

  iterator.next = function(position)
    local goto_opts = { cursor_position = diag_pos_to_cursor_pos(position), severity = opts.severity, wrap = false }
    local new_pos = vim.diagnostic.get_next_pos(goto_opts)
    if not is_position(new_pos) then return end
    return new_pos
  end

  iterator.prev = function(position)
    local goto_opts = { cursor_position = diag_pos_to_cursor_pos(position), severity = opts.severity, wrap = false }
    local new_pos = vim.diagnostic.get_prev_pos(goto_opts)
    if not is_position(new_pos) then return end
    return new_pos
  end

  -- - Define states with zero-based indexing as used in `vim.diagnostic`.
  -- - Go outside of proper buffer position for `start_edge` and `end_edge` to
  --   correctly spot diagnostic entry right and start and end of buffer.
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  iterator.state = { cursor_pos[1] - 1, cursor_pos[2] }

  iterator.start_edge = { 0, -1 }

  local last_line = vim.api.nvim_buf_line_count(0)
  iterator.end_edge = { last_line - 1, vim.fn.col({ last_line, '$' }) - 1 }

  -- Iterate
  local res_pos = MiniBracketed.advance(iterator, direction, opts)
  if res_pos == nil or res_pos == iterator.state then return end

  -- Apply. Open just enough folds.
  vim.api.nvim_win_set_cursor(0, diag_pos_to_cursor_pos(res_pos))
  vim.cmd('normal! zv')
end

MiniBracketed.file = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'backward', 'forward', 'last' }, 'file')
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1, wrap = true }, H.get_config().file.options, opts or {})

  -- Get file data
  local file_data = H.get_file_data()
  if file_data == nil then return end
  local file_basenames, directory = file_data.file_basenames, file_data.directory

  -- Define iterator that traverses all found files
  local iterator = {}
  local n_files = #file_basenames

  iterator.next = function(ind)
    -- Allow advance in untrackable current buffer
    if ind == nil then return 1 end
    if n_files <= ind then return end
    return ind + 1
  end

  iterator.prev = function(ind)
    -- Allow advance in untrackable current buffer
    if ind == nil then return n_files end
    if ind <= 1 then return end
    return ind - 1
  end

  -- - Find filename array index of current buffer
  local cur_basename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':t')
  local cur_basename_ind
  if cur_basename ~= '' then
    for i, f in ipairs(file_basenames) do
      if cur_basename == f then
        cur_basename_ind = i
        break
      end
    end
  end

  iterator.state = cur_basename_ind
  iterator.start_edge = 0
  iterator.end_edge = n_files + 1

  -- Iterate
  local res_ind = MiniBracketed.advance(iterator, direction, opts)
  if res_ind == iterator.state then return end

  -- Apply. Open target_path.
  local path_sep = package.config:sub(1, 1)
  local target_path = directory .. path_sep .. file_basenames[res_ind]
  vim.cmd('edit ' .. target_path)
end

MiniBracketed.indent = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'backward', 'forward', 'last' }, 'indent')
  opts = vim.tbl_deep_extend(
    'force',
    { change_type = 'less', n_times = vim.v.count1 },
    H.get_config().indent.options,
    opts or {}
  )

  opts.wrap = false

  if direction == 'first' then
    -- For some reason using `n_times = math.huge` leads to infinite loop
    direction, opts.n_times = 'backward', vim.api.nvim_buf_line_count(0) + 1
  end
  if direction == 'last' then
    direction, opts.n_times = 'forward', vim.api.nvim_buf_line_count(0) + 1
  end

  -- Compute loop data to traverse target commented lines in current buffer
  local predicate = ({
    less = function(new, cur) return new < cur or cur == 0 end,
    more = function(new, cur) return new > cur end,
    diff = function(new, cur) return new ~= cur end,
  })[opts.change_type]
  if predicate == nil then return end

  -- Define iterator
  local iterator = {}

  iterator.next = function(cur_lnum)
    -- Correctly process empty current line
    cur_lnum = vim.fn.nextnonblank(cur_lnum)
    local cur_indent = vim.fn.indent(cur_lnum)

    local new_lnum, new_indent = cur_lnum, cur_indent
    -- Check with `new_lnum > 0` because `nextnonblank()` returns -1 if line is
    -- outside of line range
    while new_lnum > 0 do
      new_indent = vim.fn.indent(new_lnum)
      if predicate(new_indent, cur_indent) then return new_lnum end
      new_lnum = vim.fn.nextnonblank(new_lnum + 1)
    end
  end

  iterator.prev = function(cur_lnum)
    cur_lnum = vim.fn.prevnonblank(cur_lnum)
    local cur_indent = vim.fn.indent(cur_lnum)

    local new_lnum, new_indent = cur_lnum, cur_indent
    while new_lnum > 0 do
      new_indent = vim.fn.indent(new_lnum)
      if predicate(new_indent, cur_indent) then return new_lnum end
      new_lnum = vim.fn.prevnonblank(new_lnum - 1)
    end
  end

  -- - Don't add first and last states as there is no wrapping around edges
  iterator.state = vim.fn.line('.')

  -- Iterate
  local res_line_num = MiniBracketed.advance(iterator, direction, opts)
  if res_line_num == nil or res_line_num == iterator.state then return end

  -- Apply. Open just enough folds and put cursor on first non-blank.
  vim.api.nvim_win_set_cursor(0, { res_line_num, 0 })
  vim.cmd('normal! zv^')
end

MiniBracketed.jump = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'backward', 'forward', 'last' }, 'jump')
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1, wrap = true }, H.get_config().jump.options, opts or {})

  -- Define iterator that traverses all jumplist entries inside current buffer
  local cur_buf_id = vim.api.nvim_get_current_buf()
  local jump_list, cur_jump_num = unpack(vim.fn.getjumplist())
  local n_list = #jump_list
  if n_list == 0 then return end
  -- - Correct for zero-based indexing
  cur_jump_num = cur_jump_num + 1

  local iterator = {}

  local is_jump_num_from_current_buffer = function(jump_num)
    local jump_entry = jump_list[jump_num]
    if jump_entry == nil then return end
    return jump_entry.bufnr == cur_buf_id
  end

  iterator.next = function(jump_num)
    for num = jump_num + 1, n_list do
      if is_jump_num_from_current_buffer(num) then return num end
    end
  end

  iterator.prev = function(jump_num)
    for num = jump_num - 1, 1, -1 do
      if is_jump_num_from_current_buffer(num) then return num end
    end
  end

  iterator.state = cur_jump_num
  iterator.start_edge = 0
  iterator.end_edge = n_list + 1

  -- Iterate
  local res_jump_num = MiniBracketed.advance(iterator, direction, opts)
  if res_jump_num == nil then return end

  -- Apply. Make jump. Allow jumping to current jump entry as it might be
  -- different from current cursor position.
  H.make_jump(jump_list, cur_jump_num, res_jump_num)
end

MiniBracketed.location = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'backward', 'forward', 'last' }, 'location')
  opts =
    vim.tbl_deep_extend('force', { n_times = vim.v.count1, wrap = true }, H.get_config().location.options, opts or {})

  H.qf_loc_implementation('location', direction, opts)
end

-- Files ordered from oldest to newest.
MiniBracketed.oldfile = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'backward', 'forward', 'last' }, 'oldfile')
  opts =
    vim.tbl_deep_extend('force', { n_times = vim.v.count1, wrap = true }, H.get_config().oldfile.options, opts or {})

  -- Define iterator that traverses all old files
  local cur_path = vim.api.nvim_buf_get_name(0)

  H.oldfile_normalize()
  local oldfile_arr = H.oldfile_get_array()
  local n_oldfiles = #oldfile_arr

  local iterator = {}

  iterator.next = function(ind)
    -- Allow advance in untrackable current buffer
    if ind == nil then return 1 end
    if n_oldfiles <= ind then return end
    return ind + 1
  end

  iterator.prev = function(ind)
    -- Allow advance in untrackable current buffer
    if ind == nil then return n_oldfiles end
    if ind <= 1 then return end
    return ind - 1
  end

  iterator.state = H.cache.oldfile.recency[cur_path]
  iterator.start_edge = 0
  iterator.end_edge = n_oldfiles + 1

  -- Iterate
  local res_arr_ind = MiniBracketed.advance(iterator, direction, opts)
  if res_arr_ind == nil or res_arr_ind == iterator.state then return end

  -- Apply. Edit file at path while marking it not for tracking.
  H.cache.oldfile.is_advancing = true
  vim.cmd('edit ' .. oldfile_arr[res_arr_ind])
end

MiniBracketed.quickfix = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'backward', 'forward', 'last' }, 'quickfix')
  opts =
    vim.tbl_deep_extend('force', { n_times = vim.v.count1, wrap = true }, H.get_config().quickfix.options, opts or {})

  H.qf_loc_implementation('quickfix', direction, opts)
end

MiniBracketed.undo = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'backward', 'forward', 'last' }, 'undo')
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1, wrap = true }, H.get_config().undo.options, opts or {})

  -- Define iterator that traverses undo states in order they appeared
  local buf_id = vim.api.nvim_get_current_buf()
  H.undo_sync(buf_id, vim.fn.undotree())

  local iterator = {}
  local buf_history = H.cache.undo[buf_id]
  local n = #buf_history

  iterator.next = function(id)
    if id == nil or n <= id then return end
    return id + 1
  end

  iterator.prev = function(id)
    if id == nil or id <= 1 then return end
    return id - 1
  end

  iterator.state = buf_history.current_id
  iterator.start_edge = 0
  iterator.end_edge = n + 1

  -- Iterate
  local res_id = MiniBracketed.advance(iterator, direction, opts)
  if res_id == nil or res_id == iterator.state then return end

  -- Apply. Move to undo state by number while recording current history id
  buf_history.is_advancing = true
  vim.cmd('undo ' .. buf_history[res_id])

  buf_history.current_id = res_id
end

MiniBracketed.register_undo_state = function()
  local buf_id = vim.api.nvim_get_current_buf()
  local tree = vim.fn.undotree()

  -- Synchronize undo history and stop advancing
  H.undo_sync(buf_id, tree, false)

  -- Append new undo state to linear history
  local buf_history = H.cache.undo[buf_id]
  H.undo_append_state(buf_history, tree.seq_cur)
  buf_history.current_id = #buf_history
end

MiniBracketed.window = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'backward', 'forward', 'last' }, 'window')
  opts =
    vim.tbl_deep_extend('force', { n_times = vim.v.count1, wrap = true }, H.get_config().window.options, opts or {})

  -- Define iterator that traverses all normal windows in "natural" order
  local is_normal = function(win_nr)
    local win_id = vim.fn.win_getid(win_nr)
    return vim.api.nvim_win_get_config(win_id).relative == ''
  end

  local iterator = {}

  iterator.next = function(win_nr)
    for nr = win_nr + 1, vim.fn.winnr('$') do
      if is_normal(nr) then return nr end
    end
  end

  iterator.prev = function(win_nr)
    for nr = win_nr - 1, 1, -1 do
      if is_normal(nr) then return nr end
    end
  end

  iterator.state = vim.fn.winnr()
  iterator.start_edge = 0
  iterator.end_edge = vim.fn.winnr('$') + 1

  -- Iterate
  local res_win_nr = MiniBracketed.advance(iterator, direction, opts)
  if res_win_nr == iterator.state then return end

  -- Apply
  vim.api.nvim_set_current_win(vim.fn.win_getid(res_win_nr))
end

-- Replace "latest put region" with yank history entry
--
-- "Latest put region" is (in order of decreasing priority):
-- - The one from latest `yank` advance.
-- - The one registered by user with |MiniBracketed.register_put_region()|.
-- - The one taken from |`[| and |`]| marks.
--
-- There are two approaches to managing which "latest put region" will be used:
-- - Do nothing. In this case region between `[` / `]` marks will always be used
--   for first `yank` advance.
--   Although doable, this has several drawbacks: it will use latest yanked or
--   changed region or the entier buffer if marks are not set.
--   If remember to advance `yank` only after recent put operation, this should
--   work as expected.
--
-- - Remap common put operations to use |MiniBracketed.register_put_region()|.
--   After that, only regions from mapped put operations will be used for first
--   `yank` advance. Example for custom mappings (note use of |:map-expression|): >
--
--     local put_keys = { 'p', 'P' }
--     for _, lhs in ipairs(put_keys) do
--       local rhs = 'v:lua.MiniBracketed.register_put_region("' .. lhs .. '")'
--       vim.keymap.set({ 'n', 'x' }, lhs, rhs, { expr = true })
--     end
MiniBracketed.yank = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'backward', 'forward', 'last' }, 'yank')
  opts = vim.tbl_deep_extend(
    'force',
    { n_times = vim.v.count1, operators = { 'c', 'd', 'y' }, wrap = true },
    H.get_config().yank.options,
    opts or {}
  )

  -- Update yank history data
  local cache_yank, history = H.cache.yank, H.cache.yank.history
  local n_history = #history
  local cur_state = H.get_yank_state()
  if not vim.deep_equal(cur_state, cache_yank.state) then H.yank_stop_advancing() end

  -- Define iterator that traverses yank history for entry with proper operator
  local iterator = {}

  iterator.next = function(id)
    for i = id + 1, n_history do
      if vim.tbl_contains(opts.operators, history[i].operator) then return i end
    end
  end

  iterator.prev = function(id)
    for i = id - 1, 1, -1 do
      if vim.tbl_contains(opts.operators, history[i].operator) then return i end
    end
  end

  iterator.state = cache_yank.current_id
  iterator.start_edge = 0
  iterator.end_edge = n_history + 1

  -- Iterate
  local res_id = MiniBracketed.advance(iterator, direction, opts)
  if res_id == nil then return end

  -- Apply. Replace latest put region with yank history entry
  -- - Account for possible errors when latest region became out of bounds
  local ok, _ = pcall(H.replace_latest_put_region, cache_yank.history[res_id])
  if not ok then return end

  cache_yank.current_id = res_id
  cache_yank.is_advancing = true
  cache_yank.state = H.get_yank_state()
end

-- Register "latest put region"
--
-- This function should be called after put register becomes relevant
-- (|v:register| is appropriately set) but before put operation takes place
-- (|`[| and |`]| marks become relevant).
--
-- Designed to be used in a user-facing expression mapping (see |:map-expression|).
--
--@param put_key string Put keys to be remapped.
--
--@return string Returns `put_key` for a better usage insde expression mappings.
MiniBracketed.register_put_region = function(put_key)
  local buf_id = vim.api.nvim_get_current_buf()

  -- Compute mode of register **before** putting (while it is still relevant)
  local mode = H.get_register_mode(vim.v.register)

  -- Register latest put region **after** it is done (when it becomes relevant)
  vim.schedule(function() H.cache.yank.user_put_regions[buf_id] = H.get_latest_region(mode) end)

  return put_key
end

--- Advance iterator
---
--- TODO (add notes);
--- - Directions 'first' and 'last' are convenience wrappers for 'next' and
---   'last' with pre-setting initial state to `start_edge` and `end_edge`.
--- - List some guarantees and conventions about `nil`: iterator methods are
---   never called with `nil` as input state.
--- - Only returns updates `iterator.state` in place (if result state is not `nil`) and
---   returns new state (can be `nil`).
---
---@param iterator table Table:
---   - Methods:
---       - <next> - given state, return state in forward direction (no wrap).
---       - <prev> - given state, return state in backward direction (no wrap).
---   - Fields:
---       - <state> - object describing current state.
---       - <start_edge> (optional) - object with `forward(start_edge)` describes
---         first state. If `nil`, can't wrap going forward or use direction 'first'.
---       - <end_edge> (optional) - object with `backward(end_edge)` describes
---         last state. If `nil`, can't wrap going backward or use direction 'last'.
---@param direction string Direction. One of 'first', 'backward', 'forward', 'last'.
---@param opts table|nil Options with the following keys:
---   - <wrap> - whether to wrap around edges when `next()` or `prev()` return `nil`.
---
---@return any Result state. If `nil`, could not reach any valid result state.
MiniBracketed.advance = function(iterator, direction, opts)
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1, wrap = true }, opts or {})

  -- Use two states: "result" will be used as result, "current" will be used
  -- for iteration. Separation is needed at least for two reasons:
  -- - Allow partial reach of `n_times`.
  -- - Don't allow `start_edge` and `end_edge` be the outupt.
  local res_state = iterator.state
  local cur_state = res_state

  -- Compute loop data
  local n_times, iter_method = opts.n_times, 'next'

  if direction == 'backward' then iter_method = 'prev' end

  if direction == 'first' then
    cur_state, iter_method = iterator.start_edge, 'next'
  end

  if direction == 'last' then
    cur_state, iter_method = iterator.end_edge, 'prev'
  end

  -- Loop
  local iter = iterator[iter_method]
  for _ = 1, n_times do
    -- Advance
    cur_state = iter(cur_state)

    if cur_state == nil then
      -- Stop if can't wrap around edges
      if not opts.wrap then break end

      -- Wrap around edge
      local edge = iterator.start_edge
      if iter_method == 'prev' then edge = iterator.end_edge end
      if edge == nil then break end

      cur_state = iter(edge)

      -- Ensure non-nil new state (can happen when there are no targets)
      if cur_state == nil then break end
    end

    -- Allow only partial reach of `n_times`
    res_state = cur_state
  end

  return res_state
end

MiniBracketed.track_oldfile = function()
  if H.is_disabled() then return end

  -- Ensure tracking data is initialized
  H.oldfile_ensure_initialized()

  -- Reset tracking indicator to allow proper tracking of next buffer
  local is_advancing = H.cache.oldfile.is_advancing
  H.cache.oldfile.is_advancing = false

  -- Track only appropriate buffers (normal buffers with path)
  local path = vim.api.nvim_buf_get_name(0)
  local is_proper_buffer = path ~= '' and vim.bo.buftype == ''
  if not is_proper_buffer then return end

  -- If advancing, don't touch tracking data to be able to consecutively move
  -- along recent files. Cache advanced buffer name to later update recency of
  -- the last one (just before buffer switching outside of `oldfile()`)
  local cache_oldfile = H.cache.oldfile

  if is_advancing then
    cache_oldfile.last_advanced_bufname = path
    return
  end

  -- If not advancing, update recency of a single latest advanced buffer (if
  -- present) and then update recency of current buffer
  if cache_oldfile.last_advanced_bufname ~= nil then
    H.oldfile_update_recency(cache_oldfile.last_advanced_bufname)
    cache_oldfile.last_advanced_bufname = nil
  end

  H.oldfile_update_recency(path)
end

MiniBracketed.track_yank = function()
  -- Don't track if asked not to. Allows other functionality to disable
  -- tracking (like in 'mini.move').
  if H.is_disabled() then return end

  -- Track all `TextYankPost` events without exceptions. This leads to a better
  -- handling of charwise/linewise/blockwise selection detection.
  local event = vim.v.event
  table.insert(
    H.cache.yank.history,
    { operator = event.operator, regcontents = event.regcontents, regtype = event.regtype }
  )

  H.yank_stop_advancing()
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniBracketed.config

H.cache = {
  -- Tracking of old files for `oldfile()` (this data structure is designed to be
  -- fast to add new file; initially `nil` to postpone initialization from
  -- `v:oldfiles` up until it is actually needed):
  -- - `recency` is a table with file paths as fields and numerical values
  --   indicating how recent file was accessed (higher - more recent).
  -- - `max_recency` is a maximum currently used `recency`. Used to add new file.
  -- - `is_advancing` is an indicator that buffer change was done inside
  --   `oldfile()` function. It is a key to enabling moving along old files
  --   (and not just going back and forth between two files because they swap
  --   places as two most recent files).
  -- - `last_advanced_bufname` - name of last advanced buffer. Used to update
  --   recency of only the last buffer entered during advancing.
  oldfile = nil,

  -- Per buffer history of visited undo states. A table for each buffer id:
  -- - Numerical fields indicate actual history of visited undo states (from
  --   oldest to latest).
  -- - <current_id> - identifier of current history entry (used for iteration).
  -- - <seq_last> - latest recorded state (`seq_last` from `undotree()`).
  -- - <is_advancing> - whether currently advancing. Used to allow consecutive
  --   advances along tracked undo history.
  undo = {},

  -- Cache for `yank` source
  yank = {
    -- Per-buffer region of latest advance. Used to corretly determine range
    -- and mode of latest advanced region.
    advance_put_regions = {},
    -- Current id of yank entry in yank history
    current_id = 0,
    -- Yank history. Each element contains data necessary to replace latest put
    -- region with yanked one. See `track_yank()`.
    history = {},
    -- Whether currently advancing
    is_advancing = false,
    -- State of latest yank advancement to determine of currently advancing
    state = {},
    -- Per-buffer region registered by user as "latest put region". Used to
    -- overcome limitations of automatic detection of latest put region (like
    -- not reliable mode detection when pasting from register; respecting not
    -- only regions of put operations, but also yank and change).
    user_put_regions = {},
  },
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  --stylua: ignore
  vim.validate({
    ['buffer']     = { config.buffer,     'table' },
    ['comment']    = { config.comment,    'table' },
    ['conflict']   = { config.conflict,   'table' },
    ['diagnostic'] = { config.diagnostic, 'table' },
    ['file']       = { config.file,       'table' },
    ['indent']     = { config.indent,     'table' },
    ['jump']       = { config.jump,       'table' },
    ['location']   = { config.location,   'table' },
    ['oldfile']    = { config.oldfile,    'table' },
    ['quickfix']   = { config.quickfix,   'table' },
    ['undo']       = { config.undo,     'table' },
    ['window']     = { config.window,     'table' },
    ['yank']       = { config.yank,     'table' },
  })

  --stylua: ignore
  vim.validate({
    ['buffer.suffix']  = { config.buffer.suffix, 'string' },
    ['buffer.options'] = { config.buffer.options, 'table' },

    ['comment.suffix']  = { config.comment.suffix, 'string' },
    ['comment.options'] = { config.comment.options, 'table' },

    ['conflict.suffix']  = { config.conflict.suffix, 'string' },
    ['conflict.options'] = { config.conflict.options, 'table' },

    ['diagnostic.suffix']  = { config.diagnostic.suffix, 'string' },
    ['diagnostic.options'] = { config.diagnostic.options, 'table' },

    ['file.suffix']  = { config.file.suffix, 'string' },
    ['file.options'] = { config.file.options, 'table' },

    ['indent.suffix']  = { config.indent.suffix, 'string' },
    ['indent.options'] = { config.indent.options, 'table' },

    ['jump.suffix']  = { config.jump.suffix, 'string' },
    ['jump.options'] = { config.jump.options, 'table' },

    ['location.suffix']  = { config.location.suffix, 'string' },
    ['location.options'] = { config.location.options, 'table' },

    ['oldfile.suffix']  = { config.oldfile.suffix, 'string' },
    ['oldfile.options'] = { config.oldfile.options, 'table' },

    ['quickfix.suffix']  = { config.quickfix.suffix, 'string' },
    ['quickfix.options'] = { config.quickfix.options, 'table' },

    ['undo.suffix']  = { config.undo.suffix, 'string' },
    ['undo.options'] = { config.undo.options, 'table' },

    ['window.suffix']  = { config.window.suffix, 'string' },
    ['window.options'] = { config.window.options, 'table' },

    ['yank.suffix']  = { config.yank.suffix, 'string' },
    ['yank.options'] = { config.yank.options, 'table' },
  })

  return config
end

--stylua: ignore
H.apply_config = function(config)
  MiniBracketed.config = config

  -- Make mappings. NOTE: make 'forward'/'backward' *after* 'first'/'last' to
  -- allow non-letter suffixes define 'forward'/'backward'.
  if config.buffer.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.buffer.suffix)
    H.map('n', '[' .. up,  "<Cmd>lua MiniBracketed.buffer('first')<CR>",    { desc = 'First buffer' })
    H.map('n', ']' .. up,  "<Cmd>lua MiniBracketed.buffer('last')<CR>",     { desc = 'Last buffer' })
    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.buffer('backward')<CR>", { desc = 'Previous buffer' })
    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.buffer('forward')<CR>",  { desc = 'Next buffer' })
  end

  if config.comment.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.comment.suffix)
    H.map('n', '[' .. up, "<Cmd>lua MiniBracketed.comment('first')<CR>",  { desc = 'First comment' })
    H.map('x', '[' .. up, "<Cmd>lua MiniBracketed.comment('first')<CR>",  { desc = 'First comment' })
    H.map('o', '[' .. up, "V<Cmd>lua MiniBracketed.comment('first')<CR>", { desc = 'First comment' })

    H.map('n', ']' .. up, "<Cmd>lua MiniBracketed.comment('last')<CR>",  { desc = 'Last comment' })
    H.map('x', ']' .. up, "<Cmd>lua MiniBracketed.comment('last')<CR>",  { desc = 'Last comment' })
    H.map('o', ']' .. up, "V<Cmd>lua MiniBracketed.comment('last')<CR>", { desc = 'Last comment' })

    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.comment('backward')<CR>",  { desc = 'Previous comment' })
    H.map('x', '[' .. low, "<Cmd>lua MiniBracketed.comment('backward')<CR>",  { desc = 'Previous comment' })
    H.map('o', '[' .. low, "V<Cmd>lua MiniBracketed.comment('backward')<CR>", { desc = 'Previous comment' })

    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.comment('forward')<CR>",  { desc = 'Next comment' })
    H.map('x', ']' .. low, "<Cmd>lua MiniBracketed.comment('forward')<CR>",  { desc = 'Next comment' })
    H.map('o', ']' .. low, "V<Cmd>lua MiniBracketed.comment('forward')<CR>", { desc = 'Next comment' })
  end

  if config.conflict.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.conflict.suffix)
    H.map('n', '[' .. up, "<Cmd>lua MiniBracketed.conflict('first')<CR>",  { desc = 'First conflict' })
    H.map('x', '[' .. up, "<Cmd>lua MiniBracketed.conflict('first')<CR>",  { desc = 'First conflict' })
    H.map('o', '[' .. up, "V<Cmd>lua MiniBracketed.conflict('first')<CR>", { desc = 'First conflict' })

    H.map('n', ']' .. up, "<Cmd>lua MiniBracketed.conflict('last')<CR>",  { desc = 'Last conflict' })
    H.map('x', ']' .. up, "<Cmd>lua MiniBracketed.conflict('last')<CR>",  { desc = 'Last conflict' })
    H.map('o', ']' .. up, "V<Cmd>lua MiniBracketed.conflict('last')<CR>", { desc = 'Last conflict' })

    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.conflict('backward')<CR>",  { desc = 'Previous conflict' })
    H.map('x', '[' .. low, "<Cmd>lua MiniBracketed.conflict('backward')<CR>",  { desc = 'Previous conflict' })
    H.map('o', '[' .. low, "V<Cmd>lua MiniBracketed.conflict('backward')<CR>", { desc = 'Previous conflict' })

    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.conflict('forward')<CR>",  { desc = 'Next conflict' })
    H.map('x', ']' .. low, "<Cmd>lua MiniBracketed.conflict('forward')<CR>",  { desc = 'Next conflict' })
    H.map('o', ']' .. low, "V<Cmd>lua MiniBracketed.conflict('forward')<CR>", { desc = 'Next conflict' })
  end

  if config.diagnostic.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.diagnostic.suffix)
    H.map('n', '[' .. up, "<Cmd>lua MiniBracketed.diagnostic('first')<CR>",  { desc = 'First diagnostic' })
    H.map('x', '[' .. up, "<Cmd>lua MiniBracketed.diagnostic('first')<CR>",  { desc = 'First diagnostic' })
    H.map('o', '[' .. up, "v<Cmd>lua MiniBracketed.diagnostic('first')<CR>", { desc = 'First diagnostic' })

    H.map('n', ']' .. up, "<Cmd>lua MiniBracketed.diagnostic('last')<CR>",  { desc = 'Last diagnostic' })
    H.map('x', ']' .. up, "<Cmd>lua MiniBracketed.diagnostic('last')<CR>",  { desc = 'Last diagnostic' })
    H.map('o', ']' .. up, "v<Cmd>lua MiniBracketed.diagnostic('last')<CR>", { desc = 'Last diagnostic' })

    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.diagnostic('backward')<CR>",  { desc = 'Previous diagnostic' })
    H.map('x', '[' .. low, "<Cmd>lua MiniBracketed.diagnostic('backward')<CR>",  { desc = 'Previous diagnostic' })
    H.map('o', '[' .. low, "v<Cmd>lua MiniBracketed.diagnostic('backward')<CR>", { desc = 'Previous diagnostic' })

    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.diagnostic('forward')<CR>",  { desc = 'Next diagnostic' })
    H.map('x', ']' .. low, "<Cmd>lua MiniBracketed.diagnostic('forward')<CR>",  { desc = 'Next diagnostic' })
    H.map('o', ']' .. low, "v<Cmd>lua MiniBracketed.diagnostic('forward')<CR>", { desc = 'Next diagnostic' })
  end

  if config.file.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.file.suffix)
    H.map('n', '[' .. up,  "<Cmd>lua MiniBracketed.file('first')<CR>",    { desc = 'First file' })
    H.map('n', ']' .. up,  "<Cmd>lua MiniBracketed.file('last')<CR>",     { desc = 'Last file' })
    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.file('backward')<CR>", { desc = 'Previous file' })
    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.file('forward')<CR>",  { desc = 'Next file' })
  end

  if config.indent.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.indent.suffix)
    H.map('n', '[' .. up, "<Cmd>lua MiniBracketed.indent('first')<CR>",  { desc = 'First indent' })
    H.map('x', '[' .. up, "<Cmd>lua MiniBracketed.indent('first')<CR>",  { desc = 'First indent' })
    H.map('o', '[' .. up, "V<Cmd>lua MiniBracketed.indent('first')<CR>", { desc = 'First indent' })

    H.map('n', ']' .. up, "<Cmd>lua MiniBracketed.indent('last')<CR>",  { desc = 'Last indent' })
    H.map('x', ']' .. up, "<Cmd>lua MiniBracketed.indent('last')<CR>",  { desc = 'Last indent' })
    H.map('o', ']' .. up, "V<Cmd>lua MiniBracketed.indent('last')<CR>", { desc = 'Last indent' })

    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.indent('backward')<CR>",  { desc = 'Previous indent' })
    H.map('x', '[' .. low, "<Cmd>lua MiniBracketed.indent('backward')<CR>",  { desc = 'Previous indent' })
    H.map('o', '[' .. low, "V<Cmd>lua MiniBracketed.indent('backward')<CR>", { desc = 'Previous indent' })

    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.indent('forward')<CR>",  { desc = 'Next indent' })
    H.map('x', ']' .. low, "<Cmd>lua MiniBracketed.indent('forward')<CR>",  { desc = 'Next indent' })
    H.map('o', ']' .. low, "V<Cmd>lua MiniBracketed.indent('forward')<CR>", { desc = 'Next indent' })
  end

  if config.jump.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.jump.suffix)
    H.map('n', '[' .. up, "<Cmd>lua MiniBracketed.jump('first')<CR>",  { desc = 'First jump' })
    H.map('x', '[' .. up, "<Cmd>lua MiniBracketed.jump('first')<CR>",  { desc = 'First jump' })
    H.map('o', '[' .. up, "v<Cmd>lua MiniBracketed.jump('first')<CR>", { desc = 'First jump' })

    H.map('n', ']' .. up, "<Cmd>lua MiniBracketed.jump('last')<CR>",  { desc = 'Last jump' })
    H.map('x', ']' .. up, "<Cmd>lua MiniBracketed.jump('last')<CR>",  { desc = 'Last jump' })
    H.map('o', ']' .. up, "v<Cmd>lua MiniBracketed.jump('last')<CR>", { desc = 'Last jump' })

    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.jump('backward')<CR>",  { desc = 'Previous jump' })
    H.map('x', '[' .. low, "<Cmd>lua MiniBracketed.jump('backward')<CR>",  { desc = 'Previous jump' })
    H.map('o', '[' .. low, "v<Cmd>lua MiniBracketed.jump('backward')<CR>", { desc = 'Previous jump' })

    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.jump('forward')<CR>",  { desc = 'Next jump' })
    H.map('x', ']' .. low, "<Cmd>lua MiniBracketed.jump('forward')<CR>",  { desc = 'Next jump' })
    H.map('o', ']' .. low, "v<Cmd>lua MiniBracketed.jump('forward')<CR>", { desc = 'Next jump' })
  end

  if config.oldfile.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.oldfile.suffix)
    H.map('n', '[' .. up,  "<Cmd>lua MiniBracketed.oldfile('first')<CR>",    { desc = 'First oldfile' })
    H.map('n', ']' .. up,  "<Cmd>lua MiniBracketed.oldfile('last')<CR>",     { desc = 'Last oldfile' })
    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.oldfile('backward')<CR>", { desc = 'Previous oldfile' })
    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.oldfile('forward')<CR>",  { desc = 'Next oldfile' })
  end

  if config.location.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.location.suffix)
    H.map('n', '[' .. up,  "<Cmd>lua MiniBracketed.location('first')<CR>",    { desc = 'First location' })
    H.map('n', ']' .. up,  "<Cmd>lua MiniBracketed.location('last')<CR>",     { desc = 'Last location' })
    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.location('backward')<CR>", { desc = 'Previous location' })
    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.location('forward')<CR>",  { desc = 'Next location' })
  end

  if config.quickfix.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.quickfix.suffix)
    H.map('n', '[' .. up,  "<Cmd>lua MiniBracketed.quickfix('first')<CR>",    { desc = 'First quickfix' })
    H.map('n', ']' .. up,  "<Cmd>lua MiniBracketed.quickfix('last')<CR>",     { desc = 'Last quickfix' })
    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.quickfix('backward')<CR>", { desc = 'Previous quickfix' })
    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.quickfix('forward')<CR>",  { desc = 'Next quickfix' })
  end

  if config.undo.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.undo.suffix)
    H.map('n', '[' .. up,  "<Cmd>lua MiniBracketed.undo('first')<CR>",    { desc = 'First undo' })
    H.map('n', ']' .. up,  "<Cmd>lua MiniBracketed.undo('last')<CR>",     { desc = 'Last undo' })
    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.undo('backward')<CR>", { desc = 'Previous undo' })
    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.undo('forward')<CR>",  { desc = 'Next undo' })

    H.map('n', 'u',     'u<Cmd>lua MiniBracketed.register_undo_state()<CR>')
    H.map('n', '<C-R>', '<C-R><Cmd>lua MiniBracketed.register_undo_state()<CR>')
  end

  if config.window.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.window.suffix)
    H.map('n', '[' .. up,  "<Cmd>lua MiniBracketed.window('first')<CR>",    { desc = 'First window' })
    H.map('n', ']' .. up,  "<Cmd>lua MiniBracketed.window('last')<CR>",     { desc = 'Last window' })
    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.window('backward')<CR>", { desc = 'Previous window' })
    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.window('forward')<CR>",  { desc = 'Next window' })
  end

  if config.yank.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.yank.suffix)
    H.map('n', '[' .. up,  "<Cmd>lua MiniBracketed.yank('first')<CR>",    { desc = 'First yank' })
    H.map('n', ']' .. up,  "<Cmd>lua MiniBracketed.yank('last')<CR>",     { desc = 'Last yank' })
    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.yank('backward')<CR>", { desc = 'Previous yank' })
    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.yank('forward')<CR>",  { desc = 'Next yank' })
  end
end

H.get_suffix_variants = function(char) return char:lower(), char:upper() end

H.is_disabled = function() return vim.g.minibracketed_disable == true or vim.b.minibracketed_disable == true end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniBracketed.config, vim.b.minibracketed_config or {}, config or {})
end

-- Comments -------------------------------------------------------------------
H.make_comment_checker = function()
  local left, right = unpack(vim.fn.split(vim.bo.commentstring, '%s'))
  left, right = left or '', right or ''
  if left == '' and right == '' then return nil end

  -- String is commented if it has structure:
  -- <space> <left> <anything> <right> <space>
  local regex = string.format('^%%s-%s.*%s%%s-$', vim.pesc(vim.trim(left)), vim.pesc(vim.trim(right)))

  -- Check if line with number `line_num` is a comment. NOTE: `getline()`
  -- return empty string for invalid line number, which makes them *not
  -- commented*.
  return function(line_num) return vim.fn.getline(line_num):find(regex) ~= nil end
end

-- Conflicts ------------------------------------------------------------------
H.is_conflict_mark = function(line_num)
  local l_start = vim.fn.getline(line_num):sub(1, 8)
  return l_start == '<<<<<<< ' or l_start == '=======' or l_start == '>>>>>>> '
end

-- Files ----------------------------------------------------------------------
H.get_file_data = function()
  -- Compute target directory
  local cur_buf_path = vim.api.nvim_buf_get_name(0)
  local dir_path = cur_buf_path ~= '' and vim.fn.fnamemodify(cur_buf_path, ':p:h') or vim.fn.getcwd()

  -- Compute sorted array of all files in target directory
  local dir_handle = vim.loop.fs_scandir(dir_path)
  local files_stream = function() return vim.loop.fs_scandir_next(dir_handle) end

  local files = {}
  for basename, fs_type in files_stream do
    if fs_type == 'file' then table.insert(files, basename) end
  end

  -- - Sort files ignoring case
  table.sort(files, function(x, y) return x:lower() < y:lower() end)

  if #files == 0 then return end
  return { directory = dir_path, file_basenames = files }
end

-- Jumps ----------------------------------------------------------------------
H.make_jump = function(jump_list, cur_jump_num, new_jump_num)
  local num_diff = new_jump_num - cur_jump_num

  if num_diff == 0 then
    -- Perform jump manually to always jump. Example: move to last jump and
    -- move manually; then jump with "last" direction should move to last jump.
    local jump_entry = jump_list[new_jump_num]
    pcall(vim.fn.cursor, { jump_entry.lnum, jump_entry.col + 1, jump_entry.coladd })
  else
    -- Use builtin mappings to also update current jump entry
    local key = num_diff > 0 and '\t' or '\15'
    vim.cmd('normal! ' .. math.abs(num_diff) .. key)
  end

  -- Open just enough folds
  vim.cmd('normal! zv')
end

-- Oldfile --------------------------------------------------------------------
H.oldfile_normalize = function()
  -- Ensure that tracking data is initialized
  H.oldfile_ensure_initialized()

  -- Order currently readable paths in increasing order of recency
  local recency_pairs = {}
  for path, rec in pairs(H.cache.oldfile.recency) do
    if vim.fn.filereadable(path) == 1 then table.insert(recency_pairs, { path, rec }) end
  end
  table.sort(recency_pairs, function(x, y) return x[2] < y[2] end)

  -- Construct new tracking data with recency from 1 to number of entries
  local new_recency = {}
  for i, pair in ipairs(recency_pairs) do
    new_recency[pair[1]] = i
  end

  H.cache.oldfile = { recency = new_recency, max_recency = #recency_pairs, is_advancing = H.cache.oldfile.is_advancing }
end

H.oldfile_ensure_initialized = function()
  if H.cache.oldfile ~= nil or vim.v.oldfiles == nil then return end

  local n = #vim.v.oldfiles
  local recency = {}
  for i, path in ipairs(vim.v.oldfiles) do
    if vim.fn.filereadable(path) == 1 then recency[path] = n - i + 1 end
  end

  H.cache.oldfile = { recency = recency, max_recency = n, is_advancing = false }
end

H.oldfile_get_array = function()
  local res = {}
  for path, i in pairs(H.cache.oldfile.recency) do
    res[i] = path
  end
  return res
end

H.oldfile_update_recency = function(path)
  local n = H.cache.oldfile.max_recency + 1
  H.cache.oldfile.recency[path] = n
  H.cache.oldfile.max_recency = n
end

-- Quickfix/Location lists ----------------------------------------------------
H.qf_loc_implementation = function(list_type, direction, opts)
  local get_list, goto_command = vim.fn.getqflist, 'cc'
  if list_type == 'location' then
    get_list, goto_command = function(...) return vim.fn.getloclist(0, ...) end, 'll'
  end

  -- Define iterator that traverses quickfix/location list entries
  local list = get_list()
  local n_list = #list
  if n_list == 0 then return end

  local iterator = {}

  iterator.next = function(ind)
    if ind == nil or n_list <= ind then return end
    return ind + 1
  end

  iterator.prev = function(ind)
    if ind == nil or ind <= 1 then return end
    return ind - 1
  end

  iterator.state = get_list({ idx = 0 }).idx
  iterator.start_edge = 0
  iterator.end_edge = n_list + 1

  -- Iterate
  local res_ind = MiniBracketed.advance(iterator, direction, opts)

  -- Apply. Focus target entry, open enough folds and center. Allow jumping to
  -- current quickfix/loclist entry as it might be different from current
  -- cursor position.
  vim.cmd(goto_command .. ' ' .. res_ind)
  vim.cmd('normal! zvzz')
end

-- Undo -----------------------------------------------------------------------
H.undo_sync = function(buf_id, tree, is_advancing)
  -- Get or initialize buffer history of visited undo states
  local prev_buf_history = H.cache.undo[buf_id] or H.undo_init(tree)
  if is_advancing == nil then is_advancing = prev_buf_history.is_advancing end

  -- Prune current buffer history to contain only allowed state numbers. This
  -- assumes that once undo state is not allowed, it will always be not
  -- allowed. This step is needed because allowed undo state numbers can:
  -- - Not start from 1 due to 'undolevels'.
  -- - Contain range of missing state numbers due to `:undo!`.
  --
  -- Do this even if advancing because `:undo!` can be executed at any time.
  local allowed_states = H.undo_get_allowed_state_numbers(tree)

  local buf_history = {}
  for i, state_num in ipairs(prev_buf_history) do
    -- Use only allowed states
    if allowed_states[state_num] then H.undo_append_state(buf_history, state_num) end

    -- Correctly track current id when advancing
    if i == prev_buf_history.current_id then buf_history.current_id = #buf_history end
  end
  buf_history.current_id = buf_history.current_id or #buf_history
  buf_history.is_advancing = prev_buf_history.is_advancing
  buf_history.seq_last = prev_buf_history.seq_last

  H.cache.undo[buf_id] = buf_history

  -- Continue only if not actually advancing: either if set so manually *or* if
  -- there were additions to undo history *or* some states became not allowed
  -- (due to `:undo!`).
  if is_advancing and tree.seq_last <= buf_history.seq_last and #buf_history == #prev_buf_history then return end

  -- Register current undo state (if not equal to last).
  -- Usually it is a result of advance but also can be due to `:undo`/`:undo!`.
  H.undo_append_state(buf_history, tree.seq_cur)

  -- Add all new *allowed* undo states created since last sync
  for new_state = buf_history.seq_last + 1, tree.seq_last do
    if allowed_states[new_state] then H.undo_append_state(buf_history, new_state) end
  end

  -- Update data to be most recent
  buf_history.current_id = #buf_history
  buf_history.is_advancing = false
  buf_history.seq_last = tree.seq_last
end

H.undo_append_state = function(buf_history, state_num)
  -- Ensure that there are no two consecutive equal states
  if state_num == nil or buf_history[#buf_history] == state_num then return end

  table.insert(buf_history, state_num)
end

H.undo_init = function(tree)
  -- Assume all previous states are allowed
  local res = {}
  for i = 0, tree.seq_last do
    res[i + 1] = i
  end
  res.current_id = #res
  res.is_advancing = false
  res.seq_last = tree.seq_last

  return res
end

H.undo_get_allowed_state_numbers = function(tree)
  -- `:undo 0` is always possible (goes to *before* the first allowed state).
  local res = { [0] = true }
  local traverse
  traverse = function(entries)
    for _, e in ipairs(entries) do
      if e.alt ~= nil then traverse(e.alt) end
      res[e.seq] = true
    end
  end

  traverse(tree.entries)
  return res
end

-- Yank -----------------------------------------------------------------------
H.yank_stop_advancing = function()
  H.cache.yank.current_id = #H.cache.yank.history
  H.cache.yank.is_advancing = false
  H.cache.yank.advance_put_regions[vim.api.nvim_get_current_buf()] = nil
end

H.get_yank_state = function() return { buf_id = vim.api.nvim_get_current_buf(), changedtick = vim.b.changedtick } end

H.replace_latest_put_region = function(yank_data)
  -- Squash all yank advancing in a single undo block
  local normal_command = (H.cache.yank.is_advancing and 'undojoin | ' or '') .. 'silent normal! '
  local normal_fun = function(x) vim.cmd(normal_command .. x) end

  -- Compute latest put region: from latest `yank` advance; or from user's
  -- latest put; or from `[`/`]` marks
  local cache_yank = H.cache.yank
  local buf_id = vim.api.nvim_get_current_buf()
  local latest_region = cache_yank.advance_put_regions[buf_id]
    or cache_yank.user_put_regions[buf_id]
    or H.get_latest_region()

  -- Compute modes for replaced and new regions.
  local latest_mode = latest_region.mode
  local new_mode = yank_data.regtype:sub(1, 1)

  -- Compute later put key based on replaced and new regions.
  -- Prefer `P` but use `p` in cases replaced region was on the edge: last line
  -- for linewise-linewise replace or last column for nonlinewise-nonlinewise.
  local is_linewise = (latest_mode == 'V' and new_mode == 'V')
  local is_edge_line = is_linewise and latest_region.to.line == vim.fn.line('$')

  local is_charblockwise = (latest_mode ~= 'V' and new_mode ~= 'V')
  local is_edge_col = is_charblockwise and latest_region.to.col == vim.fn.getline(latest_region.to.line):len()

  local is_edge = is_edge_line or is_edge_col
  local put_key = is_edge and 'p' or 'P'

  -- Delete latest region
  H.region_delete(latest_region, normal_fun)

  -- Paste yank data using temporary register
  local cache_z_reg = vim.fn.getreg('z')
  vim.fn.setreg('z', yank_data.regcontents, yank_data.regtype)

  normal_fun('"z' .. put_key)

  vim.fn.setreg('z', cache_z_reg)

  -- Register newly put region for correct further advancing
  cache_yank.advance_put_regions[buf_id] = H.get_latest_region(new_mode)
end

H.get_latest_region = function(mode)
  local left, right = vim.fn.getpos("'["), vim.fn.getpos("']")
  return {
    from = { line = left[2], col = left[3] },
    to = { line = right[2], col = right[3] },
    -- Mode should be one of 'v', 'V', or '\22' ('<C-v>')
    -- By default use mode of current or unnamed register
    -- NOTE: this breaks if latest paste was not from unnamed register.
    -- To account for that, use `register_put_region()`.
    mode = mode or H.get_register_mode(vim.v.register),
  }
end

H.region_delete = function(region, normal_fun)
  -- Start with `to` to have cursor positioned on region start after deletion
  vim.api.nvim_win_set_cursor(0, { region.to.line, region.to.col - 1 })

  -- Do nothing more if region is empty (or leads to unnecessary line deletion)
  local is_empty = region.from.line == region.to.line
    and region.from.col == region.to.col
    and vim.fn.getline(region.from.line) == ''

  if is_empty then return end

  -- Select region in correct Visual mode
  normal_fun(region.mode)
  vim.api.nvim_win_set_cursor(0, { region.from.line, region.from.col - 1 })

  -- Delete region in "black hole" register
  -- - NOTE: it doesn't affect history as `"_` doesn't trigger `TextYankPost`
  normal_fun('"_d')
end

H.get_register_mode = function(register)
  -- Use only first character to correctly get '\22' in blockwise mode
  return vim.fn.getregtype(register):sub(1, 1)
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.bracketed) %s', msg), 0) end

H.validate_direction = function(direction, choices, fun_name)
  if not vim.tbl_contains(choices, direction) then
    local choices_string = "'" .. table.concat(choices, "', '") .. "'"
    local error_text = string.format('In `%s()` argument `direction` should be one of %s.', fun_name, choices_string)
    H.error(error_text)
  end
end

H.map = function(mode, key, rhs, opts)
  if key == '' then return end

  opts = vim.tbl_deep_extend('force', { noremap = true, silent = true }, opts or {})

  -- Use mapping description only in Neovim>=0.7
  if vim.fn.has('nvim-0.7') == 0 then opts.desc = nil end

  vim.api.nvim_set_keymap(mode, key, rhs, opts)
end

return MiniBracketed
