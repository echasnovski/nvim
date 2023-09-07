-- stylua: ignore start

-- Create global tables with information about clue groups in certain modes
-- Structure of tables is taken to be compatible with 'mini.clue'.
EC.leader_group_clues = {
  { mode = 'n', keys = '<Leader>b', desc = '+Buffer' },
  { mode = 'n', keys = '<Leader>e', desc = '+Explore' },
  { mode = 'n', keys = '<Leader>f', desc = '+Find' },
  { mode = 'n', keys = '<Leader>g', desc = '+Git' },
  { mode = 'n', keys = '<Leader>l', desc = '+LSP' },
  { mode = 'n', keys = '<Leader>L', desc = '+Lua' },
  { mode = 'n', keys = '<Leader>m', desc = '+Map' },
  { mode = 'n', keys = '<Leader>o', desc = '+Other' },
  { mode = 'n', keys = '<Leader>r', desc = '+R' },
  { mode = 'n', keys = '<Leader>t', desc = '+Terminal/Minitest' },
  { mode = 'n', keys = '<Leader>T', desc = '+Test' },

  { mode = 'x', keys = '<Leader>l', desc = '+LSP' },
  { mode = 'x', keys = '<Leader>r', desc = '+R' },
}

-- Create `<Leader>` mappings
local nmap_leader = function(suffix, rhs, desc, opts)
  opts = opts or {}
  opts.desc = desc
  vim.keymap.set('n', '<Leader>' .. suffix, rhs, opts)
end
local xmap_leader = function(suffix, rhs, desc, opts)
  opts = opts or {}
  opts.desc = desc
  vim.keymap.set('x', '<Leader>' .. suffix, rhs, opts)
end

