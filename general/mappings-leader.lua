-- stylua: ignore start

-- Create global tables with information about leader mappings in certain modes
-- Structure of tables is taken to be compatible with 'folke/which-key.nvim'.
_G.leader_nmap = {}
_G.leader_xmap = {}

-- b is for 'buffer'
leader_nmap.b = {
  ['name'] = '+buffer',
  ['a'] = { [[<Cmd>b#<CR>]],             'alternate' },
  ['d'] = { [[<Cmd>Bclose<CR>]],         'delete' },
  ['D'] = { [[<Cmd>Bclose!<CR>]],        'delete!' },
  ['s'] = { [[<Cmd>call Scratch()<CR>]], 'scratch' },
}

-- e is for 'explore'
leader_nmap.e = {
  ['name'] = '+explore',
  ['P'] = { [[<Cmd>TroubleToggle lsp_document_diagnostics<CR>]],              'problems document' },
  ['n'] = { [[<Cmd>TroubleToggle todo<CR>]],                                  'notes (todo, etc.)' },
  ['p'] = { [[<Cmd>TroubleToggle lsp_workspace_diagnostics_diagnostics<CR>]], 'problems workspace' },
  ['t'] = { [[<Cmd>NvimTreeToggle<CR>]],                                      'tree' },
  ['u'] = { [[<Cmd>UndotreeToggle<CR>]],                                      'undo-tree' },
}

-- f is for 'fuzzy find'
leader_nmap.f = {
  ['name'] = '+find',
  ['/'] = { [[<Cmd>Telescope search_history<CR>]],            '"/" history' },
  [':'] = { [[<Cmd>Telescope command_history<CR>]],           'commands' },
  ['b'] = { [[<Cmd>Telescope buffers<CR>]],                   'open buffers' },
  ['c'] = { [[<Cmd>Telescope git_commits<CR>]],               'commits' },
  ['C'] = { [[<Cmd>Telescope git_bcommits<CR>]],              'buffer commits' },
  ['d'] = { [[<Cmd>Telescope lsp_workspace_diagnostics<CR>]], 'diagnostic workspace' },
  ['D'] = { [[<Cmd>Telescope lsp_document_diagnostics<CR>]],  'diagnostic buffer' },
  -- Custom function defined in 'nvim-telescope' config
  ['f'] = { [[<Cmd>lua telescope_project_files()<cr>]],       'files' },
  ['g'] = { [[<Cmd>Telescope live_grep<CR>]],                 'grep search' },
  ['h'] = { [[<Cmd>Telescope help_tags<CR>]],                 'help tags' },
  ['H'] = { [[<Cmd>Telescope highlights<CR>]],                'highlight groups' },
  ['j'] = { [[<Cmd>Telescope jumplist<CR>]],                  'jumplist' },
  ['n'] = { [[<Cmd>TodoTelescope<CR>]],                       'notes' },
  ['o'] = { [[<Cmd>Telescope oldfiles<CR>]],                  'old files' },
  ['O'] = { [[<Cmd>Telescope vim_options<CR>]],               'options' },
  ['r'] = { [[<Cmd>Telescope resume<CR>]],                    'resume' },
  ['R'] = { [[<Cmd>Telescope lsp_references<CR>]],            'references (LSP)' },
  ['s'] = { [[<Cmd>Telescope spell_suggest<CR>]],             'spell suggestions' },
  ['S'] = { [[<Cmd>Telescope treesitter<CR>]],                'symbols (treesitter)' },
  ['t'] = { [[<Cmd>Telescope file_browser<CR>]],              'file browser' },
}

-- g is for git
leader_nmap.g = {
  ['name'] = '+git',
  ['A'] = { [[<Cmd>lua require("gitsigns").stage_buffer()<CR>]],        'add buffer' },
  ['a'] = { [[<Cmd>lua require("gitsigns").stage_hunk()<CR>]],          'add (stage) hunk' },
  ['B'] = { [[<Cmd>Git blame<CR>]],                                     'blame buffer' },
  ['b'] = { [[<Cmd>lua require("gitsigns").blame_line()<CR>]],          'blame line' },
  ['D'] = { [[<Cmd>tab Gvdiffsplit<CR>]],                               'diff split' },
  ['d'] = { [[<Cmd>Git diff<CR>]],                                      'diff' },
  ['g'] = { [[<Cmd>Git<CR>]],                                           'git window' },
  ['h'] = { [[<Cmd>diffget //2<CR>]],                                   'merge from left (our)' },
  ['j'] = { [[<Cmd>lua require("gitsigns").next_hunk()<CR>zvzz]],       'next hunk' },
  ['k'] = { [[<Cmd>lua require("gitsigns").prev_hunk()<CR>zvzz]],       'prev hunk' },
  ['l'] = { [[<Cmd>diffget //3<CR>]],                                   'merge from right (their)' },
  ['p'] = { [[<Cmd>lua require("gitsigns").preview_hunk()<CR>]],        'preview hunk' },
  ['q'] = { [[<Cmd>lua require("gitsigns").setqflist()<CR>:copen<CR>]], 'quickfix hunks' },
  ['t'] = { [[<Cmd>GitGutterLineHighlightsToggle<CR>]],                 'toggle highlight' },
  ['u'] = { [[<Cmd>lua require("gitsigns").undo_stage_hunk()<CR>]],     'undo stage hunk' },
  ['U'] = { [[<Cmd>Git reset %<CR>]],                                   'undo stage buffer' },
  ['V'] = { [[<Cmd>GV!<CR>]],                                           'view buffer commits' },
  ['v'] = { [[<Cmd>GV<CR>]],                                            'view commits' },
  ['x'] = { [[<Cmd>lua require("gitsigns").reset_hunk()<CR>]],          'discard (reset) hunk' },
  ['X'] = { [[<Cmd>lua require("gitsigns").reset_buffer()<CR>]],        'discard (reset) buffer' },
}

-- l is for 'LSP' (Language Server Protocol)
leader_nmap.l = {
  ['name'] = '+LSP',
  ['f'] = { [[<Cmd>lua vim.lsp.buf.formatting()<CR>]],                   'format' },
  ['R'] = { [[<Cmd>lua vim.lsp.buf.references()<CR>]],                   'references' },
  ['a'] = { [[<Cmd>lua vim.lsp.buf.signature_help()<CR>]],               'arguments popup' },
  ['d'] = { [[<Cmd>lua vim.lsp.diagnostic.show_line_diagnostics()<CR>]], 'diagnostics popup' },
  ['i'] = { [[<Cmd>lua vim.lsp.buf.hover()<CR>]],                        'information' },
  ['j'] = { [[<Cmd>lua vim.lsp.diagnostic.goto_next()<CR>]],             'next diagnostic' },
  ['k'] = { [[<Cmd>lua vim.lsp.diagnostic.goto_prev()<CR>]],             'prev diagnostic' },
  ['r'] = { [[<Cmd>lua vim.lsp.buf.rename()<CR>]],                       'rename' },
  ['s'] = { [[<Cmd>lua vim.lsp.buf.definition()<CR>]],                   'source definition' },
}

leader_xmap.l = {
  -- Using `:` instead of `<Cmd>` to go back to Normal mode after `<CR>`
  f = { [[:lua vim.lsp.buf.range_formatting()<CR>]], 'format selection' },
}

-- o is for 'other'
leader_nmap.o = {
  ['name'] = '+other',
  ['a'] = { [[<Cmd>ArgWrap<CR>]],                      'arguments split' },
  ['C'] = { [[<Cmd>lua MiniCursorword.toggle()<CR>]],  'cursor word hl toggle' },
  ['d'] = { [[<Cmd>DogeGenerate<CR>]],                 'document' },
  ['h'] = { [[<Cmd>SidewaysLeft<CR>]],                 'move arg left' },
  ['H'] = { [[<Cmd>TSBufToggle highlight<CR>]],        'highlight toggle' },
  ['l'] = { [[<Cmd>SidewaysRight<CR>]],                'move arg right' },
  ['r'] = { [[<Cmd>call ResizeToColorColumn()<CR>]],   'resize to colorcolumn' },
  ['s'] = { [[<Cmd>setlocal spell! spell?<CR>]],       'spell toggle' },
  ['t'] = { [[<Cmd>lua MiniTrailspace.trim()<CR>]],    'trim trailspace' },
  ['T'] = { [[<Cmd>lua MiniTrailspace.toggle()<CR>]],  'trailspace hl toggle' },
  ['w'] = { [[<Cmd>setlocal wrap! wrap?<CR>]],         'wrap toggle' },
  ['z'] = { [[<Cmd>lua _G.zoom_toggle()<CR>]],         'zoom toggle' },
}

-- r is for 'R'
leader_nmap.r = {
  ['name'] = '+R',
  -- Mappings starting with `T` send commands to current neoterm buffer, so
  -- some sort of R interpreter should already run there
  ['c'] = { [[<Cmd>T devtools::check()<CR>]],                   'check' },
  ['C'] = { [[<Cmd>T devtools::test_coverage()<CR>]],           'coverage' },
  ['d'] = { [[<Cmd>T devtools::document()<CR>]],                'document' },
  ['i'] = { [[<Cmd>T devtools::install(keep_source=TRUE)<CR>]], 'install' },
  ['k'] = { [[<Cmd>T rmarkdown::render("%")<CR>]],              'knit file' },
  ['l'] = { [[<Cmd>T devtools::load_all()<CR>]],                'load all' },
  -- `SplitFunSeq()` is defined in 'general/functions.vim'
  ['p'] = { [[<Cmd>call SplitFunSeq("%>%",                      v:true)<CR>]], 'pipe split' },
  ['T'] = { [[<Cmd>T devtools::test_file("%")<CR>]],            'test file' },
  ['t'] = { [[<Cmd>T devtools::test()<CR>]],                    'test' },
}

leader_xmap.r = {
  ['name'] = '+R',
  -- Copy to clipboard and make reprex (which itself is loaded to clipboard)
  ['x'] = { [["+y :T reprex::reprex()<CR>]],                    'reprex selection' },
}

-- s is for 'send' (Send text to neoterm buffer)
leader_nmap.s = { [[<Cmd>TREPLSendLine<CR>j]], 'send to terminal' }
---- In simple visual mode send text and move to the last character in
---- selection and move to the right. Otherwise (like in line or block visual
---- mode) send text and move one line down from bottom of selection.
leader_xmap.s = {
  [[mode() ==# "v" ? ":TREPLSendSelection<CR>`>l" : ":TREPLSendSelection<CR>'>j"]],
  'send to terminal',
  expr = true,
}

-- t is for 'terminal' (uses 'neoterm')
leader_nmap.t = {
  ['name'] = '+terminal',
  -- `ShowActiveNeotermREPL()` is defined in 'general/functions.vim'
  ['a'] = { [[<Cmd>lua _G.print_active_neoterm()<CR>]], 'print active REPL id' },
  ['C'] = { [[<Cmd>TcloseAll!<CR>]],                    'close all terminals' },
  ['c'] = { [[:<C-u>exec v:count."Tclose\!"<CR>]],      'close term (prepend by id)' },
  ['f'] = { [[:<C-u>exec "TREPLSetTerm ".v:count<CR>]], 'focus term (prepend by id)' },
  ['l'] = { [[<Cmd>call neoterm#list_ids()<CR>]],       'list terminals' },
  ['s'] = { [[<Cmd>belowright Tnew<CR>]],               'split terminal' },
  ['v'] = { [[<Cmd>vertical Tnew<CR>]],                 'vsplit terminal' },
}

-- T is for 'test'
leader_nmap.T = {
  ['name'] = '+test',
  ['F'] = { [[<Cmd>TestFile -strategy=make | copen<CR>]],    'file (quickfix)' },
  ['f'] = { [[<Cmd>TestFile<CR>]],                           'file' },
  ['L'] = { [[<Cmd>TestLast -strategy=make | copen<CR>]],    'last (quickfix)' },
  ['l'] = { [[<Cmd>TestLast<CR>]],                           'last' },
  ['N'] = { [[<Cmd>TestNearest -strategy=make | copen<CR>]], 'nearest (quickfix)' },
  ['n'] = { [[<Cmd>TestNearest<CR>]],                        'nearest' },
  ['S'] = { [[<Cmd>TestSuite -strategy=make | copen<CR>]],   'suite (quickfix)' },
  ['s'] = { [[<Cmd>TestSuite<CR>]],                          'suite' },
}

-- stylua: ignore end

-- Make mappings manually to not depend on which-key (because it might not be
-- available for some reason, like when run inside VS Code)
local default_opts = {
  noremap = true,
  silent = true,
  expr = false,
  nowait = false,
  script = false,
  unique = false,
}

local function map_leader_tree(tree, mode, prefix)
  if type(tree) ~= 'table' then
    return
  end

  prefix = prefix or ''

  if type(tree[1]) == 'string' then
    local tree_opts = {
      noremap = tree.noremap,
      silent = tree.silent,
      expr = tree.expr,
      nowait = tree.nowait,
      script = tree.script,
      unique = tree.unique,
    }
    local opts = vim.tbl_deep_extend('force', default_opts, tree_opts)
    vim.api.nvim_set_keymap(mode, string.format('<Leader>%s', prefix), tree[1], opts)
    return
  end

  for key, t in pairs(tree) do
    if key ~= 'name' then
      map_leader_tree(t, mode, prefix .. key)
    end
  end
end

map_leader_tree(leader_nmap, 'n')
map_leader_tree(leader_xmap, 'x')
