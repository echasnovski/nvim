local has_gitsigns, gitsigns = pcall(require, 'gitsigns')
if not has_gitsigns then return end

-- Setup
gitsigns.setup({
  signs = {
    add          = {hl = 'DiffAdd'   , text = '│'},
    change       = {hl = 'DiffChange', text = '│'},
    delete       = {hl = 'DiffDelete', text = '_'},
    topdelete    = {hl = 'DiffDelete', text = '‾'},
    changedelete = {hl = 'DiffChange', text = '~'},
  },
  keymaps = {
    -- Default keymap options
    noremap = true,
    silent = true,

    ['n <leader>ga'] = '<cmd>lua require("gitsigns").stage_hunk()<CR>',
    ['n <leader>gA'] = '<cmd>lua require("gitsigns").stage_buffer()<CR>',
    ['n <leader>gb'] = '<cmd>lua require("gitsigns").blame_line()<CR>',
    ['n <leader>gj'] = '<cmd>lua require("gitsigns").next_hunk()<CR>zvzz', -- Go to next hunk and center screen
    ['n <leader>gk'] = '<cmd>lua require("gitsigns").prev_hunk()<CR>zvzz', -- Go to previous hunk and center screen
    ['n <leader>gp'] = '<cmd>lua require("gitsigns").preview_hunk()<CR>',
    ['n <leader>gq'] = '<cmd>lua require("gitsigns").setqflist()<CR>:copen<CR>',
    ['n <leader>gu'] = '<cmd>lua require("gitsigns").undo_stage_hunk()<CR>',
    ['n <leader>gx'] = '<cmd>lua require("gitsigns").reset_hunk()<CR>',
    ['n <leader>gX'] = '<cmd>lua require("gitsigns").reset_buffer()<CR>',

    -- Text objects
    ['o ih'] = ':<C-U>lua require"gitsigns".select_hunk()<CR>',
    ['x ih'] = ':<C-U>lua require"gitsigns".select_hunk()<CR>'
  },
  watch_index = {interval = 1000}
})
