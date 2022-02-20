-- MIT License Copyright (c) 2022 Evgeni Chasnovski

-- Documentation ==============================================================
--- Jump to any visible position
---
--- Somewhat similar to 'hop.nvim', but with different algorithms.
---
--- # Setup~
---
--- This module needs a setup with `require('mini.jump2d').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table
--- `MiniJump2d` which you can use for scripting or manually (with `:lua
--- MiniJump2d.*`). See |MiniJump2d.config| for available config settings.
---
--- # Comparisons~
---
--- - 'phaazon/hop.nvim':
---
--- # Highlight groups~
---
--- - `MiniJump2dSpot` - highlighting of default jump spots. By default it
---   inverts highlighting of underlying character. If it adds too much visual
---   noise, try couplel of these alternatives (or choose your own, of course):
---   `hi MiniJump2dSpot gui=undercurl guisp=red` - red undercurl
---   `hi MiniJump2dSpot gui=bold,italic` - bold italic
---
--- # Disabling~
---
--- To disable, set `g:minijump2d_disable` (globally) or `b:minijump2d_disable`
--- (for a buffer) to `v:true`. Considering high number of different scenarios
--- and customization intentions, writing exact rules for disabling module's
--- functionality is left to user. See |mini.nvim-disabling-recipes| for common
--- recipes.
---@tag mini.jump2d
---@tag MiniJump2d
---@toc_entry Jump to any visible position

-- Module definition ==========================================================
local MiniJump2d = {}
H = {}

--- Module setup
---
---@param config table Module config table. See |MiniJump2d.config|.
---
---@usage `require('mini.jump2d').setup({})` (replace `{}` with your `config` table)
function MiniJump2d.setup(config)
  -- Export module
  _G.MiniJump2d = MiniJump2d

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Create highlighting
  vim.api.nvim_exec('hi default MiniJump2dSpot gui=reverse', false)
end

--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniJump2d.config = {
  -- Function producing jump spots (byte indexed) for a particular line
  -- If `nil` (default) - spot all alphanumeric characters
  spotter = nil,

  encoders = 'abcdefghijklmnopqrstuvwxyz',

  -- Which lines are used for spots
  allowed_lines = {
    blank = true, -- Start of blank line (not sent to spotter)
    fold = true, -- Start of fold (not sent to spotter)
    cursor_before = true, -- Lines before cursor line
    cursor_at = true, -- Cursor line
    cursor_after = true, -- Lines after cursor line
  },

  all_visible_windows = true,

  after_jump_hook = nil,

  -- Module mappings. Use `''` (empty string) to disable one.
  mappings = {
    start_jumping = '<CR>',
  },
}
--minidoc_afterlines_end

-- Module functionality =======================================================
function MiniJump2d.start(opts)
  opts = vim.tbl_deep_extend('force', MiniJump2d.config, opts or {})
  opts.spotter = opts.spotter or MiniJump2d.gen_spotter_pattern()
  opts.hl_group = opts.hl_group or 'MiniJump2dSpot'

  local spots = H.spots_compute(opts)
  spots = H.spots_encode(spots, opts)

  H.spots_show(spots, opts)

  H.current.spots = spots
  -- Defer advancing jump to allow drawing before invoking `getcharstr()`.
  -- This is much faster than having to call `vim.cmd('redraw')`
  vim.defer_fn(function()
    H.advance_jump(opts)
  end, 0)
end

function MiniJump2d.gen_spotter_pattern(pattern)
  -- Don't use `%w` to account for multibyte characters
  pattern = pattern or '[^%s%p]+'

  -- Process patterns which start with `^` separately because they won't be
  -- processed correctly in the following code due to manual `()` prefix
  if pattern:sub(1, 1) == '^' then
    return function(line_num, args)
      local line = vim.fn.getline(line_num)
      return line:find(pattern) ~= nil and { 1 } or {}
    end
  end

  -- `()` means match position inside input string
  local matching_pattern = '()' .. pattern

  return function(line_num, args)
    local line = vim.fn.getline(line_num)
    local res = {}
    for i in string.gmatch(line, matching_pattern) do
      -- Ensure that index is strictly within line length (which can be not
      -- true in case of weird pattern, like when using frontier `%f[%W]`)
      i = math.min(math.max(i, 0), line:len())
      -- Add spot only if it referces new actually visible column. Deals with
      -- multibyte characters.
      if vim.str_utfindex(line, i) ~= vim.str_utfindex(line, res[#res]) then
        table.insert(res, i)
      end
    end
    return res
  end
end

function MiniJump2d.gen_spotter_line_start()
  return function(line_num, args)
    return { 1 }
  end
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniJump2d.config

-- Namespace for drawing extmarks
H.ns_id = vim.api.nvim_create_namespace('MiniJump2d')

-- Table with current relevalnt data:
H.current = {}

-- Table with special keys
H.keys = { cr = vim.api.nvim_replace_termcodes('<CR>', true, true, true) }

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
function H.setup_config(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    spotter = { config.spotter, 'function', true },
    encoders = { config.encoders, 'string' },

    allowed_lines = { config.allowed_lines, 'table' },
    ['allowed_lines.blank'] = { config.allowed_lines.blank, 'boolean' },
    ['allowed_lines.fold'] = { config.allowed_lines.fold, 'boolean' },
    ['allowed_lines.cursor_before'] = { config.allowed_lines.cursor_before, 'boolean' },
    ['allowed_lines.cursor_at'] = { config.allowed_lines.cursor_at, 'boolean' },
    ['allowed_lines.cursor_after'] = { config.allowed_lines.cursor_after, 'boolean' },

    all_visible_windows = { config.all_visible_windows, 'boolean' },

    after_jump_hook = { config.after_jump_hook, 'function', true },

    mappings = { config.mappings, 'table' },
    ['mappings.start_jumping'] = { config.mappings.start_jumping, 'string' },
  })
  return config
end

function H.apply_config(config)
  MiniJump2d.config = config

  -- Apply mappings
  H.map('n', config.mappings.start_jumping, '<Cmd>lua MiniJump2d.start()<CR>', {})
  H.map('x', config.mappings.start_jumping, '<Cmd>lua MiniJump2d.start()<CR>', {})
  H.map('o', config.mappings.start_jumping, '<Cmd>lua MiniJump2d.start()<CR>', {})
end

function H.is_disabled()
  return vim.g.minijump2d_disable == true or vim.b.minijump2d_disable == true
end

-- Jump spots -----------------------------------------------------------------
function H.spots_compute(opts)
  local win_id_init = vim.api.nvim_get_current_win()
  local win_id_arr = opts.all_visible_windows and vim.api.nvim_tabpage_list_wins(0) or { win_id_init }

  local res = {}
  for _, win_id in ipairs(win_id_arr) do
    vim.api.nvim_win_call(win_id, function()
      local cursor_pos = vim.api.nvim_win_get_cursor(win_id)
      local spotter_args = { win_id = win_id, win_id_init = win_id_init }
      local buf_id = vim.api.nvim_win_get_buf(win_id)

      -- Use all currently visible lines
      for i = vim.fn.line('w0'), vim.fn.line('w$') do
        local columns = H.spot_in_line(i, spotter_args, opts, cursor_pos)
        for _, col in ipairs(columns) do
          table.insert(res, { line = i, column = col, buf_id = buf_id, win_id = win_id })
        end
      end
    end)
  end
  return res
end

function H.spots_encode(spots, opts)
  local encode_tbl = vim.split(opts.encoders, '')

  -- Example: with 3 encoders codes should progress with progressing of number
  -- of spots like this: 'a', 'ab', 'abc', 'aabc', 'aabbc', 'aabbcc',
  -- 'aaabbcc', 'aaabbbcc', 'aaabbbccc', etc.
  local n_spots, n_encoders = #spots, #encode_tbl
  local base, extra = math.floor(n_spots / n_encoders), n_spots % n_encoders
  local cur_id, cur_id_count = 1, 0
  for _, s in ipairs(spots) do
    cur_id_count = cur_id_count + 1
    s.code = encode_tbl[cur_id]
    if cur_id_count >= (base + (cur_id <= extra and 1 or 0)) then
      cur_id, cur_id_count = cur_id + 1, 0
    end
  end

  return spots
end

function H.spots_show(spots, opts)
  spots = spots or H.current.spots or {}
  if #spots == 0 then
    H.notify('No spots to show.')
    return
  end

  for _, extmark in ipairs(H.spots_to_extmarks(spots)) do
    local extmark_opts = {
      hl_mode = 'combine',
      -- Use very high priority
      priority = 1000,
      virt_text = { { extmark.text, opts.hl_group } },
      virt_text_pos = 'overlay',
    }
    pcall(vim.api.nvim_buf_set_extmark, extmark.buf_id, H.ns_id, extmark.line, extmark.col, extmark_opts)
  end
end

function H.spots_unshow(spots)
  spots = spots or H.current.spots or {}

  -- Remove spot extmarks from all possible buffers
  local buf_ids = {}
  for _, s in ipairs(spots) do
    buf_ids[s.buf_id] = true
  end

  for _, buf_id in ipairs(vim.tbl_keys(buf_ids)) do
    pcall(vim.api.nvim_buf_clear_namespace, buf_id, H.ns_id, 0, -1)
  end
end

function H.spots_to_extmarks(spots)
  if #spots == 0 then
    return {}
  end

  local res = {}

  local buf_id, line, col = spots[1].buf_id, spots[1].line - 1, spots[1].column - 1
  local extmark_codes = {}
  local cur_col = col
  for _, s in ipairs(spots) do
    local is_new_extmark_start = not (s.buf_id == buf_id and s.line == (line + 1) and s.column == (cur_col + 1))

    if is_new_extmark_start then
      table.insert(res, { buf_id = buf_id, col = col, line = line, text = table.concat(extmark_codes) })
      buf_id, line, col = s.buf_id, s.line - 1, s.column - 1
      extmark_codes = {}
    end

    table.insert(extmark_codes, s.code)
    cur_col = s.column
  end
  table.insert(res, { buf_id = buf_id, col = col, line = line, text = table.concat(extmark_codes) })

  return res
end

function H.spot_in_line(line_num, spotter_args, opts, cursor_pos)
  local allowed = opts.allowed_lines

  -- Adjust for cursor line
  local cur_line = cursor_pos[1]
  if
    (not allowed.cursor_before and line_num < cur_line)
    or (not allowed.cursor_at and line_num == cur_line)
    or (not allowed.cursor_after and line_num > cur_line)
  then
    return {}
  end

  -- Process folds
  local fold_indicator = vim.fn.foldclosed(line_num)
  if fold_indicator ~= -1 then
    return (allowed.fold and fold_indicator == line_num) and { 1 } or {}
  end

  -- Process blank lines
  if vim.fn.prevnonblank(line_num) ~= line_num then
    return allowed.blank and { 1 } or {}
  end

  -- Finally apply spotter
  return opts.spotter(line_num, spotter_args)
end

-- Jump state -----------------------------------------------------------------
function H.advance_jump(opts)
  local encode_tbl = vim.split(opts.encoders, '')

  local spots = H.current.spots

  if type(spots) ~= 'table' or #spots < 1 then
    H.spots_unshow(spots)
    H.current.spots = nil
    return
  end

  local key = H.getchar()

  if vim.tbl_contains(encode_tbl, key) then
    H.spots_unshow(spots)
    spots = vim.tbl_filter(function(x)
      return x.code == key
    end, spots)

    if #spots > 1 then
      spots = H.spots_encode(spots, opts)
      H.spots_show(spots, opts)
      H.current.spots = spots

      -- Defer advancing jump to allow drawing before invoking `getcharstr()`.
      -- This is much faster than having to call `vim.cmd('redraw')`
      vim.defer_fn(function()
        H.advance_jump(opts)
      end, 0)
      return
    end
  end

  if #spots == 1 or key == H.keys.cr then
    vim.cmd('normal! m`')
    local first_spot = spots[1]
    vim.api.nvim_set_current_win(first_spot.win_id)
    vim.api.nvim_win_set_cursor(first_spot.win_id, { first_spot.line, first_spot.column - 1 })
    -- Possibly unfold to see cursor
    vim.cmd([[normal! zv]])
    if opts.after_jump_hook ~= nil then
      opts.after_jump_hook()
    end
  end

  H.spots_unshow(spots)
  H.current.spots = nil
end

-- Utilities ------------------------------------------------------------------
function H.notify(msg)
  vim.notify(('(mini.jump2d) %s'):format(msg))
end

function H.getchar()
  local needs_help_msg = true
  vim.defer_fn(function()
    if not needs_help_msg then
      return
    end
    H.notify('Enter encoding symbol to advance jump')
  end, 1000)

  local key = vim.fn.getcharstr()
  needs_help_msg = false

  return key
end

function H.map(mode, key, rhs, opts)
  if key == '' then
    return
  end

  opts = vim.tbl_deep_extend('force', { noremap = true, silent = true }, opts or {})
  vim.api.nvim_set_keymap(mode, key, rhs, opts)
end

return MiniJump2d
