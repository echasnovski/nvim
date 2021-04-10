local has_completion, completion = pcall(require, 'completion')
if not has_completion then return end

-- Use completion-nvim in every buffer
vim.api.nvim_exec([[
  autocmd BufEnter * lua require'completion'.on_attach()
]], false)

-- Use custom "rate of completion" (default 80). Currently this means that
-- every `x` milliseconds in insert mode some function is executed via Lua's
-- `timer:start`. This in turn triggers statusline redraw (see
-- https://github.com/neovim/neovim/issues/14303).
vim.g.completion_timer_cycle = 200

-- Enable manual trigger
vim.api.nvim_exec([[imap <silent> <C-Space> <Plug>(completion_trigger)]], false)

-- Setup snippets engine
vim.g.completion_enable_snippet = 'UltiSnips'
-- vim.g.completion_enable_snippet = 'vim-vsnip'

-- Use all available sources automatically
vim.g.completion_auto_change_source = 1

-- Use smartcase when searching for match
vim.g.completion_matching_smart_case = 1

-- Still use completion when deleting
vim.g.completion_trigger_on_delete = 1

-- Setup matching strategy
vim.g.completion_matching_strategy_list = {'exact', 'substring'}

-- Set up 'precedence' between completion sources
vim.g.completion_chain_complete_list = {
  {complete_items = {'snippet', 'lsp', 'keyn'}},
  {mode = '<c-n>'}
}

-- Make completion work nicely with auto-pairs plugin ('pear-tree' in my
-- setup). This should also enable snippet expansion.
-- NOTE: previously had some trouble with this. Solutions that worked:
-- - Moving this somewhere to be executed after all other settings.
-- - Having directly `<Plug>(PearTreeExpand)` instead of `<CR>`.
vim.g.completion_confirm_key = ''
vim.api.nvim_set_keymap(
  'i', '<CR>',
  [[pumvisible() ]] ..
    [[? complete_info()["selected"] != "-1" ]] ..
      [[? "\<Plug>(completion_confirm_completion)" ]] ..
      [[: "\<c-e>\<CR>" ]] ..
    [[: "\<CR>"]],
  {expr = true}
)

-- Don't use any sorting, as it not always intuitive (for example, puts
-- suggestions starting with '_' on top in case of 'alphabetical')
vim.g.completion_sorting = 'none'
