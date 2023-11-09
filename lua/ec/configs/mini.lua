local now, later = EC.now, EC.later

-- Step one -------------------------------------------------------------------
now(function() vim.cmd('colorscheme randomhue') end)

now(function() require('mini.sessions').setup({ directory = vim.fn.stdpath('config') .. '/misc/sessions' }) end)

now(function() require('mini.starter').setup() end)

-- TODO: Add `section_searchcount` to 'mini.statusline' default
now(function() require('mini.statusline').setup() end)

now(function() require('mini.tabline').setup() end)

now(function()
  require('mini-dev.visits').setup()
  vim.keymap.set('n', '<Leader>va', function() MiniVisits.add_flag() end, { desc = 'Add flag' })
  vim.keymap.set('n', '<Leader>vr', function() MiniVisits.remove_flag() end, { desc = 'Remove flag' })
end)

EC.pick_visits = function(local_opts, opts)
  local default_local_opts =
    { cwd = vim.fn.getcwd(), filter = nil, preserve_sort = true, recency_weight = 0.5, scope = 'all', sort = nil }
  local_opts = vim.tbl_deep_extend('force', default_local_opts, local_opts or {})

  local full_path = function(path) return (vim.fn.fnamemodify(path, ':p'):gsub('(.)/$', '%1')) end
  local short_path = function(path, cwd)
    cwd = cwd or vim.fn.getcwd()
    if not vim.startswith(path, cwd) then return vim.fn.fnamemodify(path, ':~') end
    local res = path:sub(cwd:len() + 1):gsub('^/+', ''):gsub('/+$', '')
    return res
  end

  local pick = require('mini.pick')
  local cwd = local_opts.cwd == '' and vim.fn.getcwd() or full_path(local_opts.cwd)

  -- Define source
  local filter = local_opts.filter or MiniVisits.gen_filter.default()
  local sort = local_opts.sort or MiniVisits.gen_sort.default({ recency_weight = local_opts.recency_weight })
  local items = vim.schedule_wrap(function()
    -- NOTE: Use `local_opts.cwd` instead of `cwd` to allow `cwd = ''` to not
    -- mean "current directory"
    local files = MiniVisits.list_files(local_opts.cwd, local_opts.scope, { filter = filter, sort = sort })
    files = vim.tbl_map(function(x) return short_path(x, cwd) end, files)
    pick.set_picker_items(files)
  end)

  local show = function(buf_id, items_to_show, query)
    require('mini.pick').default_show(buf_id, items_to_show, query, { show_icons = true })
  end

  local match
  if local_opts.preserve_sort then
    match = function(stritems, inds, query)
      local res = MiniPick.default_match(stritems, inds, query, true)
      table.sort(res)
      return res
    end
  end

  local default_source = { items = items, name = 'Visits', cwd = cwd, match = match, show = show }
  opts = vim.tbl_deep_extend('force', opts or {}, { source = default_source })
  return pick.start(opts)
end

EC.pick_visits_flags = function(local_opts, opts)
  -- TODO
end

vim.defer_fn(function()
  if _G.MiniPick == nil then return end
  _G.MiniPick.registry.visits = EC.pick_visits

  vim.keymap.set('n', '<Leader>fv', '<Cmd>Pick visits cwd=""<CR>', { desc = 'Visits (frecency)' })
  vim.keymap.set('n', '<Leader>fV', '<Cmd>Pick visits<CR>', { desc = 'Visits (frecency, cwd)' })

  -- local oldfiles_all = '<Cmd>Pick visits recency_weight=1 cwd="" match_exact=false<CR>'
  -- vim.keymap.set('n', '<Leader>fo', oldfiles_all, { desc = 'Visits (recent)' })
  -- local oldfiles_cwd = '<Cmd>Pick visits recency_weight=1 match_exact=false<CR>'
  -- vim.keymap.set('n', '<Leader>fO', oldfiles_cwd, { desc = 'Visits (recent, cwd)' })
end, 1000)

-- Step two -------------------------------------------------------------------
later(function() require('mini.extra').setup() end)

