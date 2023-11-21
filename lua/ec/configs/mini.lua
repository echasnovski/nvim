local now, later = EC.now, EC.later

-- Step one -------------------------------------------------------------------
now(function() vim.cmd('colorscheme randomhue') end)

now(function() require('mini.sessions').setup({ directory = vim.fn.stdpath('config') .. '/misc/sessions' }) end)

now(function() require('mini.starter').setup() end)

now(function() require('mini.statusline').setup() end)

now(function() require('mini.tabline').setup() end)

--stylua: ignore
now(function()
  local visits = require('mini-dev.visits')
  visits.setup()
  local sort_latest = visits.gen_sort.default({ recency_weight = 1 })

  -- Labels
  table.insert(EC.leader_group_clues, { mode = 'n', keys = '<Leader>v', desc = '+Visits' })

  local map_vis = function(keys, call, desc)
    local rhs = '<Cmd>lua MiniVisits.' .. call .. '<CR>'
    vim.keymap.set('n', '<Leader>' .. keys, rhs, { desc = desc })
  end
  map_vis('vv', 'add_label("core")',    'Add "core" label')
  map_vis('vV', 'remove_label("core")', 'Remove "core" label')
  map_vis('vl', 'add_label()',          'Add label')
  map_vis('vL', 'remove_label()',       'Remove label')

  --  Pick core
  local map_pick_core = function(keys, cwd, desc)
    local rhs = function()
      EC.pick_visits({ cwd = cwd, filter = 'core', sort = sort_latest }, { source = { name = desc } })
    end
    vim.keymap.set('n', '<Leader>' .. keys, rhs, { desc = desc })
  end

  map_pick_core('vc', '',  'Core visits (all)')
  map_pick_core('vC', nil, 'Core visits (all)')

  -- Iteration
  local map_iterate_core = function(lhs, direction, desc)
    local opts = { filter = 'core', sort = sort_latest, wrap = true }
    local rhs = function() MiniVisits.iterate_paths(direction, vim.fn.getcwd(), opts) end
    vim.keymap.set('n', lhs, rhs, { desc = desc })
  end

  map_iterate_core('[{', 'last',     'Core label (earliest)')
  map_iterate_core('[[', 'forward',  'Core label (earlier)')
  map_iterate_core(']]', 'backward', 'Core label (later)')
  map_iterate_core(']}', 'first',    'Core label (latest)')
end)

-- Pickers for 'mini.visits' that would go into 'mini.extra'
local full_path = function(path) return (vim.fn.fnamemodify(path, ':p'):gsub('(.)/$', '%1')) end
local short_path = function(path, cwd)
  cwd = cwd or vim.fn.getcwd()
  if not vim.startswith(path, cwd) then return vim.fn.fnamemodify(path, ':~') end
  local res = path:sub(cwd:len() + 1):gsub('^/+', ''):gsub('/+$', '')
  return res
end

local show_with_icons = function(buf_id, items_to_show, query)
  require('mini.pick').default_show(buf_id, items_to_show, query, { show_icons = true })
end

EC.pick_visits = function(local_opts, opts)
  local default_local_opts = { cwd = nil, filter = nil, preserve_sort = false, recency_weight = 0.5, sort = nil }
  local_opts = vim.tbl_deep_extend('force', default_local_opts, local_opts or {})

  local pick = require('mini.pick')
  local cwd = local_opts.cwd or vim.fn.getcwd()
  -- NOTE: Use separate cwd to allow `cwd = ''` to not mean "current directory"
  local is_for_cwd = cwd ~= ''
  local picker_cwd = cwd == '' and vim.fn.getcwd() or full_path(cwd)

  -- Define source
  local filter = local_opts.filter or MiniVisits.gen_filter.default()
  local sort = local_opts.sort or MiniVisits.gen_sort.default({ recency_weight = local_opts.recency_weight })
  local items = vim.schedule_wrap(function()
    local paths = MiniVisits.list_paths(cwd, { filter = filter, sort = sort })
    paths = vim.tbl_map(function(x) return short_path(x, picker_cwd) end, paths)
    pick.set_picker_items(paths)
  end)

  -- local show = H.pick_get_config().source.show or H.show_with_icons
  local show = show_with_icons

  local match
  if local_opts.preserve_sort then
    match = function(stritems, inds, query)
      local res = pick.default_match(stritems, inds, query, true)
      table.sort(res)
      return res
    end
  end

  local name = string.format('Visits (%s)', is_for_cwd and 'cwd' or 'all')
  local default_source = { name = name, cwd = picker_cwd, match = match, show = show }
  opts = vim.tbl_deep_extend('force', { source = default_source }, opts or {}, { source = { items = items } })
  return pick.start(opts)
