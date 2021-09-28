local has_gitsigns, gitsigns = pcall(require, 'gitsigns')
if not has_gitsigns then
  return
end

-- Setup
-- stylua: ignore start
gitsigns.setup({
  keymaps = {
    -- Default keymap options
    noremap = true,
    silent = true,

    -- Text objects
    ['o ih'] = ':<C-U>lua require"gitsigns".select_hunk()<CR>',
    ['x ih'] = ':<C-U>lua require"gitsigns".select_hunk()<CR>',
  },
  watch_gitdir = { interval = 1000 },
})
-- stylua: ignore end
