local has_compe, compe = pcall(require, 'compe')
if not has_compe then return end

vim.o.completeopt = "menuone,noselect"

compe.setup {
  enabled = true;
  autocomplete = true;
  debug = false;
  min_length = 1;
  preselect = 'enable';
  throttle_time = 80;
  source_timeout = 200;
  incomplete_delay = 400;
  max_abbr_width = 100;
  max_kind_width = 100;
  max_menu_width = 100;
  documentation = true;

  -- Make 'nvim-compe' work with non-latin letters
  default_pattern = [[\k\+]];

  source = {
    path = true;
    buffer = true;
    calc = true;
    ultisnips = true;
    nvim_lsp = true;
    nvim_lua = true;
    spell = true;
    tags = true;
    treesitter = true;
    -- omni = true;
  };
}

vim.api.nvim_set_keymap(
  'i', '<C-Space>', [[compe#complete()]],
  {silent = true, expr = true, noremap = true}
)
---- '<CR>' mapping is done in 'lua-mappings.lua'
-- vim.api.nvim_set_keymap(
--   'i', '<CR>', [[compe#confirm('<CR>')]],
--   {silent = true, expr = true, noremap = true}
-- )
vim.api.nvim_set_keymap(
  'i', '<C-e>', [[compe#close('<C-e>')]],
  {silent = true, expr = true, noremap = true}
)
