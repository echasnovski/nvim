-- Monkey patch `vim.pack.add` for compatibility with Neovim<0.12 to only
-- load plugins. Manage them (install, update, delete) on Neovim>=0.12.
if vim.fn.has('nvim-0.12') == 0 then
  vim.pack = {}
  vim.pack.add = function(specs, opts)
    specs = vim.tbl_map(function(s) return type(s) == 'string' and { src = s } or s end, specs)
    opts = vim.tbl_extend('force', { load = vim.v.did_init == 1 }, opts or {})

    local cmd_prefix = 'packadd' .. (opts.load and '' or '!')
    for _, s in ipairs(specs) do
      local name = s.name or s.src:match('/([^/]+)$')
      vim.cmd(cmd_prefix .. name)
    end
  end
end

-- Install 'mini.nvim'
vim.pack.add({ 'https://github.com/nvim-mini/mini.nvim' })

-- Set up 'mini.deps' immediately to have its `now()` and `later()` helpers
require('mini.deps').setup()

-- Define main config table to be able to pass data between scripts
_G.Config = {}

-- Define custom autocommand group
local gr = vim.api.nvim_create_augroup('custom-config', {})
_G.Config.new_autocmd = function(event, pattern, callback, desc)
  local opts = { group = gr, pattern = pattern, callback = callback, desc = desc }
  vim.api.nvim_create_autocmd(event, opts)
end

-- Define custom `vim.pack.add()` hook helper
_G.Config.on_packchanged = function(plugin_name, kinds, callback, desc)
  if vim.fn.has('nvim-0.12') == 0 then return end
  local f = function(ev)
    local name, kind = ev.data.spec.name, ev.data.kind
    if not (name == plugin_name and vim.tbl_contains(kinds, kind)) then return end
    if not ev.data.active then vim.cmd.packadd(plugin_name) end
    callback()
  end
  _G.Config.new_autocmd('PackChanged', '*', f, desc)
end

-- Define custom "`now` or `later`" helper
_G.Config.now_if_args = vim.fn.argc(-1) > 0 and MiniDeps.now or MiniDeps.later
