-- MIT License Copyright (c) 2023 Evgeni Chasnovski

-- TODO
--
-- Code:
-- - Think about modifying `MiniBracketed.config` to have per-item configs
--   (`map_suffix` and `options`).
-- - Try to make `n_times` work in `indent` with 'first' and 'last' direction.
-- - Other todos across code.
-- - Ensure that moves guaranteed to be inside current buffer have mappings in
--   Normal, Visual, and Operator-pending modes.
-- - Refactor and clean up with possible abstractions.
--
-- Tests:
--
-- Docs:
-- - Mention that it is ok to not map defaults and use functions manually.
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
        au BufEnter * lua MiniBracketed.oldfiles_append_buf()
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
  mapping_suffixes = {
    buffer     = 'b',
    comment    = 'c',
    conflict   = 'x',
    diagnostic = 'd',
    file       = 'f',
    indent     = 'i',
    jump       = 'j',
    oldfile    = 'o',
    location   = 'l',
    quickfix   = 'q',
    window     = 'w',
  }
}
--minidoc_afterlines_end

MiniBracketed.buffer = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'prev', 'next', 'last' }, 'buffer')
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1, wrap = true }, opts or {})

  -- Define iterator that traverses all valid listed buffers
  -- (should be same as `:bnext` / `:bprev`)
  local buf_list = vim.api.nvim_list_bufs()
  local is_listed = function(buf_id) return vim.api.nvim_buf_is_valid(buf_id) and vim.bo[buf_id].buflisted end

  local iterator = {}

  iterator.forward = function(buf_id)
    for id = buf_id + 1, buf_list[#buf_list] do
      if is_listed(id) then return id end
    end
  end

  iterator.backward = function(buf_id)
    for id = buf_id - 1, buf_list[1], -1 do
      if is_listed(id) then return id end
    end
  end

  iterator.state = vim.api.nvim_get_current_buf()
  iterator.start_edge = buf_list[1] - 1
  iterator.end_edge = buf_list[#buf_list] + 1

  -- Iterate
  local res_buf_id = H.iterate(iterator, direction, opts)

  -- Apply
  vim.api.nvim_set_current_buf(res_buf_id)
end

MiniBracketed.comment = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'prev', 'next', 'last' }, 'comment')
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1, wrap = true, block_side = 'near' }, opts or {})

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
  iterator.forward = function(line_num)
    local above, cur = is_commented(line_num), is_commented(line_num + 1)
    for lnum = line_num + 1, n_lines do
      local below = is_commented(lnum + 1)
      if predicate(above, cur, below, above) then return lnum end
      above, cur = cur, below
    end
  end

  iterator.backward = function(line_num)
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
  local res_line_num = H.iterate(iterator, direction, opts)

  -- Apply. Open just enough folds and put cursor on first non-blank.
  vim.api.nvim_win_set_cursor(0, { res_line_num, 0 })
  vim.cmd('normal! zv^')
end

MiniBracketed.conflict = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'prev', 'next', 'last' }, 'conflict')
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1, wrap = true }, opts or {})

  -- Define iterator that traverses all conflict markers in current buffer
  local n_lines = vim.api.nvim_buf_line_count(0)

  local iterator = {}

  iterator.forward = function(line_num)
    for lnum = line_num + 1, n_lines do
      if H.is_conflict_mark(lnum) then return lnum end
    end
  end

  iterator.backward = function(line_num)
    for lnum = line_num - 1, 1, -1 do
      if H.is_conflict_mark(lnum) then return lnum end
    end
  end

  iterator.state = vim.fn.line('.')
  iterator.start_edge = 0
  iterator.end_edge = n_lines + 1

  -- Iterate
  local res_line_num = H.iterate(iterator, direction, opts)

  -- Apply. Open just enough folds and put cursor on first non-blank.
  vim.api.nvim_win_set_cursor(0, { res_line_num, 0 })
  vim.cmd('normal! zv^')
end

