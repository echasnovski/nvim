-- TODO:
--
-- Code:
-- - Implement MacOS Finder with column view type of file explorer:
--     - Think about proper handling of permissions:
--         - Explicitly check and throgh message prior every fs action (read?).
--         - Silently ignore (as is now).
--
--     - ?Make help window tracked from `explorer` object and not focusable?
--       And make it `toggle_help()` instead of `show_help`?
--
-- - Implement 'oil.nvim' like file manipulation:
--
-- - Make an effort to ensure proper work on Windows and MacOS:
--     - Windows and MacOS use case insensitive file names.
--
-- Tests:
--
-- Docs:
-- - Open multiple entries in Visual mode.
--
-- - Use `a/b/c.lua` to created nested tables at once.
--   Always use `/` on any OS.
--
-- - `User` events to hook into:
--     - `MiniFilesBufferCreate`
--     - `MiniFilesBufferUpdate`
--     - `MiniFilesWindowOpen`
--     - `MiniFilesWindowUpdate`
--
--     Examples: >
--     -- Modify buffer mappings
--     vim.api.nvim_create_autocmd('User', {
--       pattern = 'MiniFilesBufferCreate',
--       callback = function(args)
--         vim.keymap.set('n', lhs, rhs, { buffer = args.data.buf_id })
--       end,
--     })
--
--     -- Modify window config
--     vim.api.nvim_create_autocmd('User', {
--       pattern = 'MiniFilesWindowOpen',
--       callback = function(args)
--         local win_id = args.data.win_id
--         vim.wo[win_id].winblend = 50
--         vim.api.nvim_win_set_config(win_id, { border = 'double' })
--       end,
--     })

--- *mini.files* Explore and manipulate file system
--- *MiniFiles*
---
--- MIT License Copyright (c) 2023 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Features:
--- - Explore file system structure and open files using column view (Miller columns).
---
--- - Manipulate files by editing buffers: add, delete, rename, move.
---
--- - Use as default file explorer instead of |netrw|.
---
--- What it doesn't do:
--- - It does not try to be full file explorer.
---
--- - Built-in interactive toggle of `filter` and `sort`. See |MiniFiles-examples|.
---
--- Notes:
--- - This module is written and throughly tested on Linux. Support for other
---   platform/OS (like Windows or MacOS) is a goal, but there is no guarantee.
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
--- * `MiniFilesTitleFocused`
---
--- To change any highlight group, modify it directly with |:highlight|.
---
--- # Disabling ~
---
--- This plugin provides only manually started functionality, so no disabling
--- is available.

---@tag MiniFiles-exploration

---@tag MiniFiles-manipulation

--- ?Add some examples?
---
--- - How to set up different toggles: "show"/"don't show" dot files, sort
---   alphabetically without "directory first", etc.
---@tag MiniFiles-examples

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
MiniFiles.config = {
  content = {
    filter = nil,
    sort = nil,
  },

  mappings = {
    close       = 'q',
    go_in       = 'l',
    go_in_plus  = 'L',
    go_out      = 'h',
    go_out_plus = 'H',
    reset       = '<BS>',
    show_help   = 'g?',
    synchronize = '=',
    trim_left   = '<',
    trim_right  = '>',
  },

  options = {
    use_as_default_explorer = true,
  },

  windows = {
    max_number = math.huge,
    preview = false,
    width_focus = 50,
    width_nofocus = 15,
  },
}
--minidoc_afterlines_end

--- Open file explorer
---
--- Recommended usage:
--- - `MiniFiles.open()` - open current working directory in a latest state.
--- - `MiniFiles.open(nil, false)` - fresh explorer in current working directory.
--- - `MiniFiles.open(vim.api.nvim_buf_get_name(0))` - open directory of current
---    file (in a latest state) with focus on that file.
--- - `MiniFiles.open(vim.api.nvim_buf_get_name(0), false)` - fresh explorer in
---    directory of current file.
--- - `MiniFiles.open(MiniFiles.get_latest_path())` - open last used `path`
---   (per tabpage). Current working directory for the first time.
MiniFiles.open = function(path, use_latest, opts)
  -- Validate path: allow only valid file system path
  path = H.fs_full_path(path or vim.fn.getcwd())

  local fs_type = H.fs_get_type(path)
  if fs_type == nil then H.error('`path` is not a valid path ("' .. path .. '")') end

  -- - Allow file path to use its parent while focusing on file
  local entry_name
  if fs_type == 'file' then
    path, entry_name = H.fs_get_parent(path), H.fs_get_basename(path)
  end

  -- Validate rest of the arguments
  if use_latest == nil then use_latest = true end

  -- Properly close possibly opened in the tabpage explorer
  local did_close = MiniFiles.close()
  if did_close == false then return end

  -- Get explorer to open
  local explorer
  if use_latest then explorer = H.explorer_path_history[path] end
  explorer = explorer or H.explorer_new(path)

  -- Update explorer data. Don't use current explorer's data to allow more
  -- interactive config change by modifying global/local configs.
  explorer.opts = H.normalize_opts(nil, opts)
  explorer.target_window = vim.api.nvim_get_current_win()

  -- Possibly focus on file entry
  explorer = H.explorer_focus_on_entry(explorer, path, entry_name)

  -- Refresh and register as opened
  H.explorer_refresh(explorer)
end

MiniFiles.refresh = function(opts)
  local explorer = H.explorer_get()
  if explorer == nil then return end

  -- Decide whether buffers should be forcefully updated
  local content_opts = (opts or {}).content or {}
  local force_update = content_opts.filter ~= nil or content_opts.sort ~= nil

  -- Respect explorer local options supplied inside its `open()` call but give
  -- current `opts` higher precedence
  explorer.opts = H.normalize_opts(explorer.opts, opts)

  H.explorer_refresh(explorer, force_update)
end

MiniFiles.synchronize = function()
  local explorer = H.explorer_get()
  if explorer == nil then return end

  -- Parse and apply file system operations
  local fs_actions = H.explorer_compute_fs_actions(explorer)
  if fs_actions ~= nil and H.fs_actions_confirm(fs_actions) then H.fs_actions_apply(fs_actions) end

  H.explorer_refresh(explorer, true)
end

MiniFiles.reset = function()
  local explorer = H.explorer_get()
  if explorer == nil then return end

  -- Reset branch
  explorer.branch = { explorer.anchor }
  explorer.depth_focus = 1

  -- Reset directory views
  for _, dir_view in pairs(explorer.dir_views) do
    dir_view.cursor = { 1, 0 }
  end

  H.explorer_refresh(explorer)
end

