local has_null_ls, null_ls = pcall(require, 'null-ls')
local has_lspconfig, lspconfig = pcall(require, 'lspconfig')
if not (has_null_ls and has_lspconfig) then
  return
end

local helpers = require('null-ls.helpers')

-- Define 'styler' formatting for R. Package should be installed in library
-- used by `R` command.
local r_styler = {
  name = 'styler',
  method = null_ls.methods.FORMATTING,
  filetypes = { 'r', 'rmd' },
  generator = helpers.formatter_factory({
    command = 'R',
    args = {
      '--slave',
      '--no-restore',
      '--no-save',
      '-e',
      'con=file("stdin");output=styler::style_text(readLines(con));close(con);print(output, colored=FALSE)',
    },
    to_stdin = true,
    suppress_errors = false,
  }),
}

null_ls.register(r_styler)

-- Configuring null-ls for other sources
null_ls.config({
  sources = {
    -- `black` should be set up as callable from command line (be in '$PATH')
    null_ls.builtins.formatting.black,
    -- `stylua` should be set up as callable from command line (be in '$PATH')
    null_ls.builtins.formatting.stylua,
  },
})

-- Set up null-ls server
-- NOTE: currently mappings for formatting with `vim.lsp.buf.formatting()` and
-- `vim.lsp.buf.range_formatting()` are set up for every buffer in
-- 'mappings-leader.vim'. This is done to make 'which-key' respect labels.
lspconfig['null-ls'].setup({})
