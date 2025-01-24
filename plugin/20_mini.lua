local add, now, later = MiniDeps.add, MiniDeps.now, MiniDeps.later

-- Make 'mini.nvim' part of the 'mini-deps-snap'
-- Use 'HEAD' because I personally update it and don't want to follow `main`
add({ name = 'mini.nvim', checkout = 'HEAD' })

-- Step one ===================================================================
now(function() vim.cmd('colorscheme miniwinter') end)

now(function()
  require('mini.basics').setup({
    -- Manage options manually in a spirit of transparency
    options = { basic = false },
    mappings = { windows = true, move_with_alt = true },
    autocommands = { relnum_in_visual_mode = true },
  })
end)

now(function()
  local not_lua_diagnosing = function(notif) return not vim.startswith(notif.msg, 'lua_ls: Diagnosing') end
  local filterout_lua_diagnosing = function(notif_arr)
    return MiniNotify.default_sort(vim.tbl_filter(not_lua_diagnosing, notif_arr))
  end
  require('mini.notify').setup({
    content = { sort = filterout_lua_diagnosing },
    window = { config = { border = 'double' } },
  })
  vim.notify = MiniNotify.make_notify()
end)

now(function() require('mini.sessions').setup() end)

now(function() require('mini.starter').setup() end)

now(function() require('mini.statusline').setup() end)

-- Future 'mini.statuscolumn'
now(function()
  if vim.fn.has('nvim-0.9') == 1 then
    local n_wraps = function(row)
      -- TODO: Use it for better cursor animation with 'wrap' enabled?
      -- NOTE: Include `start_vcol = 0` to not count virtual text above
      return vim.api.nvim_win_text_height(0, { start_row = row, start_vcol = 0, end_row = row }).all - 1
    end

    vim.api.nvim_set_hl(0, 'MiniStatuscolumnBorder', { link = 'LineNr' })
    vim.cmd('au ColorScheme * hi! link MiniStatuscolumnBorder LineNr')

    _G.statuscolumn = function()
      -- add_to_log({ 'statuscolumn', actual = vim.g.actual_curwin, cur = vim.api.nvim_get_current_win() })

      -- TODO: address `signcolumn=auto` and `foldcolumn=auto`
      if not vim.wo.number and vim.wo.signcolumn == 'no' and vim.wo.foldcolumn == '0' then return '' end

      -- TODO: Take a look at why `CursorLineNr` is not combined with extmark
      -- highligting from 'mini.diff'
      -- local is_cur = vim.v.relnum == 0
      -- local line_nr_hl = '%#' .. (is_cur and 'Cursor' or '') .. 'LineNr#'
      local line_nr_hl = ''

      local lnum = vim.v.virtnum == 0 and '%l'
        -- or (vim.v.virtnum < 0 and '•' or (vim.v.virtnum == n_wraps(vim.v.lnum - 1) and '└' or '├'))
        -- or (vim.v.virtnum < 0 and '•' or '↯')
        or (vim.v.virtnum < 0 and '•' or '↳')

      -- Deal with sign widths

      return '%C%s%=' .. line_nr_hl .. lnum .. '%#LineNr#│'
    end
    vim.o.statuscolumn = '%{%v:lua.statuscolumn()%}'
  end
end)

now(function() require('mini.tabline').setup() end)

now(function()
  require('mini.icons').setup({
    use_file_extension = function(ext, _)
      local suf3, suf4 = ext:sub(-3), ext:sub(-4)
      return suf3 ~= 'scm' and suf3 ~= 'txt' and suf3 ~= 'yml' and suf4 ~= 'json' and suf4 ~= 'yaml'
    end,
  })
  MiniIcons.mock_nvim_web_devicons()
  later(MiniIcons.tweak_lsp_kind)
end)

-- Future part of 'mini.detect'
-- TODO: Needs some condition to stop the comb.
_G.detect_bigline = function(threshold)
  threshold = threshold or 1000
  local step = math.floor(0.5 * threshold)
  local cur_line, cur_byte = 1, step
  local byte2line = vim.fn.byte2line
  while cur_line > 0 do
    local test_line = byte2line(cur_byte)
    if test_line == cur_line and #vim.fn.getline(test_line) >= threshold then return cur_line end
    cur_line, cur_byte = test_line, cur_byte + step
  end
  return -1
end

-- Step two ===================================================================
later(function() require('mini.extra').setup() end)