---@return boolean|nil Whether closing was successful. `nil` if there was
---   nothing to close.
MiniFiles.close = function()
  local explorer = H.explorer_get()
  if explorer == nil then return nil end

  -- Confirm close if there is modified buffer
  local has_modified_buffer = H.explorer_has_modified_buffer(explorer)
  if has_modified_buffer then
    local msg = 'There is at least one modified buffer\n\nConfirm close without synchronization?'
    local confirm_res = vim.fn.confirm(msg, '&Yes\n&No', 1, 'Question')
    if confirm_res ~= 1 then return false end
  end

  -- Update currently shown cursors
  explorer = H.explorer_update_cursors(explorer)

  -- Close shown windows
  for i, win_id in pairs(explorer.windows) do
    H.window_close(win_id)
    explorer.windows[i] = nil
  end

  -- Invalidate directory views
  for dir_path, dir_view in pairs(explorer.dir_views) do
    explorer.dir_views[dir_path] = H.dir_view_invalidate_buffer(H.dir_view_encode_cursor(dir_view))
  end

  -- Update histories and unmark as opened
  local tabpage_id, anchor = vim.api.nvim_get_current_tabpage(), explorer.anchor
  H.explorer_path_history[anchor] = explorer
  H.opened_explorers[tabpage_id] = nil
  H.latest_paths[tabpage_id] = anchor

  -- Return `true` indicating success in closing
  return true
end

MiniFiles.go_in = function()
  local explorer = H.explorer_get()
  if explorer == nil then return end

  local cur_line = vim.fn.line('.')
  explorer = H.explorer_go_in_range(explorer, vim.api.nvim_get_current_buf(), cur_line, cur_line)

  H.explorer_refresh(explorer)
end

MiniFiles.go_out = function(buf_id, line)
  local explorer = H.explorer_get()
  if explorer == nil then return end

  if explorer.depth_focus == 1 then
    explorer = H.explorer_open_root_parent(explorer)
  else
    explorer.depth_focus = explorer.depth_focus - 1
  end

  H.explorer_refresh(explorer)
end

MiniFiles.trim_left = function()
  local explorer = H.explorer_get()
  if explorer == nil then return end

  explorer = H.explorer_trim_branch_left(explorer)
  H.explorer_refresh(explorer)
end

MiniFiles.trim_right = function()
  local explorer = H.explorer_get()
  if explorer == nil then return end

  explorer = H.explorer_trim_branch_right(explorer)
  H.explorer_refresh(explorer)
end

MiniFiles.show_help = function()
  local explorer = H.explorer_get()
  if explorer == nil then return end

  local buf_id = vim.api.nvim_get_current_buf()
  if not H.is_opened_buffer(buf_id) then return end

  H.explorer_show_help(buf_id, vim.api.nvim_get_current_win())
end

MiniFiles.get_fs_entry = function(buf_id, line)
  buf_id = H.validate_opened_buffer(buf_id)
  line = H.validate_line(buf_id, line)

  local path_id = H.match_line_path_id(H.get_bufline(buf_id, line))
  if path_id == nil then return nil end

  local path = H.path_index[path_id]
  return { path = path, fs_type = H.fs_get_type(path), name = H.fs_get_basename(path) }
end

MiniFiles.get_latest_path = function() return H.latest_paths[vim.api.nvim_get_current_tabpage()] end

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
H.explorer_path_history = {}

-- Register of opened explorers per tabpage
H.opened_explorers = {}

-- Register of latest used paths per tabpage
H.latest_paths = {}

-- Register of opened buffer data for quick access. Tables per buffer id:
-- - <dir_path> - path of directory which contents this buffer displays.
-- - <win_id> - id of window this buffer is shown. Can be `nil`.
-- - <n_modified> - number of modifications since last update from this module.
--   Values bigger than 0 can be treated as if buffer was modified by user.
--   It uses number instead of boolean is to overcome `TextChanged` event on
--   initial `buf_set_lines` (`noautocmd` doesn't quick work for this event).
H.opened_buffers = {}

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
    options = { config.options, 'table' },
    windows = { config.windows, 'table' },
  })

  vim.validate({
    ['content.filter'] = { config.content.filter, 'function', true },
    ['content.sort'] = { config.content.sort, 'function', true },

    ['mappings.close'] = { config.mappings.close, 'string' },
    ['mappings.go_in'] = { config.mappings.go_in, 'string' },
    ['mappings.go_in_plus'] = { config.mappings.go_in_plus, 'string' },
    ['mappings.go_out'] = { config.mappings.go_out, 'string' },
    ['mappings.go_out_plus'] = { config.mappings.go_out_plus, 'string' },
    ['mappings.reset'] = { config.mappings.reset, 'string' },
    ['mappings.show_help'] = { config.mappings.show_help, 'string' },
    ['mappings.synchronize'] = { config.mappings.synchronize, 'string' },
    ['mappings.trim_left'] = { config.mappings.trim_left, 'string' },
    ['mappings.trim_right'] = { config.mappings.trim_right, 'string' },

    ['options.use_as_default_explorer'] = { config.options.use_as_default_explorer, 'boolean' },

    ['windows.max_number'] = { config.windows.max_number, 'number' },
    ['windows.preview'] = { config.windows.preview, 'boolean' },
    ['windows.width_focus'] = { config.windows.width_focus, 'number' },
    ['windows.width_nofocus'] = { config.windows.width_nofocus, 'number' },
  })

  return config
end

H.apply_config = function(config) MiniFiles.config = config end

H.create_autocommands = function(config)
  local augroup = vim.api.nvim_create_augroup('MiniFiles', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = augroup, pattern = pattern, callback = callback, desc = desc })
  end

  au('VimResized', '*', MiniFiles.refresh, 'Refresh on resize')

  if config.options.use_as_default_explorer then
    -- Stop 'netrw' from showing. Needs `VimEnter` event autocommand if
    -- this is called prior 'netrw' is set up
    vim.cmd('silent! autocmd! FileExplorer *')
    vim.cmd('autocmd VimEnter * ++once silent! autocmd! FileExplorer *')

    au('BufEnter', '*', H.track_dir_edit, 'Track directory edit')
  end
end

--stylua: ignore
H.create_default_hl = function()
  local hi = function(name, opts)
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end

  hi('MiniFilesBorder',         { link = 'FloatBorder' })
  hi('MiniFilesBorderModified', { link = 'DiagnosticFloatingWarn' })
  hi('MiniFilesDirectory',      { link = 'Directory'   })
  hi('MiniFilesFile',           {})
  hi('MiniFilesNormal',         { link = 'NormalFloat' })
  hi('MiniFilesTitle',          { link = 'FloatTitle'  })
  hi('MiniFilesTitleFocused',   { link = 'FloatTitle' })
end

H.get_config =
  function(config) return vim.tbl_deep_extend('force', MiniFiles.config, vim.b.minifiles_config or {}, config or {}) end

H.normalize_opts = function(explorer_opts, opts)
  opts = vim.tbl_deep_extend('force', H.get_config(), explorer_opts or {}, opts or {})
  opts.content.filter = opts.content.filter or MiniFiles.default_filter
  opts.content.sort = opts.content.sort or MiniFiles.default_sort

  return opts
