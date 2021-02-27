-- Currently is not used in favor of 'vim-gitgutter'
local ok, gitsigns = pcall(require, 'gitsigns')

if not ok then return end

-- Define custom colors
vim.api.nvim_exec([[
  hi GitSignsAdd    guifg=#b8bb26
  hi GitSignsChange guifg=#8ec07c
  hi GitSignsDelete guifg=#fb4934
]], false)

-- Setup
gitsigns.setup {
  signs = {
    add          = {hl = 'GitSignsAdd'   , text = '│'},
    change       = {hl = 'GitSignsChange', text = '│'},
    delete       = {hl = 'GitSignsDelete', text = '_'},
    topdelete    = {hl = 'GitSignsDelete', text = '‾'},
    changedelete = {hl = 'GitSignsChange', text = '~'},
  },
  numhl = false,
  keymaps = {
    -- Default keymap options
    noremap = true,
    buffer = true,

    ['n <leader>gB'] = '<cmd>lua require"gitsigns".blame_line()<CR>',
    ['n <leader>ga'] = '<cmd>lua require"gitsigns".stage_hunk()<CR>',
    ['n <leader>gj'] = '<cmd>lua require"gitsigns".next_hunk()<CR>zz', -- Go to next hunk and center screen
    ['n <leader>gk'] = '<cmd>lua require"gitsigns".prev_hunk()<CR>zz', -- Go to previous hunk and center screen
    ['n <leader>gp'] = '<cmd>lua require"gitsigns".preview_hunk()<CR>',
    ['n <leader>gr'] = '<cmd>lua require"gitsigns".reset_hunk()<CR>',
    ['n <leader>gu'] = '<cmd>lua require"gitsigns".undo_stage_hunk()<CR>',

    ['o ih'] = ':<C-U>lua require"gitsigns".text_object()<CR>',
    ['x ih'] = ':<C-U>lua require"gitsigns".text_object()<CR>'
  },
  watch_index = {
    interval = 1000
  },
  sign_priority = 6,
  status_formatter = nil -- Use default
}