later(function()
  local ai = require('mini.ai')
  ai.setup({
    custom_textobjects = {
      B = MiniExtra.gen_ai_spec.buffer(),
      F = ai.gen_spec.treesitter({ a = '@function.outer', i = '@function.inner' }),
    },
  })
end)

later(function() require('mini.align').setup() end)

later(function() require('mini.animate').setup({ scroll = { enable = false } }) end)

later(function() require('mini.bracketed').setup() end)

later(function() require('mini.bufremove').setup() end)

later(function()
  local miniclue = require('mini.clue')
  --stylua: ignore
  miniclue.setup({
    clues = {
      Config.leader_group_clues,
      miniclue.gen_clues.builtin_completion(),
      miniclue.gen_clues.g(),
      miniclue.gen_clues.marks(),
      miniclue.gen_clues.registers(),
      miniclue.gen_clues.windows({ submode_resize = true }),
      miniclue.gen_clues.z(),
    },
    triggers = {
      { mode = 'n', keys = '<Leader>' }, -- Leader triggers
      { mode = 'x', keys = '<Leader>' },
      { mode = 'n', keys = [[\]] },      -- mini.basics
      { mode = 'n', keys = '[' },        -- mini.bracketed
      { mode = 'n', keys = ']' },
      { mode = 'x', keys = '[' },
      { mode = 'x', keys = ']' },
      { mode = 'i', keys = '<C-x>' },    -- Built-in completion
      { mode = 'n', keys = 'g' },        -- `g` key
      { mode = 'x', keys = 'g' },
      { mode = 'n', keys = "'" },        -- Marks
      { mode = 'n', keys = '`' },
      { mode = 'x', keys = "'" },
      { mode = 'x', keys = '`' },
      { mode = 'n', keys = '"' },        -- Registers
      { mode = 'x', keys = '"' },
      { mode = 'i', keys = '<C-r>' },
      { mode = 'c', keys = '<C-r>' },
      { mode = 'n', keys = '<C-w>' },    -- Window commands
      { mode = 'n', keys = 'z' },        -- `z` key
      { mode = 'x', keys = 'z' },
    },
    window = { config = { border = 'double' } },
  })
end)

-- Don't really need it on daily basis
-- later(function() require('mini.colors').setup() end)

later(function() require('mini.comment').setup() end)

later(function()
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
  if vim.fn.has('nvim-0.11') == 1 then
    vim.opt.completeopt:append('fuzzy') -- Use fuzzy matching for built-in completion
  end
end)

later(function() require('mini.cursorword').setup() end)

later(function()
  require('mini.diff').setup()
  local rhs = function() return MiniDiff.operator('yank') .. 'gh' end
  vim.keymap.set('n', 'ghy', rhs, { expr = true, remap = true, desc = "Copy hunk's reference lines" })
end)

later(function() require('mini.doc').setup() end)

later(function()
  require('mini.files').setup({ windows = { preview = true } })

  local minifiles_augroup = vim.api.nvim_create_augroup('ec-mini-files', {})
  vim.api.nvim_create_autocmd('User', {
    group = minifiles_augroup,
    pattern = 'MiniFilesWindowOpen',
    callback = function(args) vim.api.nvim_win_set_config(args.data.win_id, { border = 'double' }) end,
  })
  vim.api.nvim_create_autocmd('User', {
    group = minifiles_augroup,
    pattern = 'MiniFilesExplorerOpen',
    callback = function()
      MiniFiles.set_bookmark('c', vim.fn.stdpath('config'), { desc = 'Config' })
      MiniFiles.set_bookmark('m', vim.fn.stdpath('data') .. '/site/pack/deps/start/mini.nvim', { desc = 'mini.nvim' })
      MiniFiles.set_bookmark('p', vim.fn.stdpath('data') .. '/site/pack/deps/opt', { desc = 'Plugins' })
      MiniFiles.set_bookmark('w', vim.fn.getcwd, { desc = 'Working directory' })
    end,
  })
end)

later(function() require('mini.git').setup() end)

later(function()
  local hipatterns = require('mini.hipatterns')
  local hi_words = MiniExtra.gen_highlighter.words
  hipatterns.setup({
    highlighters = {
      fixme = hi_words({ 'FIXME', 'Fixme', 'fixme' }, 'MiniHipatternsFixme'),
      hack = hi_words({ 'HACK', 'Hack', 'hack' }, 'MiniHipatternsHack'),
      todo = hi_words({ 'TODO', 'Todo', 'todo' }, 'MiniHipatternsTodo'),
      note = hi_words({ 'NOTE', 'Note', 'note' }, 'MiniHipatternsNote'),

      hex_color = hipatterns.gen_highlighter.hex_color(),
    },
  })
end)