end

-- Autocommands ---------------------------------------------------------------
H.track_dir_edit = function(data)
  local buf_id = data.buf

  -- Make early returns
  if vim.b[buf_id].minifiles_processed_dir then
    vim.api.nvim_buf_delete(buf_id, { force = true })
    return
  end

  if vim.api.nvim_get_current_buf() ~= buf_id then return end

  local path = vim.api.nvim_buf_get_name(buf_id)
  if vim.fn.isdirectory(path) ~= 1 then return end

  -- Make directory buffer disappear when it is not needed
  vim.bo[buf_id].bufhidden = 'wipe'
  vim.b[buf_id].minifiles_processed_dir = true

  -- Open directory without history
  vim.schedule(function() MiniFiles.open(path, false) end)
end

-- Explorers ------------------------------------------------------------------
---@class Explorer
---
---@field branch table Array of absolute directory paths from parent to child.
---   Its ids are called depth.
---@field depth_focus number Depth to focus.
---@field dir_views table Views of directory paths. Each view is a table with:
---   - <buf_id> where to show directory content.
---   - <cursor> to position cursor; can be:
---       - `{ line, col }` table to set cursor when buffer changes window.
---       - `entry_name` string entry name to find inside directory buffer.
---   - <children_path_ids> - array with children path ids present during
---     latest directory update.
---@field windows table Array of currently opened window ids (left to right).
---@field anchor string Anchor directory of the explorer. Used as index in
---   history and for `reset()` operation.
---@field target_window number Id of window in which files will be opened.
---@field opts table Options used for this particular explorer.
---@private
H.explorer_new = function(path)
  return {
    branch = { path },
    depth_focus = 1,
    dir_views = {},
    windows = {},
    anchor = path,
    target_window = vim.api.nvim_get_current_win(),
    opts = {},
  }
end

H.explorer_get = function(tabpage_id)
  tabpage_id = tabpage_id or vim.api.nvim_get_current_tabpage()
  local res = H.opened_explorers[tabpage_id]

  if H.explorer_is_visible(res) then return res end

  H.opened_explorers[tabpage_id] = nil
  return nil
end

H.explorer_is_visible = function(explorer)
  if explorer == nil then return nil end
  for _, win_id in ipairs(explorer.windows) do
    if H.is_valid_win(win_id) then return true end
  end
  return false
end

H.explorer_refresh = function(explorer, force_update)
  explorer = H.explorer_normalize(explorer)
  if #explorer.branch == 0 then return end
  if force_update == nil then force_update = false end

  -- Update cursor data in shown directory views
  explorer = H.explorer_update_cursors(explorer)

  -- Possibly force content updates on all explorer buffers. Doing it for *all*
  -- of them and not only on modified once to allow synch outside changes.
  if force_update then
    for dir_path, dir_view in pairs(explorer.dir_views) do
      -- Encode cursors to allow them to "stick" to current entry
      dir_view = H.dir_view_encode_cursor(dir_view)
      dir_view.children_path_ids = H.buffer_update(dir_view.buf_id, dir_path, explorer.opts)
      explorer.dir_views[dir_path] = dir_view
    end
  end

  -- Compute depth range which is possible to show in current window
  local depth_range = H.compute_visible_depth_range(explorer, explorer.opts)

  -- Refresh window for every target depth keeping track of position column
  local cur_win_col, cur_win_count = 0, 0
  for depth = depth_range.from, depth_range.to do
    cur_win_count = cur_win_count + 1
    local cur_width = H.explorer_refresh_depth_window(explorer, depth, cur_win_count, cur_win_col)

    -- Add 2 to account for left and right borders
    cur_win_col = cur_win_col + cur_width + 2
  end

  -- Close possibly opened window that don't fit (like after `VimResized`)
  for depth = cur_win_count + 1, #explorer.windows do
    H.window_close(explorer.windows[depth])
    explorer.windows[depth] = nil
  end

  -- Focus on proper window
  local win_focus_count = explorer.depth_focus - depth_range.from + 1
  local win_id_focused = explorer.windows[win_focus_count]
  H.window_focus(win_id_focused)

  -- Register as currently opened
  local tabpage_id = vim.api.nvim_win_get_tabpage(win_id_focused)
  H.opened_explorers[tabpage_id] = explorer

  return explorer
end

H.explorer_normalize = function(explorer)
  -- Ensure that all paths from branch are valid directory paths
  local norm_branch = {}
  for _, dir in ipairs(explorer.branch) do
    if vim.fn.isdirectory(dir) == 0 then break end
    table.insert(norm_branch, dir)
  end

  local cur_max_depth = #norm_branch

  explorer.branch = norm_branch
  explorer.depth_focus = math.min(math.max(explorer.depth_focus, 1), cur_max_depth)

  -- Close all unnecessary windows
  for i = cur_max_depth + 1, #explorer.windows do
    H.window_close(explorer.windows[i])
    explorer.windows[i] = nil
  end

  return explorer
end

H.explorer_go_in_range = function(explorer, buf_id, from_line, to_line)
  -- Compute which entries to go in: all files and only last directory
  local files, dir_path, dir_line = {}, nil, nil
  for i = from_line, to_line do
    local fs_entry = MiniFiles.get_fs_entry(buf_id, i) or {}
    if fs_entry.fs_type == 'file' then table.insert(files, fs_entry.path) end
    if fs_entry.fs_type == 'directory' then
      dir_path, dir_line = fs_entry.path, i
    end
  end

  for _, file_path in ipairs(files) do
    explorer = H.explorer_open_file(explorer, file_path)
  end

  if dir_path ~= nil then
    explorer = H.explorer_open_directory(explorer, dir_path, explorer.depth_focus + 1)

    -- Ensure that cursor points to the directory in current window (can be not
    -- the case if cursor is not on the actually opened directory)
    local win_id = H.opened_buffers[buf_id].win_id
    if H.is_valid_win(win_id) then vim.api.nvim_win_set_cursor(win_id, { dir_line, 0 }) end
  end

  return explorer
end

H.explorer_focus_on_entry = function(explorer, dir_path, entry_name)
  if entry_name == nil then return explorer end

  -- Set focus on directory. Reset if it is not in current branch.
  explorer.depth_focus = H.explorer_get_path_depth(explorer, dir_path)
  if explorer.depth_focus == nil then
    explorer.branch, explorer.depth_focus = { dir_path }, 1
  end

  -- Set cursor on entry
  local path_dir_view = explorer.dir_views[dir_path] or {}
  path_dir_view.cursor = entry_name
  explorer.dir_views[dir_path] = path_dir_view

  return explorer
end

