require('mini-dev.sessions').setup({ directory = '~/.config/nvim/misc/sessions' })

-- -- Default starter
-- require('mini-dev.starter').setup()

-- Test starter
local starter = require('mini-dev.starter')
starter.setup({
  autoopen = true,
  items = {
    starter.section_sessions(5, true),
    starter.section_mru_files(5, false, false),
    starter.section_mru_files(5, true, false),
    _G.test_items,
  },
  content_hooks = {
    starter.get_hook_item_bullets('▊ ', true),
    starter.get_hook_indexing('section', { 'Sessions', 'Section 2' }),
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

local has_minijump = pcall(function()
  require('mini.jump').setup()
end)
if not has_minijump then
  pcall(function()
    require('mini-dev.jump').setup()
  end)
end

local function section_searchcount(args)
  if vim.v.hlsearch == 0 or MiniStatusline.is_truncated(args.trunc_width) then
    return ''
  end
  local s_count = vim.fn.searchcount({ recompute = args.recompute or 1 })
  if s_count.current == nil or s_count.total == 0 then
    return ''
  end

  if s_count.incomplete == 1 then
    return '?/?'
  end

  local total_sign = s_count.total > s_count.maxcount and '>' or ''
  local current_sign = s_count.current > s_count.maxcount and '>' or ''
  return ('%s%d/%s%d'):format(current_sign, s_count.current, total_sign, s_count.total)
end

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
      local searchcount   = section_searchcount({ trunc_width = 75})
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
