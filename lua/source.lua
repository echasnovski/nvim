-- Entry point from 'init.vim' to source all Lua files

-- Source external plugin configurations
require('plugin-setup')

-- Source internal 'mini' plugins
require('mini')

-- Source miscellaneous functions
require('misc')

-- Source everything that should be sourced last
require('zzz')
