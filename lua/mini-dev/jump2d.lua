-- MIT License Copyright (c) 2022 Evgeni Chasnovski

-- Documentation ==============================================================
--- Custom minimal and fast Lua plugin for jumping within visible lines. Main
--- inspiration for it is a 'phaazon/hop.nvim' plugin, but this module has a
--- slightly different idea about how eventual jump spot is be chosen.
---
--- Features:
--- - Make jump by sequential filtering of allowed jump spots until there is
---   only one. Filtering is done by typing a label character that is
---   visualized over jump spot.
--- - Customizable:
---     - Way of computing allowed jump spots.
---     - Characters used to label jump spots during sequential filtering.
---     - Action hooks to be executed at certain events during jump.
---     - And more.
--- - Works in Visual and Operator-pending modes for default mapping.
---
--- General overview of how jump is performed:
--- - Lock eyes on desired location ("spot") recognizable by future jump.
---   Should be within visible lines at place where cursor can be put.
--- - Initiate jump. Either by custom keybinding or with a call to
---   |MiniJump2d.start()| (takes options allowing for customization). This
---   will highlight all possible jump spots with their labels (letters from
---   "a" to "z" by default).
--- - Type character that appeared over desired location. If its label was
---   unique, jump is performed. If it wasn't unique, allowed jump spots are
---   filtered to those having the same label character.
--- - Repeat previous step until there is only single allowed jump spot or type
---   `<CR>` to jump to first allowed jump spot.
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
---     - Both are fast and customizable.
---     - Both have several builtin ways to specify type of jump (word start,
---       line start, one character or query based on user input).
---     - Algorithm used to define
---     - TODO: Main differences ...
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
---@toc_entry Jump within visible lines

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

  -- Characters used for jump spots labels (in that order)
  labels = 'abcdefghijklmnopqrstuvwxyz',

  -- Which lines are used for spots
  allowed_lines = {
    blank = true, -- Start of blank line (not sent to spotter)
    fold = true, -- Start of fold (not sent to spotter)
    cursor_before = true, -- Lines before cursor line
    cursor_at = true, -- Cursor line
    cursor_after = true, -- Lines after cursor line
  },

  -- Whether to use all visible windows
  all_visible_windows = true,

  -- Functions to be executed at certain events
  hooks = {
    before_start = nil, -- Before jump start
    after_jump = nil, -- After jump was actually done
  },

  -- Module mappings. Use `''` (empty string) to disable one.
  mappings = {
    start_jumping = '<CR>',
  },
}
--minidoc_afterlines_end

-- Module functionality =======================================================
function MiniJump2d.start(opts)
  if H.is_disabled() then
    return
  end

  opts = opts or {}

  -- Apply `before_start` before `tbl_deep_extend` to allow it modify options
  -- inside it (notably `spotter`). Example: `builtins.single_character`.
  local before_start = (opts.hooks or {}).before_start or MiniJump2d.config.hooks.before_start
  if before_start ~= nil then
    before_start()
  end

  opts = vim.tbl_deep_extend('force', MiniJump2d.config, opts)
  opts.spotter = opts.spotter or MiniJump2d.gen_pattern_spotter()
  opts.hl_group = opts.hl_group or 'MiniJump2dSpot'

  local spots = H.spots_compute(opts)
  spots = H.spots_label(spots, opts)

  H.spots_show(spots, opts)

  H.current.spots = spots

  -- Defer advancing jump to allow drawing before invoking `getcharstr()`.
  -- This is much faster than having to call `vim.cmd('redraw')`.
  -- Don't do that in Operator-pending mode because it doesn't work otherwise.
  if H.is_operator_pending() then
    H.advance_jump(opts)
  else
    vim.defer_fn(function()
      H.advance_jump(opts)
    end, 0)
  end
end

