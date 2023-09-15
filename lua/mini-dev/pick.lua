-- Quick start
--
-- - Copy this file to runtime 'lua' directory.
--
-- - Run `require('<path-to-module>').setup()` (this will at least create
--   necessary highlight groups).
--
-- - Start picker via `MiniPick.start({ source = { items = { ... } } })` or
--   `MiniPick.builtin....()`. Like:
--     - MiniPick.builtin.files()
--     - MiniPick.builtin.grep()
--     - MiniPick.builtin.grep_live()
--     - MiniPick.builtin.help()
--     - MiniPick.builtin.buffers()
--
-- - Best used with latest Nightly.
--
-- Life cycle after opened:
--
-- - Type characters to filter. By default uses `default_match`:
--     - If query starts with `'`, the match is exact.
--     - If query starts with `^`, the match is exact at start.
--     - If query starts with `$`, the match is exact at end.
--     - Otherwise match is fuzzy.
--     - Sorting is done to first minimize match width and then match start.
--       Nothing more: no favoring certain places, etc.
--
-- - Press `<Tab>` to toggle preview.
--
-- - Press `<S-Tab>` to toggle information window with all available mappings.
--
-- - Press `<CR>` to choose an item.
--
-- - Tip: moving and scrolling works even if preview or info buffers are shown.
--   Moving changes current item and updates buffer, scrolling scrolls as is.
--
-- Implementation details:
--
-- - It is non-blocking but waits to return the chosen item.
--
-- - Respects 'ignorecase' and 'smartcase' for case of search out of the box.
--   This is done by non-blocking computation of `lower` variant of string
--   items during startup.

-- TODO:
--
-- - Think about how to enable fuzzy search for special queries:
--   "'exact", '^start', 'end$'.
--
-- - Think about fully making coherent naming for items fields (`line` instead
--   of `lnum`, `line_end` instead of `end_lnum`, etc.).
--
-- - Profile memory usage.
--
-- Tests:
--
-- - All actions should work when `items` is not yet set.
--
-- - Automatically respects 'ignorecase'/'smartcase' by adjusting `stritems`.
--
-- - Works with multibyte characters.
--
-- - Any mouse click stops picker.
--
-- - Builtin:
--     - Files:
--         - Respects `source.cwd`.
--
--     - Grep:
--         - Respects `source.cwd`.
--
--     - Grep live:
--         - Respects `source.cwd`.
--
--     - CLI:
--         - Respects `source.cwd`.
--
--     - Help:
--         - Works when "Open tag" -> "Open tag in same file".
--         - Can be properly aborted.
--
--     - Buffers:
--         - Preview doesn't trigger `BufEnter` which might interfer with many
--           plugins (like `setup_auto_root()` from 'mini.misc').
--
-- Docs:
--
-- - Example mappings to switch `toggle_{preview,info}` and `move_{up,down}`: >
--   require('mini.pick').setup({
--     mappings = {
--       toggle_info    = '<C-k>',
--       toggle_preview = '<C-p>',
--       move_down      = '<Tab>',
--       move_up        = '<S-Tab>',
--     }
--   })
--
-- - Recommendations on how to structure item as a table for it to properly
--   work with `default_preview` and `default_choose`.
--   `default_preview` for region data assumes structure similar to
--   |diagnostic-structure| but with 1-indexing (end line inclusive; end col
--   exclusive).
--
-- - `MiniPick.builtin.grep({ pattern = vim.fn.expand('<cword>') })` to find
--   word under cursor.
--
-- - Example of `execute` custom action:
--   execute = function(picker, _) vim.cmd(vim.fn.input('Execute: ')) end,
--
-- - <C-c> is hard-coded to always stop the picker.
--
-- - Make `refine` action very visible.

--- *mini.pick* Pick anything
--- *MiniPick*
---
--- MIT License Copyright (c) 2023 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Features:
--- - Single-window interface for picking element from any array with
---   interactive filtering and/or vertical navigation.
---
--- - Customizable
---     - "On choice" action.
---     - Filter and sort.
---     - On-demand item's extended info (usually preview).
---     - Mappings for special actions.
---
--- - Converters for Telescope pickers and sorters.
---
--- - |vim.ui.select()| wrapper.
---
--- Notes:
--- - Works on all supported versions but using Neovim>=0.9 is recommended.
---
--- See |MiniPick-overview| for more details.
---
--- # Dependencies~
---
--- Suggested dependencies (provide extra functionality, will work without them):
---
--- - Plugin 'nvim-tree/nvim-web-devicons' for filetype icons near the items.
---   If missing, default or no icons will be used.
---
--- - CLI tool for |MiniPick.builtin.files()|, |MiniPick.builtin.grep()|, and
---   |MiniPick.builtin.grep_live()|:
---     - `rg`
---     - `git`
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.pick').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniPick`
--- which you can use for scripting or manually (with `:lua MiniPick.*`).
---
--- See |MiniPick.config| for available config settings.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.minioperators_config` which should have same structure as
--- `MiniPick.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons ~
---
--- - 'nvim-telescope/telescope.nvim':
---
--- - 'ibhagwan/fzf-lua':
---
--- # Highlight groups ~
---
--- * `MiniPickBorder` - window border.
--- * `MiniPickBorderBusy` - window border while picker is busy processing.
--- * `MiniPickBorderText` - non-prompt on border.
--- * `MiniPickIconDirectory` - default icon for directory.
--- * `MiniPickIconFile` - default icon for file.
--- * `MiniPickHeader` - headers in info buffer and previews.
--- * `MiniPickMatchCurrent` - current matched item.
--- * `MiniPickMatchOffsets` - offset characters matching query elements.
--- * `MiniPickNormal` - basic foreground/background highlighting.
--- * `MiniPickPreviewLine` - target line in preview.
--- * `MiniPickPreviewRegion` - target region in preview.
--- * `MiniPickPrompt` - prompt.
---
--- To change any highlight group, modify it directly with |:highlight|.

---@MiniPick-events

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local
---@diagnostic disable:cast-local-type

-- Module definition ==========================================================
local MiniPick = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniPick.config|.
---
---@usage `require('mini.pick').setup({})` (replace `{}` with your `config` table).
MiniPick.setup = function(config)
  -- Export module
  _G.MiniPick = MiniPick

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
---@text # Source ~
---
--- `config.source` defines single picker related data. Usually should be set
--- for each picker individually inside |MiniPick.start()|. Setting them directly
--- in config serves as default fallback.
---
--- `source.items` is an array of items to choose from or callable.
--- Each item can be either string or table containing string `item` field.
--- Callable can either return array of items directly (use as is) or not
--- (expected an explicit |MiniPick.set_picker_items()| call; right away or later).
---
--- `source.name` is a string containing the source name.
---
--- `source.preview` is a callable to be executed on item to show more
--- information about it. ??? What signature and what should it return ???
--- If `nil` (default) uses |MiniPick.default_preview()|.
---
--- `source.choose` is also a callable to be executed on the chosen item.
--- ??? What signature and what should it return ???
--- If `nil` (default) uses |MiniPick.default_choose()|.
MiniPick.config = {
  content = {
    match = nil,

    show = nil,

    direction = 'from_top',

    -- Cache matches to ~ncrease speed on repeated prompts (uses more memory)
    use_cache = false,
  },

  delay = {
    -- Delay between forcing asynchronous behavior
    async = 10,

    -- Delay between start processing and visual feedback about it
    busy = 50,
  },

  -- Special keys for active picker
  mappings = {
    caret_left  = '<Left>',
    caret_right = '<Right>',

    choose            = '<CR>',
    choose_all        = '<C-a>',
    choose_in_split   = '<C-s>',
    choose_in_tabpage = '<C-t>',
    choose_in_vsplit  = '<C-v>',

    delete_char       = '<BS>',
    delete_char_right = '<Del>',
    delete_left       = '<C-u>',
    delete_word       = '<C-w>',

    move_down  = '<C-n>',
    move_start = '<C-g>',
    move_up    = '<C-p>',

    paste = '<C-r>',

    refine = '<C-Space>',

    scroll_down  = '<C-f>',
    scroll_up    = '<C-b>',
    scroll_left  = '<C-h>',
    scroll_right = '<C-l>',

    stop = '<Esc>',

    toggle_info    = '<S-Tab>',
    toggle_preview = '<Tab>',
  },

  source = {
    name = nil,
    items = nil,
    cwd = nil,
    preview = nil,
    choose = nil,
    choose_all = nil,
  },

  window = {
    config = nil,
  },
}
--minidoc_afterlines_end

---@param opts table|nil Options. Should have the same structure as |MiniPick.config|.
---   Default values are inferred from there. Should have proper `source.items`.
---
--- @return ... Tuple of current item and its index just before picker is stopped.
MiniPick.start = function(opts)
  if MiniPick.is_picker_active() then
    MiniPick.stop()
    -- NOTE: Needs `schedule()` for `stop()` to properly finish code flow
    return vim.schedule(function()
      -- NOTE: if `MiniPick.stop()` still didn't stop, force clean and start
      if MiniPick.is_picker_active() then H.pickers.active = nil end
      MiniPick.start(opts)
    end)
  end

  opts = H.validate_picker_opts(opts)
  local picker = H.picker_new(opts)
  H.pickers.active, H.cache = picker, {}
  vim.api.nvim_exec_autocmds('User', { pattern = 'MiniPickStart' })
  return H.picker_advance(picker)
end

--- Stop active picker
MiniPick.stop = function()
  if not MiniPick.is_picker_active() then return end
  H.cache.is_force_stop_advance = true
  if H.cache.is_in_getcharstr then vim.api.nvim_feedkeys('\27', 't', true) end
end

MiniPick.refresh = function()
  if not MiniPick.is_picker_active() then return end
  local picker = H.pickers.active
  local config = H.picker_compute_win_config(picker.opts.window.config)
  vim.api.nvim_win_set_config(picker.windows.main, config)
  H.picker_set_current_ind(picker, picker.current_ind, true)
  H.picker_update(picker, false)
end

MiniPick.default_match = function(inds, stritems, query)
  if #query == 0 then return H.seq_along(stritems) end
  local f = function()
    local match_data, match_type = H.match_filter(inds, stritems, query)
    if match_data == nil then return end
    if match_type == 'nosort' then return MiniPick.set_picker_match_inds(H.seq_along(stritems)) end
    local match_inds = H.match_sort(match_data)
    if match_inds == nil then return end
    MiniPick.set_picker_match_inds(match_inds)
  end
  coroutine.resume(coroutine.create(f))