later(function()
  local gen_word_spec = function(use_nonblank)
    if use_nonblank == nil then use_nonblank = false end

    local matchstrpos = vim.fn.matchstrpos
    local char = use_nonblank and '[^ \t\n]' or '\\k'
    local a_keyword_pattern = string.format('[ \t]*%s\\+[ \t]*', char)

    local find_a_keyword = function(line, init)
      local m = matchstrpos(line, a_keyword_pattern, init - 1)
      local from, to = m[2] + 1, m[3]

      -- Make it not select parts of word as they would match during 'mini.ai'
      -- iterative search (with `init = from + 1`).
      -- Overcome the fact that callable inside 'mini.ai' composed pattern
      -- can't return index strictly less than `init`
      if from == init and init ~= 1 then
        -- FIXME: This clause is wrongly entered if previous keyword consists
        -- from single character. Example: "x xxx x"
        init = line:sub(1, to):match('()%s*$')
        m = matchstrpos(line, a_keyword_pattern, init - 1)
        from, to = m[2] + 1, m[3]
      end

      if from == 0 then return nil, nil end

      -- Use only single whitespace (preferring trailing)
      if line:sub(to, to):find('[ \t]') ~= nil then from = line:find('[^ \t]', from) end

      return from, to
    end

    return { find_a_keyword, '^%s*()%S*()%s*$' }
  end

  local ai = require('mini.ai')
  ai.setup({
    custom_textobjects = {
      F = ai.gen_spec.treesitter({ a = '@function.outer', i = '@function.inner' }),
      -- w = gen_word_spec(false),
      -- W = gen_word_spec(true),
    },
  })
end)

later(function() require('mini.align').setup() end)

later(function()
  require('mini.animate').setup({
    scroll = {
      timing = function(_, n) return 150 / n end,
    },
  })
end)

later(function()
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
end)

later(function() require('mini.bracketed').setup() end)

later(function() require('mini.bufremove').setup() end)

later(function()
  local miniclue = require('mini.clue')
  miniclue.setup({
    clues = {
      EC.leader_group_clues,
      miniclue.gen_clues.builtin_completion(),
      miniclue.gen_clues.g(),
      miniclue.gen_clues.marks(),
      miniclue.gen_clues.registers(),
      miniclue.gen_clues.windows({ submode_resize = true }),
      miniclue.gen_clues.z(),
    },

    triggers = {
      -- Leader triggers
      { mode = 'n', keys = '<Leader>' },
      { mode = 'x', keys = '<Leader>' },

      -- mini.basics
      { mode = 'n', keys = [[\]] },

      -- mini.bracketed
      { mode = 'n', keys = '[' },
      { mode = 'n', keys = ']' },
      { mode = 'x', keys = '[' },
      { mode = 'x', keys = ']' },

      -- Built-in completion
      { mode = 'i', keys = '<C-x>' },

      -- `g` key
      { mode = 'n', keys = 'g' },
      { mode = 'x', keys = 'g' },

      -- Marks
      { mode = 'n', keys = "'" },
      { mode = 'n', keys = '`' },
      { mode = 'x', keys = "'" },
      { mode = 'x', keys = '`' },

      -- Registers
      { mode = 'n', keys = '"' },
      { mode = 'x', keys = '"' },
      { mode = 'i', keys = '<C-r>' },
      { mode = 'c', keys = '<C-r>' },

      -- Window commands
      { mode = 'n', keys = '<C-w>' },

      -- `z` key
      { mode = 'n', keys = 'z' },
      { mode = 'x', keys = 'z' },
    },

    window = { config = { border = 'double' } },
  })
  -- Enable triggers in help buffer
  local clue_group = vim.api.nvim_create_augroup('my-miniclue', { clear = true })
  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'help',
    group = clue_group,
    callback = function(data) MiniClue.enable_buf_triggers(data.buf) end,
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
end)

later(function() require('mini.cursorword').setup() end)

later(function() require('mini.doc').setup() end)

later(function()
  require('mini.files').setup({ windows = { preview = true } })
  local minifiles_augroup = vim.api.nvim_create_augroup('ec-mini-files', {})
  vim.api.nvim_create_autocmd('User', {
    group = minifiles_augroup,
    pattern = 'MiniFilesWindowOpen',
    callback = function(args) vim.api.nvim_win_set_config(args.data.win_id, { border = 'double' }) end,
  })
end)

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

later(function() require('mini.jump2d').setup({ view = { dim = true } }) end)

later(function()
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
end)

later(function()
  require('mini.misc').setup({ make_global = { 'put', 'put_text', 'stat_summary', 'bench_time' } })
  MiniMisc.setup_auto_root()
end)

later(function() require('mini.move').setup({ options = { reindent_linewise = false } }) end)

later(function() require('mini.operators').setup() end)

later(function()
  require('mini.pairs').setup({ modes = { insert = true, command = true, terminal = true } })
  vim.keymap.set('i', '<CR>', 'v:lua.EC.cr_action()', { expr = true })
end)

later(function()
  require('mini.pick').setup({ window = { config = { border = 'double' } } })
  vim.ui.select = MiniPick.ui_select
  vim.keymap.set('n', ',', [[<Cmd>Pick buf_lines scope='current'<CR>]], { nowait = true })
end)

later(function() require('mini.splitjoin').setup() end)

later(function() require('mini.surround').setup({ search_method = 'cover_or_next' }) end)

later(function()
  local test = require('mini.test')
  local reporter = test.gen_reporter.buffer({ window = { border = 'double' } })
  test.setup({
    execute = { reporter = reporter },
  })
end)

later(function() require('mini.trailspace').setup() end)
