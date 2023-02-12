-- MIT License Copyright (c) 2023 Evgeni Chasnovski

-- TODO
--
-- Code:
-- - Try to make `n_times` work in `indent` with 'first' and 'last' direction.
-- - Other todos across code.
-- - Refactor and clean up with possible abstractions.
--
-- Tests:
-- - Ensure moves that guaranteed to be inside current buffer have mappings in
--   Normal, Visual, and Operator-pending modes (linewise if source is
--   linewise, charwise otherwise).
-- - Yank:
--     - Initial detection of put-region mode (charwise/linewise/blockwise) is
--       correct (apart putting from register).
--     - Handles all 9 transition pairs of regtype:
--       c - c - l - c - b - c - l - l - b - l - b - b
--     - No side effects (doesn't change registers, etc.).
--     - Squashing undo blocks.
-- - `MiniBracketed.map_put_for_yank()` improves detection of put region:
--     - Advancing doesn't take into account recently yanked or changed region.
--       Steps: yank, put; change, yank; advance - should change put region.
--     - Correctly detects mode of latest put region even if it was put from
--       register. Steps: `"ay` blockwise selection; `yy` (linewise); `"ap`
--       (put blockwise into existing line); advance - should replace
--       originally put blockwise region, not whole line.
--
-- Docs:
-- - Mention that it is ok to not map defaults and use functions manually.
-- - Mention in `conflict` about possibility of resolving merge conflicts by
--   placing cursor on `===` line and executing one of these:
--   `d]x[xdd` (choose upper part), `d[x]xdd` (choose lower part).
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
        au BufEnter * lua MiniBracketed.track_oldfiles()
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
  yank       = { suffix = 'y', options = {} },
  window     = { suffix = 'w', options = {} },
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
  if res_line_num == iterator.state then return end

  -- Apply. Open just enough folds and put cursor on first non-blank.
  vim.api.nvim_win_set_cursor(0, { res_line_num, 0 })
  vim.cmd('normal! zv^')
end

MiniBracketed.diagnostic = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'backward', 'forward', 'last' }, 'diagnostic')
  opts = vim.tbl_deep_extend(
    'force',
    { n_times = vim.v.count1, wrap = true, severity = nil },
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

  -- - Define states with zero-based indexing as used in `vim.diagnostic`
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  iterator.state = { cursor_pos[1] - 1, cursor_pos[2] }

  iterator.start_edge = { 0, 0 }

  local last_line = vim.api.nvim_buf_line_count(0)
  local last_line_col = vim.fn.col({ last_line, '$' }) - 1
  iterator.end_edge = { last_line - 1, math.max(last_line_col - 1, 0) }

  -- Iterate
  local res_pos = MiniBracketed.advance(iterator, direction, opts)
  if res_pos == iterator.state then return end

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

  iterator.next = function(ind)
    if ind == nil or #file_basenames <= ind then return end
    return ind + 1
  end

  iterator.prev = function(ind)
    if ind == nil or ind <= 1 then return end
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
  iterator.end_edge = #file_basenames + 1

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
  if res_line_num == iterator.state then return end

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

  H.oldfiles_normalize()
  local oldfiles = H.oldfiles_get_array()
  local n_oldfiles = #oldfiles

  local iterator = {}

  iterator.next = function(ind)
    if ind == nil or n_oldfiles <= ind then return end
    return ind + 1
  end

  iterator.prev = function(ind)
    if ind == nil or ind <= 1 then return end
    return ind - 1
  end

  iterator.state = H.cache.oldfiles.recency[cur_path]
  iterator.start_edge = 0
  iterator.end_edge = n_oldfiles + 1

  -- Iterate
  local res_path_ind = MiniBracketed.advance(iterator, direction, opts)
  if res_path_ind == iterator.state then return end

  -- Apply. Edit file at path while marking it not for tracking.
  H.cache.oldfiles.is_from_oldfile = true
  vim.cmd('edit ' .. oldfiles[res_path_ind])
end

MiniBracketed.quickfix = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'backward', 'forward', 'last' }, 'quickfix')
  opts =
    vim.tbl_deep_extend('force', { n_times = vim.v.count1, wrap = true }, H.get_config().quickfix.options, opts or {})

  H.qf_loc_implementation('quickfix', direction, opts)
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
-- - Remap common put operations with |MiniBracketed.map_put_for_yank()| (call
--   it once). After that, only regions from mapped put operations will be used
--   for first `yank` advance.
MiniBracketed.yank = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'backward', 'forward', 'last' }, 'yank')
  opts = vim.tbl_deep_extend(
    'force',
    { n_times = vim.v.count1, wrap = true, operators = { 'c', 'd', 'y' } },
    H.get_config().yank.options,
    opts or {}
  )

  -- Update yank history data
  local cache, history = H.cache.yank, H.cache.yank.history
  local n_history = #history
  local cur_state = H.get_yank_state()
  if not vim.deep_equal(cur_state, cache.state) then H.yank_stop_advancing() end

  -- Define iterator that traverses yank history
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

  iterator.state = cache.current_history_id
  iterator.start_edge = 0
  iterator.end_edge = n_history + 1

  -- Iterate
  local res_id = MiniBracketed.advance(iterator, direction, opts)
  if res_id == nil then return end

  -- Apply. Replace latest put region with yank history entry
  -- - Account for possible errors when latest region became out of bounds
  local ok, _ = pcall(H.replace_latest_put_region, cache.history[res_id])
  if not ok then return end

  cache.current_history_id = res_id
  cache.is_advancing = true
  cache.state = H.get_yank_state()
