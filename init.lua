require('ec.settings')
require('ec.functions')
require('ec.mappings')
require('ec.mappings-leader')

if vim.fn.exists('g:vscode') == 1 then
  require('ec.vscode')
end

require('ec.packadd')

require('ec.zzz')
