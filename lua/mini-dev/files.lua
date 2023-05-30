-- TODO:
--
-- Code:
-- - Implement MacOS Finder with column view type of file explorer:
--     - Think about always using full path in title.
--     - Think about least problematic default highlighting of a file (which
--       mostly likely to not override cursor line).
--
-- - Implement 'oil.nvim' like file manipulation:
--     - Concealed index should encode absolute file path allowing moving files
--       across directories.
--
-- - Design (and, probably, implement some) for asynchronous integrations.
--
-- - Make an effort to ensure proper work on Linux, Windows, and MacOS:
--     - Windows and MacOS use case insensitive file names.
--
-- Tests:
--
-- Docs:

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
    width_active = 50,
    width_nonactive = 30,
  },
}
--minidoc_afterlines_end

MiniFiles.open = function(path, opts)
  path = H.full_path(path or vim.fn.getcwd())
  opts = vim.tbl_deep_extend('force', H.get_config(), opts or {})
  opts.content.filter = opts.content.filter or MiniFiles.default_filter
  opts.content.sort = opts.content.sort or MiniFiles.default_sort

  -- Properly close possibly opened in the tabpage explorer
  MiniFiles.close()

  -- Get explorer to open
  local explorer = H.explorer_history[path] or { branch = { path }, active_depth = 1 }

  H.explorer_open(explorer, opts)
end

MiniFiles.refresh = function()
  -- TODO
end

MiniFiles.close = function()
  local tabpage_id = vim.api.nvim_get_current_tabpage()
  local cur_explorer = H.opened_explorers[tabpage_id]
  if cur_explorer == nil then return end

  -- Close active windows
  for _, win_id in pairs(cur_explorer.windows) do
    pcall(vim.api.nvim_win_close, win_id, true)
  end
  cur_explorer.windows = nil

  -- Unregister depth buffers
  cur_explorer.depth_buffers = nil

  -- Save to history and remove from registry
  H.explorer_history[cur_explorer.branch[1]] = cur_explorer
  H.opened_explorers[tabpage_id] = nil
end

MiniFiles.synchronize = function()
  -- TODO
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

-- History of explorers per root directory. Each entry is an inactive explorer:
-- - <branch> - array of absolute directory paths from parent to child.
-- - <active_depth> - id in `branch` of active path.
H.explorer_history = {}

-- Registry of active explorers per tabpage
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
    ['windows.width_active'] = { config.windows.width_active, 'number' },
    ['windows.width_nonactive'] = { config.windows.width_nonactive, 'number' },
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
  hi('MiniFilesFile',      { link = 'Special'     })
  hi('MiniFilesNormal',    { link = 'NormalFloat' })
  hi('MiniFilesTitle',     { link = 'FloatTitle'  })
end

H.is_disabled = function() return vim.g.minifiles_disable == true or vim.b.minifiles_disable == true end

H.get_config =
  function(config) return vim.tbl_deep_extend('force', MiniFiles.config, vim.b.minifiles_config or {}, config or {}) end

-- Explorers ------------------------------------------------------------------
H.explorer_open = function(explorer, opts)
  explorer = H.normalize_explorer(explorer)
  if #explorer.branch == 0 then return end

  local tabpage_id = vim.api.nvim_get_current_tabpage()

  local windows = {}
  local active_depth = explorer.active_depth
  local cur_pane_col = 0
  local depth_range = H.compute_visible_depth_range(explorer, opts)
  for depth = depth_range.from, depth_range.to do
    -- Prepare buffer
    local buf_id = H.depth_buffer_get(tabpage_id, depth, opts.mappings)
    local dir_path = explorer.branch[depth]
    H.depth_buffer_update(buf_id, dir_path, opts.content)

    -- Create and register floating window
    local cur_width = depth == active_depth and opts.windows.width_active or opts.windows.width_nonactive
    local config = {
      col = cur_pane_col,
      border = opts.windows.border,
      height = vim.api.nvim_buf_line_count(buf_id),
      -- Use full path in first pane
      title = cur_pane_col == 0 and dir_path or vim.fn.fnamemodify(dir_path, ':t'),
      -- title = dir_path,
      width = cur_width,
    }
    local win_id = H.open_pane(buf_id, config)
    windows[depth] = win_id

    -- Add 2 to account for left and right borders
    cur_pane_col = cur_pane_col + cur_width + 2
  end
  explorer.windows = windows

  -- Focus on proper window
  vim.api.nvim_set_current_win(windows[active_depth])

  -- Register explorer as active
  H.opened_explorers[tabpage_id] = explorer
end

H.open_pane = function(buf_id, config)
  -- Compute helper data
  local has_tabline = vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)
  local has_statusline = vim.o.laststatus > 0
  -- Remove 2 from maximum hight to accout for top and bottom borders
  local max_height = vim.o.lines - vim.o.cmdheight - (has_tabline and 1 or 0) - (has_statusline and 1 or 0) - 2

  -- Infer extra data
  config.anchor = 'NW'
  config.focusable = true
  config.relative = 'editor'
  config.row = has_tabline and 1 or 0
  config.style = 'minimal'
  config.zindex = 1000

  -- Ensure proper fit
  config.height = math.min(config.height, max_height)
  config.width = math.min(config.width, vim.o.columns)

  if vim.fn.has('nvim-0.9') == 0 then
    -- Titles supported only in Neovim>=0.9
    config.title = nil
  else
    -- Show only tail if title is too long
    local title_string, width = config.title, config.width
    local title_chars = vim.fn.strcharlen(title_string)
    if width < title_chars then
      title_string = '…' .. vim.fn.strcharpart(title_string, title_chars - width + 1, width - 1)
    end
    config.title = title_string
  end

  -- Open without entering
  local res = vim.api.nvim_open_win(buf_id, false, config)

  -- Set window options
  vim.wo[res].cursorline = true
  vim.wo[res].conceallevel = 3
  vim.wo[res].concealcursor = 'nvic'

  -- Conceal path id
  vim.api.nvim_win_call(res, function() vim.fn.matchadd('conceal', [[^/\d\+]]) end)

  -- Set window highlights
  vim.wo[res].winhighlight = 'FloatBorder:MiniFilesBorder,FloatTitle:MiniFilesTitle,NormalFloat:MiniFilesNormal'

  return res