H.explorer_compute_fs_actions = function(explorer)
  -- Compute differences
  local fs_diffs = {}
  for dir_path, dir_view in pairs(explorer.dir_views) do
    local dir_fs_diff = H.buffer_compute_fs_diff(dir_view.buf_id, dir_view.children_path_ids)
    if #dir_fs_diff > 0 then vim.list_extend(fs_diffs, dir_fs_diff) end
  end
  if #fs_diffs == 0 then return nil end

  -- Convert differences into actions
  local create, delete_map, rename, move, raw_copy = {}, {}, {}, {}, {}

  -- - Differentiate between create, delete, and copy
  for _, diff in ipairs(fs_diffs) do
    if diff.from == nil then
      table.insert(create, diff.to)
    elseif diff.to == nil then
      delete_map[diff.from] = true
    else
      table.insert(raw_copy, diff)
    end
  end

  -- - Possibly narrow down copy action into move or rename:
  --   `delete + copy` is `rename` if in same directory and `move` otherwise
  local copy = {}
  for _, diff in pairs(raw_copy) do
    if delete_map[diff.from] then
      if H.fs_get_parent(diff.from) == H.fs_get_parent(diff.to) then
        table.insert(rename, diff)
      else
        table.insert(move, diff)
      end

      -- NOTE: Can't use `delete` as array here in order for path to be moved
      -- or rename only single time
      delete_map[diff.from] = nil
    else
      table.insert(copy, diff)
    end
  end

  return { create = create, delete = vim.tbl_keys(delete_map), copy = copy, rename = rename, move = move }
end

H.explorer_update_cursors = function(explorer)
  for _, win_id in ipairs(explorer.windows) do
    if H.is_valid_win(win_id) then
      local buf_id = vim.api.nvim_win_get_buf(win_id)
      local dir_path = H.opened_buffers[buf_id].dir_path
      explorer.dir_views[dir_path].cursor = vim.api.nvim_win_get_cursor(win_id)
    end
  end

  return explorer
end

H.explorer_refresh_depth_window = function(explorer, depth, win_count, win_col)
  local dir_path = explorer.branch[depth]
  local dir_views, windows, opts = explorer.dir_views, explorer.windows, explorer.opts

  -- Prepare directory view
  local dir_view = dir_views[dir_path] or {}
  dir_view = H.dir_view_ensure_proper(dir_view, dir_path, opts)
  dir_views[dir_path] = dir_view

  -- Create relevant window config
  local win_is_focused = depth == explorer.depth_focus
  local cur_width = win_is_focused and opts.windows.width_focus or opts.windows.width_nofocus
  local config = {
    col = win_col,
    height = vim.api.nvim_buf_line_count(dir_view.buf_id),
    width = cur_width,
    -- Use shortened full path in left most window
    title = win_count == 1 and H.fs_shorten_path(H.fs_full_path(dir_path)) or H.fs_get_basename(dir_path),
  }

  -- Prepare and register window
  local win_id = windows[win_count]
  if not H.is_valid_win(win_id) then
    H.window_close(win_id)
    win_id = H.window_open(dir_view.buf_id, config)
    windows[win_count] = win_id
  end

  H.window_update(win_id, config)

  -- Show directory view in window
  H.window_set_dir_view(win_id, dir_view)

  -- Update explorer data
  explorer.dir_views = dir_views
  explorer.windows = windows

  -- Return width of current window to keep track of window column
  return cur_width
end

H.explorer_get_path_depth = function(explorer, path)
  for depth, depth_path in pairs(explorer.branch) do
    if path == depth_path then return depth end
  end
end

H.explorer_get_buffer_depth =
  function(explorer, buf_id) return H.explorer_get_path_depth(explorer, H.opened_buffers[buf_id].dir_path) end

H.explorer_has_modified_buffer = function(explorer)
  for _, dir_view in pairs(explorer.dir_views) do
    if H.is_modified_buffer(dir_view.buf_id) then return true end
  end
  return false
end

H.explorer_open_file = function(explorer, path)
  if not vim.api.nvim_win_is_valid(explorer.target_window) then
    explorer.target_window = H.get_first_valid_normal_window()
  end

  -- Try to use already created buffer, if present. This avoids not needed
  -- `:edit` call and avoids some problems with auto-root from 'mini.misc'.
  local path_buf_id
  for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
    if H.is_valid_buf(buf_id) and vim.api.nvim_buf_get_name(buf_id) == path then path_buf_id = buf_id end
  end

  if path_buf_id ~= nil then
    vim.api.nvim_win_set_buf(explorer.target_window, path_buf_id)
  else
    vim.fn.win_execute(explorer.target_window, 'edit ' .. vim.fn.fnameescape(path))
  end

  return explorer
end

H.explorer_open_directory = function(explorer, path, target_depth)
  -- Update focused depth
  explorer.depth_focus = target_depth

  -- Truncate rest of the branch if opening another path at target depth
  local show_new_path_at_depth = path ~= explorer.branch[target_depth]
  if show_new_path_at_depth then
    explorer.branch[target_depth] = path
    explorer = H.explorer_trim_branch_right(explorer)
  end

  return explorer
end

H.explorer_open_root_parent = function(explorer)
  local root = explorer.branch[1]
  local root_parent = H.fs_get_parent(root)
  if root_parent == nil then return explorer end

  -- Update branch data
  table.insert(explorer.branch, 1, root_parent)

  -- Focus on previous root entry in its parent
  return H.explorer_focus_on_entry(explorer, root_parent, H.fs_get_basename(root))
end

H.explorer_trim_branch_right = function(explorer)
  for i = explorer.depth_focus + 1, #explorer.branch do
    explorer.branch[i] = nil
  end
  return explorer
end

H.explorer_trim_branch_left = function(explorer)
  local new_branch = {}
  for i = explorer.depth_focus, #explorer.branch do
    table.insert(new_branch, explorer.branch[i])
  end
  explorer.branch = new_branch
  explorer.depth_focus = 1
  return explorer
end