end

-- Default value of `show_icons` is `false`. However, for pickers showing
-- file/directory paths, `true` is used by default.
MiniPick.default_show = function(items, buf_id, opts)
  opts = vim.tbl_deep_extend('force', { show_icons = false }, opts or {})

  -- Compute and set lines
  local lines = vim.tbl_map(H.item_to_string, items)
  lines = vim.tbl_map(function(l) return l:gsub('\n', ' ') end, lines)

  local get_prefix_data = opts.show_icons and H.get_icon or function() return { text = '' } end
  local prefix_data = vim.tbl_map(get_prefix_data, lines)

  local lines_to_show = {}
  for i, l in ipairs(lines) do
    lines_to_show[i] = prefix_data[i].text .. l
  end

  H.set_buflines(buf_id, lines_to_show)

  -- Extract match offsets
  local ns_id = H.ns_id.offsets
  H.clear_namespace(buf_id, ns_id)

  local stritems, query = lines, MiniPick.get_picker_query()
  if H.query_is_ignorecase(query) then
    stritems, query = vim.tbl_map(H.tolower, stritems), vim.tbl_map(H.tolower, query)
  end
  local match_data, match_type, query_adjusted = H.match_filter(H.seq_along(stritems), stritems, query)
  if match_data == nil then return end

  local match_offsets_fun = match_type == 'fuzzy' and H.match_offsets_fuzzy or H.match_offsets_exact
  local match_offsets = match_offsets_fun(match_data, query_adjusted, stritems)

  -- Place offset highlights accounting for possible shift due to prefixes
  local extmark_opts = { hl_group = 'MiniPickMatchOffsets', hl_mode = 'combine', priority = 200 }
  for i = 1, #match_data do
    local row, offsets = match_data[i][4], match_offsets[i]
    local start_offset = prefix_data[row].text:len()
    for _, off in ipairs(offsets) do
      extmark_opts.end_row, extmark_opts.end_col = row - 1, start_offset + H.get_next_char_bytecol(lines[row], off)
      H.set_extmark(buf_id, ns_id, row - 1, start_offset + off - 1, extmark_opts)
    end
  end

  -- Highlight prefixes
  if not opts.show_icons then return end
  local icon_extmark_opts = { hl_mode = 'combine', priority = 200 }
  for i = 1, #prefix_data do
    icon_extmark_opts.hl_group = prefix_data[i].hl
    icon_extmark_opts.end_row, icon_extmark_opts.end_col = i - 1, prefix_data[i].text:len()
    H.set_extmark(buf_id, ns_id, i - 1, 0, icon_extmark_opts)
  end
end

MiniPick.default_preview = function(item, buf_id, opts)
  opts = vim.tbl_deep_extend('force', { n_context_lines = 2 * vim.o.lines, line_position = 'top' }, opts or {})
  local item_data = H.parse_item(item)
  if item_data.type == 'file' then return H.preview_file(item_data, buf_id, opts) end
  if item_data.type == 'directory' then return H.preview_directory(item_data, buf_id) end
  if item_data.type == 'buffer' then return H.preview_buffer(item_data, buf_id, opts) end
  H.preview_inspect(item, buf_id)
end

MiniPick.default_choose = function(item)
  if item == nil then return end
  local item_data = H.parse_item(item)
  if item_data.type == 'file' or item_data.type == 'directory' then return H.choose_path(item_data) end
  if item_data.type == 'buffer' then return H.choose_buffer(item_data) end
  H.choose_print(item)
end

MiniPick.default_choose_all = function(items, opts)
  opts = vim.tbl_deep_extend('force', { list_type = 'quickfix' }, opts or {})

  -- Construct a list
  local list = {}
  for _, item in ipairs(items) do
    local data = H.parse_item(item)
    if data.type == 'file' or data.type == 'buffer' then
      local entry = { bufnr = data.buf_id, filename = data.path }
      entry.lnum, entry.col, entry.text = data.line or 1, data.col or 1, data.text or ''
      entry.end_lnum, entry.end_col = data.line_end, data.col_end
      table.insert(list, entry)
    end
  end
  if #list == 0 then return end

  -- Set as quickfix or location list
  local win_target = MiniPick.get_picker_state().windows.target
  if opts.list_type == 'location' then
    vim.fn.setloclist(win_target, list, ' ')
    vim.schedule(function() vim.cmd('lopen') end)
  end

  vim.fn.setqflist(list, ' ')
  local source_name, prompt = MiniPick.get_picker_opts().source.name, table.concat(MiniPick.get_picker_query())
  vim.fn.setqflist({}, 'a', { title = source_name .. ':' .. prompt })
  vim.schedule(function() vim.cmd('copen') end)
end

MiniPick.ui_select = function(items, opts, on_choice)
  local format_item = opts.format_item or function(x) return tostring(x) end
  local items_ext = {}
  for i = 1, #items do
    table.insert(items_ext, { index = i, item = format_item(items[i]), item_original = items[i] })
  end

  local picker_opts = {
    source = {
      items = items_ext,
      name = opts.prompt,
      choose = function(item) on_choice((item or {}).item_original, (item or {}).index) end,
      preview = H.preview_inspect,
    },
  }
  MiniPick.start(picker_opts)
end

MiniPick.builtin = {}

MiniPick.builtin.files = function(local_opts, opts)
  local_opts = vim.tbl_deep_extend('force', { tool = nil }, local_opts or {})
  local tool = local_opts.tool or H.files_get_tool()
  local show = H.get_config().content.show or H.show_with_icons
  local default_opts = { source = { name = string.format('Files (%s)', tool) }, content = { show = show } }
  opts = vim.tbl_deep_extend('force', default_opts, opts or {})

  if tool == 'fallback' then
    opts.source.items = H.files_fallback_items
    return MiniPick.start(opts)
  end

  return MiniPick.builtin.cli({ command = H.files_get_command(tool) }, opts)
end

MiniPick.builtin.grep = function(local_opts, opts)
  local_opts = vim.tbl_deep_extend('force', { tool = nil, pattern = nil }, local_opts or {})
  local tool = local_opts.tool or H.grep_get_tool()
  local show = H.get_config().content.show or H.show_with_icons
  local default_opts = { source = { name = string.format('Grep (%s)', tool) }, content = { show = show } }
  opts = vim.tbl_deep_extend('force', default_opts, opts or {})

  local pattern = type(local_opts.pattern) == 'string' and local_opts.pattern or vim.fn.input('Grep pattern: ')
  if tool == 'fallback' then
    opts.source.items = function() H.grep_fallback_items(pattern) end
    return MiniPick.start(opts)
  end

  return MiniPick.builtin.cli({ command = H.grep_get_command(tool, pattern) }, opts)
end

MiniPick.builtin.grep_live = function(local_opts, opts)
  local_opts = vim.tbl_deep_extend('force', { tool = nil }, local_opts or {})
  local tool = local_opts.tool or H.grep_get_tool()
  if tool == 'fallback' or not H.is_executable(tool) then H.error('`grep_live` needs non-fallback executable tool.') end

  local show = H.get_config().content.show or H.show_with_icons
  local default_opts = { source = { name = string.format('Grep live (%s)', tool) }, content = { show = show } }
  opts = vim.tbl_deep_extend('force', default_opts, opts or {})

  local set_items_opts, spawn_opts = { do_match = false, querytick = H.querytick }, { cwd = opts.source.cwd }
  local process
  local match = function(_, _, query)
    if H.querytick == set_items_opts.querytick then return end
    if #query == 0 then return MiniPick.set_picker_items({}, set_items_opts) end

    set_items_opts.querytick = H.querytick
    pcall(vim.loop.process_kill, process)
    local command = H.grep_get_command('rg', table.concat(query))
    process = MiniPick.set_picker_items_from_cli(command, { set_items_opts = set_items_opts, spawn_opts = spawn_opts })
  end

  opts = vim.tbl_deep_extend('force', opts or {}, { source = { items = {} }, content = { match = match } })
  return MiniPick.start(opts)
end

MiniPick.builtin.help = function(local_opts, opts)
  -- Get all tags
  local help_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[help_buf].buftype = 'help'
  local tags = vim.api.nvim_buf_call(help_buf, function() return vim.fn.taglist('.*') end)
  vim.api.nvim_buf_delete(help_buf, { force = true })
  vim.tbl_map(function(t) t.item = t.name end, tags)

  -- NOTE: Choosing is done after returning item. This is done to properly
  -- overcome special nature of `:help {subject}` command. For example, it
  -- didn't quite work when choosing tags in same file consecutively.
  local choose = function(item) end
  local choose_all = function(items) end
  local preview = function(item, buf_id)
    -- Take advantage of `taglist` output on how to open tag
    vim.api.nvim_buf_call(buf_id, function()
      vim.cmd('noautocmd edit ' .. vim.fn.fnameescape(item.filename))
      vim.bo.buflisted, vim.bo.bufhidden, vim.bo.syntax = false, 'wipe', 'help'

      local cache_hlsearch = vim.v.hlsearch
      vim.cmd('silent keeppatterns ' .. item.cmd)
      vim.v.hlsearch = cache_hlsearch
      vim.cmd('normal! zt')
    end)
  end

  local source = { items = tags, name = 'Help', choose = choose, choose_all = choose_all, preview = preview }
  opts = vim.tbl_deep_extend('force', { source = source }, opts or {})
  local item = MiniPick.start(opts)
  if item ~= nil then vim.cmd('help ' .. (item.name or '')) end
  return item
end

MiniPick.builtin.buffers = function(local_opts, opts)
  local_opts = vim.tbl_deep_extend('force', { include_unlisted = false, include_current = true }, local_opts or {})

  local buffers_output = vim.api.nvim_exec('buffers' .. (local_opts.include_unlisted and '!' or ''), true)
  local cur_buf_id, include_current = vim.api.nvim_get_current_buf(), local_opts.include_current
  local items = {}
  for _, l in ipairs(vim.split(buffers_output, '\n')) do
    local buf_str, name = l:match('^%s*%d+'), l:match('"(.*)"')
    local buf_id = tonumber(buf_str)
    local item = { item = name, buf_id = buf_id }
    if buf_id ~= cur_buf_id or include_current then table.insert(items, item) end
  end

  local show = H.get_config().content.show or H.show_with_icons
  local default_opts = { source = { name = 'Buffers' }, content = { show = show } }
  opts = vim.tbl_deep_extend('force', default_opts, opts or {}, { source = { items = items } })
  MiniPick.start(opts)