end

H.normalize_explorer = function(explorer)
  -- Ensure that all paths from branch are valid directory paths
  local norm_branch = {}
  for _, dir in ipairs(explorer.branch) do
    if vim.fn.isdirectory(dir) == 0 then break end
    table.insert(norm_branch, dir)
  end

  return { branch = norm_branch, active_depth = math.min(explorer.active_depth, #norm_branch) }
end

H.compute_visible_depth_range = function(explorer, opts)
  -- Compute maximum number panes able to fit in current Neovim instance width
  -- Add 2 to widths to take into account width of left and right borders
  local w_active, w_nonactive = opts.windows.width_active + 2, opts.windows.width_nonactive + 2
  local max_n_panes = math.floor((vim.o.columns - w_active) / w_nonactive)
  max_n_panes = math.max(max_n_panes, 0) + 1

  -- Compute which branch entries to show with the following idea:
  -- - Always show current entry as centered as possible.
  -- - Show as much as possible.
  -- Logic is similar to how text for 'mini.tabline' is computed.
  local branch_depth, active_depth = #explorer.branch, explorer.active_depth
  local n_panes = math.min(branch_depth, max_n_panes)

  local to = math.min(branch_depth, math.floor(active_depth + 0.5 * n_panes))
  local from = math.max(1, to - n_panes + 1)
  to = from + math.min(n_panes, branch_depth) - 1

  return { from = from, to = to }
end

-- Depth buffers --------------------------------------------------------------
H.depth_buffer_get = function(tabpage_id, depth, mappings)
  -- Try return an already created buffer
  local tabpage_buffers = H.depth_buffers[tabpage_id] or {}
  local res = tabpage_buffers[depth]
  if res ~= nil then return res end

  -- Create and register depth buffer
  res = vim.api.nvim_create_buf(false, true)
  tabpage_buffers[depth] = res
  H.depth_buffers[tabpage_id] = tabpage_buffers

  -- Set buffer options
  vim.bo[res].filetype = 'minifiles'

  -- Make buffer mappings
  -- TODO
  -- H.map('n', mappings.go_left, ..., { buffer = res, desc = 'Go left in file explorer' })
  -- H.map('n', mappings.go_right, ..., { buffer = res, desc = 'Go right in file explorer' })
  H.map('n', mappings.synchronize, MiniFiles.synchronize, { buffer = res, desc = 'Synchronize file explorer' })
  H.map('n', mappings.quit, MiniFiles.close, { buffer = res, desc = 'Close file explorer' })

  -- Tweak buffer to be used nicely with other 'mini.nvim' modules
  vim.b[res].minicursorword_disable = true

  return res
end

H.depth_buffer_update = function(buf_id, dir_path, content_opts)
  -- Compute and set lines
  local fs_entries = H.read_dir(dir_path, content_opts)
  local get_icon_data = H.make_icon_getter()

  local lines, icon_hl, name_hl = {}, {}, {}
  for _, entry in ipairs(fs_entries) do
    local icon, hl = get_icon_data(entry.name, entry.fs_type)
    table.insert(lines, string.format('/%d %s %s', H.path_index[entry.path], icon, entry.name))
    table.insert(icon_hl, hl)
    table.insert(name_hl, entry.fs_type == 'directory' and 'MiniFilesDirectory' or 'MiniFilesFile')
  end

  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)

  -- Add highlighting
  local ns_id = H.ns_id.highlight
  vim.api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)

  for l_num, l in ipairs(lines) do
    local icon_start, name_start = l:match('^%S+ ()%S+ ()')
    H.set_extmark(buf_id, ns_id, l_num - 1, icon_start - 1, { hl_group = icon_hl[l_num], end_col = name_start - 1 })
    H.set_extmark(buf_id, ns_id, l_num - 1, name_start - 1, { hl_group = name_hl[l_num], end_row = l_num, end_col = 0 })
  end
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

-- File system ----------------------------------------------------------------
H.read_dir = function(dir_path, content_opts)
  local fs = vim.loop.fs_scandir(dir_path)
  local res = {}
  if not fs then return res end

  -- Read all entries
  local name, fs_type = vim.loop.fs_scandir_next(fs)
  while name do
    table.insert(res, { name = name, fs_type = fs_type })
    name, fs_type = vim.loop.fs_scandir_next(fs)
  end

  -- Filter and sort entries
  res = content_opts.sort(content_opts.filter(res))

  -- Add absolute file paths to result and index
  for _, entry in ipairs(res) do
    local path = H.join_path(dir_path, entry.name)
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

H.join_path = function(dir, name) return string.format('%s%s%s', dir, H.path_sep, name) end

H.full_path = function(path) return vim.fn.fnamemodify(path, ':p'):gsub(H.path_sep .. '$', '') end

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

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.files) %s', msg), 0) end

H.map = function(mode, lhs, rhs, opts)
  if lhs == '' then return end
  opts = vim.tbl_deep_extend('force', { silent = true }, opts or {})
  vim.keymap.set(mode, lhs, rhs, opts)
end

H.set_extmark = function(...) pcall(vim.api.nvim_buf_set_extmark, ...) end

return MiniFiles