H.explorer_show_help = function(explorer_buf_id, explorer_win_id)
  -- Compute lines
  local buf_mappings = vim.api.nvim_buf_get_keymap(explorer_buf_id, 'n')
  local map_data, desc_width = {}, 0
  for _, data in ipairs(buf_mappings) do
    map_data[data.desc] = data.lhs:lower() == '<lt>' and '<' or data.lhs
    desc_width = math.max(desc_width, data.desc:len())
  end

  local desc_arr = vim.tbl_keys(map_data)
  table.sort(desc_arr)
  local map_format = string.format('%%-%ds │ %%s', desc_width)

  local lines = { 'Buffer mappings:', '' }
  for _, desc in ipairs(desc_arr) do
    table.insert(lines, string.format(map_format, desc, map_data[desc]))
  end
  table.insert(lines, '')
  table.insert(lines, '(Press `q` to close)')

  -- Create buffer
  local buf_id = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)

  vim.keymap.set('n', 'q', '<Cmd>close<CR>', { buffer = buf_id, desc = 'Close this window' })

  vim.b[buf_id].minicursorword_disable = true
  vim.b[buf_id].miniindentscope_disable = true

  -- Compute window data
  local line_widths = vim.tbl_map(vim.fn.strdisplaywidth, lines)
  local max_line_width = math.max(unpack(line_widths))

  local config = vim.api.nvim_win_get_config(explorer_win_id)
  config.relative = 'win'
  config.row = 0
  config.col = 0
  config.width = max_line_width
  config.height = #lines
  config.title = vim.fn.has('nvim-0.9') == 1 and [['mini.files' help]] or nil
  config.zindex = config.zindex + 1
  config.style = 'minimal'

  -- Open window
  local win_id = vim.api.nvim_open_win(buf_id, false, config)
  H.window_update_highlight(win_id, 'NormalFloat', 'MiniFilesNormal')
  H.window_update_highlight(win_id, 'FloatTitle', 'MiniFilesTitle')
  vim.wo[win_id].cursorline = true

  vim.api.nvim_set_current_win(win_id)
  return win_id
end

H.compute_visible_depth_range = function(explorer, opts)
  -- Compute maximum number of windows possible to fit in current Neovim width
  -- Add 2 to widths to take into account width of left and right borders
  local width_focus, width_nofocus = opts.windows.width_focus + 2, opts.windows.width_nofocus + 2
  local max_number = math.floor((vim.o.columns - width_focus) / width_nofocus)
  max_number = math.max(max_number, 0) + 1
  -- - Account for dedicated option
  max_number = math.min(math.max(max_number, 1), opts.windows.max_number)

  -- Compute which branch entries to show with the following idea:
  -- - Always show focused depth as centered as possible.
  -- - Show as much as possible.
  -- Logic is similar to how text for 'mini.tabline' is computed.
  local branch_depth, depth_focus = #explorer.branch, explorer.depth_focus
  local n_panes = math.min(branch_depth, max_number)

  local to = math.min(branch_depth, math.floor(depth_focus + 0.5 * n_panes))
  local from = math.max(1, to - n_panes + 1)
  to = from + math.min(n_panes, branch_depth) - 1

  return { from = from, to = to }
end

-- Directory views ------------------------------------------------------------
H.dir_view_ensure_proper = function(dir_view, dir_path, opts)
  -- Ensure proper buffer
  if not H.is_valid_buf(dir_view.buf_id) then
    H.buffer_delete(dir_view.buf_id)
    dir_view.buf_id = H.buffer_create(dir_path, opts.mappings)
    dir_view.children_path_ids = H.buffer_update(dir_view.buf_id, dir_path, opts)
  end

  -- Ensure proper cursor. If string, find it as line in current buffer.
  dir_view.cursor = dir_view.cursor or { 1, 0 }
  if type(dir_view.cursor) == 'string' then dir_view = H.dir_view_decode_cursor(dir_view) end

  return dir_view
end

H.dir_view_encode_cursor = function(dir_view)
  local buf_id, cursor = dir_view.buf_id, dir_view.cursor
  if not H.is_valid_buf(buf_id) or type(cursor) ~= 'table' then return dir_view end

  -- Replace exact cursor coordinates with entry name to try and find later.
  -- This allows more robust opening explorer from history (as directory
  -- content may have changed and exact cursor position would be not valid).
  local l = H.get_bufline(buf_id, cursor[1])
  dir_view.cursor = H.match_line_entry_name(l)
  return dir_view
end

H.dir_view_decode_cursor = function(dir_view)
  local buf_id, cursor = dir_view.buf_id, dir_view.cursor
  if not H.is_valid_buf(buf_id) or type(cursor) ~= 'string' then return dir_view end

  -- Find entry name named as stored in `cursor`. If not - use {1, 0}.
  local lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
  for i, l in ipairs(lines) do
    if cursor == H.match_line_entry_name(l) then dir_view.cursor = { i, 0 } end
  end

  if type(dir_view.cursor) ~= 'table' then dir_view.cursor = { 1, 0 } end

  return dir_view
end

H.dir_view_invalidate_buffer = function(dir_view)
  H.buffer_delete(dir_view.buf_id)
  dir_view.buf_id = nil
  dir_view.children_path_ids = nil
  return dir_view
end

H.dir_view_track_cursor = vim.schedule_wrap(function(data)
  -- Schedule this in order to react *after* all pending changes are applied
  local buf_id = data.buf
  local buf_data = H.opened_buffers[buf_id]
  if buf_data == nil then return end

  local win_id = buf_data.win_id
  if not H.is_valid_win(win_id) then return end

  -- Ensure cursor doesn't go over path id and icon
  local cur_cursor = vim.api.nvim_win_get_cursor(win_id)
  local l = H.get_bufline(buf_id, cur_cursor[1])

  local cur_offset = H.match_line_offset(l)
  if cur_cursor[2] < (cur_offset - 1) then
    vim.api.nvim_win_set_cursor(win_id, { cur_cursor[1], cur_offset - 1 })
    -- Ensure icons are shown (may be not the case after horizontal scroll)
    vim.cmd('normal! 1000zh')
  end

  -- Ensure cursor line doesn't contradict window on the right
  local tabpage_id = vim.api.nvim_win_get_tabpage(win_id)
  local explorer = H.explorer_get(tabpage_id)
  if explorer == nil then return end

  local buf_depth = H.explorer_get_path_depth(explorer, buf_data.dir_path)
  if buf_depth == nil then return end

  local path_to_right = explorer.branch[buf_depth + 1]
  local cursor_path = H.path_index[H.match_line_path_id(l)]

  if cursor_path == path_to_right then return end

  -- - Truncate branch if cursor path is not aligned with what is to the right
  explorer = H.explorer_trim_branch_right(explorer)

  -- - Show preview if needed
  if explorer.opts.windows.preview and vim.fn.isdirectory(cursor_path) == 1 then
    table.insert(explorer.branch, cursor_path)
  end

  H.explorer_refresh(explorer)
end)

H.dir_view_track_text_change = function(data)
  -- Track 'modified'
  local buf_id = data.buf
  local new_n_modified = H.opened_buffers[buf_id].n_modified + 1
  H.opened_buffers[buf_id].n_modified = new_n_modified
  local win_id = H.opened_buffers[buf_id].win_id
  if new_n_modified > 0 and H.is_valid_win(win_id) then H.window_update_border_hl(win_id) end

  -- Track window height
  if not H.is_valid_win(win_id) then return end

  local n_lines = vim.api.nvim_buf_line_count(buf_id)
  local height = math.min(n_lines, H.window_get_max_height())
  vim.api.nvim_win_set_height(win_id, height)

  -- Ensure that only buffer lines are shown. This can be not the case if after
  -- text edit cursor moved past previous last line.
  local last_visible_line = vim.fn.line('w0', win_id) + height - 1
  local out_of_buf_lines = last_visible_line - n_lines
  -- - Possibly scroll window upward (`\25` is an escaped `<C-y>`)
  if out_of_buf_lines > 0 then vim.cmd('normal! ' .. out_of_buf_lines .. '\25') end
