-- TODO:
--
-- Code:
-- - Implement MacOS Finder with column view type of file explorer:
--     - Think about the best way to keep track of relevant cursor positions,
--       so that:
--       - Opening from history results in exactly the same view.
--       - Moving through branch preserves highlighted cursor line when window
--         displays different buffer. **Even** if cursor line is not on a line
--         with proper path id (relevant to future modifying functionality).
--
--     - Deal with changing window view (sometimes shows current line at the
--       top) when the window is assigned new buffer.
--
-- - Implement 'oil.nvim' like file manipulation:
--     - Concealed index should encode absolute file path allowing moving files
--       across directories.
--
-- - Design (and, probably, implement some) for asynchronous integrations.
--
-- - Make an effort to ensure proper work on Windows and MacOS:
--     - Windows and MacOS use case insensitive file names.
--
-- Tests:
-- - Going to the root's parent:
--     - Shouldn't force update of present buffers.
--     - Shouldn't reuse already created buffers (no new ones should be created
--       if not needed).
--
-- Docs:
-- - Open multiple files in Visual mode.

--- *mini.files* Explore and manipulate files
--- *MiniFiles*
---
--- MIT License Copyright (c) 2023 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Features:
--- - Explore file tree structure and open files using panes.
---
--- - Manipulate files by editing buffers: add, delete, rename, move.
---
--- - Use as default file explorer instead of |netrw|.
---
--- - Customizable asynchronous integrations.
---
--- - Highlighting is updated asynchronously with configurable debounce delay.
---
--- # Dependencies~
---
--- Suggested dependencies (provide extra functionality, will work without them):
--- - Plugin 'nvim-tree/nvim-web-devicons' for filetype icons near the buffer
---   name. If missing, default icons will be used.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.files').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniFiles`
--- which you can use for scripting or manually (with `:lua MiniFiles.*`).
---
--- See |MiniFiles.config| for available config settings.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.minifiles_config` which should have same structure as `MiniFiles.config`.
--- See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons ~
---
--- - 'nvim-tree/nvim-tree':
---
--- - 'stevearc/oil.nvim':
---
--- - 'nvim-neo-tree/neo-tree.nvim':
---
--- # Highlight groups ~
---
--- * `MiniFilesBorder`
--- * `MiniFilesDirectory`
--- * `MiniFilesFile`
--- * `MiniFilesNormal`
--- * `MiniFilesTitle`
---
--- To change any highlight group, modify it directly with |:highlight|.
---
--- # Disabling ~
---
--- To disable, set `vim.g.minifiles_disable` (globally) or `vim.b.minifiles_disable`
--- (for a buffer) to `true`. Considering high number of different scenarios
--- and customization intentions, writing exact rules for disabling module's
--- functionality is left to user. See |mini.nvim-disabling-recipes| for common
--- recipes.

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local
---@diagnostic disable:cast-local-type

-- Module definition ==========================================================
-- TODO: Make local before public release
MiniFiles = {}
H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniFiles.config|.
---
---@usage `require('mini.files').setup({})` (replace `{}` with your `config` table)
---@text
--- Note: no highlighters is defined by default. Add them for visible effect.
MiniFiles.setup = function(config)
  -- Export module
  _G.MiniFiles = MiniFiles

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Create default highlighting
  H.create_default_hl()
end

--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniFiles.config = {
  content = {
    filter = nil,
    sort = nil,
  },

  mappings = {
    go_left = 'h',
    go_right = 'l',
    synchronize = '=',
    quit = 'q',
  },

  windows = {
    border = 'single',
    width_focus = 50,
    width_nofocus = 15,
  },
}
--minidoc_afterlines_end

MiniFiles.open = function(path, use_latest, opts)
  -- Validate path: allow only valid file system path
  path = path or vim.fn.getcwd()
  local fs_type = H.fs_get_type(path)
  if fs_type == nil then H.error('`path` is not a valid path ("' .. path .. '")') end
  path = H.fs_full_path(path)
  -- - Allow file path and use its parent
  if fs_type == 'file' then path = H.fs_get_parent(path) end

  -- Validate rest of the arguments
  if use_latest == nil then use_latest = true end
  opts = H.get_opts(opts)

  -- Properly close possibly opened in the tabpage explorer
  MiniFiles.close()

  -- Get explorer to open
  local explorer
  if use_latest then explorer = H.explorer_history[path] end
  explorer = explorer or H.explorer_new({ path }, opts)
  explorer.target_window = vim.api.nvim_get_current_win()

  -- Refresh
  explorer = H.explorer_refresh(explorer, opts)

  -- Register explorer as opened
  H.opened_explorers[vim.api.nvim_get_current_tabpage()] = explorer
end

MiniFiles.refresh = function(opts)
  local cur_explorer = H.explorer_get()
  if cur_explorer == nil then return end

  -- Respect explorer local options supplied inside its `open()` call but give
  -- current `opts` higher precedence
  opts = H.get_opts(vim.tbl_deep_extend('force', cur_explorer.opts, opts or {}))

  H.explorer_refresh(cur_explorer, opts)
end

MiniFiles.close = function()
  local cur_explorer = H.explorer_get()
  if cur_explorer == nil then return end

  -- Invalidate all depths as not up to date
  cur_explorer.depth_valid = {}

  -- Close shown windows
  for i, win_id in pairs(cur_explorer.windows) do
    pcall(vim.api.nvim_win_close, win_id, true)
    cur_explorer.windows[i] = nil
  end

  -- Save to history at the root and remove from registry
  H.explorer_history[cur_explorer.branch[1]] = cur_explorer
  H.opened_explorers[vim.api.nvim_get_current_tabpage()] = nil
end

MiniFiles.synchronize = function()
  -- TODO
end

MiniFiles.go_right = function(buf_id, line)
  buf_id = H.validate_depth_buffer(buf_id)
  line = H.validate_line(buf_id, line)

  local cur_explorer = H.explorer_get()
  if cur_explorer == nil then return end

  local buf_depth = H.depth_buffer_get_depth(buf_id)
  if buf_depth == nil then return end

  local fs_entry = MiniFiles.get_fs_entry(buf_id, line)
  if fs_entry == nil then return nil end

  if fs_entry.fs_type == 'file' then
    -- Open file in target window
    H.explorer_open_file(cur_explorer, fs_entry.path)
  else
    -- Show child directory at next depth
    H.explorer_open_child_directory(cur_explorer, fs_entry.path, buf_depth + 1)
  end
end

MiniFiles.go_left = function(buf_id, line)
  buf_id = H.validate_depth_buffer(buf_id)
  line = H.validate_line(buf_id, line)

  local cur_explorer = H.explorer_get()
  if cur_explorer == nil then return end

  local buf_depth = H.depth_buffer_get_depth(buf_id)
  if buf_depth == nil then return end

  if buf_depth == 1 then
    H.explorer_open_root_parent(cur_explorer)
  else
    cur_explorer.depth_focus = buf_depth - 1
    H.explorer_refresh(cur_explorer, cur_explorer.opts)
  end
end

MiniFiles.get_fs_entry = function(buf_id, line)
  buf_id = H.validate_depth_buffer(buf_id)
  line = line or vim.fn.line('.')

  local path_id = H.depth_buffer_get_path_id(buf_id, line)
  if path_id == nil then return nil end

  local path = H.path_index[path_id]
  return { path = path, fs_type = H.fs_get_type(path), name = H.fs_get_basename(path) }
end

MiniFiles.default_filter = function(fs_entries)
  -- Nothing is filtered by default
  return fs_entries
end

MiniFiles.default_sort = function(fs_entries)
  -- Sort ignoring case
  local res = vim.tbl_map(
    function(x) return { name = x.name, fs_type = x.fs_type, lower_name = x.name:lower(), is_dir = x.fs_type == 'directory' } end,
    fs_entries
  )

  -- Sort based on default order
  table.sort(res, H.compare_fs_entries)

  return vim.tbl_map(function(x) return { name = x.name, fs_type = x.fs_type } end, res)
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniFiles.config

-- Namespaces
H.ns_id = {
  highlight = vim.api.nvim_create_namespace('MiniFilesHighlight'),
}

-- Index of all visited files
H.path_index = {}

-- History of explorers per root directory
H.explorer_history = {}

-- Registry of opened explorers per tabpage
H.opened_explorers = {}

-- Registry of depth buffers (to show content at branch depth) per tabpage
H.depth_buffers = {}

-- File system data
H.path_sep = package.config:sub(1, 1)
H.system_name = vim.loop.os_uname().sysname:lower()

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    content = { config.content, 'table' },
    mappings = { config.mappings, 'table' },
    windows = { config.windows, 'table' },
  })

  vim.validate({
    ['content.filter'] = { config.content.filter, 'function', true },
    ['content.sort'] = { config.content.sort, 'function', true },

    ['mappings.go_right'] = { config.mappings.go_right, 'string' },
    ['mappings.go_left'] = { config.mappings.go_right, 'string' },
    ['mappings.synchronize'] = { config.mappings.synchronize, 'string' },
    ['mappings.quit'] = { config.mappings.quit, 'string' },

    ['windows.border'] = { config.windows.border, 'string' },
    ['windows.width_focus'] = { config.windows.width_focus, 'number' },
    ['windows.width_nofocus'] = { config.windows.width_nofocus, 'number' },
  })

  return config
end

H.apply_config = function(config) MiniFiles.config = config end

--stylua: ignore
H.create_default_hl = function()
  local hi = function(name, opts)
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end

  hi('MiniFilesBorder',    { link = 'FloatBorder' })
  hi('MiniFilesDirectory', { link = 'Directory'   })
  hi('MiniFilesFile',      {})
  hi('MiniFilesNormal',    { link = 'NormalFloat' })
  hi('MiniFilesTitle',     { link = 'FloatTitle'  })
end

H.is_disabled = function() return vim.g.minifiles_disable == true or vim.b.minifiles_disable == true end

H.get_config =
  function(config) return vim.tbl_deep_extend('force', MiniFiles.config, vim.b.minifiles_config or {}, config or {}) end

H.get_opts = function(opts)
  opts = vim.tbl_deep_extend('force', H.get_config(), opts or {})
  opts.content.filter = opts.content.filter or MiniFiles.default_filter
  opts.content.sort = opts.content.sort or MiniFiles.default_sort

  return opts
end

-- Explorers ------------------------------------------------------------------
---@class Explorer
---
---@field branch table Array of absolute directory paths from parent to child.
---   Its ids are called depth.
---@field depth_focus number Depth to focus.
---@field depth_valid table Table valid depths which are already up to date (no
---   need to update buffer content). Depth as fields, `true` for valid depths.
---@field windows table Array of currently opened window ids (left to right).
---@field target_window number Id of window in which files will be opened.
---@field opts table Options used for this particular explorer.
---@private
H.explorer_new = function(branch, opts)
  return {
    branch = branch,
    depth_focus = 1,
    depth_valid = {},
    windows = {},
    target_window = vim.api.nvim_get_current_win(),
    opts = opts,
  }
end

H.explorer_get = function(tabpage_id)
  tabpage_id = tabpage_id or vim.api.nvim_get_current_tabpage()
  return H.opened_explorers[tabpage_id]
end

H.explorer_refresh = function(explorer, opts)
  explorer = H.explorer_normalize(explorer, opts)
  if #explorer.branch == 0 then return end

  local tabpage_id = vim.api.nvim_get_current_tabpage()
  local depth_valid, windows = explorer.depth_valid, explorer.windows

  local cur_pane_col, focus_win_id = 0, nil
  local depth_range = H.compute_visible_depth_range(explorer, opts)
  for depth = depth_range.from, depth_range.to do
    local dir_path = explorer.branch[depth]

    -- Prepare and possibly update buffer
    local buf_id = H.depth_buffer_get(tabpage_id, depth, opts.mappings)
    local buf_is_valid = depth_valid[depth]
    if not buf_is_valid then
      H.depth_buffer_update(buf_id, dir_path, opts.content)
      depth_valid[depth] = true
    end

    -- Create relevant window config
    local win_is_focused = depth == explorer.depth_focus
    local cur_width = win_is_focused and opts.windows.width_focus or opts.windows.width_nofocus
    local config = {
      col = cur_pane_col,
      height = vim.api.nvim_buf_line_count(buf_id),
      width = cur_width,
      title = cur_pane_col == 0 and dir_path or H.fs_get_basename(dir_path),
      border = opts.windows.border,
    }

    -- Prepare and register floating window
    local pane_id = depth - depth_range.from + 1
    local win_id = windows[pane_id] or H.window_open(buf_id, config)
    H.window_update(win_id, config)
    windows[pane_id] = win_id
    if win_is_focused then focus_win_id = win_id end

    -- Show buffer in window
    H.window_set_buf(win_id, buf_id)

    -- Add 2 to account for left and right borders
    cur_pane_col = cur_pane_col + cur_width + 2
  end

  -- Update explorer data
  explorer.depth_valid = depth_valid
  explorer.windows = windows

  -- Focus on proper window
  vim.api.nvim_set_current_win(focus_win_id)

  return explorer
end

H.explorer_normalize = function(explorer, opts)
  -- Ensure that all paths from branch are valid directory paths
  local norm_branch = {}
  for _, dir in ipairs(explorer.branch) do
    if vim.fn.isdirectory(dir) == 0 then break end
    table.insert(norm_branch, dir)
  end

  local cur_max_depth = #norm_branch

  explorer.branch = norm_branch
  explorer.depth_focus = math.min(explorer.depth_focus, cur_max_depth)
  explorer.opts = opts

  -- Invalidate unnecessary depths
  for depth, _ in pairs(explorer.depth_valid) do
    if cur_max_depth < depth then explorer.depth_valid[depth] = nil end
  end

  -- Close all unnecessary windows
  for i = cur_max_depth + 1, #explorer.windows do
    pcall(vim.api.nvim_win_close, explorer.windows[i], true)
    explorer.windows[i] = nil
  end

  return explorer
end

H.explorer_open_file = function(explorer, path)
  local target_window = explorer.target_window
  if not vim.api.nvim_win_is_valid(target_window) then target_window = H.get_first_valid_normal_window() end

  vim.api.nvim_win_call(target_window, function()
    local cmd = string.format('exec "edit %s"', path)
    vim.cmd(cmd)
  end)
end

H.explorer_open_child_directory = function(explorer, path, at_depth)
  -- Update focused depth
  explorer.depth_focus = at_depth

  -- Invalidate branch and buffer data if opening another path at target depth
  local path_is_shown_at_depth = path == explorer.branch[at_depth]
  if not path_is_shown_at_depth then
    -- Update branch data
    local branch = explorer.branch
    branch[at_depth] = path
    for i = at_depth + 1, #branch do
      branch[i] = nil
    end

    -- Invalidate outdated depths
    for depth, _ in pairs(explorer.depth_valid) do
      if at_depth <= depth then explorer.depth_valid[depth] = nil end
    end
  end

  -- Refresh
  H.explorer_refresh(explorer, explorer.opts)
end

H.explorer_open_root_parent = function(explorer)
  local path = H.fs_get_parent(explorer.branch[1])
  if path == nil then return end

  -- Update branch data
  table.insert(explorer.branch, 1, path)

  -- Update focused depth
  explorer.depth_focus = 1

  -- Shift up-to-date depths and buffers to make room for depth 1.
  -- This avoids unnecessary updates of already up to date depths
  local tabpage_id = vim.api.nvim_get_current_tabpage()

  local tabpage_buffers = H.depth_buffers[tabpage_id] or {}
  local new_depth = #explorer.branch

  local new_buf_id = H.depth_buffer_get(tabpage_id, new_depth, explorer.opts.mappings)
  table.remove(tabpage_buffers, new_depth)
  table.insert(tabpage_buffers, 1, new_buf_id)
  H.depth_buffers[tabpage_id] = tabpage_buffers

  local new_depth_valid = {}
  for depth, val in pairs(explorer.depth_valid) do
    new_depth_valid[depth + 1] = val
  end
  explorer.depth_valid = new_depth_valid

  -- Refresh
  H.explorer_refresh(explorer, explorer.opts)
end

H.compute_visible_depth_range = function(explorer, opts)
  -- Compute maximum number panes able to fit in current Neovim instance width
  -- Add 2 to widths to take into account width of left and right borders
  local width_focus, width_nofocus = opts.windows.width_focus + 2, opts.windows.width_nofocus + 2
  local max_n_panes = math.floor((vim.o.columns - width_focus) / width_nofocus)
  max_n_panes = math.max(max_n_panes, 0) + 1

  -- Compute which branch entries to show with the following idea:
  -- - Always show focused depth as centered as possible.
  -- - Show as much as possible.
  -- Logic is similar to how text for 'mini.tabline' is computed.
  local branch_depth, depth_focus = #explorer.branch, explorer.depth_focus
  local n_panes = math.min(branch_depth, max_n_panes)

  local to = math.min(branch_depth, math.floor(depth_focus + 0.5 * n_panes))
  local from = math.max(1, to - n_panes + 1)
  to = from + math.min(n_panes, branch_depth) - 1

  return { from = from, to = to }
end

-- Depth buffers --------------------------------------------------------------
H.depth_buffer_get = function(tabpage_id, depth, mappings)
  -- Try return an already created buffer
  local tabpage_buffers = H.depth_buffers[tabpage_id] or {}
  local res = tabpage_buffers[depth]
  if res ~= nil and vim.api.nvim_buf_is_valid(res) then return res end

  -- Create and register depth buffer
  res = vim.api.nvim_create_buf(false, true)
  tabpage_buffers[depth] = res
  H.depth_buffers[tabpage_id] = tabpage_buffers

  -- Set buffer options
  vim.bo[res].filetype = 'minifiles'

  -- Make buffer mappings
  --stylua: ignore start
  H.map('n', mappings.go_left,     MiniFiles.go_left,     { buffer = res, desc = 'Go left in file explorer' })
  H.map('n', mappings.go_right,    MiniFiles.go_right,    { buffer = res, desc = 'Go right in file explorer' })
  H.map('n', mappings.synchronize, MiniFiles.synchronize, { buffer = res, desc = 'Synchronize file explorer' })
  H.map('n', mappings.quit,        MiniFiles.close,       { buffer = res, desc = 'Close file explorer' })

  local go_right_visual = function()
    local line_1, line_2 = vim.fn.line('v'), vim.fn.line('.')
    -- Go to Normal mode. '\28\14' is an escaped version of `<C-\><C-n>`.
    vim.cmd('normal! \28\14')

    local from, to = math.min(line_1, line_2), math.max(line_1, line_2)
    for line=from, to do
      MiniFiles.go_right(res, line)
    end
  end
  H.map('x', mappings.go_right, go_right_visual, { buffer = res, desc = 'Go right in file explorer' })
  --stylua: ignore end

  -- Make buffer autocommands
  local augroup = vim.api.nvim_create_augroup('MiniFiles', { clear = false })
  local opts =
    { group = augroup, buffer = res, desc = 'Tweak cursor position', callback = H.depth_buffer_tweak_cursor_position }
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, opts)

  -- Tweak buffer to be used nicely with other 'mini.nvim' modules
  vim.b[res].minicursorword_disable = true

  return res
end

H.depth_buffer_update = function(buf_id, dir_path, content_opts)
  -- Compute and set lines
  local fs_entries = H.fs_read_dir(dir_path, content_opts)
  local get_icon_data = H.make_icon_getter()

  -- - Compute format expression resulting into same width path ids
  local path_width = math.floor(math.log10(#H.path_index)) + 1
  local line_format = '/%0' .. path_width .. 'd%s %s'

  local lines, icon_hl, name_hl = {}, {}, {}
  for _, entry in ipairs(fs_entries) do
    local icon, hl = get_icon_data(entry.name, entry.fs_type)
    table.insert(lines, string.format(line_format, H.path_index[entry.path], icon, entry.name))
    table.insert(icon_hl, hl)
    table.insert(name_hl, entry.fs_type == 'directory' and 'MiniFilesDirectory' or 'MiniFilesFile')
  end

  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)

  -- Add highlighting
  local ns_id = H.ns_id.highlight
  vim.api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)

  for l_num, l in ipairs(lines) do
    local icon_start, name_start = l:match('^/%d+()%S+ ()')
    H.set_extmark(buf_id, ns_id, l_num - 1, icon_start - 1, { hl_group = icon_hl[l_num], end_col = name_start - 1 })
    H.set_extmark(buf_id, ns_id, l_num - 1, name_start - 1, { hl_group = name_hl[l_num], end_row = l_num, end_col = 0 })
  end
end

H.depth_buffer_tweak_cursor_position = function(data)
  local cur_cursor = vim.api.nvim_win_get_cursor(0)
  local cur_offset = H.depth_buffer_get_offset(data.buf, cur_cursor[1])

  if (cur_offset - 1) <= cur_cursor[2] then return end

  vim.api.nvim_win_set_cursor(0, { cur_cursor[1], cur_offset - 1 })
  -- Make sure that icons are shown
  vim.cmd('normal! 1000zh')
end

H.depth_buffer_get_depth = function(buf_id)
  local tabpage_id = vim.api.nvim_get_current_tabpage()
  for depth, depth_buf_id in pairs(H.depth_buffers[tabpage_id]) do
    if buf_id == depth_buf_id then return depth end
  end
end

H.depth_buffer_get_offset = function(buf_id, line)
  local l = vim.api.nvim_buf_get_lines(buf_id, line - 1, line, false)[1]
  if l == nil then return nil end
  return l:match('^%S+ ()') or 0
end

H.depth_buffer_get_path_id = function(buf_id, line)
  local l = vim.api.nvim_buf_get_lines(buf_id, line - 1, line, false)[1]
  return H.match_line_path_id(l)
end

H.is_depth_buffer = function(buf_id)
  return type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id) and vim.bo[buf_id].filetype == 'minifiles'
end

H.match_line_path_id = function(l)
  if l == nil then return nil end

  local id_str = l:match('^/(%d+)')
  local ok, res = pcall(tonumber, id_str)
  if not ok then return nil end
  return res
end

H.make_icon_getter = function()
  local has_devicons, devicons = pcall(require, 'nvim-web-devicons')
  local get_file_icon = has_devicons and devicons.get_icon or function(...) end

  return function(name, fs_type)
    if fs_type == 'directory' then return '', 'MiniFilesDirectory' end
    local icon, hl = get_file_icon(name, nil, { default = false })
    return icon or '', hl or 'MiniFilesFile'
  end
end

-- Windows --------------------------------------------------------------------
H.window_open = function(buf_id, config)
  -- Add always the same extra data
  config.anchor = 'NW'
  config.focusable = true
  config.relative = 'editor'
  config.style = 'minimal'
  -- - Use 99 to allow built-in completion to be on top
  config.zindex = 99

  -- Add temporary data which will be updated later
  config.row = 1

  -- Open without entering
  local res = vim.api.nvim_open_win(buf_id, false, config)

  -- Set permanent window options
  vim.wo[res].conceallevel = 3
  vim.wo[res].concealcursor = 'nvic'
  vim.wo[res].wrap = false

  -- Conceal path id
  vim.api.nvim_win_call(res, function() vim.fn.matchadd('Conceal', [[^/\d\+]]) end)

  -- Set window highlights
  vim.wo[res].winhighlight = 'FloatBorder:MiniFilesBorder,FloatTitle:MiniFilesTitle,NormalFloat:MiniFilesNormal'

  return res
end

H.window_update = function(win_id, config)
  -- Compute helper data
  local has_tabline = vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)
  local has_statusline = vim.o.laststatus > 0
  -- Remove 2 from maximum hight to accout for top and bottom borders
  local max_height = vim.o.lines - vim.o.cmdheight - (has_tabline and 1 or 0) - (has_statusline and 1 or 0) - 2

  -- Ensure proper fit
  config.row = has_tabline and 1 or 0
  config.height = config.height ~= nil and math.min(config.height, max_height) or nil
  config.width = config.width ~= nil and math.min(config.width, vim.o.columns) or nil

  -- Ensure proper title on Neovim>=0.9 (as they are not supported earlier)
  if vim.fn.has('nvim-0.9') == 1 and config.title ~= nil then
    -- Show only tail if title is too long
    local title_string, width = config.title, config.width
    local title_chars = vim.fn.strcharlen(title_string)
    if width < title_chars then
      title_string = '…' .. vim.fn.strcharpart(title_string, title_chars - width + 1, width - 1)
    end
    config.title = title_string
  else
    config.title = nil
  end

  -- Update config
  config.relative = 'editor'
  vim.api.nvim_win_set_config(win_id, config)

  -- Make sure that 'cursorline' is not overriden by `config.style`
  vim.wo[win_id].cursorline = true
end

H.window_set_buf = function(win_id, buf_id, cursor_pos_data)
  -- Do nothing if buffer is already shown
  if vim.api.nvim_win_get_buf(win_id) == buf_id then return end

  -- Set buffer
  vim.api.nvim_win_set_buf(win_id, buf_id)

  -- Set 'cursorline' here also because changing buffer might have removed it
  vim.wo[win_id].cursorline = true
end

-- File system ----------------------------------------------------------------
-- TODO: Replace with `vim.fs` after Neovim=0.7 compatibility is dropped
H.fs_read_dir = function(dir_path, content_opts)
  local fs = vim.loop.fs_scandir(dir_path)
  local res = {}
  if not fs then return res end

  -- Read all entries
  local name, fs_type = vim.loop.fs_scandir_next(fs)
  while name do
    if not (fs_type == 'file' or fs_type == 'directory') then
      fs_type = H.fs_get_type(H.fs_child_path(dir_path, name))
    end
    table.insert(res, { name = name, fs_type = fs_type })
    name, fs_type = vim.loop.fs_scandir_next(fs)
  end

  -- Filter and sort entries
  res = content_opts.sort(content_opts.filter(res))

  -- Add absolute file paths to result and index
  for _, entry in ipairs(res) do
    local path = H.fs_child_path(dir_path, entry.name)
    entry.path = path
    H.add_path_to_index(path)
  end

  return res
end

H.add_path_to_index = function(path)
  if H.path_index[path] ~= nil then return end

  local new_id = #H.path_index + 1
  H.path_index[new_id] = path
  H.path_index[path] = new_id
end

H.compare_fs_entries = function(a, b)
  -- Put directory first
  if a.is_dir and not b.is_dir then return true end
  if not a.is_dir and b.is_dir then return false end

  -- Otherwise order alphabetically ignoring case
  return a.lower_name < b.lower_name
end

H.fs_child_path = function(dir, name)
  local res = string.format('%s%s%s', dir, H.path_sep, name):gsub(H.path_sep .. '+', H.path_sep)
  return res
end

H.fs_full_path = function(path)
  local res = vim.fn.fnamemodify(path, ':p'):gsub(H.path_sep .. '$', '')
  return res
end

H.fs_get_type = function(path)
  local ok, stat = pcall(vim.loop.fs_stat, path)
  if not ok or stat == nil then return nil end
  return vim.fn.isdirectory(path) == 1 and 'directory' or 'file'
end

H.fs_get_basename = function(path) return vim.fn.fnamemodify(path, ':t') end

H.fs_get_parent = function(path)
  local res = vim.fn.fnamemodify(path, ':h')
  if res == path then return nil end
  return res
end

-- TODO: Remove when not needed
H.create_test_dir = function(dir_path, n_dirs, n_files)
  vim.fn.mkdir(vim.fn.fnamemodify(dir_path, ':p'), 'p')

  -- Directories
  local possible_dir_basenames = { '.dir', '.Dir', 'dir', 'DIR', 'DiR', 'dIr' }
  local n_dir_basenames = #possible_dir_basenames
  for i = 1, n_dirs do
    local base_name = possible_dir_basenames[math.random(n_dir_basenames)] .. '_' .. string.format('%06d', i)
    vim.fn.mkdir(dir_path .. '/' .. base_name)
  end

  -- Files
  --stylua: ignore
  local possible_file_basenames = {
    '.dot', '.git', '.gitmodules', '.gitignore',
    'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j',
    'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't',
    'u', 'v', 'w', 'x', 'y', 'z',
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J',
    'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T',
    'U', 'V', 'W', 'X', 'Y', 'Z',
    '1', '2', '3', '4', '5', '6', '7', '8', '9', '0',
  }
  local n_file_basenames = #possible_file_basenames
  for i = 1, n_files do
    local base_name = possible_file_basenames[math.random(n_file_basenames)] .. '_' .. string.format('%06d', i)
    vim.fn.writefile({}, dir_path .. '/' .. base_name)
  end
end

-- Validators -----------------------------------------------------------------
H.validate_depth_buffer = function(x)
  if x == nil or x == 0 then x = vim.api.nvim_get_current_buf() end
  if not H.is_depth_buffer(x) then H.error('`buf_id` should be an identifier of a depth buffer.') end
  return x
end

H.validate_line = function(buf_id, x)
  x = x or vim.fn.line('.')
  if not (type(x) == 'number' and 1 <= x and x <= vim.api.nvim_buf_line_count(buf_id)) then
    H.error('`line` should be a valid line number in buffer ' .. buf_id .. '.')
  end
  return x
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.files) %s', msg), 0) end

H.map = function(mode, lhs, rhs, opts)
  if lhs == '' then return end
  opts = vim.tbl_deep_extend('force', { silent = true }, opts or {})
  vim.keymap.set(mode, lhs, rhs, opts)
end

H.set_extmark = function(...) pcall(vim.api.nvim_buf_set_extmark, ...) end

H.get_first_valid_normal_window = function()
  for _, win_id in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(win_id).relative == '' then return win_id end
  end
end

return MiniFiles
