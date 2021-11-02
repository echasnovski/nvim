require('mini-dev.sessions').setup({ directory = '~/.config/nvim/misc/sessions' })

local starter = require('mini-dev.starter')
starter.setup({
  autoopen = true,
  items = {
    starter.section_sessions(5, true),
    starter.section_mru_files(5, false, false),
    starter.section_mru_files(5, true, false),
    -- _G.test_items,
  },
  content_hooks = {
    starter.get_hook_item_bullets('▊ ', true),
    starter.get_hook_indexing('section', { 'Sessions' }),
    starter.get_hook_aligning('center', 'center'),
  },
})

-- -- 'vim-startify'
-- local starter = require('mini-dev.starter')
-- starter.setup({
--   evaluate_single = true,
--   items = {
--     {
--       { action = [[enew]], name = 'Edit file', section = 'Actions' },
--       { action = [[quit]], name = 'Quit', section = 'Actions' },
--     },
--     starter.section_mru_files(10, false),
--     starter.section_mru_files(10, true),
--   },
--   content_hooks = {
--     starter.get_hook_item_bullets(),
--     starter.get_hook_indexing('all', { 'Actions' }),
--     starter.get_hook_padding(3, 2),
--   },
-- })

require('mini.statusline').setup({
  content = {
    active = function()
      -- stylua: ignore start
      local mode, mode_hl = MiniStatusline.section_mode({ trunc_width = 120 })
      local spell         = vim.wo.spell and (MiniStatusline.is_truncated(120) and 'S' or 'SPELL') or ''
      local wrap          = vim.wo.wrap  and (MiniStatusline.is_truncated(120) and 'W' or 'WRAP')  or ''
      local git           = MiniStatusline.section_git({ trunc_width = 75 })
      local diagnostics   = MiniStatusline.section_diagnostics({ trunc_width = 75 })
      local filename      = MiniStatusline.section_filename({ trunc_width = 140 })
      local fileinfo      = MiniStatusline.section_fileinfo({ trunc_width = 120 })
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
        { hl = mode_hl,                  strings = { location } },
      })
      -- stylua: ignore end
    end,
  },
})
require('mini.tabline').setup()

vim.defer_fn(function()
  require('mini.bufremove').setup()
  require('mini.comment').setup()
  require('mini.completion').setup({
    lsp_completion = {
      source_func = 'omnifunc',
      auto_setup = false,
      process_items = function(items, base)
        -- Don't show 'Text' and 'Snippet' suggestions
        items = vim.tbl_filter(function(x)
          return x.kind ~= 1 and x.kind ~= 15
        end, items)
        return MiniCompletion.default_process_items(items, base)
      end,
    },
  })
  require('mini.cursorword').setup()
  require('mini.misc').setup()
  require('mini.pairs').setup({ modes = { insert = true, command = true, terminal = true } })
  require('mini.surround').setup()
  require('mini.trailspace').setup()
end, 0)
