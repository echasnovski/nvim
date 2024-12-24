-- Initialization =============================================================
pcall(function() vim.loader.enable() end)

-- Define main config table
_G.Config = {
  path_package = vim.fn.stdpath('data') .. '/site/',
  path_source = vim.fn.stdpath('config') .. '/src/',
}

-- Ensure 'mini.nvim' is set up
local mini_path = Config.path_package .. 'pack/deps/start/mini.nvim'
if not vim.loop.fs_stat(mini_path) then
  vim.cmd([[echo "Installing 'mini.nvim'" | redraw]])
  local clone_cmd = { 'git', 'clone', '--filter=blob:none', 'https://github.com/echasnovski/mini.nvim', mini_path }
  vim.fn.system(clone_cmd)
end
require('mini.deps').setup({ path = { package = Config.path_package } })

-- Define helpers
local add, now, later = MiniDeps.add, MiniDeps.now, MiniDeps.later
local source = function(path) dofile(Config.path_source .. path) end

-- Settings and mappings ======================================================
now(function() source('settings.lua') end)
now(function() source('functions.lua') end)
now(function() source('mappings.lua') end)
now(function() source('mappings-leader.lua') end)
if vim.g.vscode ~= nil then now(function() source('vscode.lua') end) end

-- Mini.nvim ==================================================================
add({ name = 'mini.nvim', checkout = 'HEAD' })

-- Step one
now(function()
  -- Use this color scheme in 'mini.nvim' demos:
  -- require('mini.hues').setup({ background = '#11262d', foreground = '#c0c8cb' })
  vim.cmd('colorscheme randomhue')
end)

now(function()
  local filterout_lua_diagnosing = function(notif_arr)
    local not_diagnosing = function(notif) return not vim.startswith(notif.msg, 'lua_ls: Diagnosing') end
    notif_arr = vim.tbl_filter(not_diagnosing, notif_arr)
    return MiniNotify.default_sort(notif_arr)
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

-- Step two
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
  -- Have no transparency to always have "overflow" icons (otherwise there can
  -- be a symbol visible from underneath blocking "overflow if next to space"
  -- approach from terminal emulator)
  vim.o.pumblend = 0
  vim.o.winblend = 0
end)

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
  local encode_symbols = map.gen_encode_symbols.block('3x2')
  -- Use dots in `st` terminal because it can render them as blocks
  if vim.startswith(vim.fn.getenv('TERM'), 'st') then encode_symbols = map.gen_encode_symbols.dot('4x2') end
  map.setup({
    symbols = { encode = encode_symbols },
    integrations = { gen_integr.builtin_search(), gen_integr.diff(), gen_integr.diagnostic() },
  })
  vim.keymap.set('n', [[\h]], ':let v:hlsearch = 1 - v:hlsearch<CR>', { desc = 'Toggle hlsearch' })
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

-- Dependencies ===============================================================
-- Tree-sitter: advanced syntax parsing, highlighting, and text objects
later(function()
  local ts_spec = {
    source = 'nvim-treesitter/nvim-treesitter',
    checkout = 'master',
    hooks = { post_checkout = function() vim.cmd('TSUpdate') end },
  }
  add({ source = 'nvim-treesitter/nvim-treesitter-textobjects', depends = { ts_spec } })
  source('plugins/nvim-treesitter.lua')
end)

-- Install LSP/formatting/linter executables
later(function()
  add('williamboman/mason.nvim')
  require('mason').setup()
end)

-- Formatting
later(function()
  add('stevearc/conform.nvim')
  source('plugins/conform.lua')
end)

-- Language server configurations
later(function()
  add('neovim/nvim-lspconfig')
  source('plugins/nvim-lspconfig.lua')
end)

-- Tweak Neovim's terminal to be more REPL-aware
later(function()
  add('kassio/neoterm')
  source('plugins/neoterm.lua')
end)

-- Snippet collection
later(function() add('rafamadriz/friendly-snippets') end)

-- Documentation generator
later(function()
  add('danymat/neogen')
  require('neogen').setup({
    languages = {
      lua = { template = { annotation_convention = 'emmylua' } },
      python = { template = { annotation_convention = 'numpydoc' } },
    },
  })
end)

-- Test runner
later(function()
  add({ source = 'vim-test/vim-test', depends = { 'tpope/vim-dispatch' } })
  vim.cmd([[let test#strategy = 'neoterm']])
  vim.cmd([[let test#python#runner = 'pytest']])
end)

-- Filetype: csv
later(function()
  vim.g.disable_rainbow_csv_autodetect = true
  add('mechatroner/rainbow_csv')
end)

-- Filetype: rmarkdown
later(function()
  -- This option should be set before loading plugin to take effect. See
  -- https://github.com/vim-pandoc/vim-pandoc/issues/342
  vim.g['pandoc#filetypes#pandoc_markdown'] = 0

  add({
    source = 'vim-pandoc/vim-rmarkdown',
    depends = { 'vim-pandoc/vim-pandoc', 'vim-pandoc/vim-pandoc-syntax' },
  })

  -- Show raw symbols
  vim.g['pandoc#syntax#conceal#use'] = 0

  -- Folding
  vim.g['pandoc#folding#fold_yaml'] = 1
  vim.g['pandoc#folding#fold_fenced_codeblocks'] = 1
  vim.g['pandoc#folding#fastfolds'] = 1
  vim.g['pandoc#folding#fdc'] = 0
end)

later(function()
  local build = function() vim.fn['mkdp#util#install']() end
  add({
    source = 'iamcco/markdown-preview.nvim',
    hooks = {
      post_install = function() later(build) end,
      post_checkout = build,
    },
  })

  -- Do not close the preview tab when switching to other buffers
  vim.g.mkdp_auto_close = 0
end)
