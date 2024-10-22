-- All language servers are expected to be installed with 'mason.vnim'.
-- Currently used ones:
-- - clangd for C/C++
-- - pyright for Python
-- - r_language_server for R
-- - sumneko_lua for Lua
-- - typescript-language-server for Typescript and Javascript

local lspconfig = require('lspconfig')

-- Preconfiguration ===========================================================
local on_attach_custom = function(client, buf_id)
  vim.bo[buf_id].omnifunc = 'v:lua.MiniCompletion.completefunc_lsp'

  -- Mappings are created globally for simplicity

  -- Currently all formatting is handled with 'null-ls' plugin
  if vim.fn.has('nvim-0.8') == 1 then
    client.server_capabilities.documentFormattingProvider = false
    client.server_capabilities.documentRangeFormattingProvider = false
  else
    client.resolved_capabilities.document_formatting = false
    client.resolved_capabilities.document_range_formatting = false
  end
end

local diagnostic_opts = {
  float = { border = 'double' },
  -- Show gutter sings
  signs = {
    -- With highest priority
    priority = 9999,
    -- Only for warnings and errors
    severity = { min = 'WARN', max = 'ERROR' },
  },
  -- Show virtual text only for errors
  virtual_text = { severity = { min = 'ERROR', max = 'ERROR' } },
  -- Don't update diagnostics when typing
  update_in_insert = false,
}

vim.diagnostic.config(diagnostic_opts)

-- R (r_language_server) ======================================================
lspconfig.r_language_server.setup({
  on_attach = on_attach_custom,
  -- Debounce "textDocument/didChange" notifications because they are slowly
  -- processed (seen when going through completion list with `<C-N>`)
  flags = { debounce_text_changes = 150 },
})

-- Python (pyright) ===========================================================
lspconfig.pyright.setup({ on_attach = on_attach_custom })

-- Lua (sumneko_lua) ==========================================================
local luals_root = vim.fn.stdpath('data') .. '/mason'
if vim.fn.isdirectory(luals_root) == 1 then
  -- if false then
  local sumneko_binary = luals_root .. '/bin/lua-language-server'

  -- Deal with the fact that LuaLS in case of `local a = function()` style
  -- treats both `a` and `function()` as definitions of `a`.
  local filter_line_locations = function(locations)
    add_to_log(locations)
    local present, res = {}, {}
    for _, l in ipairs(locations) do
      local t = present[l.filename] or {}
      if not t[l.lnum] then
        table.insert(res, l)
        t[l.lnum] = true
      end
      present[l.filename] = t
    end
    return res
  end

  local show_location = function(location)
    local buf_id = location.bufnr or vim.fn.bufadd(location.filename)
    vim.bo[buf_id].buflisted = true
    vim.api.nvim_win_set_buf(0, buf_id)
    vim.api.nvim_win_set_cursor(0, { location.lnum, location.col - 1 })
    vim.cmd('normal! zv')
  end

  lspconfig.lua_ls.setup({
    cmd = { sumneko_binary },
    on_attach = function(client, bufnr)
      on_attach_custom(client, bufnr)

      -- Reduce unnecessarily long list of completion triggers for better
      -- `MiniCompletion` experience
      client.server_capabilities.completionProvider.triggerCharacters = { '.', ':' }

      -- Tweak mapping for `vim.lsp.buf_definition` as client-local handlers
      -- are ignored after https://github.com/neovim/neovim/pull/30877
      local unique_definition = function()
        local on_list = function(args)
          local items = filter_line_locations(args.items)
          if #items > 1 then
            vim.fn.setqflist({}, ' ', { title = 'LSP locations', items = items })
            vim.cmd('botright copen')
            return
          end
          show_location(items[1])
        end
        vim.lsp.buf.definition({ on_list = on_list })
      end
      vim.keymap.set('n', '<Leader>ls', unique_definition, { buffer = bufnr, desc = 'Lua source definition' })
    end,
    root_dir = function(fname) return lspconfig.util.root_pattern('.git')(fname) or lspconfig.util.path.dirname(fname) end,
    settings = {
      Lua = {
        runtime = {
          -- Tell the language server which version of Lua you're using (most likely LuaJIT in the case of Neovim)
          version = 'LuaJIT',
          -- Setup your lua path
          path = vim.split(package.path, ';'),
        },
        diagnostics = {
          -- Get the language server to recognize common globals
          globals = { 'vim', 'describe', 'it', 'before_each', 'after_each' },
          disable = { 'need-check-nil' },
          -- Don't make workspace diagnostic, as it consumes too much CPU and RAM
          workspaceDelay = -1,
        },
        workspace = {
          -- Don't analyze code from submodules
          ignoreSubmodules = true,
        },
        -- Do not send telemetry data containing a randomized but unique identifier
        telemetry = {
          enable = false,
        },
      },
    },
  })
end

-- C/C++ (clangd) =============================================================
lspconfig.clangd.setup({ on_attach = on_attach_custom })

-- Typescript (tsserver) ======================================================
lspconfig.tsserver.setup({ on_attach = on_attach_custom })
