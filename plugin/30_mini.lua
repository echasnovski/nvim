local add, now, later = MiniDeps.add, MiniDeps.now, MiniDeps.later
local now_if_args = _G.Config.now_if_args

-- Use 'HEAD' because I personally update it and don't want to follow `main`
-- This means that 'start/mini.nvim' will usually be present twice in
-- 'runtimepath' as there is a '.../pack/*/start/*' entry there.
add({ name = 'mini.nvim', checkout = 'HEAD' })

-- Step one ===================================================================
now(function() vim.cmd('colorscheme miniwinter') end)
-- now(function() vim.cmd('colorscheme minispring') end)
-- now(function() vim.cmd('colorscheme minisummer') end)
-- now(function() vim.cmd('colorscheme miniautumn') end)

now(function()
  require('mini.basics').setup({
    -- Manage options manually in a spirit of transparency
    options = { basic = false },
    mappings = { windows = true, move_with_alt = true },
    autocommands = { relnum_in_visual_mode = true },
  })
end)

now(function()
  require('mini.icons').setup({
    use_file_extension = function(ext, _)
      local suf3, suf4 = ext:sub(-3), ext:sub(-4)
      return suf3 ~= 'scm' and suf3 ~= 'txt' and suf3 ~= 'yml' and suf4 ~= 'json' and suf4 ~= 'yaml'
    end,
  })
  later(MiniIcons.mock_nvim_web_devicons)
  later(MiniIcons.tweak_lsp_kind)
end)

now_if_args(function()
  require('mini.misc').setup({ make_global = { 'put', 'put_text', 'stat_summary', 'bench_time' } })
  MiniMisc.setup_auto_root()
  MiniMisc.setup_restore_cursor()
  MiniMisc.setup_termbg_sync()
end)

now(function()
  local predicate = function(notif)
    if not (notif.data.source == 'lsp_progress' and notif.data.client_name == 'lua_ls') then return true end
    -- Filter out some LSP progress notifications from 'lua_ls'
    return notif.msg:find('Diagnosing') == nil and notif.msg:find('semantic tokens') == nil
  end
  local custom_sort = function(notif_arr) return MiniNotify.default_sort(vim.tbl_filter(predicate, notif_arr)) end

  require('mini.notify').setup({ content = { sort = custom_sort } })
end)

now(function() require('mini.sessions').setup() end)

now(function() require('mini.starter').setup() end)

now(function() require('mini.statusline').setup() end)

-- Future 'mini.statuscolumn'
now(function()
  if vim.fn.has('nvim-0.9') == 1 then
    -- TODO: Add "scrollbar" section:
    -- - Treat whole window height as representation of buffer height.
    -- - Show a bar for window lines that span from top to bottom visible
    --   buffer lines. At least a single line should be covered.
    -- - Maybe point in a middle with where the cursor is (like in 'mini.map').
    -- - Maybe combine it with │ rightmost delimiter (╏ is good for scrollbar).
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

-- Unfortunately, `_lines` is ~3x faster
_G.get_all_indent_lines = function()
  local res, lines = {}, vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for i = 1, #lines do
    local indent = lines[i]:match('^%s+')
    if indent ~= nil then table.insert(res, indent) end
  end
  return res
end

_G.get_all_indent_text = function()
  local res, n = {}, vim.api.nvim_buf_line_count(0)
  local get_text = vim.api.nvim_buf_get_text
  for i = 1, n do
    local first_byte = get_text(0, i - 1, 0, i - 1, 1, {})[1]
    if first_byte == '\t' or first_byte == ' ' then table.insert(res, vim.fn.getline(i):match('^%s+')) end
  end
  return res
end

-- Unfortunately, `_lines` is 10x faster
_G.get_maxwidth_lines = function()
  local res, lines = 0, vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for i = 1, #lines do
    res = res < lines[i]:len() and lines[i]:len() or res
  end
  return res
end

_G.get_maxwidth_bytes = function()
  local res, n = 0, vim.api.nvim_buf_line_count(0)
  local cur_byte, line2byte = 1, vim.fn.line2byte
  for i = 2, n + 1 do
    local new_byte = line2byte(i)
    res = math.max(res, new_byte - cur_byte)
    cur_byte = new_byte
  end
  return res - 1
end

-- Step two ===================================================================
later(function() require('mini.extra').setup() end)

later(function()
  local ai = require('mini.ai')
  ai.setup({
    custom_textobjects = {
      B = MiniExtra.gen_ai_spec.buffer(),
      F = ai.gen_spec.treesitter({ a = '@function.outer', i = '@function.inner' }),
      o = ai.gen_spec.treesitter({ a = '@block.outer', i = '@block.inner' }),
    },
    search_method = 'cover',
  })
end)

later(function() require('mini.align').setup() end)

-- later(function() require('mini.animate').setup({ scroll = { enable = false } }) end)

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
      { mode = 'n', keys = '\\' },       -- mini.basics
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
      { mode = 'n', keys = 's' },        -- `s` key
      { mode = 'x', keys = 's' },
    },
  })