MiniBracketed.diagnostic = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'prev', 'next', 'last' }, 'diagnostic')
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1, wrap = true }, opts or {})

  -- Define iterator that traverses all diagnostic entries in current buffer
  local is_position = function(x) return type(x) == 'table' and #x == 2 end
  local diag_pos_to_cursor_pos = function(pos) return { pos[1] + 1, pos[2] } end
  local iterator = {}

  iterator.forward = function(position)
    local new_pos = vim.diagnostic.get_next_pos({ cursor_position = diag_pos_to_cursor_pos(position), wrap = false })
    if not is_position(new_pos) then return end
    return new_pos
  end

  iterator.backward = function(position)
    local new_pos = vim.diagnostic.get_prev_pos({ cursor_position = diag_pos_to_cursor_pos(position), wrap = false })
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
  local res_pos = H.iterate(iterator, direction, opts)

  -- Apply. Open just enough folds.
  vim.api.nvim_win_set_cursor(0, diag_pos_to_cursor_pos(res_pos))
  vim.cmd('normal! zv')
end

MiniBracketed.file = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'prev', 'next', 'last' }, 'file')
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1, wrap = true }, opts or {})

  -- Get file data
  local file_data = H.get_file_data()
  if file_data == nil then return end
  local file_basenames, directory = file_data.file_basenames, file_data.directory

  -- Define iterator that traverses all found files
  local iterator = {}

  iterator.forward = function(ind)
    if ind == nil or #file_basenames <= ind then return end
    return ind + 1
  end

  iterator.backward = function(ind)
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
  local res_ind = H.iterate(iterator, direction, opts)
  -- - Do nothing if it should open current buffer. Reduces flickering.
  if res_ind == iterator.state then return end

  -- Apply. Open target_path.
  local path_sep = package.config:sub(1, 1)
  local target_path = directory .. path_sep .. file_basenames[res_ind]
  vim.cmd('edit ' .. target_path)
end

MiniBracketed.indent = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'prev', 'next', 'last' }, 'indent')
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1, change_type = 'diff' }, opts or {})

  opts.wrap = false

  if direction == 'first' then
    -- For some reason using `n_times = math.huge` leads to infinite loop
    direction, opts.n_times = 'prev', vim.api.nvim_buf_line_count(0) + 1
  end
  if direction == 'last' then
    direction, opts.n_times = 'next', vim.api.nvim_buf_line_count(0) + 1
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

  iterator.forward = function(cur_lnum)
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

  iterator.backward = function(cur_lnum)
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
  local res_line_num = H.iterate(iterator, direction, opts)

  -- Apply. Open just enough folds and put cursor on first non-blank.
  vim.api.nvim_win_set_cursor(0, { res_line_num, 0 })
  vim.cmd('normal! zv^')
end

MiniBracketed.jump = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'prev', 'next', 'last' }, 'jump')
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1, wrap = true }, opts or {})

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

  iterator.forward = function(jump_num)
    for num = jump_num + 1, n_list do
      if is_jump_num_from_current_buffer(num) then return num end
    end
  end

  iterator.backward = function(jump_num)
    for num = jump_num - 1, 1, -1 do
      if is_jump_num_from_current_buffer(num) then return num end
    end
  end

  iterator.state = cur_jump_num
  iterator.start_edge = 0
  iterator.end_edge = n_list + 1

  -- Iterate
  local res_jump_num = H.iterate(iterator, direction, opts)

  -- Apply. Make jump.
  H.make_jump(jump_list, cur_jump_num, res_jump_num)
end

