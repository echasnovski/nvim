-- Initialize global object to store custom objects
_G.EC = {}

-- Source configuration files
require('ec.settings')
require('ec.functions')
require('ec.mappings')
require('ec.mappings-leader')
require('ec.packadd')

if vim.g.vscode ~= nil then
  require('ec.vscode')
end