end)

later(function() require('mini.cmdline').setup() end)

-- Don't really need it on daily basis
-- later(function() require('mini.colors').setup() end)

later(function() require('mini.comment').setup() end)

later(function()
  -- Don't show 'Text' suggestions
  local process_items_opts = { kind_priority = { Text = -1, Snippet = 99 } }
  local process_items = function(items, base)
    return MiniCompletion.default_process_items(items, base, process_items_opts)
  end
  require('mini.completion').setup({
    lsp_completion = { source_func = 'omnifunc', auto_setup = false, process_items = process_items },
  })

  -- Set up LSP part of completion
  local on_attach = function(args) vim.bo[args.buf].omnifunc = 'v:lua.MiniCompletion.completefunc_lsp' end
  _G.Config.new_autocmd('LspAttach', '*', on_attach, 'Custom `on_attach`')
  if vim.fn.has('nvim-0.11') == 1 then vim.lsp.config('*', { capabilities = MiniCompletion.get_lsp_capabilities() }) end
end)

later(function() require('mini.cursorword').setup() end)

later(function() require('mini.diff').setup() end)

later(function() require('mini.doc').setup() end)

later(function()
  require('mini.files').setup({ windows = { preview = true } })

  _G.Config.new_autocmd('User', 'MiniFilesExplorerOpen', function()
    MiniFiles.set_bookmark('c', vim.fn.stdpath('config'), { desc = 'Config' })
    MiniFiles.set_bookmark('m', vim.fn.stdpath('data') .. '/site/pack/deps/start/mini.nvim', { desc = 'mini.nvim' })
    MiniFiles.set_bookmark('p', vim.fn.stdpath('data') .. '/site/pack/deps/opt', { desc = 'Plugins' })
    MiniFiles.set_bookmark('w', vim.fn.getcwd, { desc = 'Working directory' })
  end, "Create 'mini.files' bookmarks")
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
    spotter = jump2d.gen_spotter.pattern('[^%s%p]+'),
    labels = 'asdfghjkl;',
    view = { dim = true, n_steps_ahead = 2 },
  })
  vim.keymap.set({ 'n', 'x', 'o' }, 'sj', function() MiniJump2d.start(MiniJump2d.builtin_opts.single_character) end)
end)

later(function()
  require('mini.keymap').setup()
  MiniKeymap.map_multistep('i', '<Tab>', { 'pmenu_next' })
  MiniKeymap.map_multistep('i', '<S-Tab>', { 'pmenu_prev' })
  MiniKeymap.map_multistep('i', '<CR>', { 'pmenu_accept', 'minipairs_cr' })
  MiniKeymap.map_multistep('i', '<BS>', { 'minipairs_bs' })
end)

later(function()
  local map = require('mini.map')
  local gen_integr = map.gen_integration
  map.setup({
    symbols = { encode = map.gen_encode_symbols.dot('4x2') },
    integrations = { gen_integr.builtin_search(), gen_integr.diff(), gen_integr.diagnostic() },
  })
  for _, key in ipairs({ 'n', 'N', '*', '#' }) do
    vim.keymap.set('n', key, key .. 'zv<Cmd>lua MiniMap.refresh({}, { lines = false, scrollbar = false })<CR>')
  end
end)

later(function() require('mini.move').setup({ options = { reindent_linewise = false } }) end)

later(function()
  require('mini.operators').setup()

  vim.keymap.set('n', '(', '<Cmd>normal gxiagxila<CR>', { desc = 'Move arg left' })
  vim.keymap.set('n', ')', '<Cmd>normal gxiagxina<CR>', { desc = 'Move arg right' })
end)

later(function() require('mini.pairs').setup({ modes = { insert = true, command = true, terminal = false } }) end)

later(function()
  require('mini.pick').setup()
  vim.keymap.set('n', ',', '<Cmd>Pick buf_lines scope="current" preserve_order=true<CR>', { nowait = true })

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

  local latex_patterns = { 'latex/**/*.json', '**/latex.json' }
  local lang_patterns = {
    tex = latex_patterns,
    plaintex = latex_patterns,
    -- Recognize special injected language of markdown tree-sitter parser
    markdown_inline = { 'markdown.json' },
  }
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

later(function() require('mini.surround').setup() end)

later(function() require('mini.test').setup() end)

later(function() require('mini.trailspace').setup() end)

later(function() require('mini.visits').setup() end)
