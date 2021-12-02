-- MIT License Copyright (c) 2021 Evgeni Chasnovski

---@brief [[
--- Minimal generation of help files from EmmyLua-like annotations. Key design
--- ideas:
--- - Any consecutive lines with predefined prefix will be considered as
---   documentation block.
--- - Allow custom hooks at multiple conversion stages for more granular
---   management of output help file.
---
--- # Setup
---
--- This module needs a setup with `require('mini.doc').setup({})`
--- (replace `{}` with your `config` table). It will create global Lua table
--- `MiniDoc` which you can use for scripting or manually (with
--- `:lua MiniDoc.*`).
---
--- Default `config`:
--- <code>
---   {
---     hooks = {
---       block_pre = -- function
---       tags = {
---         ['@class'] = -- function
---         ['@param'] = -- function
---         ['@property'] = -- function
---         ['@return'] = -- function
---         ['@tag'] = -- function
---         ['@text'] = -- function
---         ['@type'] = -- function
---         ['@usage'] = -- function
---       },
---       block_post = -- function
---       file = -- function
---       doc = -- function
---     }
---   }
--- </code>
---
--- # Tips
---
--- - Set up 'formatoptions' and 'formatlistpat'.
---
--- # Comparisons
---
--- - 'tjdevries/tree-sitter-lua':
---
--- # Disabling
---
--- To disable, set `g:minidoc_disable` (globally) or
--- `b:minidoc_disable` (for a buffer) to `v:true`.
---@brief ]]
---@tag MiniDoc mini.doc

-- Module and its helper --
local MiniDoc = {}
H = {}

--- Module setup
---
---@param config table: Module config table.
---@usage `require('mini.doc').setup({})` (replace `{}` with your `config` table)
function MiniDoc.setup(config)
  -- Export module
  _G.MiniDoc = MiniDoc

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)
end

-- Module config --
MiniDoc.config = {
  hooks = {
    block_pre = function() end,
    tags = {
      ['@class'] = function() end,
      ['@param'] = function() end,
      ['@property'] = function() end,
      ['@return'] = function() end,
      ['@tag'] = function() end,
      ['@text'] = function() end,
      ['@type'] = function() end,
      ['@usage'] = function() end,
    },
    block_post = function() end,
    file = function() end,
    doc = function() end,
  },
}

-- Helper data --
-- Module default config
H.default_config = MiniDoc.config

-- Helper functions --
-- Settings
function H.setup_config(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    hooks = { config.hooks, 'table' },
    ['hooks.block_pre'] = { config.hooks.block_pre, 'function' },

    ['hooks.tags'] = { config.hooks.tags, 'table' },
    ['hooks.tags.@class'] = { config.hooks.tags['@class'], 'function' },
    ['hooks.tags.@param'] = { config.hooks.tags['@param'], 'function' },
    ['hooks.tags.@property'] = { config.hooks.tags['@property'], 'function' },
    ['hooks.tags.@return'] = { config.hooks.tags['@return'], 'function' },
    ['hooks.tags.@tag'] = { config.hooks.tags['@tag'], 'function' },
    ['hooks.tags.@text'] = { config.hooks.tags['@text'], 'function' },
    ['hooks.tags.@type'] = { config.hooks.tags['@type'], 'function' },
    ['hooks.tags.@usage'] = { config.hooks.tags['@usage'], 'function' },

    ['hooks.block_post'] = { config.hooks.block_post, 'function' },
    ['hooks.file'] = { config.hooks.file, 'function' },
    ['hooks.doc'] = { config.hooks.doc, 'function' },
  })

  return config
end

function H.apply_config(config)
  MiniDoc.config = config
end

function H.is_disabled()
  return vim.g.minidoc_disable == true or vim.b.minidoc_disable == true
end

return MiniDoc
