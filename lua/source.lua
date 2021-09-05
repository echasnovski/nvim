-- Entry point from 'init.vim' to source all Lua files

-- Source internal 'mini' plugins
require('mini')

-- Source everything that should be sourced last
require('zzz')