-- Files ordered from oldest to newest.
MiniBracketed.oldfile = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'prev', 'next', 'last' }, 'oldfile')
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1, wrap = true }, opts or {})

  -- Define iterator that traverses all old files
  local cur_path = vim.api.nvim_buf_get_name(0)

  H.oldfiles_normalize()
  local oldfiles = H.oldfiles_get_array()
  local n_oldfiles = #oldfiles

  local iterator = {}

  iterator.forward = function(ind)
    if ind == nil or n_oldfiles <= ind then return end
    return ind + 1
  end

  iterator.backward = function(ind)
    if ind == nil or ind <= 1 then return end
    return ind - 1
  end

  iterator.state = H.oldfiles_data.recency[cur_path]
  iterator.start_edge = 0
  iterator.end_edge = n_oldfiles + 1

  -- Iterate
  local res_path_ind = H.iterate(iterator, direction, opts)
  local res_path = oldfiles[res_path_ind]

  if res_path == cur_path then return end

  -- Apply. Edit file at path while marking it not for tracking.
  H.oldfiles_data.is_from_oldfile = true
  vim.cmd('edit ' .. res_path)
end

MiniBracketed.location = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'prev', 'next', 'last' }, 'location')
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1, wrap = true }, opts or {})

  H.qf_loc_implementation('location', direction, opts)
end

MiniBracketed.quickfix = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'prev', 'next', 'last' }, 'quickfix')
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1, wrap = true }, opts or {})

  H.qf_loc_implementation('quickfix', direction, opts)
end

MiniBracketed.window = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'prev', 'next', 'last' }, 'window')
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1, wrap = true }, opts or {})

  -- Define iterator that traverses all normal windows in "natural" order
  local is_normal = function(win_nr)
    local win_id = vim.fn.win_getid(win_nr)
    return vim.api.nvim_win_get_config(win_id).relative == ''
  end

  local iterator = {}

  iterator.forward = function(win_nr)
    for nr = win_nr + 1, vim.fn.winnr('$') do
      if is_normal(nr) then return nr end
    end
  end

  iterator.backward = function(win_nr)
    for nr = win_nr - 1, 1, -1 do
      if is_normal(nr) then return nr end
    end
  end

  iterator.state = vim.fn.winnr()
  iterator.start_edge = 0
  iterator.end_edge = vim.fn.winnr('$') + 1

  -- Iterate
  local res_win_nr = H.iterate(iterator, direction, opts)

  -- Apply
  vim.api.nvim_set_current_win(vim.fn.win_getid(res_win_nr))
end

MiniBracketed.oldfiles_append_buf = function()
  -- Ensure tracking data is initialized
  H.oldfiles_ensure_initialized()

  -- Reset tracking indicator to allow proper tracking of next buffer
  local is_from_oldfile = H.oldfiles_data.is_from_oldfile
  H.oldfiles_data.is_from_oldfile = false

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
    H.shadow_oldfiles_data = H.shadow_oldfiles_data or vim.deepcopy(H.oldfiles_data)
    track_table = H.shadow_oldfiles_data
  else
    H.oldfiles_data = H.shadow_oldfiles_data or H.oldfiles_data
    track_table = H.oldfiles_data
    H.shadow_oldfiles_data = nil
  end

  -- Update tracking table
  local n = track_table.max_recency + 1
  track_table.recency[path] = n
  track_table.max_recency = n
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniBracketed.config

-- Tracking of old files for `oldfile()` (this data structure is designed to be
-- fast to add new file):
-- - `recency` is a table with file paths as fields and numerical values
--   indicating how recent file was accessed (higher - more recent).
-- - `max_recency` is a maximum currently used `recency`. Used to add new file.
-- - `is_from_oldfile` is an indicator of buffer change was done inside
--   `oldfile()` function. It is a key to enabling moving along old files (and
--   not just going back and forth between two files because they swap places
--   as two most recent files).
H.oldfiles_data = nil

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
    ['mapping_suffixes.oldfile'] = { config.mapping_suffixes.oldfile, 'string' },
    ['mapping_suffixes.location'] = { config.mapping_suffixes.location, 'string' },
    ['mapping_suffixes.quickfix'] = { config.mapping_suffixes.quickfix, 'string' },
    ['mapping_suffixes.window'] = { config.mapping_suffixes.window, 'string' },
  })

  return config
end