end

-- Map put keys for better yank advance
--
--@param put_keys table Array of left hand side of mapping keys.
--   Default: `{ 'p', 'P' }`.
MiniBracketed.map_put_for_yank = function(put_keys)
  put_keys = put_keys or { 'p', 'P' }

  for _, lhs in ipairs(put_keys) do
    vim.keymap.set({ 'n', 'x' }, lhs, function()
      local buf_id = vim.api.nvim_get_current_buf()

      -- Compute mode of register prior putting (when it is still relevant)
      local mode = H.get_register_mode(vim.v.register)

      -- Put accounting for register and count
      vim.cmd('normal! "' .. vim.v.register .. vim.v.count1 .. lhs)

      -- Register user's latest put region
      H.cache.yank.user_put_regions[buf_id] = H.get_latest_region(mode)
    end)
  end
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

  local res_state = iterator.state

  -- Compute loop data
  local n_times, iter_method = opts.n_times, 'next'

  if direction == 'backward' then iter_method = 'prev' end

  if direction == 'first' then
    res_state, iter_method = iterator.start_edge, 'next'
  end

  if direction == 'last' then
    res_state, iter_method = iterator.end_edge, 'prev'
  end

  if res_state == nil then return nil end

  -- Loop
  local iter = iterator[iter_method]
  for _ = 1, n_times do
    -- Advance
    local new_state = iter(res_state)

    if new_state == nil then
      -- Stop if can't wrap around edges
      if not opts.wrap then break end

      -- Wrap around edge
      local edge = iterator.start_edge
      if iter_method == 'prev' then edge = iterator.end_edge end
      if edge == nil then break end

      new_state = iter(edge)

      -- Ensure non-nil new state (can happen when there are no targets)
      if new_state == nil then break end
    end

    -- Allow only partial reach of `n_times`
    res_state = new_state
  end

  return res_state
end

MiniBracketed.track_oldfiles = function()
  -- Ensure tracking data is initialized
  H.oldfiles_ensure_initialized()

  -- Reset tracking indicator to allow proper tracking of next buffer
  local is_from_oldfile = H.cache.oldfiles.is_from_oldfile
  H.cache.oldfiles.is_from_oldfile = false

  -- Track only appropriate buffers (normal buffers with path)
  local path = vim.api.nvim_buf_get_name(0)
  local is_proper_buffer = path ~= '' and vim.bo.buftype == ''
  if not is_proper_buffer then return end

  -- Compute which tracking table to update. Logic:
  -- - If buffer is entered from `oldfile()` then it should postpone update.
  --   The reason is to allow consecutive `oldfile()` calls to move along old
  --   files. Updating right away leads to jumping between two latest files.
  --   Postponing updates is done by updating shadow tracking table.
  -- - If buffer is entered not from `oldfile()` then it should receive all
  --   postponed updates and then be updated with current buffer.
  local track_table
  if is_from_oldfile then
    H.shadow_oldfiles_data = H.shadow_oldfiles_data or vim.deepcopy(H.cache.oldfiles)
    track_table = H.shadow_oldfiles_data
  else
    H.cache.oldfiles = H.shadow_oldfiles_data or H.cache.oldfiles
    track_table = H.cache.oldfiles
    H.shadow_oldfiles_data = nil
  end

  -- Update tracking table
  local n = track_table.max_recency + 1
  track_table.recency[path] = n
  track_table.max_recency = n