-- b is for 'buffer'
nmap_leader('ba', [[<Cmd>b#<CR>]],                                 'Alternate')
nmap_leader('bd', [[<Cmd>lua MiniBufremove.delete()<CR>]],         'Delete')
nmap_leader('bD', [[<Cmd>lua MiniBufremove.delete(0, true)<CR>]],  'Delete!')
nmap_leader('bs', [[<Cmd>lua EC.new_scratch_buffer()<CR>]],        'Scratch')
nmap_leader('bw', [[<Cmd>lua MiniBufremove.wipeout()<CR>]],        'Wipeout')
nmap_leader('bW', [[<Cmd>lua MiniBufremove.wipeout(0, true)<CR>]], 'Wipeout!')

-- e is for 'explore'
nmap_leader('ed', [[<Cmd>lua MiniFiles.open()<CR>]],                                       'Directory')
nmap_leader('ef', [[<Cmd>lua MiniFiles.open(vim.api.nvim_buf_get_name(0))<CR>]],           'File directory')
nmap_leader('em', [[<Cmd>lua MiniFiles.open('~/.config/nvim/pack/plugins/opt/mini')<CR>]], 'Mini.nvim directory')
nmap_leader('eq', [[<Cmd>lua EC.toggle_quickfix()<CR>]],                                   'Quickfix')

-- f is for 'fuzzy find'
nmap_leader('f/', [[<Cmd>Telescope search_history<CR>]],            '"/" history')
nmap_leader('f:', [[<Cmd>Telescope command_history<CR>]],           'Commands')
nmap_leader('fb', [[<Cmd>lua MiniPick.builtin.buffers()<CR>]],      'Open buffers')
nmap_leader('fB', [[<Cmd>Telescope current_buffer_fuzzy_find<CR>]], 'Open buffers')
nmap_leader('fc', [[<Cmd>Telescope git_commits<CR>]],               'Commits')
nmap_leader('fC', [[<Cmd>Telescope git_bcommits<CR>]],              'Buffer commits')
nmap_leader('fd', [[<Cmd>lua MiniExtra.pickers.diagnostic()<CR>]],         'Diagnostic workspace')
nmap_leader('fD', [[<Cmd>lua MiniExtra.pickers.diagnostic({bufnr=0})<CR>]],       'Diagnostic buffer')
nmap_leader('ff', [[<Cmd>lua MiniPick.builtin.files()<CR>]],        'Files')
nmap_leader('fg', [[<Cmd>lua MiniPick.builtin.grep_live()<CR>]],    'Grep live')
nmap_leader('fh', [[<Cmd>lua MiniPick.builtin.help()<CR>]],         'Help tags')
nmap_leader('fH', [[<Cmd>Telescope highlights<CR>]],                'Highlight groups')
nmap_leader('fj', [[<Cmd>Telescope jumplist<CR>]],                  'Jumplist')
nmap_leader('fo', [[<Cmd>Telescope oldfiles<CR>]],                  'Old files')
nmap_leader('fO', [[<Cmd>Telescope vim_options<CR>]],               'Options')
nmap_leader('fr', [[<Cmd>lua MiniPick.builtin.resume()<CR>]],       'Resume')
nmap_leader('fR', [[<Cmd>Telescope lsp_references<CR>]],            'References (LSP)')
nmap_leader('fs', [[<Cmd>Telescope spell_suggest<CR>]],             'Spell suggestions')
nmap_leader('fS', [[<Cmd>Telescope treesitter<CR>]],                'Symbols (treesitter)')
nmap_leader('ft', [[<Cmd>Telescope file_browser<CR>]],              'File browser')

-- g is for git
nmap_leader('gA', [[<Cmd>lua require("gitsigns").stage_buffer()<CR>]],        'Add buffer')
nmap_leader('ga', [[<Cmd>lua require("gitsigns").stage_hunk()<CR>]],          'Add (stage) hunk')
nmap_leader('gb', [[<Cmd>lua require("gitsigns").blame_line()<CR>]],          'Blame line')
nmap_leader('gg', [[<Cmd>lua EC.open_lazygit()<CR>]],                         'Git tab')
nmap_leader('gp', [[<Cmd>lua require("gitsigns").preview_hunk()<CR>]],        'Preview hunk')
nmap_leader('gq', [[<Cmd>lua require("gitsigns").setqflist()<CR>:copen<CR>]], 'Quickfix hunks')
nmap_leader('gu', [[<Cmd>lua require("gitsigns").undo_stage_hunk()<CR>]],     'Undo stage hunk')
nmap_leader('gx', [[<Cmd>lua require("gitsigns").reset_hunk()<CR>]],          'Discard (reset) hunk')
nmap_leader('gX', [[<Cmd>lua require("gitsigns").reset_buffer()<CR>]],        'Discard (reset) buffer')

-- l is for 'LSP' (Language Server Protocol)
local formatting_command = [[<Cmd>lua vim.lsp.buf.formatting()<CR>]]
if vim.fn.has('nvim-0.8') == 1 then
  formatting_command = [[<Cmd>lua vim.lsp.buf.format({ async = true })<CR>]]
end
nmap_leader('la', [[<Cmd>lua vim.lsp.buf.signature_help()<CR>]], 'Arguments popup')
nmap_leader('ld', [[<Cmd>lua vim.diagnostic.open_float()<CR>]],  'Diagnostics popup')
nmap_leader('lf', formatting_command,                            'Format')
nmap_leader('li', [[<Cmd>lua vim.lsp.buf.hover()<CR>]],          'Information')
nmap_leader('lj', [[<Cmd>lua vim.diagnostic.goto_next()<CR>]],   'Next diagnostic')
nmap_leader('lk', [[<Cmd>lua vim.diagnostic.goto_prev()<CR>]],   'Prev diagnostic')
nmap_leader('lR', [[<Cmd>lua vim.lsp.buf.references()<CR>]],     'References')
nmap_leader('lr', [[<Cmd>lua vim.lsp.buf.rename()<CR>]],         'Rename')
nmap_leader('ls', [[<Cmd>lua vim.lsp.buf.definition()<CR>]],     'Source definition')

xmap_leader('lf' , [[<Cmd>lua vim.lsp.buf.format()<CR><Esc>]],   'Format selection')

-- L is for 'Lua'
nmap_leader('Lf', '<Cmd>luafile %<CR>',                   '`luafile` buffer')
nmap_leader('Lx', [[<Cmd>lua EC.execute_lua_line()<CR>]], 'Execute `lua` line')

-- m is for 'map'
nmap_leader('mc', [[<Cmd>lua MiniMap.close()<CR>]],        'Close')
nmap_leader('mf', [[<Cmd>lua MiniMap.toggle_focus()<CR>]], 'Focus (toggle)')
nmap_leader('mo', [[<Cmd>lua MiniMap.open()<CR>]],         'Open')
nmap_leader('mr', [[<Cmd>lua MiniMap.refresh()<CR>]],      'Refresh')
nmap_leader('ms', [[<Cmd>lua MiniMap.toggle_side()<CR>]],  'Side (toggle)')
nmap_leader('mt', [[<Cmd>lua MiniMap.toggle()<CR>]],       'Toggle')

-- o is for 'other'
local trailspace_toggle_command = [[<Cmd>lua vim.b.minitrailspace_disable = not vim.b.minitrailspace_disable<CR>]]
nmap_leader('oC', [[<Cmd>lua MiniCursorword.toggle()<CR>]],  'Cursor word hl toggle')
nmap_leader('od', [[<Cmd>Neogen<CR>]],                       'Document')
nmap_leader('oh', [[<Cmd>normal gxiagxila<CR>]],             'Move arg left')
nmap_leader('oH', [[<Cmd>TSBufToggle highlight<CR>]],        'Highlight toggle')
nmap_leader('og', [[<Cmd>lua MiniDoc.generate()<CR>]],       'Generate plugin doc')
nmap_leader('ol', [[<Cmd>normal gxiagxina<CR>]],             'Move arg right')
nmap_leader('or', [[<Cmd>lua MiniMisc.resize_window()<CR>]], 'Resize to default width')
nmap_leader('os', [[<Cmd>lua MiniSessions.select()<CR>]],    'Session select')
nmap_leader('oS', [[<Cmd>lua EC.insert_section()<CR>]],      'Section insert')
nmap_leader('ot', [[<Cmd>lua MiniTrailspace.trim()<CR>]],    'Trim trailspace')
nmap_leader('oT', trailspace_toggle_command,                 'Trailspace hl toggle')
nmap_leader('oz', [[<Cmd>lua MiniMisc.zoom()<CR>]],          'Zoom toggle')

-- r is for 'R'
-- - Mappings starting with `T` send commands to current neoterm buffer, so
--   some sort of R interpreter should already run there
nmap_leader('rc', [[<Cmd>T devtools::check()<CR>]],                   'Check')
nmap_leader('rC', [[<Cmd>T devtools::test_coverage()<CR>]],           'Coverage')
nmap_leader('rd', [[<Cmd>T devtools::document()<CR>]],                'Document')
nmap_leader('ri', [[<Cmd>T devtools::install(keep_source=TRUE)<CR>]], 'Install')
nmap_leader('rk', [[<Cmd>T rmarkdown::render("%")<CR>]],              'Knit file')
nmap_leader('rl', [[<Cmd>T devtools::load_all()<CR>]],                'Load all')
nmap_leader('rT', [[<Cmd>T testthat::test_file("%")<CR>]],            'Test file')
nmap_leader('rt', [[<Cmd>T devtools::test()<CR>]],                    'Test')

-- - Copy to clipboard and make reprex (which itself is loaded to clipboard)
xmap_leader('rx', [["+y :T reprex::reprex()<CR>]],                    'Reprex selection')

-- s is for 'send' (Send text to neoterm buffer)
nmap_leader('s', [[<Cmd>TREPLSendLine<CR>j]], 'Send to terminal')

-- - In simple visual mode send text and move to the last character in
--   selection and move to the right. Otherwise (like in line or block visual
--   mode) send text and move one line down from bottom of selection.
xmap_leader(
  's',
  [[mode() ==# "v" ? ":TREPLSendSelection<CR>`>l" : ":TREPLSendSelection<CR>'>j"]],
  'Send to terminal',
  { expr = true }
)

-- t is for 'terminal' (uses 'neoterm') and 'minitest'
nmap_leader('ta', '<Cmd>lua MiniTest.run()<CR>',                   'Test run all')
nmap_leader('tf', '<Cmd>lua MiniTest.run_file()<CR>',              'Test run file')
nmap_leader('tl', '<Cmd>lua MiniTest.run_at_location()<CR>',       'Test run location')
nmap_leader('ts', '<Cmd>lua EC.minitest_screenshots.browse()<CR>', 'Test show screenshot')
nmap_leader('tT', '<Cmd>belowright Tnew<CR>',                      'Terminal (horizontal)')
nmap_leader('tt', '<Cmd>vertical Tnew<CR>',                        'Terminal (vertical)')

-- T is for 'test'
nmap_leader('TF', [[<Cmd>TestFile -strategy=make | copen<CR>]],    'File (quickfix)')
nmap_leader('Tf', [[<Cmd>TestFile<CR>]],                           'File')
nmap_leader('TL', [[<Cmd>TestLast -strategy=make | copen<CR>]],    'Last (quickfix)')
nmap_leader('Tl', [[<Cmd>TestLast<CR>]],                           'Last')
nmap_leader('TN', [[<Cmd>TestNearest -strategy=make | copen<CR>]], 'Nearest (quickfix)')
nmap_leader('Tn', [[<Cmd>TestNearest<CR>]],                        'Nearest')
nmap_leader('TS', [[<Cmd>TestSuite -strategy=make | copen<CR>]],   'Suite (quickfix)')
nmap_leader('Ts', [[<Cmd>TestSuite<CR>]],                          'Suite')
-- stylua: ignore end