end

MiniPick.builtin.cli = function(local_opts, opts)
  local_opts = vim.tbl_deep_extend('force', { command = {}, postprocess = nil, spawn_opts = {} }, local_opts or {})
  opts = vim.tbl_deep_extend('force', { source = { name = 'CLI output' } }, opts or {})

  local command = local_opts.command
  local set_from_cli_opts = { postprocess = local_opts.postprocess, spawn_opts = local_opts.spawn_opts }
  set_from_cli_opts.spawn_opts.cwd = set_from_cli_opts.spawn_opts.cwd or opts.source.cwd
  opts.source.items = vim.schedule_wrap(function() MiniPick.set_picker_items_from_cli(command, set_from_cli_opts) end)
  return MiniPick.start(opts)
end

MiniPick.builtin.resume = function()
  local picker = H.pickers.latest
  if picker == nil then H.error('There is no latest picker.') end

  local buf_id = H.picker_new_buf()
  local win_id = H.picker_new_win(buf_id, picker.opts.window.config)
  picker.buffers = { main = buf_id }
  picker.windows = { main = win_id, target = vim.api.nvim_get_current_win() }
  picker.view_state = 'main'

  H.pickers.active = picker
  return H.picker_advance(picker)
end

---@seealso |MiniPick.set_picker_items()| and |MiniPick.set_picker_items_from_cli()|
MiniPick.get_picker_items = function() return vim.deepcopy((H.pickers.active or {}).items) end

---@seealso |MiniPick.set_picker_match_inds()|
MiniPick.get_picker_matches = function()
  if not MiniPick.is_picker_active() then return end
  local picker = H.pickers.active
  if picker.items == nil then return {} end

  local res = { all_ind = vim.deepcopy(picker.match_inds), current_ind = picker.match_inds[picker.current_ind] }
  res.all = vim.tbl_map(function(ind) return picker.items[ind] end, picker.match_inds)
  res.current = picker.items[res.current_ind]
  return res
end

---@seealso |MiniPick.set_picker_opts()|
MiniPick.get_picker_opts = function(opts) return vim.deepcopy((H.pickers.active or {}).opts) end

---@seealso |MiniPick.set_picker_target_window()|
MiniPick.get_picker_state = function()
  if not MiniPick.is_picker_active() then return end
  local picker = H.pickers.active
  return vim.deepcopy({ is_busy = picker.is_busy, buffers = picker.buffers, windows = picker.windows })
end

---@seealso |MiniPick.set_picker_query()|
MiniPick.get_picker_query = function() return vim.deepcopy((H.pickers.active or {}).query) end

---@seealso |MiniPick.get_picker_items()|
MiniPick.set_picker_items = function(items, opts)
  if not vim.tbl_islist(items) then H.error('`items` should be list.') end
  if not MiniPick.is_picker_active() then return end
  opts = vim.tbl_deep_extend('force', { do_match = true, querytick = nil }, opts or {})

  -- Set items in async because computing lower `stritems` can block much time
  coroutine.wrap(H.picker_set_items)(H.pickers.active, items, opts)
end

---@seealso |MiniPick.get_picker_items()|
MiniPick.set_picker_items_from_cli = function(command, opts)
  if not vim.tbl_islist(command) then H.error('`command` should be an array of strings.') end
  if not MiniPick.is_picker_active() then return end
  local default_opts = { postprocess = H.cli_postprocess, set_items_opts = { do_match = true }, spawn_opts = {} }
  opts = vim.tbl_deep_extend('force', default_opts, opts or {})

  local executable, args = command[1], vim.list_slice(command, 2, #command)
  local process, pid, stdout = nil, nil, vim.loop.new_pipe()
  local spawn_opts = vim.tbl_deep_extend('force', opts.spawn_opts, { args = args, stdio = { nil, stdout, nil } })
  if type(spawn_opts.cwd) == 'string' then spawn_opts.cwd = vim.fn.fnamemodify(spawn_opts.cwd, ':p') end
  process, pid = vim.loop.spawn(executable, spawn_opts, function() process:close() end)

  local data_feed = {}
  stdout:read_start(function(err, data)
    assert(not err, err)
    if data then return table.insert(data_feed, data) end

    local items = vim.split(table.concat(data_feed), '\n')
    items, data_feed = opts.postprocess(items), nil
    stdout:close()
    vim.schedule(function() MiniPick.set_picker_items(items, opts.set_items_opts) end)
  end)

  return process, pid
end

---@seealso |MiniPick.get_picker_matches()|
MiniPick.set_picker_match_inds = function(match_inds, target_query)
  if not vim.tbl_islist(match_inds) then H.error('`match_inds` should be list.') end
  if target_query ~= nil and not vim.tbl_islist(target_query) then H.error('`target_query` should be list.') end
  if not MiniPick.is_picker_active() then return end

  H.picker_set_match_inds(H.pickers.active, match_inds, target_query)
  H.picker_update(H.pickers.active, false)
end

---@seealso |MiniPick.get_picker_opts()|
MiniPick.set_picker_opts = function(opts)
  if not MiniPick.is_picker_active() then return end
  H.pickers.active.opts = vim.tbl_deep_extend('force', H.pickers.active.opts, opts or {})
end

---@seealso |MiniPick.get_picker_state()|
MiniPick.set_picker_target_window = function(win_id)
  if not (MiniPick.is_picker_active() and H.is_valid_win(win_id)) then return end
  H.pickers.active.windows.target = win_id
end

---@seealso |MiniPick.get_picker_query()|
MiniPick.set_picker_query = function(query)
  if not vim.tbl_islist(query) then H.error('`query` should be list.') end
  if not MiniPick.is_picker_active() then return end

  H.pickers.active.query, H.pickers.active.caret = query, #query + 1
  local all_inds = H.seq_along(MiniPick.get_picker_items())
  H.picker_set_match_inds(H.pickers.active, all_inds, query)
  H.picker_update(H.pickers.active, true)
end

--- Get query tick
MiniPick.get_querytick = function() return H.querytick end

---@seealso |MiniPick.poke_is_picker_active()|
MiniPick.is_picker_active = function() return H.pickers.active ~= nil end

---@seealso |MiniPick.is_picker_active()|
MiniPick.poke_is_picker_active = function()
  local co = coroutine.running()
  if co == nil then return MiniPick.is_picker_active() end
  H.schedule_resume_is_active(co)
  return coroutine.yield()
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniPick.config

-- Namespaces
H.ns_id = {
  current = vim.api.nvim_create_namespace('MiniPickCurrent'),
  offsets = vim.api.nvim_create_namespace('MiniPickOffsets'),
  headers = vim.api.nvim_create_namespace('MiniPickHeaders'),
  preview = vim.api.nvim_create_namespace('MiniPickPreview'),
}

-- Timers
H.timers = {
  getcharstr = vim.loop.new_timer(),
  busy = vim.loop.new_timer(),
}

-- Pickers
H.pickers = { active = nil, latest = nil }

-- Picker-independent counter of query updates
H.querytick = 0

-- General purpose cache
H.cache = {}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    content = { config.content, 'table' },
    delay = { config.delay, 'table' },
    mappings = { config.mappings, 'table' },
    window = { config.window, 'table' },
  })

  vim.validate({
    ['content.match'] = { config.content.match, 'function', true },
    ['content.show'] = { config.content.show, 'function', true },
    ['content.direction'] = { config.content.direction, 'string' },
    ['content.use_cache'] = { config.content.use_cache, 'boolean' },

    ['delay.async'] = { config.delay.async, 'number' },
    ['delay.busy'] = { config.delay.busy, 'number' },

    ['mappings.caret_left'] = { config.mappings.caret_left, 'string' },
    ['mappings.caret_right'] = { config.mappings.caret_right, 'string' },
    ['mappings.choose'] = { config.mappings.choose, 'string' },
    ['mappings.choose_all'] = { config.mappings.choose_all, 'string' },
    ['mappings.choose_in_split'] = { config.mappings.choose_in_split, 'string' },
    ['mappings.choose_in_tabpage'] = { config.mappings.choose_in_tabpage, 'string' },
    ['mappings.choose_in_vsplit'] = { config.mappings.choose_in_vsplit, 'string' },
    ['mappings.delete_char'] = { config.mappings.delete_char, 'string' },
    ['mappings.delete_char_right'] = { config.mappings.delete_char_right, 'string' },
    ['mappings.delete_left'] = { config.mappings.delete_left, 'string' },
    ['mappings.delete_word'] = { config.mappings.delete_word, 'string' },
    ['mappings.move_down'] = { config.mappings.move_down, 'string' },
    ['mappings.move_start'] = { config.mappings.move_start, 'string' },
    ['mappings.move_up'] = { config.mappings.move_up, 'string' },
    ['mappings.paste'] = { config.mappings.paste, 'string' },
    ['mappings.refine'] = { config.mappings.refine, 'string' },
    ['mappings.scroll_down'] = { config.mappings.scroll_down, 'string' },
    ['mappings.scroll_up'] = { config.mappings.scroll_up, 'string' },
    ['mappings.scroll_left'] = { config.mappings.scroll_left, 'string' },
    ['mappings.scroll_right'] = { config.mappings.scroll_right, 'string' },
    ['mappings.stop'] = { config.mappings.stop, 'string' },
    ['mappings.toggle_info'] = { config.mappings.toggle_info, 'string' },
    ['mappings.toggle_preview'] = { config.mappings.toggle_preview, 'string' },

    ['source.items'] = { config.source.items, 'table', true },
    ['source.name'] = { config.source.name, 'string', true },
    ['source.cwd'] = { config.source.cwd, 'string', true },
    ['source.preview'] = { config.source.preview, 'function', true },
    ['source.choose'] = { config.source.choose, 'function', true },
    ['source.choose_all'] = { config.source.choose_all, 'function', true },

    ['window.config'] = {
      config.window.config,
      function(x) return x == nil or type(x) == 'table' or vim.is_callable(x) end,
      'table or callable',
    },
  })

  return config
end

H.apply_config = function(config) MiniPick.config = config end

H.get_config =
  function(config) return vim.tbl_deep_extend('force', MiniPick.config, vim.b.minipick_config or {}, config or {}) end

H.create_autocommands = function(config)
  local augroup = vim.api.nvim_create_augroup('MiniPick', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = augroup, pattern = pattern, callback = callback, desc = desc })
  end

  au('VimResized', '*', MiniPick.refresh, 'Refresh on resize')
end