end

MiniBracketed.track_yank = function()
  -- Don't track if asked not to
  if not H.cache.yank.do_track_next then
    H.cache.yank.do_track_next = true
    return
  end

  local event = vim.v.event

  -- Track all `TextYankPost` events without exceptions. This leads to a better
  -- handling of charwise/linewise/blockwise selection detection.
  table.insert(
    H.cache.yank.history,
    { operator = event.operator, regcontents = event.regcontents, regtype = event.regtype }
  )
  H.yank_stop_advancing()
  H.cache.yank.do_track_next = true
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniBracketed.config

H.cache = {
  -- Tracking of old files for `oldfile()` (this data structure is designed to be
  -- fast to add new file):
  -- - `recency` is a table with file paths as fields and numerical values
  --   indicating how recent file was accessed (higher - more recent).
  -- - `max_recency` is a maximum currently used `recency`. Used to add new file.
  -- - `is_from_oldfile` is an indicator of buffer change was done inside
  --   `oldfile()` function. It is a key to enabling moving along old files (and
  --   not just going back and forth between two files because they swap places
  --   as two most recent files).
  oldfiles = nil,

  yank = {
    current_history_id = 0,
    do_track_next = true,
    history = {},
    is_advancing = false,
    advance_put_regions = {},
    user_put_regions = {},
    state = {},
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
    ['window']     = { config.window,     'table' },
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

    ['window.suffix']  = { config.window.suffix, 'string' },
    ['window.options'] = { config.window.options, 'table' },
  })

  return config
end

