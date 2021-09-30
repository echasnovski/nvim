require('ec.settings')
require('ec.functions')
require('ec.mappings')
require('ec.mappings-leader')

if vim.fn.exists('g:vscode') == 1 then
  -- Configuration for integration with VS Code
  require('ec.vscode')
else
  -- Source internal 'mini' plugins
  require('mini')
end

require('ec.packadd')

-- Everything that should be configured at the end
require('ec.zzz')
