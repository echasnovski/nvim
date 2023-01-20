-- Initialize global object to store custom objects
_G.EC = {}

-- Source configuration files
require('ec.packadd')
require('ec.settings')
require('ec.functions')
require('ec.mappings')
require('ec.mappings-leader')

if vim.g.vscode ~= nil then require('ec.vscode') end