end

-- Buffers --------------------------------------------------------------------
H.buffer_create = function(dir_path, mappings)
  -- Create buffer
  local buf_id = vim.api.nvim_create_buf(false, true)

  -- Register buffer
  H.opened_buffers[buf_id] = { dir_path = dir_path }

  -- Make buffer mappings
  H.buffer_make_mappings(buf_id, mappings)

  -- Make buffer autocommands
  local augroup = vim.api.nvim_create_augroup('MiniFiles', { clear = false })
  local au = function(events, desc, callback)
    vim.api.nvim_create_autocmd(events, { group = augroup, buffer = buf_id, desc = desc, callback = callback })
  end

  au({ 'CursorMoved', 'CursorMovedI' }, 'Tweak cursor position', H.dir_view_track_cursor)
  au({ 'TextChanged', 'TextChangedI', 'TextChangedP' }, 'Track buffer modification', H.dir_view_track_text_change)

  -- Tweak buffer to be used nicely with other 'mini.nvim' modules
  vim.b[buf_id].minicursorword_disable = true

  -- Set buffer options
  vim.bo[buf_id].filetype = 'minifiles'

  -- Trigger dedicated event
  H.trigger_event('MiniFilesBufferCreate', { buf_id = buf_id })

  return buf_id
end

H.buffer_make_mappings = function(buf_id, mappings)
  local go_out_plus = function()
    MiniFiles.go_out()
    MiniFiles.trim_right()
  end

  local go_in_plus = function()
    local fs_entry = MiniFiles.get_fs_entry()
    local is_at_file = fs_entry ~= nil and fs_entry.fs_type == 'file'
    MiniFiles.go_in()
    if is_at_file then MiniFiles.close() end
  end

  local go_in_visual = function()
    -- React only on linewise mode, as others can be used for editing
    if vim.fn.mode() ~= 'V' then return mappings.go_in end

    -- Schedule actions because they are not allowed inside expression mapping
    vim.schedule(function()
      local line_1, line_2 = vim.fn.line('v'), vim.fn.line('.')
      local explorer = H.explorer_get()
      local from_line, to_line = math.min(line_1, line_2), math.max(line_1, line_2)
      explorer = H.explorer_go_in_range(explorer, buf_id, from_line, to_line)
      H.explorer_refresh(explorer)
    end)

    -- Go to Normal mode. '\28\14' is an escaped version of `<C-\><C-n>`.
    return [[<C-\><C-n>]]
  end

  local buf_map = function(mode, lhs, rhs, desc)
    -- Use `nowait` to account for non-buffer mappings starting with `lhs`
    H.map(mode, lhs, rhs, { buffer = buf_id, desc = desc, nowait = true })
  end

  --stylua: ignore start
  buf_map('n', mappings.close,       MiniFiles.close,       'Close')
  buf_map('n', mappings.go_in,       MiniFiles.go_in,       'Go in entry')
  buf_map('n', mappings.go_in_plus,  go_in_plus,            'Go in entry plus')
  buf_map('n', mappings.go_out,      MiniFiles.go_out,      'Go out of directory')
  buf_map('n', mappings.go_out_plus, go_out_plus,           'Go out of directory plus')
  buf_map('n', mappings.reset,       MiniFiles.reset,       'Reset')
  buf_map('n', mappings.show_help,   MiniFiles.show_help,   'Show Help')
  buf_map('n', mappings.synchronize, MiniFiles.synchronize, 'Synchronize')
  buf_map('n', mappings.trim_left,   MiniFiles.trim_left,   'Trim branch left')
  buf_map('n', mappings.trim_right,  MiniFiles.trim_right,  'Trim branch right')

  H.map('x', mappings.go_in, go_in_visual, { buffer = buf_id, desc = 'Go in selected entries', expr = true })
  --stylua: ignore end
end

H.buffer_update = function(buf_id, dir_path, opts)
  if not H.is_valid_buf(buf_id) then return end

  -- Compute and set lines
  local fs_entries = H.fs_read_dir(dir_path, opts.content)
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

  H.set_buflines(buf_id, lines)

  -- Add highlighting
  local ns_id = H.ns_id.highlight
  vim.api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)

  for l_num, l in ipairs(lines) do
    local icon_start, name_start = l:match('^/%d+()%S+ ()')
    H.set_extmark(buf_id, ns_id, l_num - 1, icon_start - 1, { hl_group = icon_hl[l_num], end_col = name_start - 1 })
    H.set_extmark(buf_id, ns_id, l_num - 1, name_start - 1, { hl_group = name_hl[l_num], end_row = l_num, end_col = 0 })
  end

  -- Trigger dedicated event
  H.trigger_event('MiniFilesBufferUpdate', { buf_id = buf_id, win_id = H.opened_buffers[buf_id].win_id })

  -- Reset buffer as not modified
  H.opened_buffers[buf_id].n_modified = -1

  -- Return array with children entries path ids for future synchronization
  return vim.tbl_map(function(x) return x.path_id end, fs_entries)
end

H.buffer_delete = function(buf_id)
  if buf_id == nil then return end
  pcall(vim.api.nvim_buf_delete, buf_id, { force = true })
  H.opened_buffers[buf_id] = nil
end

H.buffer_compute_fs_diff = function(buf_id, ref_path_ids)
  if not H.is_modified_buffer(buf_id) then return {} end

  local dir_path = H.opened_buffers[buf_id].dir_path
  local lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
  local res, present_path_ids = {}, {}

  -- Process present file system entries
  for _, l in ipairs(lines) do
    local path_id = H.match_line_path_id(l)
    local path_from = H.path_index[path_id]

    local name_to = path_id ~= nil and l:sub(H.match_line_offset(l)) or l
    local path_to = H.fs_child_path(dir_path, name_to)

    if not H.is_whitespace(name_to) and path_from ~= path_to then
      table.insert(res, { from = path_from, to = path_to })
    elseif path_id ~= nil then
      present_path_ids[path_id] = true
    end
  end

  -- Detect missing file system entries
  for _, ref_id in ipairs(ref_path_ids) do
    if not present_path_ids[ref_id] then table.insert(res, { from = H.path_index[ref_id], to = nil }) end
  end

  return res
end

H.is_opened_buffer = function(buf_id) return H.opened_buffers[buf_id] ~= nil end

H.is_modified_buffer = function(buf_id)
  local data = H.opened_buffers[buf_id]
  return data ~= nil and data.n_modified > 0
end

