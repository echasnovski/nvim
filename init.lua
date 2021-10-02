require('ec.settings')
require('ec.functions')
require('ec.mappings')
require('ec.mappings-leader')
require('ec.packadd')

if vim.fn.exists('g:vscode') == 1 then
  require('ec.vscode')
end