--stylua: ignore
H.create_default_hl = function()
  local hi = function(name, opts)
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end

  hi('MiniPickBorder',        { link = 'FloatBorder' })
  hi('MiniPickBorderBusy',    { link = 'DiagnosticFloatingWarn' })
  hi('MiniPickBorderText',    { link = 'FloatTitle' })
  hi('MiniPickIconDirectory', { link = 'Directory' })
  hi('MiniPickIconFile',      { link = 'MiniPickNormal' })
  hi('MiniPickHeader',        { link = 'DiagnosticFloatingHint' })
  hi('MiniPickMatchCurrent',  { link = 'CursorLine' })
  hi('MiniPickMatchOffsets',  { link = 'DiagnosticFloatingHint' })
  hi('MiniPickNormal',        { link = 'NormalFloat' })
  hi('MiniPickPreviewLine',   { link = 'CursorLine' })
  hi('MiniPickPreviewRegion', { link = 'IncSearch' })
  hi('MiniPickPrompt',        { link = 'DiagnosticFloatingInfo' })
end

-- Picker object --------------------------------------------------------------
H.validate_picker_opts = function(opts)
  opts = vim.deepcopy(H.get_config(opts))

  local validate_callable = function(x, x_name)
    if not vim.is_callable(x) then H.error(string.format('`%s` should be callable.', x_name)) end
  end

  -- Source
  local source = opts.source

  local items = source.items or {}
  local is_valid_items = vim.tbl_islist(items) or vim.is_callable(items)
  if not is_valid_items then H.error('`source.items` should be list or callable.') end

  source.name = tostring(source.name or '<No name>')

  source.cwd = type(source.cwd) == 'string' and vim.fn.fnamemodify(source.cwd, ':p') or vim.fn.getcwd()
  if vim.fn.isdirectory(source.cwd) == 0 then H.error('`source.cwd` should be a valid directory path.') end

  source.preview = source.preview or MiniPick.default_preview
  validate_callable(source.preview, 'source.preview')

  source.choose = source.choose or MiniPick.default_choose
  validate_callable(source.choose, 'source.choose')

  source.choose_all = source.choose_all or MiniPick.default_choose_all
  validate_callable(source.choose_all, 'source.choose_all')

  -- Content
  local content = opts.content
  content.match = content.match or MiniPick.default_match
  validate_callable(content.match, 'content.match')

  content.show = content.show or MiniPick.default_show
  validate_callable(content.show, 'content.show')

  local is_valid_direction = content.direction == 'from_top' or content.direction == 'from_bottom'
  if not is_valid_direction then H.error('`content.direction` should be one of "from_top" or "from_bottom".') end

  if type(content.use_cache) ~= 'boolean' then H.error('`content.use_cache` should be boolean.') end

  -- Delay
  for key, value in pairs(opts.delay) do
    local is_valid_value = type(value) == 'number' and value > 0
    if not is_valid_value then H.error(string.format('`delay.%s` should be a positive number.', key)) end
  end

  -- Mappings
  for key, x in pairs(opts.mappings) do
    if type(key) ~= 'string' then H.error('`mappings` should have only string fields.') end
    local ok = type(x) == 'string' or (type(x) == 'table' and type(x.char) == 'string' and vim.is_callable(x.func))
    if not ok then H.error(string.format('`mappings["%s"]` should be string or table with `char` and `func`.', key)) end
  end

  -- Window
  local win_config = opts.window.config
  local is_valid_winconfig = win_config == nil or type(win_config) == 'table' or vim.is_callable(win_config)
  if not is_valid_winconfig then H.error('`window.config` should be table or callable.') end

  return opts
end

H.picker_new = function(opts)
  -- Create buffer
  local buf_id = H.picker_new_buf()

  -- Create window
  local win_id = H.picker_new_win(buf_id, opts.window.config)

  -- Constuct and return object
  local picker = {
    -- Permanent data about picker (should not change)
    opts = opts,

    -- Items to pick from
    items = nil,
    stritems = nil,
    stritems_ignorecase = nil,

    -- Associated Neovim objects
    buffers = { main = buf_id, preview = nil, info = nil },
    windows = { main = win_id, target = vim.api.nvim_get_current_win() },

    -- Query data
    query = {},
    -- - Query index at which new entry will be inserted
    caret = 1,
    -- - Array of `stritems` indexes matching current query
    match_inds = nil,

    -- Whether picker is currently busy processing data
    is_busy = false,

    -- Cache for `matches` per prompt for more performant querying
    cache = {},

    -- View data
    -- - Which buffer should currently be shown
    view_state = 'main',

    -- - Index range of `match_inds` currently visible. Present for significant
    --   performance increase to render only what is visible.
    visible_range = { from = nil, to = nil },

    -- - Index of `match_inds` pointing at current item
    current_ind = nil,
  }

  H.querytick = H.querytick + 1

  -- Set items on next event loop to not block when computing stritems
  H.picker_set_busy(picker, true)
  local items = H.expand_callable(opts.source.items)
  if vim.tbl_islist(items) then vim.schedule(function() MiniPick.set_picker_items(items) end) end

  return picker
end

H.picker_advance = function(picker)
  local char_data = H.picker_get_char_data(picker)

  local do_match, is_aborted = false, false
  while true do
    if H.cache.is_force_stop_advance then break end
    H.picker_update(picker, do_match)

    local char = H.getcharstr()
    if H.cache.is_force_stop_advance then break end

    is_aborted = char == nil
    if is_aborted then break end

    local cur_data = char_data[char] or {}
    do_match = cur_data.name == nil or vim.startswith(cur_data.name, 'delete') or cur_data.name == 'paste'
    is_aborted = cur_data.name == 'stop'

    if cur_data.is_custom then
      cur_data.func()
    else
      local func = cur_data.func or H.picker_query_add
      local should_stop = func(picker, char)
      if should_stop then break end
    end
  end

  local item
  if not is_aborted then item = H.picker_get_current_item(picker) end
  H.cache.is_force_stop_advance = nil
  H.picker_stop(picker)
  return item
end

H.picker_update = function(picker, do_match)
  if do_match then H.picker_match(picker) end
  H.picker_set_bordertext(picker)
  H.picker_set_lines(picker)
  H.redraw()
end

H.picker_new_buf = function()
  local buf_id = vim.api.nvim_create_buf(false, true)
  vim.bo[buf_id].filetype = 'minipick'
  return buf_id
end

H.picker_new_win = function(buf_id, win_config)
  -- Create window without focus. Instead focus cursor on Command line to not
  -- have it seen on top of floating window text.
  local win_id = vim.api.nvim_open_win(buf_id, false, H.picker_compute_win_config(win_config))
  vim.cmd('noautocmd normal! :')

  -- Set window-local data
  vim.wo[win_id].foldenable = false
  vim.wo[win_id].list = true
  vim.wo[win_id].listchars = 'extends:…'
  vim.wo[win_id].wrap = false
  H.win_update_hl(win_id, 'NormalFloat', 'MiniPickNormal')
  H.win_update_hl(win_id, 'FloatBorder', 'MiniPickBorder')

  return win_id
end

H.picker_compute_win_config = function(win_config)
  local has_tabline = vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)
  local has_statusline = vim.o.laststatus > 0
  local max_height = vim.o.lines - vim.o.cmdheight - (has_tabline and 1 or 0) - (has_statusline and 1 or 0)
  local max_width = vim.o.columns

  local default_config = {
    relative = 'editor',
    anchor = 'SW',
    width = math.floor(0.618 * max_width),
    height = math.floor(0.618 * max_height),
    col = 0,
    row = max_height + (has_tabline and 1 or 0),
    border = 'single',
    style = 'minimal',
  }
  local config = vim.tbl_deep_extend('force', default_config, H.expand_callable(win_config) or {})

  -- Tweak config values to ensure they are proper
  if config.border == 'none' then config.border = { ' ' } end
  -- - Account for border
  config.height = math.min(config.height, max_height - 2)
  config.width = math.min(config.width, max_width - 2)

  return config
end

H.picker_set_items = function(picker, items, opts)
  -- Compute string items to work with (along with their lower variants)
  local stritems, stritems_ignorecase = {}, {}
  -- NOTE: optimize `tolower` as it severily reduces start time on many items
  local tolower = vim.o.ignorecase and H.tolower or function(x) return nil end
  local poke_picker = H.poke_picker_throttle(opts.querytick)
  for i, x in ipairs(items) do
    if not poke_picker() then return end
    local to_add = H.item_to_string(x)
    table.insert(stritems, to_add)
    table.insert(stritems_ignorecase, tolower(to_add))
  end

  picker.items, picker.stritems, picker.stritems_ignorecase = items, stritems, stritems_ignorecase
  H.picker_set_busy(picker, false)

  H.picker_set_match_inds(picker, H.seq_along(items), {})
  H.picker_update(picker, opts.do_match)
end

H.item_to_string = function(item)
  item = H.expand_callable(item)
  if type(item) == 'table' then item = item.item end
  return type(item) == 'string' and item or vim.inspect(item, { newline = ' ', indent = '' })
end

H.picker_set_busy = function(picker, value)
  picker.is_busy = value

  local win_id = picker.windows.main
  local new_hl_group = value and 'MiniPickBorderBusy' or 'MiniPickBorder'
  local update_border_hl = function() H.win_update_hl(win_id, 'FloatBorder', new_hl_group) end

  if value then
    H.timers.busy:start(picker.opts.delay.busy, 0, vim.schedule_wrap(update_border_hl))
  else
    H.timers.busy:stop()
    update_border_hl()
  end
end

H.picker_set_match_inds = function(picker, inds, query)
  if inds == nil then return end
  H.picker_set_busy(picker, false)

  picker.match_inds = inds

  local cache_prompt = table.concat(query or picker.query)
  if picker.opts.content.use_cache then picker.cache[cache_prompt] = { inds = inds } end

  -- Always show result of updated matches
  H.picker_show_main(picker)

  -- Reset current index if match indexes are updated
  H.picker_set_current_ind(picker, 1)
end