--stylua: ignore
H.apply_config = function(config)
  MiniBracketed.config = config

  -- Make mappings
  if config.buffer.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.buffer.suffix)
    H.map('n', '[' .. up,  "<Cmd>lua MiniBracketed.buffer('first')<CR>",    { desc = 'First buffer' })
    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.buffer('backward')<CR>", { desc = 'Previous buffer' })
    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.buffer('forward')<CR>",  { desc = 'Next buffer' })
    H.map('n', ']' .. up,  "<Cmd>lua MiniBracketed.buffer('last')<CR>",     { desc = 'Last buffer' })
  end

  if config.comment.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.comment.suffix)
    H.map('n', '[' .. up, "<Cmd>lua MiniBracketed.comment('first')<CR>",  { desc = 'First comment' })
    H.map('x', '[' .. up, "<Cmd>lua MiniBracketed.comment('first')<CR>",  { desc = 'First comment' })
    H.map('o', '[' .. up, "V<Cmd>lua MiniBracketed.comment('first')<CR>", { desc = 'First comment' })

    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.comment('backward')<CR>",  { desc = 'Previous comment' })
    H.map('x', '[' .. low, "<Cmd>lua MiniBracketed.comment('backward')<CR>",  { desc = 'Previous comment' })
    H.map('o', '[' .. low, "V<Cmd>lua MiniBracketed.comment('backward')<CR>", { desc = 'Previous comment' })

    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.comment('forward')<CR>",  { desc = 'Next comment' })
    H.map('x', ']' .. low, "<Cmd>lua MiniBracketed.comment('forward')<CR>",  { desc = 'Next comment' })
    H.map('o', ']' .. low, "V<Cmd>lua MiniBracketed.comment('forward')<CR>", { desc = 'Next comment' })

    H.map('n', ']' .. up, "<Cmd>lua MiniBracketed.comment('last')<CR>",  { desc = 'Last comment' })
    H.map('x', ']' .. up, "<Cmd>lua MiniBracketed.comment('last')<CR>",  { desc = 'Last comment' })
    H.map('o', ']' .. up, "V<Cmd>lua MiniBracketed.comment('last')<CR>", { desc = 'Last comment' })
  end

  if config.conflict.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.conflict.suffix)
    H.map('n', '[' .. up, "<Cmd>lua MiniBracketed.conflict('first')<CR>",  { desc = 'First conflict' })
    H.map('x', '[' .. up, "<Cmd>lua MiniBracketed.conflict('first')<CR>",  { desc = 'First conflict' })
    H.map('o', '[' .. up, "V<Cmd>lua MiniBracketed.conflict('first')<CR>", { desc = 'First conflict' })

    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.conflict('backward')<CR>",  { desc = 'Previous conflict' })
    H.map('x', '[' .. low, "<Cmd>lua MiniBracketed.conflict('backward')<CR>",  { desc = 'Previous conflict' })
    H.map('o', '[' .. low, "V<Cmd>lua MiniBracketed.conflict('backward')<CR>", { desc = 'Previous conflict' })

    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.conflict('forward')<CR>",  { desc = 'Next conflict' })
    H.map('x', ']' .. low, "<Cmd>lua MiniBracketed.conflict('forward')<CR>",  { desc = 'Next conflict' })
    H.map('o', ']' .. low, "V<Cmd>lua MiniBracketed.conflict('forward')<CR>", { desc = 'Next conflict' })

    H.map('n', ']' .. up, "<Cmd>lua MiniBracketed.conflict('last')<CR>",  { desc = 'Last conflict' })
    H.map('x', ']' .. up, "<Cmd>lua MiniBracketed.conflict('last')<CR>",  { desc = 'Last conflict' })
    H.map('o', ']' .. up, "V<Cmd>lua MiniBracketed.conflict('last')<CR>", { desc = 'Last conflict' })
  end

  if config.diagnostic.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.diagnostic.suffix)
    H.map('n', '[' .. up, "<Cmd>lua MiniBracketed.diagnostic('first')<CR>",  { desc = 'First diagnostic' })
    H.map('x', '[' .. up, "<Cmd>lua MiniBracketed.diagnostic('first')<CR>",  { desc = 'First diagnostic' })
    H.map('o', '[' .. up, "v<Cmd>lua MiniBracketed.diagnostic('first')<CR>", { desc = 'First diagnostic' })

    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.diagnostic('backward')<CR>",  { desc = 'Previous diagnostic' })
    H.map('x', '[' .. low, "<Cmd>lua MiniBracketed.diagnostic('backward')<CR>",  { desc = 'Previous diagnostic' })
    H.map('o', '[' .. low, "v<Cmd>lua MiniBracketed.diagnostic('backward')<CR>", { desc = 'Previous diagnostic' })

    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.diagnostic('forward')<CR>",  { desc = 'Next diagnostic' })
    H.map('x', ']' .. low, "<Cmd>lua MiniBracketed.diagnostic('forward')<CR>",  { desc = 'Next diagnostic' })
    H.map('o', ']' .. low, "v<Cmd>lua MiniBracketed.diagnostic('forward')<CR>", { desc = 'Next diagnostic' })

    H.map('n', ']' .. up, "<Cmd>lua MiniBracketed.diagnostic('last')<CR>",  { desc = 'Last diagnostic' })
    H.map('x', ']' .. up, "<Cmd>lua MiniBracketed.diagnostic('last')<CR>",  { desc = 'Last diagnostic' })
    H.map('o', ']' .. up, "v<Cmd>lua MiniBracketed.diagnostic('last')<CR>", { desc = 'Last diagnostic' })
  end

  if config.file.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.file.suffix)
    H.map('n', '[' .. up,  "<Cmd>lua MiniBracketed.file('first')<CR>",    { desc = 'First file' })
    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.file('backward')<CR>", { desc = 'Previous file' })
    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.file('forward')<CR>",  { desc = 'Next file' })
    H.map('n', ']' .. up,  "<Cmd>lua MiniBracketed.file('last')<CR>",     { desc = 'Last file' })
  end

  if config.indent.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.indent.suffix)
    H.map('n', '[' .. up, "<Cmd>lua MiniBracketed.indent('first')<CR>",  { desc = 'First indent' })
    H.map('x', '[' .. up, "<Cmd>lua MiniBracketed.indent('first')<CR>",  { desc = 'First indent' })
    H.map('o', '[' .. up, "V<Cmd>lua MiniBracketed.indent('first')<CR>", { desc = 'First indent' })

    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.indent('backward')<CR>",  { desc = 'Previous indent' })
    H.map('x', '[' .. low, "<Cmd>lua MiniBracketed.indent('backward')<CR>",  { desc = 'Previous indent' })
    H.map('o', '[' .. low, "V<Cmd>lua MiniBracketed.indent('backward')<CR>", { desc = 'Previous indent' })

    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.indent('forward')<CR>",  { desc = 'Next indent' })
    H.map('x', ']' .. low, "<Cmd>lua MiniBracketed.indent('forward')<CR>",  { desc = 'Next indent' })
    H.map('o', ']' .. low, "V<Cmd>lua MiniBracketed.indent('forward')<CR>", { desc = 'Next indent' })

    H.map('n', ']' .. up, "<Cmd>lua MiniBracketed.indent('last')<CR>",  { desc = 'Last indent' })
    H.map('x', ']' .. up, "<Cmd>lua MiniBracketed.indent('last')<CR>",  { desc = 'Last indent' })
    H.map('o', ']' .. up, "V<Cmd>lua MiniBracketed.indent('last')<CR>", { desc = 'Last indent' })
  end

  if config.jump.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.jump.suffix)
    H.map('n', '[' .. up, "<Cmd>lua MiniBracketed.jump('first')<CR>",  { desc = 'First jump' })
    H.map('x', '[' .. up, "<Cmd>lua MiniBracketed.jump('first')<CR>",  { desc = 'First jump' })
    H.map('o', '[' .. up, "v<Cmd>lua MiniBracketed.jump('first')<CR>", { desc = 'First jump' })

    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.jump('backward')<CR>",  { desc = 'Previous jump' })
    H.map('x', '[' .. low, "<Cmd>lua MiniBracketed.jump('backward')<CR>",  { desc = 'Previous jump' })
    H.map('o', '[' .. low, "v<Cmd>lua MiniBracketed.jump('backward')<CR>", { desc = 'Previous jump' })

    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.jump('forward')<CR>",  { desc = 'Next jump' })
    H.map('x', ']' .. low, "<Cmd>lua MiniBracketed.jump('forward')<CR>",  { desc = 'Next jump' })
    H.map('o', ']' .. low, "v<Cmd>lua MiniBracketed.jump('forward')<CR>", { desc = 'Next jump' })

    H.map('n', ']' .. up, "<Cmd>lua MiniBracketed.jump('last')<CR>",  { desc = 'Last jump' })
    H.map('x', ']' .. up, "<Cmd>lua MiniBracketed.jump('last')<CR>",  { desc = 'Last jump' })
    H.map('o', ']' .. up, "v<Cmd>lua MiniBracketed.jump('last')<CR>", { desc = 'Last jump' })
  end

  if config.oldfile.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.oldfile.suffix)
    H.map('n', '[' .. up,  "<Cmd>lua MiniBracketed.oldfile('first')<CR>",    { desc = 'First oldfile' })
    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.oldfile('backward')<CR>", { desc = 'Previous oldfile' })
    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.oldfile('forward')<CR>",  { desc = 'Next oldfile' })
    H.map('n', ']' .. up,  "<Cmd>lua MiniBracketed.oldfile('last')<CR>",     { desc = 'Last oldfile' })
  end

  if config.location.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.location.suffix)
    H.map('n', '[' .. up,  "<Cmd>lua MiniBracketed.location('first')<CR>",    { desc = 'First location' })
    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.location('backward')<CR>", { desc = 'Previous location' })
    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.location('forward')<CR>",  { desc = 'Next location' })
    H.map('n', ']' .. up,  "<Cmd>lua MiniBracketed.location('last')<CR>",     { desc = 'Last location' })
  end

  if config.quickfix.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.quickfix.suffix)
    H.map('n', '[' .. up,  "<Cmd>lua MiniBracketed.quickfix('first')<CR>",    { desc = 'First quickfix' })
    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.quickfix('backward')<CR>", { desc = 'Previous quickfix' })
    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.quickfix('forward')<CR>",  { desc = 'Next quickfix' })
    H.map('n', ']' .. up,  "<Cmd>lua MiniBracketed.quickfix('last')<CR>",     { desc = 'Last quickfix' })
  end

  if config.yank.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.yank.suffix)
    H.map('n', '[' .. up,  "<Cmd>lua MiniBracketed.yank('first')<CR>",    { desc = 'First yank' })
    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.yank('backward')<CR>", { desc = 'Previous yank' })
    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.yank('forward')<CR>",  { desc = 'Next yank' })
    H.map('n', ']' .. up,  "<Cmd>lua MiniBracketed.yank('last')<CR>",     { desc = 'Last yank' })
  end

  if config.window.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.window.suffix)
    H.map('n', '[' .. up,  "<Cmd>lua MiniBracketed.window('first')<CR>",    { desc = 'First window' })
    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.window('backward')<CR>", { desc = 'Previous window' })
    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.window('forward')<CR>",  { desc = 'Next window' })
    H.map('n', ']' .. up,  "<Cmd>lua MiniBracketed.window('last')<CR>",     { desc = 'Last window' })
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