--stylua: ignore
H.apply_config = function(config)
  MiniBracketed.config = config

  -- Make mappings
  local suffixes = config.mapping_suffixes

  if suffixes.buffer ~= '' then
    local low, up = H.get_suffix_variants(suffixes.buffer)
    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.buffer('prev')<CR>",  { desc = 'Previous buffer' })
    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.buffer('next')<CR>",  { desc = 'Next buffer' })
    H.map('n', '[' .. up,  "<Cmd>lua MiniBracketed.buffer('first')<CR>", { desc = 'First buffer' })
    H.map('n', ']' .. up,  "<Cmd>lua MiniBracketed.buffer('last')<CR>",  { desc = 'Last buffer' })
  end

  if suffixes.comment ~= '' then
    local low, up = H.get_suffix_variants(suffixes.comment)
    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.comment('prev')<CR>",  { desc = 'Previous comment' })
    H.map('x', '[' .. low, "<Cmd>lua MiniBracketed.comment('prev')<CR>",  { desc = 'Previous comment' })
    H.map('o', '[' .. low, "V<Cmd>lua MiniBracketed.comment('prev')<CR>", { desc = 'Previous comment' })

    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.comment('next')<CR>",  { desc = 'Next comment' })
    H.map('x', ']' .. low, "<Cmd>lua MiniBracketed.comment('next')<CR>",  { desc = 'Next comment' })
    H.map('o', ']' .. low, "V<Cmd>lua MiniBracketed.comment('next')<CR>", { desc = 'Next comment' })

    H.map('n', '[' .. up, "<Cmd>lua MiniBracketed.comment('first')<CR>",  { desc = 'First comment' })
    H.map('x', '[' .. up, "<Cmd>lua MiniBracketed.comment('first')<CR>",  { desc = 'First comment' })
    H.map('o', '[' .. up, "V<Cmd>lua MiniBracketed.comment('first')<CR>", { desc = 'First comment' })

    H.map('n', ']' .. up, "<Cmd>lua MiniBracketed.comment('last')<CR>",   { desc = 'Last comment' })
    H.map('x', ']' .. up, "<Cmd>lua MiniBracketed.comment('last')<CR>",   { desc = 'Last comment' })
    H.map('o', ']' .. up, "V<Cmd>lua MiniBracketed.comment('last')<CR>",  { desc = 'Last comment' })
  end

  if suffixes.conflict ~= '' then
    local low, up = H.get_suffix_variants(suffixes.conflict)
    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.conflict('prev')<CR>",  { desc = 'Previous conflict' })
    H.map('x', '[' .. low, "<Cmd>lua MiniBracketed.conflict('prev')<CR>",  { desc = 'Previous conflict' })
    H.map('o', '[' .. low, "V<Cmd>lua MiniBracketed.conflict('prev')<CR>", { desc = 'Previous conflict' })

    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.conflict('next')<CR>",  { desc = 'Next conflict' })
    H.map('x', ']' .. low, "<Cmd>lua MiniBracketed.conflict('next')<CR>",  { desc = 'Next conflict' })
    H.map('o', ']' .. low, "V<Cmd>lua MiniBracketed.conflict('next')<CR>", { desc = 'Next conflict' })

    H.map('n', '[' .. up, "<Cmd>lua MiniBracketed.conflict('first')<CR>",  { desc = 'First conflict' })
    H.map('x', '[' .. up, "<Cmd>lua MiniBracketed.conflict('first')<CR>",  { desc = 'First conflict' })
    H.map('o', '[' .. up, "V<Cmd>lua MiniBracketed.conflict('first')<CR>", { desc = 'First conflict' })

    H.map('n', ']' .. up, "<Cmd>lua MiniBracketed.conflict('last')<CR>",   { desc = 'Last conflict' })
    H.map('x', ']' .. up, "<Cmd>lua MiniBracketed.conflict('last')<CR>",   { desc = 'Last conflict' })
    H.map('o', ']' .. up, "V<Cmd>lua MiniBracketed.conflict('last')<CR>",  { desc = 'Last conflict' })
  end

  if suffixes.diagnostic ~= '' then
    local low, up = H.get_suffix_variants(suffixes.diagnostic)
    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.diagnostic('prev')<CR>",  { desc = 'Previous diagnostic' })
    H.map('x', '[' .. low, "<Cmd>lua MiniBracketed.diagnostic('prev')<CR>",  { desc = 'Previous diagnostic' })
    H.map('o', '[' .. low, "V<Cmd>lua MiniBracketed.diagnostic('prev')<CR>", { desc = 'Previous diagnostic' })

    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.diagnostic('next')<CR>",  { desc = 'Next diagnostic' })
    H.map('x', ']' .. low, "<Cmd>lua MiniBracketed.diagnostic('next')<CR>",  { desc = 'Next diagnostic' })
    H.map('o', ']' .. low, "V<Cmd>lua MiniBracketed.diagnostic('next')<CR>", { desc = 'Next diagnostic' })

    H.map('n', '[' .. up, "<Cmd>lua MiniBracketed.diagnostic('first')<CR>",  { desc = 'First diagnostic' })
    H.map('x', '[' .. up, "<Cmd>lua MiniBracketed.diagnostic('first')<CR>",  { desc = 'First diagnostic' })
    H.map('o', '[' .. up, "V<Cmd>lua MiniBracketed.diagnostic('first')<CR>", { desc = 'First diagnostic' })

    H.map('n', ']' .. up, "<Cmd>lua MiniBracketed.diagnostic('last')<CR>",   { desc = 'Last diagnostic' })
    H.map('x', ']' .. up, "<Cmd>lua MiniBracketed.diagnostic('last')<CR>",   { desc = 'Last diagnostic' })
    H.map('o', ']' .. up, "V<Cmd>lua MiniBracketed.diagnostic('last')<CR>",  { desc = 'Last diagnostic' })
  end

  if suffixes.file ~= '' then
    local low, up = H.get_suffix_variants(suffixes.file)
    H.map('n', '[' .. low,  "<Cmd>lua MiniBracketed.file('prev')<CR>",     { desc = 'Previous file' })
    H.map('n', ']' .. low,  "<Cmd>lua MiniBracketed.file('next')<CR>",     { desc = 'Next file' })
    H.map('n', '[' .. up,   "<Cmd>lua MiniBracketed.file('first')<CR>",    { desc = 'First file' })
    H.map('n', ']' .. up,   "<Cmd>lua MiniBracketed.file('last')<CR>",     { desc = 'Last file' })
  end

  if suffixes.indent ~= '' then
    local low, up = H.get_suffix_variants(suffixes.indent)
    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.indent('prev')<CR>",  { desc = 'Previous indent' })
    H.map('x', '[' .. low, "<Cmd>lua MiniBracketed.indent('prev')<CR>",  { desc = 'Previous indent' })
    H.map('o', '[' .. low, "V<Cmd>lua MiniBracketed.indent('prev')<CR>", { desc = 'Previous indent' })

    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.indent('next')<CR>",  { desc = 'Next indent' })
    H.map('x', ']' .. low, "<Cmd>lua MiniBracketed.indent('next')<CR>",  { desc = 'Next indent' })
    H.map('o', ']' .. low, "V<Cmd>lua MiniBracketed.indent('next')<CR>", { desc = 'Next indent' })

    H.map('n', '[' .. up, "<Cmd>lua MiniBracketed.indent('first')<CR>",  { desc = 'First indent' })
    H.map('x', '[' .. up, "<Cmd>lua MiniBracketed.indent('first')<CR>",  { desc = 'First indent' })
    H.map('o', '[' .. up, "V<Cmd>lua MiniBracketed.indent('first')<CR>", { desc = 'First indent' })

    H.map('n', ']' .. up, "<Cmd>lua MiniBracketed.indent('last')<CR>",  { desc = 'Last indent' })
    H.map('x', ']' .. up, "<Cmd>lua MiniBracketed.indent('last')<CR>",  { desc = 'Last indent' })
    H.map('o', ']' .. up, "V<Cmd>lua MiniBracketed.indent('last')<CR>", { desc = 'Last indent' })
  end

  if suffixes.jump ~= '' then
    local low, up = H.get_suffix_variants(suffixes.jump)
    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.jump('prev')<CR>",  { desc = 'Previous jump' })
    H.map('x', '[' .. low, "<Cmd>lua MiniBracketed.jump('prev')<CR>",  { desc = 'Previous jump' })
    H.map('o', '[' .. low, "V<Cmd>lua MiniBracketed.jump('prev')<CR>", { desc = 'Previous jump' })

    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.jump('next')<CR>",  { desc = 'Next jump' })
    H.map('x', ']' .. low, "<Cmd>lua MiniBracketed.jump('next')<CR>",  { desc = 'Next jump' })
    H.map('o', ']' .. low, "V<Cmd>lua MiniBracketed.jump('next')<CR>", { desc = 'Next jump' })

    H.map('n', '[' .. up, "<Cmd>lua MiniBracketed.jump('first')<CR>",  { desc = 'First jump' })
    H.map('x', '[' .. up, "<Cmd>lua MiniBracketed.jump('first')<CR>",  { desc = 'First jump' })
    H.map('o', '[' .. up, "v<Cmd>lua MiniBracketed.jump('first')<CR>", { desc = 'First jump' })

    H.map('n', ']' .. up, "<Cmd>lua MiniBracketed.jump('last')<CR>",   { desc = 'Last jump' })
    H.map('x', ']' .. up, "<Cmd>lua MiniBracketed.jump('last')<CR>",   { desc = 'Last jump' })
    H.map('o', ']' .. up, "v<Cmd>lua MiniBracketed.jump('last')<CR>",  { desc = 'Last jump' })
  end

  if suffixes.oldfile ~= '' then
    local low, up = H.get_suffix_variants(suffixes.oldfile)
    H.map('n', '[' .. low,  "<Cmd>lua MiniBracketed.oldfile('prev')<CR>",  { desc = 'Previous oldfile' })
    H.map('n', ']' .. low,  "<Cmd>lua MiniBracketed.oldfile('next')<CR>",  { desc = 'Next oldfile' })
    H.map('n', '[' .. up,   "<Cmd>lua MiniBracketed.oldfile('first')<CR>", { desc = 'First oldfile' })
    H.map('n', ']' .. up,   "<Cmd>lua MiniBracketed.oldfile('last')<CR>",  { desc = 'Last oldfile' })
  end

  if suffixes.location ~= '' then
    local low, up = H.get_suffix_variants(suffixes.location)
    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.location('prev')<CR>",  { desc = 'Previous location' })
    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.location('next')<CR>",  { desc = 'Next location' })
    H.map('n', '[' .. up,  "<Cmd>lua MiniBracketed.location('first')<CR>", { desc = 'First location' })
    H.map('n', ']' .. up,  "<Cmd>lua MiniBracketed.location('last')<CR>",  { desc = 'Last location' })
  end

  if suffixes.quickfix ~= '' then
    local low, up = H.get_suffix_variants(suffixes.quickfix)
    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.quickfix('prev')<CR>",  { desc = 'Previous quickfix' })
    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.quickfix('next')<CR>",  { desc = 'Next quickfix' })
    H.map('n', '[' .. up,  "<Cmd>lua MiniBracketed.quickfix('first')<CR>", { desc = 'First quickfix' })
    H.map('n', ']' .. up,  "<Cmd>lua MiniBracketed.quickfix('last')<CR>",  { desc = 'Last quickfix' })
  end

  if suffixes.window ~= '' then
    local low, up = H.get_suffix_variants(suffixes.window)
    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.window('prev')<CR>",  { desc = 'Previous window' })
    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.window('next')<CR>",  { desc = 'Next window' })
    H.map('n', '[' .. up,  "<Cmd>lua MiniBracketed.window('first')<CR>", { desc = 'First window' })
    H.map('n', ']' .. up,  "<Cmd>lua MiniBracketed.window('last')<CR>",  { desc = 'Last window' })
  end