H.picker_set_current_ind = function(picker, ind, force_update)
  if picker.items == nil or #picker.match_inds == 0 then
    picker.current_ind, picker.visible_range = nil, {}
    return
  end

  -- Wrap index around edges
  local n_matches = #picker.match_inds
  ind = (ind - 1) % n_matches + 1

  -- (Re)Compute visible range (centers current index if it is currently outside)
  local from, to, querytick = picker.visible_range.from, picker.visible_range.to, picker.visible_range.querytick
  local needs_update = H.querytick ~= querytick or from == nil or to == nil or not (from <= ind and ind <= to)
  if (force_update or needs_update) and H.is_valid_win(picker.windows.main) then
    local win_height = vim.api.nvim_win_get_height(picker.windows.main)
    to = math.min(n_matches, math.floor(ind + 0.5 * win_height))
    from = math.max(1, to - win_height + 1)
    to = from + math.min(win_height, n_matches) - 1
  end

  -- Set data
  picker.current_ind = ind
  picker.visible_range = { from = from, to = to, querytick = H.querytick }
end

H.picker_set_lines = function(picker)
  local buf_id, win_id = picker.buffers.main, picker.windows.main
  if not (H.is_valid_buf(buf_id) and H.is_valid_win(win_id)) then return end

  if picker.is_busy then return end

  local visible_range = picker.visible_range
  if picker.items == nil or visible_range.from == nil or visible_range.to == nil then
    picker.opts.content.show({}, buf_id)
    H.clear_namespace(buf_id, H.ns_id.current)
    return
  end

  -- Construct target items
  local items_to_show, items, inds = {}, picker.items, picker.match_inds
  local cur_ind, cur_line = picker.current_ind, nil
  local is_direction_bottom = picker.opts.content.direction == 'from_bottom'
  local from = is_direction_bottom and visible_range.to or visible_range.from
  local to = is_direction_bottom and visible_range.from or visible_range.to
  for i = from, to, (from <= to and 1 or -1) do
    table.insert(items_to_show, items[inds[i]])
    if i == cur_ind then cur_line = #items_to_show end
  end

  local n_empty_top_lines = is_direction_bottom and (vim.api.nvim_win_get_height(win_id) - #items_to_show) or 0
  cur_line = cur_line + n_empty_top_lines

  -- Update visible content accounting for "from_bottom" direction
  picker.opts.content.show(items_to_show, buf_id)
  if n_empty_top_lines > 0 then
    local empty_lines = vim.fn['repeat']({ '' }, n_empty_top_lines)
    vim.api.nvim_buf_set_lines(buf_id, 0, 0, true, empty_lines)
  end

  -- Update current item
  if cur_line > vim.api.nvim_buf_line_count(buf_id) then return end

  H.clear_namespace(buf_id, H.ns_id.current)
  local cur_opts = { end_row = cur_line, end_col = 0, hl_eol = true, hl_group = 'MiniPickMatchCurrent', priority = 201 }
  H.set_extmark(buf_id, H.ns_id.current, cur_line - 1, 0, cur_opts)

  -- Update cursor if showing item matches (needed for 'scroll_{left,right}')
  local is_not_curline = vim.api.nvim_win_get_cursor(win_id)[1] ~= cur_line
  if picker.view_state == 'main' and is_not_curline then vim.api.nvim_win_set_cursor(win_id, { cur_line, 0 }) end
end

H.picker_match = function(picker)
  if picker.items == nil then return end

  -- Try to use cache first
  local prompt_cache
  if picker.opts.content.use_cache then prompt_cache = picker.cache[table.concat(picker.query)] end
  if prompt_cache ~= nil then return H.picker_set_match_inds(picker, prompt_cache.inds) end

  local is_ignorecase = H.query_is_ignorecase(picker.query)
  local stritems = is_ignorecase and picker.stritems_ignorecase or picker.stritems
  local query = is_ignorecase and vim.tbl_map(H.tolower, picker.query) or picker.query

  H.picker_set_busy(picker, true)
  local new_inds = picker.opts.content.match(picker.match_inds, stritems, query)
  H.picker_set_match_inds(picker, new_inds)
end

H.query_is_ignorecase = function(query)
  if not vim.o.ignorecase then return false end
  if not vim.o.smartcase then return true end
  local prompt = table.concat(query, '')
  return vim.fn.match(prompt, '[[:upper:]]') < 0
end

H.picker_get_char_data = function(picker, skip_alternatives)
  local term = H.replace_termcodes
  local res = {}

  -- Use alternative keys for some common actions
  local alt_chars = {}
  if not skip_alternatives then
    --stylua: ignore
    alt_chars = {
      move_down = '<Down>', move_start = '<Home>', move_up = '<Up>', scroll_down = '<PageDown>', scroll_up = '<PageUp>',
    }
  end

  -- Process
  for name, rhs in pairs(picker.opts.mappings) do
    local is_custom = type(rhs) == 'table'
    local char = is_custom and rhs.char or rhs
    local data = { char = char, name = name, func = is_custom and rhs.func or H.actions[name], is_custom = is_custom }
    res[term(char)] = data

    local alt = alt_chars[name]
    if alt ~= nil then res[term(alt)] = data end
  end

  return res
end

H.picker_set_bordertext = function(picker)
  local win_id = picker.windows.main
  if vim.fn.has('nvim-0.9') == 0 or not H.is_valid_win(win_id) then return end

  -- Compute main text managing views separately and truncating from left
  local view_state = picker.view_state
  local config
  if view_state == 'main' then
    local query, caret = picker.query, picker.caret
    local before_caret = table.concat(vim.list_slice(query, 1, caret - 1), '')
    local after_caret = table.concat(vim.list_slice(query, caret, #query), '')
    local prompt_text = '> ' .. before_caret .. '▏' .. after_caret
    local prompt = { { H.win_trim_to_width(win_id, prompt_text), 'MiniPickPrompt' } }
    config = { title = prompt }
  end

  local has_items = picker.items ~= nil
  if view_state == 'preview' and has_items then
    local stritem_cur = picker.stritems[picker.match_inds[picker.current_ind]] or ''
    config = { title = { { H.win_trim_to_width(win_id, stritem_cur), 'MiniPickBorderText' } } }
  end

  if view_state == 'info' then
    config = { title = { { H.win_trim_to_width(win_id, 'Info'), 'MiniPickBorderText' } } }
  end

  -- Compute helper footer only if Neovim version permits and not in busy
  -- picker (otherwise it will flicker number of matches data on char delete)
  if vim.fn.has('nvim-0.10') == 1 and not picker.is_busy then
    local info = H.picker_get_general_info(picker)
    local source_name = string.format(' %s ', info.source_name)
    local inds = string.format(' %s|%s|%s ', info.relative_current_ind, info.n_items_matched, info.n_items_total)
    local win_width, source_width, inds_width =
      vim.api.nvim_win_get_width(win_id), vim.fn.strchars(source_name), vim.fn.strchars(inds)

    local footer = { { source_name, 'MiniPickBorderText' } }
    local n_spaces_between = win_width - (source_width + inds_width)
    if n_spaces_between > 0 then
      footer[2] = { H.win_get_bottom_border(win_id):rep(n_spaces_between), 'MiniPickBorder' }
      footer[3] = { inds, 'MiniPickBorderText' }
    end
    config.footer, config.footer_pos = footer, 'left'

    if picker.opts.content.direction ~= 'from_top' then
      config.title, config.footer = config.footer, config.title
    end
  end

  vim.api.nvim_win_set_config(win_id, config)
  vim.wo[win_id].list = true
end

H.picker_stop = function(picker)
  if picker == nil then return end

  vim.api.nvim_exec_autocmds('User', { pattern = 'MiniPickStop' })

  pcall(vim.api.nvim_set_current_win, picker.windows.target)

  pcall(vim.api.nvim_win_close, picker.windows.main, true)
  pcall(vim.api.nvim_buf_delete, picker.buffers.main, { force = true })
  pcall(vim.api.nvim_buf_delete, picker.buffers.info, { force = true })

  local new_latest = vim.deepcopy(picker)
  H.picker_free(H.pickers.latest)
  H.pickers = { active = nil, latest = new_latest }
  H.querytick = H.querytick + 1
end

H.picker_free = function(picker)
  if picker == nil then return end
  picker.match_inds = nil
  picker.cache = nil
  picker.stritems, picker.stritems_ignorecase = nil, nil
  picker.items = nil
  picker = nil
  vim.schedule(function() collectgarbage('collect') end)
end

--stylua: ignore
H.actions = {
  caret_left  = function(picker, _) H.picker_move_caret(picker, -1) end,
  caret_right = function(picker, _) H.picker_move_caret(picker, 1)  end,

  choose             = function(picker, _) return H.picker_choose(picker, nil)      end,
  choose_all         = function(picker, _)
    local choose_all = picker.opts.source.choose_all
    if not vim.is_callable(choose_all) then return true end
    return not choose_all(MiniPick.get_picker_matches().all)
  end,
  choose_in_split    = function(picker, _) return H.picker_choose(picker, 'split')  end,
  choose_in_tabpage  = function(picker, _) return H.picker_choose(picker, 'tabnew') end,
  choose_in_vsplit   = function(picker, _) return H.picker_choose(picker, 'vsplit') end,

  delete_char       = function(picker, _) H.picker_query_delete(picker, 1)                end,
  delete_char_right = function(picker, _) H.picker_query_delete(picker, 0)                end,
  delete_left       = function(picker, _) H.picker_query_delete(picker, picker.caret - 1) end,
  delete_word = function(picker, _)
    local init, n_del = picker.caret - 1, 0
    if init == 0 then return end
    local ref_is_keyword = vim.fn.match(picker.query[init], '[[:keyword:]]') >= 0
    for i = init, 1, -1 do
      local cur_is_keyword = vim.fn.match(picker.query[i], '[[:keyword:]]') >= 0
      if (ref_is_keyword and not cur_is_keyword) or (not ref_is_keyword and cur_is_keyword) then break end
      n_del = n_del + 1
    end
    H.picker_query_delete(picker, n_del)
  end,

  move_down  = function(picker, _) H.picker_move_current(picker, 1)  end,
  move_start = function(picker, _) H.picker_move_current(picker, nil, 1)  end,
  move_up    = function(picker, _) H.picker_move_current(picker, -1) end,

  paste = function(picker, _)
    local register = H.getcharstr()
    local has_register, reg_contents = pcall(vim.fn.getreg, register)
    if not has_register then return end
    for i = 1, vim.fn.strchars(reg_contents) do
      H.picker_query_add(picker, vim.fn.strcharpart(reg_contents, i - 1, 1))
    end
  end,

  refine = function(picker, _)
    if picker.items == nil then return end

    -- Make current matches be new items to be matched with default match
    picker.opts.content.match = H.get_config().content.match or MiniPick.default_match
    picker.query, picker.caret = {}, 1
    MiniPick.set_picker_items(MiniPick.get_picker_matches().all)

    picker._refine = picker._refine or { orig_name = picker.opts.source.name, count = 0 }
    picker._refine.count = picker._refine.count + 1
    local count_suffix = picker._refine.count == 1 and '' or (' ' .. picker._refine.count)
    picker.opts.source.name = string.format('%s (Refine%s)', picker._refine.orig_name, count_suffix)
  end,

  scroll_down  = function(picker, _) H.picker_scroll(picker, 'down')  end,
  scroll_up    = function(picker, _) H.picker_scroll(picker, 'up')    end,
  scroll_left  = function(picker, _) H.picker_scroll(picker, 'left')  end,
  scroll_right = function(picker, _) H.picker_scroll(picker, 'right') end,

  toggle_info = function(picker, _)
    if picker.view_state == 'info' then return H.picker_show_main(picker) end
    H.picker_show_info(picker)
  end,

  toggle_preview = function(picker, _)
    if picker.view_state == 'preview' then return H.picker_show_main(picker) end
    H.picker_show_preview(picker)
  end,

  stop = function(_, _) return true end,
}

H.picker_query_add = function(picker, char)
  -- Determine if it **is** proper single character
  if vim.fn.strchars(char) > 1 or vim.fn.char2nr(char) <= 31 then return end
  table.insert(picker.query, picker.caret, char)
  picker.caret = picker.caret + 1
  H.querytick = H.querytick + 1
end

H.picker_query_delete = function(picker, n)
  local delete_to_left = n > 0
  local left = delete_to_left and math.max(picker.caret - n, 1) or picker.caret
  local right = delete_to_left and picker.caret - 1 or math.min(picker.caret + n, #picker.query)
  for i = right, left, -1 do
    table.remove(picker.query, i)
  end
  picker.caret = left
  H.querytick = H.querytick + 1

  -- Deleting query character increases number of possible matches, so need to
  -- reset already matched indexes prior deleting. Use cache to speed this up.
  if picker.items ~= nil then picker.match_inds = H.seq_along(picker.items) end
end

H.picker_choose = function(picker, pre_command)
  if picker.items == nil then return end
  local choose = picker.opts.source.choose
  if not vim.is_callable(choose) then return true end

  local win_id_target = picker.windows.target
  if pre_command ~= nil and H.is_valid_win(win_id_target) then
    vim.api.nvim_win_call(win_id_target, function()
      vim.cmd(pre_command)
      picker.windows.target = vim.api.nvim_get_current_win()
    end)
  end

  -- Returning nothing, `nil`, or `false` should lead to picker stop
  return not choose(H.picker_get_current_item(picker))
end

H.picker_move_caret = function(picker, n) picker.caret = math.min(math.max(picker.caret + n, 1), #picker.query + 1) end

H.picker_move_current = function(picker, by, to)
  if picker.items == nil then return end
  local n_matches = #picker.match_inds
  if n_matches == 0 then return end

  if to == nil then
    -- Account for content direction
    by = (picker.opts.content.direction == 'from_top' and 1 or -1) * by

    -- Wrap around edges only if current index is at edge
    to = picker.current_ind
    if to == 1 and by < 0 then
      to = n_matches
    elseif to == n_matches and by > 0 then
      to = 1
    else
      to = to + by
    end
    to = math.min(math.max(to, 1), n_matches)
  end

  H.picker_set_current_ind(picker, to)

  -- Update buffer(s)
  H.picker_set_lines(picker)
  if picker.view_state == 'info' then H.picker_show_info(picker) end
  if picker.view_state == 'preview' then H.picker_show_preview(picker) end
end

H.picker_scroll = function(picker, direction)
  if picker.items == nil then return end
  local win_id = picker.windows.main
  if picker.view_state == 'main' and (direction == 'down' or direction == 'up') then
    local n = (direction == 'down' and 1 or -1) * vim.api.nvim_win_get_height(win_id)
    H.picker_move_current(picker, n)
  else
    local keys = ({ down = '<C-f>', up = '<C-b>', left = 'zH', right = 'zL' })[direction]
    vim.api.nvim_win_call(win_id, function() vim.cmd('normal! ' .. H.replace_termcodes(keys)) end)
  end
end

H.picker_get_current_item = function(picker)
  if picker.items == nil then return nil end
  return picker.items[picker.match_inds[picker.current_ind]]
end

H.picker_show_main = function(picker)
  H.set_winbuf(picker.windows.main, picker.buffers.main)
  picker.view_state = 'main'
end

H.picker_show_info = function(picker)
  -- General information
  local info = H.picker_get_general_info(picker)
  local lines = {
    'General',
    'Source name   │ ' .. info.source_name,
    'Total items   │ ' .. info.n_items_total,
    'Matched items │ ' .. info.n_items_matched,
    'Current index │ ' .. info.relative_current_ind,
  }
  local hl_lines = { 1 }

  local append_char_data = function(data, header)
    if #data == 0 then return end
    table.insert(lines, '')
    table.insert(lines, header)
    table.insert(hl_lines, #lines)

    local width_max = 0
    for _, t in ipairs(data) do
      local desc = t.name:gsub('[%s%p]', ' ')
      t.desc = vim.fn.toupper(desc:sub(1, 1)) .. desc:sub(2)
      t.width = vim.fn.strchars(t.desc)
      width_max = math.max(width_max, t.width)
    end
    table.sort(data, function(a, b) return a.desc < b.desc end)

    for _, t in ipairs(data) do
      table.insert(lines, string.format('%s%s │ %s', t.desc, string.rep(' ', width_max - t.width), t.char))
    end
  end

  local char_data = H.picker_get_char_data(picker, true)
  append_char_data(vim.tbl_filter(function(x) return x.is_custom end, char_data), 'Mappings (custom)')
  append_char_data(vim.tbl_filter(function(x) return not x.is_custom end, char_data), 'Mappings (built-in)')

  -- Manage buffer/window/state
  local buf_id_info = picker.buffers.info
  if not H.is_valid_buf(buf_id_info) then buf_id_info = vim.api.nvim_create_buf(false, true) end
  picker.buffers.info = buf_id_info

  H.set_buflines(buf_id_info, lines)
  H.set_winbuf(picker.windows.main, buf_id_info)
  picker.view_state = 'info'

  local ns_id = H.ns_id.headers
  H.clear_namespace(buf_id_info, ns_id)
  for _, lnum in ipairs(hl_lines) do
    H.set_extmark(buf_id_info, ns_id, lnum - 1, 0, { end_row = lnum, end_col = 0, hl_group = 'MiniPickHeader' })
  end
end

H.picker_get_general_info = function(picker)
  local has_items = picker.items ~= nil
  return {
    source_name = picker.opts.source.name or '---',
    n_items_total = has_items and #picker.items or '-',
    n_items_matched = has_items and #picker.match_inds or '-',
    relative_current_ind = has_items and picker.current_ind or '-',
  }
end

H.picker_show_preview = function(picker)
  local preview = picker.opts.source.preview
  local item = H.picker_get_current_item(picker)
  if not vim.is_callable(preview) or item == nil then return end

  local win_id, buf_id = picker.windows.main, vim.api.nvim_create_buf(false, true)
  vim.bo[buf_id].bufhidden = 'wipe'
  H.set_winbuf(win_id, buf_id)
  preview(item, buf_id)
  picker.buffers.preview = buf_id
  picker.view_state = 'preview'
end

-- Default match --------------------------------------------------------------
H.match_filter = function(inds, stritems, query)
  local n_query = #query
  -- 'abc' and '*abc' - fuzzy match; "'abc" and 'a' - exact substring match;
  -- '^abc' and 'abc$' - exact substring match at start and end.
  local is_fuzzy_forced, is_exact_plain, is_exact_start, is_exact_end =
    query[1] == '*', query[1] == "'", query[1] == '^', query[n_query] == '$'

  local start_offset = (is_fuzzy_forced or is_exact_plain or is_exact_start) and 2 or 1
  local end_offset = (not is_fuzzy_forced and not is_exact_plain and is_exact_end) and (n_query - 1) or n_query
  query = vim.list_slice(query, start_offset, end_offset)
  n_query = #query

  if n_query == 0 then return {}, 'nosort', query end

  -- End-matching filtering doesn't result into nested matches.
  -- Example: type "$", move caret to left, type "m" (filters for "m$") and
  -- type "d" (should filter for "md$" but it is not a subset of "m$" matches).
  inds = is_exact_end and H.seq_along(stritems) or inds

  local is_fuzzy_plain = not (is_exact_plain or is_exact_start or is_exact_end) and n_query > 1
  if is_fuzzy_forced or is_fuzzy_plain then return H.match_filter_fuzzy(inds, stritems, query), 'fuzzy', query end

  local prefix = is_exact_start and '^' or ''
  local suffix = is_exact_end and '$' or ''
  local pattern = prefix .. vim.pesc(table.concat(query)) .. suffix

  return H.match_filter_exact(inds, stritems, query, pattern), 'exact', query
end

H.match_filter_exact = function(inds, stritems, query, pattern)
  local match_single = H.match_filter_exact_single
  local poke_picker = H.poke_picker_throttle(H.querytick)
  local match_data = {}
  for _, ind in ipairs(inds) do
    if not poke_picker() then return nil end
    local data = match_single(stritems[ind], ind, pattern)
    if data ~= nil then table.insert(match_data, data) end
  end

  return match_data
end

H.match_filter_exact_single = function(candidate, index, pattern, rel_offsets)
  local start = string.find(candidate, pattern)
  if start == nil then return nil end

  return { 1, 0, start, index }
end

H.match_offsets_exact = function(match_data, query)
  -- All matches have same match offsets relative to match start
  local rel_offsets = { 0 }
  for i = 2, #query do
    rel_offsets[i] = rel_offsets[i - 1] + query[i - 1]:len()
  end

  local res = {}
  for i = 1, #match_data do
    res[i] = vim.tbl_map(function(x) return match_data[i][3] + x end, rel_offsets)
  end

  return res
end

H.match_filter_fuzzy = function(inds, stritems, query)
  local match_single, find_query = H.match_filter_fuzzy_single, H.find_query
  local poke_picker = H.poke_picker_throttle(H.querytick)
  local match_data = {}
  for _, ind in ipairs(inds) do
    if not poke_picker() then return nil end
    local data = match_single(stritems[ind], ind, query, find_query)
    if data ~= nil then table.insert(match_data, data) end
  end
  return match_data
end

H.match_filter_fuzzy_single = function(candidate, index, query, find_query)
  -- - Candidate is matched if all query chars are present in same order.
  -- - For matched candidate compute information about "best" match: number of
  --   contiguous groups, width, match start, index. Those are listed from most
  --   important to least important.
  --   NOTE: Information is computed not based on **all** possible matches but
  --   only on a small handful (smallest width matches for every possible start
  --   match). It is fine to optimize width but not contiguous groups number.
  --   This is essentially a performance/relevance compromise.
  --   Example: for query {'a', 'b', 'c'} candidate 'aaxbbbc' will be matched as
  --   having 3 groups (indexes 2, 4, 7) but correct one is 2 groups (2, 6, 7).

  -- Search forward to find matching positions with left-most last char match
  local groups, first, last = find_query(candidate, query, 1)
  if groups == nil then return nil end
  if groups == 1 then return { 1, last - first, first, index } end

  -- Iteratively try to find better matches by advancing first match
  local best_groups, best_first, best_last, best_width = groups, first, last, last - first
  while groups do
    local width = last - first
    if groups < best_groups or (groups == best_groups and width < best_width) then
      best_groups, best_first, best_last, best_width = groups, first, last, width
    end

    groups, first, last = find_query(candidate, query, first + 1)
  end

  -- NOTE: No field names is not clear code, but consistently better performant
  return { best_groups, best_last - best_first, best_first, index }
end

H.match_offsets_fuzzy = function(match_data, query, stritems)
  local res, n_query = {}, #query
  for i_match, data in ipairs(match_data) do
    local s, offsets, to = stritems[data[4]], { data[3] }, data[3]
    for j_query = 2, n_query do
      offsets[j_query], to = string.find(s, query[j_query], to + 1, true)
    end
    res[i_match] = offsets
  end
  return res
end

H.find_query = function(s, query, init)
  local first, to = string.find(s, query[1], init, true)
  if first == nil then return nil, nil, nil end

  -- Both `first` and `last` indicate the start byte of first and last match
  local last, groups = first, 1
  for i = 2, #query do
    local prev_to = to
    last, to = string.find(s, query[i], to + 1, true)
    if not last then return nil, nil, nil end
    groups = groups + ((last > prev_to + 1) and 1 or 0)
  end
  return groups, first, last
end

H.match_sort = function(match_data)
  -- Spread indexes in groups-width-start buckets tracking maximum values
  local buckets, max_groups, groups_max_width, groups_width_max_start = {}, 0, {}, {}
  for i = 1, #match_data do
    local data = match_data[i]
    local groups, width, start = data[1], data[2], data[3]
    local buck_groups = buckets[groups] or {}
    local buck_width = buck_groups[width] or {}
    local buck_start = buck_width[start] or {}
    table.insert(buck_start, data[4])
    buck_width[start] = buck_start
    buck_groups[width] = buck_width
    buckets[groups] = buck_groups

    max_groups = math.max(max_groups, groups)
    groups_max_width[groups] = math.max(groups_max_width[groups] or 0, width)

    local width_max_start = groups_width_max_start[groups] or {}
    width_max_start[width] = math.max(width_max_start[width] or 0, start)
    groups_width_max_start[groups] = width_max_start
  end

  -- Sort index in place (to make stable sort) within buckets
  local poke_picker = H.poke_picker_throttle(H.querytick)
  for _, buck_groups in pairs(buckets) do
    for _, buck_width in pairs(buck_groups) do
      for _, buck_start in pairs(buck_width) do
        if not poke_picker() then return nil end
        table.sort(buck_start)
      end
    end
  end

  -- Gather indexes back in order
  local res = {}
  for groups = 1, max_groups do
    local buck_groups = buckets[groups]
    local width_max_start = groups_width_max_start[groups] or {}
    for width = 0, (groups_max_width[groups] or -1) do
      local buck_width = buck_groups[width]
      for start = 1, (width_max_start[width] or 0) do
        local buck_start = buck_width[start] or {}
        for i = 1, #buck_start do
          table.insert(res, buck_start[i])
        end
      end
    end
  end

  return res
end

-- Default show ---------------------------------------------------------------
H.get_icon = function(x)
  local path_type, path = H.parse_path(x)
  if path_type == nil then return { text = '' } end
  if path_type == 'directory' then return { text = ' ', hl = 'MiniPickIconDirectory' } end
  if path_type == 'none' then return { text = '  ', hl = 'MiniPickNormal' } end
  local has_devicons, devicons = pcall(require, 'nvim-web-devicons')
  if not has_devicons then return { text = ' ', hl = 'MiniPickIconFile' } end

  local icon, hl = devicons.get_icon(path, nil, { default = false })
  return { text = (icon or '') .. ' ', hl = hl or 'MiniPickIconFile' }
end

H.show_with_icons = function(items, buf_id) MiniPick.default_show(items, buf_id, { show_icons = true }) end

-- Items helpers for default functions ----------------------------------------
H.parse_item = function(item)
  -- Try parsing table item first
  if type(item) == 'table' then return H.parse_item_table(item) end

  -- Parse item's string representation
  local stritem = H.item_to_string(item)

  -- - Buffer
  local ok, numitem = pcall(tonumber, stritem)
  if ok and H.is_valid_buf(numitem) then return { type = 'buffer', buf_id = numitem } end

  -- File or Directory
  local path_type, path, line, col, rest = H.parse_path(stritem)
  if path_type ~= 'none' then return { type = path_type, path = path, line = line, col = col, text = rest } end

  return {}
end

H.parse_item_table = function(item)
  -- Buffer
  local buf_id = item.buf_id or item.bufnr or item.buf
  if H.is_valid_buf(buf_id) then
    --stylua: ignore
    return {
      type = 'buffer',  buf_id   = buf_id,
      line = item.lnum, line_end = item.end_lnum,
      col  = item.col,  col_end  = item.end_col,
      text = item.text,
    }
  end

  -- File or Directory
  if type(item.path) == 'string' then
    local path_type, path, line, col, rest = H.parse_path(item.path)
    if path_type == 'file' then
      --stylua: ignore
      return {
        type = 'file',            path     = path,
        line = line or item.lnum, line_end = item.end_lnum,
        col  = col or item.col,   col_end  = item.end_col,
        text = rest or item.text,
      }
    end

    if path_type == 'directory' then return { type = 'directory', path = item.path } end
  end

  return {}
end

H.parse_path = function(x)
  if type(x) ~= 'string' or x == '' then return nil end
  -- Allow inputs like 'aa/bb', 'aa/bb:10', 'aa/bb:10:5', 'aa/bb:10:5:xxx'
  -- Should also work for paths like 'aa-5'
  local location_pattern = ':(%d+):?(%d*)(.*)$'
  local line, col, rest = x:match(location_pattern)
  local path = x:gsub(location_pattern, '', 1)

  -- Verify that path is real
  local path_type = H.get_fs_type(path)
  if path_type == 'none' then
    path = string.format('%s/%s', H.get_cwd(), path)
    path_type = H.get_fs_type(path)
  end

  return path_type, path, tonumber(line), tonumber(col), rest or ''
end

H.get_cwd = function()
  if H.pickers.active == nil then return vim.fn.getcwd() end
  return H.pickers.active.opts.source.cwd
end

H.get_fs_type = function(path)
  if path:find('^~') then path = vim.loop.os_homedir() .. path:sub(2) end
  if vim.fn.filereadable(path) == 1 then return 'file' end
  if vim.fn.isdirectory(path) == 1 then return 'directory' end
  return 'none'
end

-- Default preview ------------------------------------------------------------
H.preview_file = function(item_data, buf_id, opts)
  -- Fully preview only text files
  if not H.is_file_text(item_data.path) then return H.set_buflines(buf_id, { '-Non-text-file-' }) end

  -- Compute lines. Limit number of read lines to work better on large files.
  local has_lines, lines = pcall(vim.fn.readfile, item_data.path, '', (item_data.line or 1) + opts.n_context_lines)
  if not has_lines then return end

  item_data.line_position = opts.line_position
  H.preview_set_lines(buf_id, lines, item_data)
end

H.preview_directory = function(item_data, buf_id)
  local path = item_data.path
  local lines = vim.tbl_map(
    function(x) return x .. (vim.fn.isdirectory(path .. '/' .. x) == 1 and '/' or '') end,
    vim.fn.readdir(path)
  )
  H.set_buflines(buf_id, lines)
end

H.preview_buffer = function(item_data, buf_id, opts)
  -- NOTE: ideally just setting target buffer to window would be enough, but it
  -- has side effects. See https://github.com/neovim/neovim/issues/24973 .
  -- Reading lines and applying custom styling is a passable alternative.
  local buf_id_source = item_data.buf_id

  -- Get lines from buffer ensuring it is loaded without important consequences
  local cache_eventignore = vim.o.eventignore
  vim.o.eventignore = 'BufEnter'
  vim.fn.bufload(buf_id_source)
  vim.o.eventignore = cache_eventignore
  local lines = vim.api.nvim_buf_get_lines(buf_id_source, 0, (item_data.line or 1) + opts.n_context_lines, false)

  item_data.filetype, item_data.line_position = vim.bo[buf_id_source].filetype, opts.line_position
  H.preview_set_lines(buf_id, lines, item_data)
end

H.preview_inspect = function(obj, buf_id) H.set_buflines(buf_id, vim.split(vim.inspect(obj), '\n')) end

H.preview_set_lines = function(buf_id, lines, extra)
  -- Lines
  H.set_buflines(buf_id, lines)

  -- Cursor position and window view
  local win_id = MiniPick.get_picker_state().windows.main
  if H.is_valid_win(win_id) then
    pcall(vim.api.nvim_win_set_cursor, win_id, { extra.line or 1, (extra.col or 1) - 1 })
    local pos_keys = ({ top = 'zt', center = 'zz', bottom = 'zb' })[extra.line_position] or 'zt'
    vim.api.nvim_win_call(win_id, function() vim.cmd('normal! ' .. pos_keys) end)
  end

  -- Highlighting
  H.preview_highlight_region(buf_id, extra.line, extra.col, extra.line_end, extra.col_end)

  if vim.fn.has('nvim-0.8') == 1 then
    local ft = extra.filetype or vim.filetype.match({ buf = buf_id, filename = extra.path })
    local has_lang, lang = pcall(vim.treesitter.language.get_lang, ft)
    local has_ts, _ = pcall(vim.treesitter.start, buf_id, has_lang and lang or ft)
    if not has_ts then vim.bo[buf_id].syntax = ft end
  end
end

H.preview_highlight_region = function(buf_id, line, col, line_end, col_end)
  -- Highlight line
  if line == nil then return end
  local hl_line_opts = { end_row = line, end_col = 0, hl_eol = true, hl_group = 'MiniPickPreviewLine', priority = 201 }
  H.set_extmark(buf_id, H.ns_id.preview, line - 1, 0, hl_line_opts)

  -- Highlight position/region
  if col == nil then return end

  local end_row, end_col = line - 1, col
  if line_end ~= nil and col_end ~= nil then
    end_row, end_col = line_end - 1, col_end - 1
  end
  end_col = H.get_next_char_bytecol(vim.fn.getbufline(buf_id, end_row + 1)[1], end_col)

  local hl_region_opts = { end_row = end_row, end_col = end_col, hl_group = 'MiniPickPreviewRegion', priority = 202 }
  H.set_extmark(buf_id, H.ns_id.preview, line - 1, col - 1, hl_region_opts)
end

-- Default choose -------------------------------------------------------------
H.choose_path = function(item_data)
  local win_target = (MiniPick.get_picker_state().windows or {}).target
  if not H.is_valid_win(win_target) then return end

  local path, line, col = item_data.path, item_data.line, item_data.col

  -- Try to use already created buffer, if present. This avoids not needed
  -- `:edit` call and avoids some problems with auto-root from 'mini.misc'.
  local path_buf_id
  for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
    if H.is_valid_buf(buf_id) and vim.api.nvim_buf_get_name(buf_id) == path then path_buf_id = buf_id end
  end

  -- Set buffer in target window
  if path_buf_id ~= nil then
    H.set_winbuf(win_target, path_buf_id)
  else
    -- Use `pcall()` to avoid possible `:edti` errors, like present swap file
    vim.api.nvim_win_call(win_target, function() pcall(vim.cmd, 'edit ' .. vim.fn.fnameescape(path)) end)
  end

  H.choose_set_cursor(win_target, line, col)
end

H.choose_buffer = function(item_data)
  local win_target = (MiniPick.get_picker_state().windows or {}).target
  if not H.is_valid_win(win_target) then return end
  H.set_winbuf(win_target, item_data.buf_id)
  H.choose_set_cursor(win_target, item_data.line, item_data.col)
end

H.choose_print = function(x) print(vim.inspect(x)) end

H.choose_set_cursor = function(win_id, line, col)
  if line == nil then return end
  pcall(vim.api.nvim_win_set_cursor, win_id, { line, (col or 1) - 1 })
  pcall(vim.api.nvim_win_call, win_id, function() vim.cmd('normal! zvzz') end)
end

-- Builtins -------------------------------------------------------------------
H.cli_postprocess = function(items)
  while items[#items] == '' do
    items[#items] = nil
  end
  return items
end

H.is_executable = function(tool)
  if tool == 'fallback' then return true end
  return vim.fn.executable(tool) == 1
end

H.files_get_tool = function()
  if H.is_executable('rg') then return 'rg' end
  if H.is_executable('fd') then return 'fd' end
  if H.is_executable('git') then return 'git' end
  if H.is_executable('find') then return 'find' end
  return 'fallback'
end

H.files_get_command = function(tool)
  if tool == 'rg' then return { 'rg', '--files', '--hidden', '--no-follow', '--color=never', '-g', '!.git' } end
  if tool == 'fd' then return { 'fd', '--type=f', '--hidden', '--no-follow', '--color=never', '--exclude=.git' } end
  if tool == 'git' then return { 'git', 'ls-files', '--cached', '--others', '--exclude-standard' } end
  H.error([[Wrong 'tool' for `files` builtin.]])
end

H.files_fallback_items = function()
  if vim.fn.has('nvim-0.8') == 0 then H.error('Tool "fallback" of `files` builtin needs Neovim>=0.8.') end
  local poke_picker = H.poke_picker_throttle()
  local f = function()
    local items = {}
    for path, path_type in vim.fs.dir('.', { depth = math.huge }) do
      if not poke_picker() then return end
      if path_type == 'file' and H.is_file_text(path) then table.insert(items, path) end
    end
    MiniPick.set_picker_items(items)
  end

  vim.schedule(coroutine.wrap(f))
end

H.grep_get_tool = function()
  if H.is_executable('rg') then return 'rg' end
  if H.is_executable('git') then return 'git' end
  return 'fallback'
end

--stylua: ignore
H.grep_get_command = function(tool, pattern)
  if tool == 'rg' then
    return {
      'rg', '--column', '--line-number', '--no-heading', '--hidden', '--no-follow', '--color=never', '--smart-case',
      '--', pattern,
    }
  end
  if tool == 'git' then
    local res = { 'git', 'grep', '--column', '--line-number', '--color=never', '--', pattern }
    if vim.o.ignorecase then table.insert(res, 6, '--ignore-case') end
    return res
  end
  H.error([[Wrong 'tool' for `grep` builtin.]])
end

H.grep_fallback_items = function(pattern)
  if vim.fn.has('nvim-0.8') == 0 then H.error('Tool "lua" of `grep` builtin needs Neovim>=0.8.') end
  local poke_picker = H.poke_picker_throttle()
  local f = function()
    local files = {}
    for path, path_type in vim.fs.dir('.', { depth = math.huge }) do
      if not poke_picker() then return end
      if path_type == 'file' and H.is_file_text(path) then table.insert(files, path) end
    end

    local items = {}
    for _, path in ipairs(files) do
      if not poke_picker() then return end
      for lnum, l in ipairs(vim.fn.readfile(path)) do
        local col = string.find(l, pattern)
        if col ~= nil then table.insert(items, string.format('%s:%d:%d:%s', path, lnum, col, l)) end
      end
    end

    MiniPick.set_picker_items(items)
  end

  vim.schedule(coroutine.wrap(f))
end

-- Async ----------------------------------------------------------------------
H.schedule_resume_is_active = vim.schedule_wrap(function(co) coroutine.resume(co, MiniPick.is_picker_active()) end)

H.poke_picker_every_n = function(n, querytick_ref)
  local count, dont_check_querytick = 0, querytick_ref == nil
  return function()
    count = count + 1
    if count < n then return true end
    count = 0
    -- Return positive if picker is active and no query updates (if asked)
    return MiniPick.poke_is_picker_active() and (dont_check_querytick or querytick_ref == H.querytick)
  end
end

H.poke_picker_throttle = function(querytick_ref)
  local latest_time, dont_check_querytick = vim.loop.hrtime(), querytick_ref == nil
  local threshold = 1000000 * H.get_config().delay.async
  local hrtime = vim.loop.hrtime
  return function()
    local now = hrtime()
    if (now - latest_time) < threshold then return true end
    latest_time = now
    -- Return positive if picker is active and no query updates (if asked)
    return MiniPick.poke_is_picker_active() and (dont_check_querytick or querytick_ref == H.querytick)
  end
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.pick) %s', msg), 0) end

H.is_valid_buf = function(buf_id) return type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id) end

H.is_valid_win = function(win_id) return type(win_id) == 'number' and vim.api.nvim_win_is_valid(win_id) end

H.set_buflines = function(buf_id, lines) pcall(vim.api.nvim_buf_set_lines, buf_id, 0, -1, false, lines) end

H.set_winbuf = function(win_id, buf_id) vim.api.nvim_win_set_buf(win_id, buf_id) end

H.set_extmark = function(...) pcall(vim.api.nvim_buf_set_extmark, ...) end

H.clear_namespace = function(buf_id, ns_id) pcall(vim.api.nvim_buf_clear_namespace, buf_id, ns_id, 0, -1) end

H.replace_termcodes = function(x)
  if x == nil then return nil end
  return vim.api.nvim_replace_termcodes(x, true, true, true)
end

H.expand_callable = function(x)
  if vim.is_callable(x) then return x() end
  return x
end

H.redraw = function() vim.cmd('redraw') end

H.redraw_scheduled = vim.schedule_wrap(H.redraw)

H.getcharstr = function()
  -- Ensure that redraws still happen
  H.timers.getcharstr:start(0, H.get_config().delay.async, H.redraw_scheduled)
  H.cache.is_in_getcharstr = true
  local ok, char = pcall(vim.fn.getcharstr)
  H.cache.is_in_getcharstr = nil
  H.timers.getcharstr:stop()

  -- Terminate if couldn't get input; on hard-coded <C-c>; on any mouse click
  if not ok or char == '' or char == '\3' or vim.v.mouse_winid ~= 0 then return end
  return char
end

H.tolower = (function()
  -- Cache `tolower` for speed
  local tolower = vim.fn.tolower
  return function(x)
    -- `vim.fn.tolower` can throw errors on bad string (like with '\0')
    local ok, res = pcall(tolower, x)
    return ok and res or string.lower(x)
  end
end)()

H.win_update_hl = function(win_id, new_from, new_to)
  if not H.is_valid_win(win_id) then return end

  local new_entry = new_from .. ':' .. new_to
  local replace_pattern = string.format('(%s:[^,]*)', vim.pesc(new_from))
  local new_winhighlight, n_replace = vim.wo[win_id].winhighlight:gsub(replace_pattern, new_entry)
  if n_replace == 0 then new_winhighlight = new_winhighlight .. ',' .. new_entry end

  -- Use `pcall()` because Neovim<0.8 doesn't allow non-existing highlight
  -- groups inside `winhighlight` (like `FloatTitle` at the time).
  pcall(function() vim.wo[win_id].winhighlight = new_winhighlight end)
end

H.win_trim_to_width = function(win_id, text)
  local win_width = vim.api.nvim_win_get_width(win_id)
  return vim.fn.strcharpart(text, vim.fn.strchars(text) - win_width, win_width)
end

H.win_get_bottom_border = function(win_id)
  local border = vim.api.nvim_win_get_config(win_id).border or {}
  return border[6] or ' '
end

H.seq_along = function(arr)
  if arr == nil then return nil end
  local res = {}
  for i = 1, #arr do
    table.insert(res, i)
  end
  return res
end

H.get_next_char_bytecol = function(line_str, col)
  local utf_index = vim.str_utfindex(line_str, math.min(line_str:len(), col))
  return vim.str_byteindex(line_str, utf_index)
end

H.is_file_text = function(path)
  local fd = vim.loop.fs_open(path, 'r', 1)
  local is_text = vim.loop.fs_read(fd, 1024):find('\0') == nil
  vim.loop.fs_close(fd)
  return is_text
end

return MiniPick