H.match_line_entry_name = function(l)
  if l == nil then return nil end
  local offset = H.match_line_offset(l)
  -- Go up until first occurence of path separator allowing to track entries
  -- like `a/b.lua` when creating nested structure
  local res = l:sub(offset):gsub('/.*$', '')
  return res
end

H.match_line_offset = function(l)
  if l == nil then return nil end
  return l:match('^/%d+%S+ ()') or 1
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
    return icon or '', hl or 'MiniFilesFile'
  end
end

-- Windows --------------------------------------------------------------------
H.window_open = function(buf_id, config)
  -- Add always the same extra data
  config.anchor = 'NW'
  config.border = 'single'
  config.focusable = true
  config.relative = 'editor'
  config.style = 'minimal'
  -- - Use 99 to allow built-in completion to be on top
  config.zindex = 99

  -- Add temporary data which will be updated later
  config.row = 1

  -- Ensure it works on Neovim<0.9
  if vim.fn.has('nvim-0.9') == 0 then config.title = nil end

  -- Open without entering
  local win_id = vim.api.nvim_open_win(buf_id, false, config)

  -- Set permanent window options
  vim.wo[win_id].concealcursor = 'nvic'
  vim.wo[win_id].wrap = false

  -- Conceal path id
  vim.api.nvim_win_call(win_id, function() vim.fn.matchadd('Conceal', [[^/\d\+]]) end)

  -- Set permanent window highlights
  H.window_update_highlight(win_id, 'NormalFloat', 'MiniFilesNormal')
  H.window_update_highlight(win_id, 'FloatTitle', 'MiniFilesTitle')

  -- Trigger dedicated event
  H.trigger_event('MiniFilesWindowOpen', { buf_id = buf_id, win_id = win_id })

  return win_id
end

H.window_update = function(win_id, config)
  -- Compute helper data
  local has_tabline = vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)
  local max_height = H.window_get_max_height()

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
    config.border = vim.api.nvim_win_get_config(win_id).border
  else
    config.title = nil
  end

  -- Update config
  config.relative = 'editor'
  vim.api.nvim_win_set_config(win_id, config)

  -- Reset basic highlighting (removes possible "focused" highlight group)
  H.window_update_highlight(win_id, 'FloatTitle', 'MiniFilesTitle')

  -- Make sure that 'cursorline' is not overriden by `config.style`
  vim.wo[win_id].cursorline = true

  -- Make sure proper `conceallevel` (can be not the case with 'noice.nvim')
  vim.wo[win_id].conceallevel = 3

  -- Trigger dedicated event
  H.trigger_event('MiniFilesWindowUpdate', { buf_id = vim.api.nvim_win_get_buf(win_id), win_id = win_id })
end

H.window_update_highlight = function(win_id, new_from, new_to)
  local new_entry = new_from .. ':' .. new_to
  local replace_pattern = string.format('(%s:[^,]*)', vim.pesc(new_from))
  local new_winhighlight, n_replace = vim.wo[win_id].winhighlight:gsub(replace_pattern, new_entry)
  if n_replace == 0 then new_winhighlight = new_winhighlight .. ',' .. new_entry end

  -- Use `pcall()` because Neovim<0.8 doesn't allow non-existing highlight
  -- groups inside `winhighlight` (like `FloatTitle` at the time).
  pcall(function() vim.wo[win_id].winhighlight = new_winhighlight end)
end

H.window_focus = function(win_id)
  vim.api.nvim_set_current_win(win_id)
  H.window_update_highlight(win_id, 'FloatTitle', 'MiniFilesTitleFocused')
end

H.window_close = function(win_id)
  if win_id == nil then return end
  local has_buffer, buf_id = pcall(vim.api.nvim_win_get_buf, win_id)
  if has_buffer then H.opened_buffers[buf_id].win_id = nil end
  pcall(vim.api.nvim_win_close, win_id, true)
end

H.window_set_dir_view = function(win_id, dir_view)
  local init_buf_id = vim.api.nvim_win_get_buf(win_id)
  local buf_id = dir_view.buf_id

  -- Set buffer
  vim.api.nvim_win_set_buf(win_id, buf_id)

  -- Set cursor
  pcall(vim.api.nvim_win_set_cursor, win_id, dir_view.cursor)

  -- Set 'cursorline' here also because changing buffer might have removed it
  vim.wo[win_id].cursorline = true

  -- Update border highlight based on buffer status
  H.window_update_border_hl(win_id)

  -- Update buffer register
  H.opened_buffers[init_buf_id].win_id = nil
  H.opened_buffers[buf_id].win_id = win_id
end

H.window_update_border_hl = function(win_id)
  if not H.is_valid_win(win_id) then return end
  local buf_id = vim.api.nvim_win_get_buf(win_id)

  local border_hl = H.is_modified_buffer(buf_id) and 'MiniFilesBorderModified' or 'MiniFilesBorder'
  H.window_update_highlight(win_id, 'FloatBorder', border_hl)
end

H.window_get_max_height = function()
  local has_tabline = vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)
  local has_statusline = vim.o.laststatus > 0
  -- Remove 2 from maximum hight to accout for top and bottom borders
  return vim.o.lines - vim.o.cmdheight - (has_tabline and 1 or 0) - (has_statusline and 1 or 0) - 2
end

-- File system ----------------------------------------------------------------
-- TODO: Replace with `vim.fs` after Neovim=0.7 compatibility is dropped

---@class fs_entry
---@field name string Base name.
---@field fs_type string One of "directory" or "file".
---@field path string Full path.
---@field path_id number Id of full path.
---@private
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

  -- Add new data: absolute file path and its index
  for _, entry in ipairs(res) do
    local path = H.fs_child_path(dir_path, entry.name)
    entry.path = path
    entry.path_id = H.add_path_to_index(path)
  end

  return res
end

H.add_path_to_index = function(path)
  local cur_id = H.path_index[path]
  if cur_id ~= nil then return cur_id end

  local new_id = #H.path_index + 1
  H.path_index[new_id] = path
  H.path_index[path] = new_id

  return new_id
end

H.compare_fs_entries = function(a, b)
  -- Put directory first
  if a.is_dir and not b.is_dir then return true end
  if not a.is_dir and b.is_dir then return false end

  -- Otherwise order alphabetically ignoring case
  return a.lower_name < b.lower_name
end

H.fs_child_path = function(dir, name)
  local res = string.format('%s/%s', dir, name):gsub('//+', '/')
  return res
end

H.fs_full_path = function(path)
  local res = vim.fn.fnamemodify(path, ':p'):gsub('/$', '')
  return res
end

H.fs_shorten_path = function(path) return vim.fn.fnamemodify(path, ':~') end

H.fs_get_type = function(path)
  local ok, stat = pcall(vim.loop.fs_stat, path)
  if not ok or stat == nil then return nil end
  return vim.fn.isdirectory(path) == 1 and 'directory' or 'file'
end