end

H.get_suffix_variants = function(char) return char:lower(), char:upper() end

H.is_disabled = function() return vim.g.minibracketed_disable == true or vim.b.minibracketed_disable == true end

-- Iterator -------------------------------------------------------------------
--@param iterator table Table:
--   - Methods:
--       - <forward> - given state, return state in forward direction.
--       - <backward> - given state, return state in backward direction.
--   - Fields:
--       - <state> - object describing current state.
--       - <start_edge> (optional) - object with `forward(start_edge)` describes
--         first state.
--       - <end_edge> (optional) - object with `backward(end_edge)` describes
--         last state.
--@param direction string Direction. One of 'first', 'prev', 'next', 'last'.
--@param opts table|nil Options with the following keys:
--   - <n_times> - number of times to iterate.
--   - <wrap> - whether to wrap around edges when `forward()` or `backward()`
--     return `nil`.
H.iterate = function(iterator, direction, opts)
  local res_state = iterator.state

  -- Compute loop data
  local n_times, iter_method = opts.n_times, 'forward'

  if direction == 'prev' then iter_method = 'backward' end

  if direction == 'first' then
    res_state = iterator.start_edge or res_state
    iter_method = 'forward'
  end

  if direction == 'last' then
    res_state = iterator.end_edge or res_state
    iter_method = 'backward'
  end

  -- Loop
  local iter = iterator[iter_method]
  for _ = 1, n_times do
    -- Advance
    local new_state = iter(res_state)

    if new_state == nil then
      -- Stop if can't wrap around edges
      if not opts.wrap then break end

      -- Wrap around edge
      local edge = iter_method == 'forward' and iterator.start_edge or iterator.end_edge
      new_state = iter(edge)

      -- Ensure non-nil new state (can happen when there are no targets)
      if new_state == nil then break end
    end

    res_state = new_state
  end

  return res_state
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
  for path, rec in pairs(H.oldfiles_data.recency) do
    if vim.fn.filereadable(path) == 1 then table.insert(recency_pairs, { path, rec }) end
  end
  table.sort(recency_pairs, function(x, y) return x[2] < y[2] end)

  -- Construct new tracking data
  local new_recency = {}
  for i, pair in ipairs(recency_pairs) do
    new_recency[pair[1]] = i
  end

  H.oldfiles_data =
    { recency = new_recency, max_recency = #recency_pairs, is_from_oldfile = H.oldfiles_data.is_from_oldfile }
end

H.oldfiles_ensure_initialized = function()
  if H.oldfiles_data ~= nil or vim.v.oldfiles == nil then return end

  local n = #vim.v.oldfiles
  local recency = {}
  for i, path in ipairs(vim.v.oldfiles) do
    if vim.fn.filereadable(path) == 1 then recency[path] = n - i + 1 end
  end

  H.oldfiles_data = { recency = recency, max_recency = n, is_from_oldfile = false }
end

H.oldfiles_get_array = function()
  local res = {}
  for path, i in pairs(H.oldfiles_data.recency) do
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

  iterator.forward = function(ind)
    if ind == nil or n_list <= ind then return end
    return ind + 1
  end

  iterator.backward = function(ind)
    if ind == nil or ind <= 1 then return end
    return ind - 1
  end

  iterator.state = get_list({ idx = 0 }).idx
  iterator.start_edge = 0
  iterator.end_edge = n_list + 1

  -- Iterate
  local res_ind = H.iterate(iterator, direction, opts)

  -- Apply
  -- Focus target entry, open enough folds and center
  vim.cmd(goto_command .. ' ' .. res_ind)
  vim.cmd('normal! zvzz')
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