--- Generate spotter for Lua pattern
---
---@param pattern string Lua pattern. Default: `'[^%s%p]+'` which matches group
---   of "non-whitespace non-punctuation characters" (basically a way of saying
---   "group of alphanumeric characters" that works with multibyte characters).
---@param side string Which side of pattern match should be considered as
---   jumping spot. Should be one of 'start' (start of match, default), 'end'
---   (inclusive end of match), or 'none' (match for spot is done manually
---   inside pattern with plain `()` matching group).
---
---@usage - Match any punctuation:
---   `MiniJump2d.gen_pattern_spotter('%p')`
--- - Match first non-whitespace character:
---   `MiniJump2d.gen_pattern_spotter('^%s*%S', 'end')`
--- - Match start of last word:
---   `MiniJump2d.gen_pattern_spotter('[^%s%p]+[%s%p]-$', 'start')`
--- - Match letter followed by another letter (example of manual matching
---   inside pattern):
---   `MiniJump2d.gen_pattern_spotter('%a()%a', 'none')`
function MiniJump2d.gen_pattern_spotter(pattern, side)
  -- Don't use `%w` to account for multibyte characters
  pattern = pattern or '[^%s%p]+'
  side = side or 'start'

  -- Process anchored patterns separately because:
  -- - `gmatch()` doesn't work if pattern start with `^`.
  -- - Manual adding of `()` will conflict with anchors.
  local is_anchored = pattern:sub(1, 1) == '^' or pattern:sub(-1, -1) == '$'
  if is_anchored then
    return function(line_num, args)
      local line = vim.fn.getline(line_num)
      local s, e, m = line:find(pattern)
      return { ({ ['start'] = s, ['end'] = e, ['none'] = m })[side] }
    end
  end

  -- Handle `side = 'end'` later by appending length of match to match start.
  -- This, unlike appending `()` to end of pattern, makes output spot to be
  -- inside matched pattern.
  -- Having `(%s)` for `side = 'none'` is for compatibility with later `gmatch`
  local pattern_template = side == 'none' and '(%s)' or '(()%s)'
  pattern = pattern_template:format(pattern)

  return function(line_num, args)
    local line = vim.fn.getline(line_num)
    local res = {}
    -- NOTE: maybe a more straightforward approach would be a series of
    -- `line:find(original_pattern, init)` with moving `init`, but it has some
    -- weird behavior with quantifiers.
    -- For example: `string.find('  --', '%s*', 4)` returns `4 3`.
    for whole, spot in string.gmatch(line, pattern) do
      -- Correct spot to be index of last matched position
      local correction = side == 'end' and math.max(whole:len() - 1, 0) or 0
      spot = spot + correction

      -- Ensure that index is strictly within line length (which can be not
      -- true in case of weird pattern, like when using frontier `%f[%W]`)
      spot = math.min(math.max(spot, 0), line:len())

      -- Add spot only if it referces new actually visible column. Deals with
      -- multibyte characters.
      if vim.str_utfindex(line, spot) ~= vim.str_utfindex(line, res[#res]) then
        table.insert(res, spot)
      end
    end
    return res
  end
end

--- Table with builtin `opts` for |MiniJump2d.start()|
---
---@usage MiniJump2d.start(MiniJump2d.builtin_opts.line_start)
MiniJump2d.builtin_opts = {}

--- Jump to line start
MiniJump2d.builtin_opts.line_start = {
  spotter = function(line_num, args)
    return { 1 }
  end,
  hooks = {
    after_jump = function()
      -- Move to first non-blank character
      vim.cmd('normal! ^')
    end,
  },
}

-- Produce `opts` which modifies spotter based on user input
local function user_input_opts(input_fun)
  local res = {
    spotter = function()
      return {}
    end,
    allowed_lines = { blank = false, fold = false },
  }

  res.hooks = {
    before_start = function()
      local pattern = vim.pesc(input_fun())
      res.spotter = MiniJump2d.gen_pattern_spotter(pattern)
    end,
  }

  return res
end

--- Jump to single character taken from user input
MiniJump2d.builtin_opts.single_character = user_input_opts(function()
  return H.getcharstr('Enter single character to search')
end)

--- Jump to query taken from user input
MiniJump2d.builtin_opts.query = user_input_opts(function()
  return vim.fn.input('(mini.jump2d) Enter query to search: ', '')
end)

-- Helper data ================================================================
-- Module default config
H.default_config = MiniJump2d.config

-- Namespace for drawing extmarks
H.ns_id = vim.api.nvim_create_namespace('MiniJump2d')

-- Table with current relevalnt data:
H.current = {}

-- Table with special keys
H.keys = {
  cr = vim.api.nvim_replace_termcodes('<CR>', true, true, true),
  block_operator_pending = vim.api.nvim_replace_termcodes('no<C-V>', true, true, true),
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
function H.setup_config(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    spotter = { config.spotter, 'function', true },

    labels = { config.labels, 'string' },

    allowed_lines = { config.allowed_lines, 'table' },
    ['allowed_lines.blank'] = { config.allowed_lines.blank, 'boolean' },
    ['allowed_lines.fold'] = { config.allowed_lines.fold, 'boolean' },
    ['allowed_lines.cursor_before'] = { config.allowed_lines.cursor_before, 'boolean' },
    ['allowed_lines.cursor_at'] = { config.allowed_lines.cursor_at, 'boolean' },
    ['allowed_lines.cursor_after'] = { config.allowed_lines.cursor_after, 'boolean' },

    all_visible_windows = { config.all_visible_windows, 'boolean' },

    hooks = { config.hooks, 'table' },
    ['hooks.before_start'] = { config.hooks.before_start, 'function', true },
    ['hooks.after_jump'] = { config.hooks.after_jump, 'function', true },

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

function H.spots_label(spots, opts)
  local label_tbl = vim.split(opts.labels, '')

  -- Example: with 3 label characters labels should progress with progressing
  -- of number of spots like this: 'a', 'ab', 'abc', 'aabc', 'aabbc', 'aabbcc',
  -- 'aaabbcc', 'aaabbbcc', 'aaabbbccc', etc.
  local n_spots, n_label_chars = #spots, #label_tbl
  local base, extra = math.floor(n_spots / n_label_chars), n_spots % n_label_chars
  local cur_id, cur_id_count = 1, 0
  for _, s in ipairs(spots) do
    cur_id_count = cur_id_count + 1
    s.label = label_tbl[cur_id]
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

  -- Need to redraw in Operator-pending mode, because otherwise extmarks won't
  -- be shown and deferring disable this mode.
  if H.is_operator_pending() then
    vim.cmd('redraw')
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
  local extmark_chars = {}
  local cur_col = col
  for _, s in ipairs(spots) do
    local is_new_extmark_start = not (s.buf_id == buf_id and s.line == (line + 1) and s.column == (cur_col + 1))

    if is_new_extmark_start then
      table.insert(res, { buf_id = buf_id, col = col, line = line, text = table.concat(extmark_chars) })
      buf_id, line, col = s.buf_id, s.line - 1, s.column - 1
      extmark_chars = {}
    end

    table.insert(extmark_chars, s.label)
    cur_col = s.column
  end
  table.insert(res, { buf_id = buf_id, col = col, line = line, text = table.concat(extmark_chars) })

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
  local label_tbl = vim.split(opts.labels, '')

  local spots = H.current.spots

  if type(spots) ~= 'table' or #spots < 1 then
    H.spots_unshow(spots)
    H.current.spots = nil
    return
  end

  local key = H.getcharstr('Enter encoding symbol to advance jump')

  if vim.tbl_contains(label_tbl, key) then
    H.spots_unshow(spots)
    spots = vim.tbl_filter(function(x)
      return x.label == key
    end, spots)

    if #spots > 1 then
      spots = H.spots_label(spots, opts)
      H.spots_show(spots, opts)
      H.current.spots = spots

      -- Defer advancing jump to allow drawing before invoking `getcharstr()`.
      -- This is much faster than having to call `vim.cmd('redraw')`. Don't do that
      -- in Operator-pending mode because it doesn't work otherwise.
      if H.is_operator_pending() then
        H.advance_jump(opts)
      else
        vim.defer_fn(function()
          H.advance_jump(opts)
        end, 0)
        return
      end
    end
  end

  if #spots == 1 or key == H.keys.cr then
    vim.cmd('normal! m`')
    local first_spot = spots[1]
    vim.api.nvim_set_current_win(first_spot.win_id)
    vim.api.nvim_win_set_cursor(first_spot.win_id, { first_spot.line, first_spot.column - 1 })
    -- Possibly unfold to see cursor
    vim.cmd([[normal! zv]])
    if opts.hooks.after_jump ~= nil then
      opts.hooks.after_jump()
    end
  end

  H.spots_unshow(spots)
  H.current.spots = nil
end

-- Utilities ------------------------------------------------------------------
function H.notify(msg)
  vim.notify(('(mini.jump2d) %s'):format(msg))
end

function H.is_operator_pending()
  return vim.tbl_contains({ 'no', 'noV', H.keys.block_operator_pending }, vim.fn.mode(1))
end

function H.getcharstr(msg)
  local needs_help_msg = true
  if msg ~= nil then
    vim.defer_fn(function()
      if needs_help_msg then
        H.notify(msg)
      end
    end, 1000)
  end

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
