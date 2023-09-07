-- TODO:
--
-- - 'mini.pick':
--     - Try to match with built-ins of Telescope and Fzf-Lua.
--     - Adapter for Telescope "native" sorters.
--     - Adapter for Telescope extensions.
--
-- - 'mini.clue':
--     - Clues for 'mini.surround' and 'mini.ai'.
--
-- - 'mini.surround':
--     - Lua string spec.
--
-- - 'mini.ai':
--     - Line.
--     - Buffer.
--
-- Tests:
--
--
-- Docs:
--

--- *mini.extra* Extra 'mini.nvim' functionality
--- *MiniExtra*
---
--- MIT License Copyright (c) 2023 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Features:
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.extra').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniExtra`
--- which you can use for scripting or manually (with `:lua MiniExtra.*`).
---
--- See |MiniExtra.config| for available config settings.
---
--- This module doesn't have runtime options, so using `vim.b.minimisc_config`
--- will have no effect here.
---
--- # Comparisons ~
---
--- - 'chrisgrieser/nvim-various-textobjs':

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local
---@diagnostic disable:cast-local-type

-- Module definition ==========================================================
MiniExtra = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniExtra.config|.
---
---@usage `require('mini.pick').setup({})` (replace `{}` with your `config` table).
MiniExtra.setup = function(config)
  -- Export module
  _G.MiniExtra = MiniExtra

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
MiniExtra.config = {}
--minidoc_afterlines_end

MiniExtra.pickers = {}

-- TODO: Make respect `cwd`
MiniExtra.pickers.diagnostic = function(local_opts, opts)
  local_opts = vim.tbl_deep_extend('force', { bufnr = nil, get_opts = {}, sort_by_severity = true }, local_opts or {})

  local plus_one = function(x)
    if x == nil then return nil end
    return x + 1
  end

  local items = vim.diagnostic.get(local_opts.bufnr, local_opts.get_opts)
  -- NOTE: Account for output of `vim.diagnostic.get()` being  modifiable:
  -- https://github.com/neovim/neovim/pull/25010
  if vim.fn.has('nvim-0.10') == 0 then items = vim.deepcopy(items) end
  if local_opts.sort_by_severity then
    table.sort(items, function(a, b) return (a.severity or 0) < (b.severity or 0) end)
  end

  -- Compute final path width
  local path_width = 0
  for _, item in ipairs(items) do
    item.path = ''
    if H.is_valid_buf(item.bufnr) then item.path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(item.bufnr), ':.') end
    path_width = math.max(path_width, vim.fn.strchars(item.path))
  end

  -- Update items
  for _, item in ipairs(items) do
    local severity = vim.diagnostic.severity[item.severity] or ' '
    local text = item.message:gsub('\n', ' ')
    item.item = string.format('%s │ %s │ %s', severity:sub(1, 1), H.ensure_text_width(item.path, path_width), text)
    item.lnum, item.col, item.end_lnum, item.end_col =
      plus_one(item.lnum), plus_one(item.col), plus_one(item.end_lnum), plus_one(item.end_col)
    item.text = string.format('%s %s', severity, text)
  end

  local hl_groups_ref = {
    [vim.diagnostic.severity.ERROR] = 'DiagnosticFloatingError',
    [vim.diagnostic.severity.WARN] = 'DiagnosticFloatingWarn',
    [vim.diagnostic.severity.INFO] = 'DiagnosticFloatingInfo',
    [vim.diagnostic.severity.HINT] = 'DiagnosticFloatingHint',
  }

  local show = function(items_to_show, buf_id)
    local lines, hl_groups = {}, {}
    for _, item in ipairs(items_to_show) do
      table.insert(lines, item.item)
      table.insert(hl_groups, hl_groups_ref[item.severity])
    end

    vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
    for i = 1, #lines do
      H.pickers_highlight_line(buf_id, i, hl_groups[i])
    end
  end

  local default_opts = { source = { items = items, name = 'Diagnostic' }, content = { show = show } }
  opts = vim.tbl_deep_extend('force', default_opts, opts or {})
  return MiniPick.start(opts)
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniExtra.config

-- Namespaces
H.ns_id = {
  pickers = vim.api.nvim_create_namespace('MiniExtraPickers'),
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config) end

H.apply_config = function(config) MiniExtra.config = config end

-- Pickers --------------------------------------------------------------------
H.pickers_highlight_line = function(buf_id, line, hl_group)
  local opts = { end_row = line, end_col = 0, hl_mode = 'combine', hl_group = hl_group, priority = 199 }
  vim.api.nvim_buf_set_extmark(buf_id, H.ns_id.pickers, line - 1, 0, opts)
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.pick) %s', msg), 0) end

H.is_valid_buf = function(buf_id) return type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id) end

H.ensure_text_width = function(text, width)
  local text_width = vim.fn.strchars(text)
  if text_width <= width then return text .. string.rep(' ', width - text_width) end
  return '…' .. vim.fn.strcharpart(text, text_width - width + 1, width - 1)
end

return MiniExtra