-- Oldfiles -------------------------------------------------------------------
H.oldfiles_normalize = function()
  -- Ensure that tracking data is initialized
  H.oldfiles_ensure_initialized()

  -- Order currently readable paths in increasing order of recency
  local recency_pairs = {}
  for path, rec in pairs(H.cache.oldfiles.recency) do
    if vim.fn.filereadable(path) == 1 then table.insert(recency_pairs, { path, rec }) end
  end
  table.sort(recency_pairs, function(x, y) return x[2] < y[2] end)

  -- Construct new tracking data
  local new_recency = {}
  for i, pair in ipairs(recency_pairs) do
    new_recency[pair[1]] = i
  end

  H.cache.oldfiles =
    { recency = new_recency, max_recency = #recency_pairs, is_from_oldfile = H.cache.oldfiles.is_from_oldfile }
end

H.oldfiles_ensure_initialized = function()
  if H.cache.oldfiles ~= nil or vim.v.oldfiles == nil then return end

  local n = #vim.v.oldfiles
  local recency = {}
  for i, path in ipairs(vim.v.oldfiles) do
    if vim.fn.filereadable(path) == 1 then recency[path] = n - i + 1 end
  end

  H.cache.oldfiles = { recency = recency, max_recency = n, is_from_oldfile = false }
end

H.oldfiles_get_array = function()
  local res = {}
  for path, i in pairs(H.cache.oldfiles.recency) do
    res[i] = path
  end
  return res
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

-- Yank -----------------------------------------------------------------------
H.yank_stop_advancing = function()
  H.cache.yank.current_history_id = #H.cache.yank.history
  H.cache.yank.is_advancing = false
  H.cache.yank.advance_put_regions[vim.api.nvim_get_current_buf()] = nil
end

H.get_yank_state = function() return { buf_id = vim.api.nvim_get_current_buf(), changedtick = vim.b.changedtick } end

H.replace_latest_put_region = function(yank_data)
  -- Squash all yank advancing in a single undo block
  local normal_command = (H.cache.yank.is_advancing and 'undojoin | ' or '') .. 'silent normal! '
  local cmd = function(x) vim.cmd(normal_command .. x) end

  -- Compute latest put region: from latest `yank` advance; or from user's
  -- latest put; or from `[`/`]` marks
  local cache = H.cache.yank
  local buf_id = vim.api.nvim_get_current_buf()
  local latest_region = cache.advance_put_regions[buf_id] or cache.user_put_regions[buf_id] or H.get_latest_region()

  -- Delete latest region in "black hole" register: visually select from
  -- finish to start (so that cursor ends up at start) and delete.
  vim.api.nvim_win_set_cursor(0, { latest_region.to.line, latest_region.to.col - 1 })
  cmd(latest_region.mode)
  vim.api.nvim_win_set_cursor(0, { latest_region.from.line, latest_region.from.col - 1 })

  H.cache.yank.do_track_next = false
  cmd('"_d')

  -- Paste yank data using temporary register
  local cache_z_reg = vim.fn.getreg('z')
  vim.fn.setreg('z', yank_data.regcontents, yank_data.regtype)

  local new_mode = yank_data.regtype:sub(1, 1)
  H.cache.yank.do_track_next = false
  cmd('"z' .. (new_mode == 'V' and 'P' or 'p'))

  vim.fn.setreg('z', cache_z_reg)

  -- Register newly put region for correct further advancing
  cache.advance_put_regions[buf_id] = H.get_latest_region(new_mode)
end

H.get_latest_region = function(mode)
  local left, right = vim.fn.getpos("'["), vim.fn.getpos("']")
  return {
    from = { line = left[2], col = left[3] },
    to = { line = right[2], col = right[3] },
    -- Mode should be one of 'v', 'V', or '\22' ('<C-v>')
    -- By default use mode of recent or unnamed register
    mode = mode or H.get_register_mode(vim.v.register),
  }
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