end

EC.pick_visit_labels = function(local_opts, opts)
  local default_local_opts = { path = '', cwd = nil, filter = nil, sort = nil }
  local_opts = vim.tbl_deep_extend('force', default_local_opts, local_opts or {})

  local pick = require('mini.pick')
  local cwd = local_opts.cwd or vim.fn.getcwd()
  -- NOTE: Use separate cwd to allow `cwd = ''` to not mean "current directory"
  local is_for_cwd = cwd ~= ''
  local picker_cwd = cwd == '' and vim.fn.getcwd() or full_path(cwd)

  local filter = local_opts.filter or MiniVisits.gen_filter.default()
  local items = MiniVisits.list_labels(local_opts.path, local_opts.cwd, { filter = filter })

  -- Define source
  local list_label_paths = function(label)
    local new_filter =
      function(path_data) return filter(path_data) and type(path_data.labels) == 'table' and path_data.labels[label] end
    local all_paths = MiniVisits.list_paths(local_opts.cwd, { filter = new_filter, sort = local_opts.sort })
    return vim.tbl_map(function(path) return short_path(path, picker_cwd) end, all_paths)
  end

  local preview = function(buf_id, label) vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, list_label_paths(label)) end
  local choose = function(label)
    if label == nil then return end

    pick.set_picker_items(list_label_paths(label), { do_match = false })
    pick.set_picker_query({})
    local name = string.format('Paths for %s label', vim.inspect(label))
    pick.set_picker_opts({ source = { name = name, show = show_with_icons, choose = pick.default_choose } })
    return true
  end

  local name = string.format('Visit labels (%s)', is_for_cwd and 'cwd' or 'all')
  local default_source = { name = name, cwd = picker_cwd, preview = preview, choose = choose }
  opts = vim.tbl_deep_extend('force', { source = default_source }, opts or {}, { source = { items = items } })
  return pick.start(opts)
end

--stylua: ignore start
-- vim.keymap.set('n', '<Leader>fo', '<Cmd>Pick visits recency_weight=1 cwd=""<CR>', { desc = 'Old visits (all)' })
-- vim.keymap.set('n', '<Leader>fO', '<Cmd>Pick visits recency_weight=1<CR>',        { desc = 'Old visits (cwd)' })
vim.keymap.set('n', '<Leader>fv', '<Cmd>Pick visits cwd=""<CR>',       { desc = 'Visits (all)' })
vim.keymap.set('n', '<Leader>fV', '<Cmd>Pick visits<CR>',              { desc = 'Visits (cwd)' })
--stylua: ignore end

vim.defer_fn(function()
  if _G.MiniPick == nil then return end
  _G.MiniPick.registry.visits = EC.pick_visits
  _G.MiniPick.registry.visit_labels = EC.pick_visit_labels
end, 1000)

-- Step two -------------------------------------------------------------------
later(function() require('mini.extra').setup() end)

later(function()
  local ai = require('mini.ai')
  ai.setup({
    custom_textobjects = {
      F = ai.gen_spec.treesitter({ a = '@function.outer', i = '@function.inner' }),
    },
  })
end)

later(function() require('mini.align').setup() end)

later(function()
  require('mini.animate').setup({
    scroll = { enable = false },
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