later(function() require('mini.indentscope').setup() end)

later(function() require('mini.jump').setup() end)

later(function()
  local jump2d = require('mini.jump2d')
  jump2d.setup({
    spotter = jump2d.gen_pattern_spotter('[^%s%p]+'),
    view = { dim = true, n_steps_ahead = 2 },
  })
end)

later(function()
  local map = require('mini.map')
  local gen_integr = map.gen_integration
  map.setup({
    symbols = { encode = map.gen_encode_symbols.dot('4x2') },
    integrations = { gen_integr.builtin_search(), gen_integr.diff(), gen_integr.diagnostic() },
  })
  vim.keymap.set('n', [[\h]], ':let v:hlsearch = 1 - v:hlsearch<CR>', { desc = 'Toggle hlsearch', silent = true })
  for _, key in ipairs({ 'n', 'N', '*' }) do
    vim.keymap.set('n', key, key .. 'zv<Cmd>lua MiniMap.refresh({}, { lines = false, scrollbar = false })<CR>')
  end
end)

later(function()
  require('mini.misc').setup({ make_global = { 'put', 'put_text', 'stat_summary', 'bench_time' } })
  MiniMisc.setup_auto_root()
  MiniMisc.setup_termbg_sync()
end)

later(function() require('mini.move').setup({ options = { reindent_linewise = false } }) end)

later(function()
  local remap = function(mode, lhs_from, lhs_to)
    local keymap = vim.fn.maparg(lhs_from, mode, false, true)
    local rhs = keymap.callback or keymap.rhs
    if rhs == nil then error('Could not remap from ' .. lhs_from .. ' to ' .. lhs_to) end
    vim.keymap.set(mode, lhs_to, rhs, { desc = keymap.desc })
  end
  remap('n', 'gx', '<Leader>ox')
  remap('x', 'gx', '<Leader>ox')

  require('mini.operators').setup()
end)

later(function()
  require('mini.pairs').setup({ modes = { insert = true, command = true, terminal = true } })
  vim.keymap.set('i', '<CR>', 'v:lua.Config.cr_action()', { expr = true })
end)

later(function()
  require('mini.pick').setup({ window = { config = { border = 'double' } } })
  vim.ui.select = MiniPick.ui_select
  vim.keymap.set('n', ',', [[<Cmd>Pick buf_lines scope='current' preserve_order=true<CR>]], { nowait = true })

  MiniPick.registry.projects = function()
    local cwd = vim.fn.expand('~/repos')
    local choose = function(item)
      vim.schedule(function() MiniPick.builtin.files(nil, { source = { cwd = item.path } }) end)
    end
    return MiniExtra.pickers.explorer({ cwd = cwd }, { source = { choose = choose } })
  end
end)

later(function()
  local snippets, config_path = require('mini.snippets'), vim.fn.stdpath('config')

  local lang_patterns = { tex = { 'latex.json' }, plaintex = { 'latex.json' } }
  local load_if_minitest_buf = function(context)
    local buf_name = vim.api.nvim_buf_get_name(context.buf_id)
    local is_test_buf = vim.fn.fnamemodify(buf_name, ':t'):find('^test_.+%.lua$') ~= nil
    if not is_test_buf then return {} end
    return MiniSnippets.read_file(config_path .. '/snippets/mini-test.json')
  end

  snippets.setup({
    snippets = {
      snippets.gen_loader.from_file(config_path .. '/snippets/global.json'),
      snippets.gen_loader.from_lang({ lang_patterns = lang_patterns }),
      load_if_minitest_buf,
    },
  })
end)

later(function() require('mini.splitjoin').setup() end)

later(function()
  require('mini.surround').setup({ search_method = 'cover_or_next' })
  -- Disable `s` shortcut (use `cl` instead) for safer usage of 'mini.surround'
  vim.keymap.set({ 'n', 'x' }, 's', '<Nop>')
end)

later(function()
  local test = require('mini.test')
  local reporter = test.gen_reporter.buffer({ window = { border = 'double' } })
  test.setup({
    execute = { reporter = reporter },
  })
end)

later(function() require('mini.trailspace').setup() end)

later(function() require('mini.visits').setup() end)
