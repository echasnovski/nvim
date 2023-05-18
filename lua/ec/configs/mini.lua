require('mini.sessions').setup({ directory = vim.fn.stdpath('config') .. '/misc/sessions' })

require('mini.starter').setup()
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

vim.schedule(function()
  local ai = require('mini.ai')
  ai.setup({
    custom_textobjects = {
      F = ai.gen_spec.treesitter({ a = '@function.outer', i = '@function.inner' }),
    },
  })

  require('mini.align').setup()

  require('mini.animate').setup()

  require('mini.basics').setup({
    options = {
      -- Manage options manually
      basic = false,
    },
    mappings = {
      windows = true,
      move_with_alt = true,
    },
    autocommands = {
      relnum_in_visual_mode = true,
    },
  })

  require('mini.bracketed').setup()

  require('mini.bufremove').setup()

  -- Don't really need it on daily basis
  -- require('mini.colors').setup()

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
    window = {
      info = { border = 'double' },
      signature = { border = 'double' },
    },
  })

  require('mini.cursorword').setup()

  require('mini.doc').setup()

  require('mini.indentscope').setup()

  require('mini.jump').setup()

  require('mini.jump2d').setup()

  local map = require('mini.map')
  local gen_integr = map.gen_integration
  local encode_symbols = map.gen_encode_symbols.block('3x2')
  -- Use dots in `st` terminal because it can render them as blocks
  if vim.startswith(vim.fn.getenv('TERM'), 'st') then encode_symbols = map.gen_encode_symbols.dot('4x2') end
  map.setup({
    symbols = { encode = encode_symbols },
    integrations = { gen_integr.builtin_search(), gen_integr.gitsigns(), gen_integr.diagnostic() },
  })
  for _, key in ipairs({ 'n', 'N', '*' }) do
    vim.keymap.set('n', key, key .. 'zv<Cmd>lua MiniMap.refresh({}, { lines = false, scrollbar = false })<CR>')
  end

  require('mini.misc').setup({ make_global = { 'put', 'put_text', 'stat_summary', 'bench_time' } })
  MiniMisc.setup_auto_root()

  require('mini.move').setup({ options = { reindent_linewise = false } })

  require('mini.pairs').setup({ modes = { insert = true, command = true, terminal = true } })
  vim.keymap.set('i', '<CR>', 'v:lua.EC.cr_action()', { expr = true })

  require('mini.splitjoin').setup()

  require('mini.surround').setup({ search_method = 'cover_or_next' })

  local test = require('mini.test')
  local reporter = test.gen_reporter.buffer({ window = { border = 'double' } })
  test.setup({
    execute = { reporter = reporter },
  })

  require('mini.trailspace').setup()

  local ok, hipatterns = pcall(require, 'mini-dev.hipatterns')
  if ok then
    local gen_hi = hipatterns.gen_highlighter

    -- local gen_indent_pattern = function(n)
    --   return function()
    --     local pad = vim.bo.expandtab and string.rep(' ', vim.fn.shiftwidth()) or '\t'
    --     return string.format('^%s()%s()', pad:rep(n - 1), pad)
    --   end
    -- end

    hipatterns.setup({
      highlighters = {
        abcd = gen_hi.pattern('abcd', 'Search', {
          filter = function(buf_id) return vim.bo[buf_id].filetype ~= 'lua' end,
        }),
        more_less = {
          pattern = function(buf_id) return vim.api.nvim_buf_line_count(buf_id) > 300 and 'MORE' or 'LESS' end,
          group = function(buf_id, match) return match == 'MORE' and 'DiagnosticError' or 'DiagnosticInfo' end,
          priority = 200,
        },

        fixme = gen_hi.pattern('%f[%w]()FIXME()%f[%W]', 'MiniHipatternsFixme'),
        hack = gen_hi.pattern('%f[%w]()HACK()%f[%W]', 'MiniHipatternsHack'),
        todo = gen_hi.pattern('%f[%w]()TODO()%f[%W]', 'MiniHipatternsTodo'),
        note = gen_hi.pattern('%f[%w]()NOTE()%f[%W]', 'MiniHipatternsNote'),

        hex_color = gen_hi.hex_color(),

        -- trailspace = gen_hi.pattern('%f[%s]%s*$', 'Error'),

        -- indent_level1 = { pattern = gen_indent_pattern(1), group = 'MiniHipatternsNote' },
        -- indent_level2 = { pattern = gen_indent_pattern(2), group = 'MiniHipatternsTodo' },
        -- indent_level3 = { pattern = gen_indent_pattern(3), group = 'MiniHipatternsHack' },
        -- indent_level4 = { pattern = gen_indent_pattern(4), group = 'MiniHipatternsFixme' },
      },
    })
  end
end)
