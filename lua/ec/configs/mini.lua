require('mini.sessions').setup({ directory = '~/.config/nvim/misc/sessions' })
require('mini.starter').setup()
vim.cmd([[autocmd User MiniStarterOpened setlocal fillchars=eob:\ ]])
vim.cmd([[autocmd User MiniStarterOpened
  \ lua vim.keymap.set(
  \   'n',
  \   '<CR>',
  \   '<Cmd>lua MiniStarter.eval_current_item(); MiniMap.open()<CR>',
  \   { buffer = true }
  \ )]])

require('mini.statusline').setup({
  content = {
    active = function()
      -- stylua: ignore start
      local mode, mode_hl = MiniStatusline.section_mode({ trunc_width = 120 })
      local spell         = vim.wo.spell and (MiniStatusline.is_truncated(120) and 'S' or 'SPELL') or ''
      local wrap          = vim.wo.wrap  and (MiniStatusline.is_truncated(120) and 'W' or 'WRAP')  or ''
      local git           = MiniStatusline.section_git({ trunc_width = 75 })
      -- Default diagnstics icon has some problems displaying in Kitty terminal
      local diagnostics   = MiniStatusline.section_diagnostics({ trunc_width = 75 })
      local filename      = MiniStatusline.section_filename({ trunc_width = 140 })
      local fileinfo      = MiniStatusline.section_fileinfo({ trunc_width = 120 })
      local searchcount   = MiniStatusline.section_searchcount({ trunc_width = 75})
      local location      = MiniStatusline.section_location({ trunc_width = 75 })

      -- Usage of `MiniStatusline.combine_groups()` ensures highlighting and
      -- correct padding with spaces between groups (accounts for 'missing'
      -- sections, etc.)
      return MiniStatusline.combine_groups({
        { hl = mode_hl,                  strings = { mode, spell, wrap } },
        { hl = 'MiniStatuslineDevinfo',  strings = { git, diagnostics } },
        '%<', -- Mark general truncate point
        { hl = 'MiniStatuslineFilename', strings = { filename } },
        '%=', -- End left alignment
        { hl = 'MiniStatuslineFileinfo', strings = { fileinfo } },
        { hl = mode_hl,                  strings = { searchcount, location } },
      })
      -- stylua: ignore end
    end,
  },
})
require('mini.tabline').setup()

vim.defer_fn(function()
  require('mini.ai').setup({
    custom_textobjects = {
      F = require('mini.ai').gen_spec.treesitter({ a = '@function.outer', i = '@function.inner' }),
    },
  })
  require('mini.align').setup()
  require('mini.bufremove').setup()
  require('mini.comment').setup()
  require('mini.completion').setup({
    lsp_completion = {
      source_func = 'omnifunc',
      auto_setup = false,
      process_items = function(items, base)
        -- Don't show 'Text' and 'Snippet' suggestions
        items = vim.tbl_filter(function(x) return x.kind ~= 1 and x.kind ~= 15 end, items)
        return MiniCompletion.default_process_items(items, base)
      end,
    },
  })
  require('mini.cursorword').setup()
  require('mini.doc').setup()
  require('mini.indentscope').setup()
  require('mini.jump').setup()
  require('mini.jump2d').setup()

  local gen_integr = require('mini.map').gen_integration
  require('mini.map').setup({
    integrations = { gen_integr.builtin_search(), gen_integr.gitsigns(), gen_integr.diagnostic() },
  })
  for _, key in ipairs({ 'n', 'N', '*' }) do
    vim.keymap.set('n', key, key .. 'zv<Cmd>lua MiniMap.refresh({}, { lines = false, scrollbar = false })<CR>')
  end

  require('mini.misc').setup()
  require('mini.pairs').setup({ modes = { insert = true, command = true, terminal = true } })
  require('mini.surround').setup({ search_method = 'cover_or_next' })
  require('mini.test').setup()
  require('mini.trailspace').setup()

  require('mini-dev.map').setup()
  vim.keymap.set('n', '<Leader>mc', MiniMap.close)
  vim.keymap.set('n', '<Leader>mf', MiniMap.toggle_focus)
  vim.keymap.set('n', '<Leader>mo', MiniMap.open)
  vim.keymap.set('n', '<Leader>mr', MiniMap.refresh)
  vim.keymap.set('n', '<Leader>ms', MiniMap.toggle_side)
  vim.keymap.set('n', '<Leader>mt', MiniMap.toggle)
end, 0)