H.fs_get_basename = function(path) return vim.fn.fnamemodify(H.fs_full_path(path), ':t') end

H.fs_get_parent = function(path)
  local res = vim.fn.fnamemodify(H.fs_full_path(path), ':h')
  if res == path then return nil end
  return res
end

-- File system actions --------------------------------------------------------
H.fs_actions_confirm = function(fs_actions)
  local msg = table.concat(H.fs_actions_to_lines(fs_actions), '\n')
  local confirm_res = vim.fn.confirm(msg, '&Yes\n&No', 1, 'Question')
  return confirm_res == 1
end

H.fs_actions_to_lines = function(fs_actions)
  -- Gather actions per source directory
  local actions_per_dir = {}

  local get_dir_actions = function(path)
    local dir_path = H.fs_shorten_path(H.fs_get_parent(path))
    local dir_actions = actions_per_dir[dir_path] or {}
    actions_per_dir[dir_path] = dir_actions
    return dir_actions
  end

  local get_quoted_basename = function(path) return string.format("'%s'", H.fs_get_basename(path)) end

  for _, diff in ipairs(fs_actions.copy) do
    local dir_actions = get_dir_actions(diff.from)
    local l = string.format('    COPY: %s to %s', get_quoted_basename(diff.from), H.fs_shorten_path(diff.to))
    table.insert(dir_actions, l)
  end

  for _, path in ipairs(fs_actions.create) do
    local dir_actions = get_dir_actions(path)
    local fs_type = path:find('/$') == nil and 'file' or 'directory'
    local l = string.format('  CREATE: %s (%s)', get_quoted_basename(path), fs_type)
    table.insert(dir_actions, l)
  end

  for _, path in ipairs(fs_actions.delete) do
    local dir_actions = get_dir_actions(path)
    local l = string.format('  DELETE: %s', get_quoted_basename(path))
    table.insert(dir_actions, l)
  end

  for _, diff in ipairs(fs_actions.move) do
    local dir_actions = get_dir_actions(diff.from)
    local l = string.format('    MOVE: %s to %s', get_quoted_basename(diff.from), H.fs_shorten_path(diff.to))
    table.insert(dir_actions, l)
  end

  for _, diff in ipairs(fs_actions.rename) do
    local dir_actions = get_dir_actions(diff.from)
    local l = string.format('  RENAME: %s to %s', get_quoted_basename(diff.from), get_quoted_basename(diff.to))
    table.insert(dir_actions, l)
  end

  -- Convert to lines
  local res = { 'CONFIRM FILE SYSTEM ACTIONS', '' }
  for dir_path, dir_actions in pairs(actions_per_dir) do
    table.insert(res, dir_path .. ':')
    vim.list_extend(res, dir_actions)
    table.insert(res, '')
  end

  return res
end

H.fs_actions_apply = function(fs_actions)
  -- Copy first to allow later proper deleting
  for _, diff in ipairs(fs_actions.copy) do
    pcall(H.fs_copy, diff.from, diff.to)
  end

  for _, path in ipairs(fs_actions.create) do
    pcall(H.fs_create, path)
  end

  for _, diff in ipairs(fs_actions.move) do
    pcall(H.fs_move, diff.from, diff.to)
  end

  for _, diff in ipairs(fs_actions.rename) do
    pcall(H.fs_rename, diff.from, diff.to)
  end

  -- Delete last to not lose anything too early (just in case)
  for _, path in ipairs(fs_actions.delete) do
    pcall(H.fs_delete, path)
  end
end

H.fs_create = function(path)
  -- Create parent directory allowing nested names
  vim.fn.mkdir(H.fs_get_parent(path), 'p')

  -- Create
  local fs_type = path:find('/$') == nil and 'file' or 'directory'
  if fs_type == 'directory' then
    vim.fn.mkdir(path)
  else
    vim.fn.writefile({}, path)
  end
end

H.fs_copy = function(from, to)
  if H.fs_get_type(from) == 'file' then
    vim.loop.fs_copyfile(from, to)
    return
  end

  -- Recursively copy a directory
  local self = function(x) return x end
  local fs_entries = H.fs_read_dir(from, { filter = self, sort = self })
  -- NOTE: Create directory *after* reading entries to allow copy inside itself
  vim.fn.mkdir(to)
  for _, entry in ipairs(fs_entries) do
    H.fs_copy(entry.path, H.fs_child_path(to, entry.name))
  end
end

H.fs_delete = function(path) vim.fn.delete(path, 'rf') end

H.fs_move = function(from, to)
  vim.loop.fs_rename(from, to)

  -- Rename in loaded buffers
  for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
    H.rename_loaded_buffer(buf_id, from, to)
  end
end

H.fs_rename = H.fs_move

H.rename_loaded_buffer = function(buf_id, from, to)
  if not (vim.api.nvim_buf_is_loaded(buf_id) and vim.bo[buf_id].buftype == '') then return end
  local cur_name = vim.api.nvim_buf_get_name(buf_id)

  -- Use `gsub('^' ...)` to also take into account directory renames
  local new_name = cur_name:gsub('^' .. vim.pesc(from), to)
  if cur_name == new_name then return end
  vim.api.nvim_buf_set_name(buf_id, new_name)

  -- Force write to avoid the 'overwrite existing file' error message on write
  -- for normal files
  vim.api.nvim_buf_call(buf_id, function() vim.cmd('silent! write! | edit') end)
end

-- Validators -----------------------------------------------------------------
H.validate_opened_buffer = function(x)
  if x == nil or x == 0 then x = vim.api.nvim_get_current_buf() end
  if not H.is_opened_buffer(x) then H.error('`buf_id` should be an identifier of an opened directory buffer.') end
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

H.trigger_event = function(event_name, data)
  -- TODO: Remove after compatibility with Neovim=0.7 is dropped
  if vim.fn.has('nvim-0.8') == 0 then data = nil end
  vim.api.nvim_exec_autocmds('User', { pattern = event_name, data = data })
end

H.is_valid_buf = function(buf_id) return type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id) end

H.is_valid_win = function(win_id) return type(win_id) == 'number' and vim.api.nvim_win_is_valid(win_id) end

H.is_whitespace = function(l) return l:find('^%s*$') ~= nil end

H.get_bufline = function(buf_id, line) return vim.api.nvim_buf_get_lines(buf_id, line - 1, line, false)[1] end

H.set_buflines = function(buf_id, lines)
  local cmd =
    string.format('lockmarks lua vim.api.nvim_buf_set_lines(%d, 0, -1, false, %s)', buf_id, vim.inspect(lines))
  vim.cmd(cmd)
end

H.set_extmark = function(...) pcall(vim.api.nvim_buf_set_extmark, ...) end

H.get_first_valid_normal_window = function()
  for _, win_id in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(win_id).relative == '' then return win_id end
  end
end

return MiniFiles
