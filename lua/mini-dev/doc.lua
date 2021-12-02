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
-- stylua: ignore start
MiniDoc.config = {
  -- Pattern to determine if line has documentation annotation
  annotation_pattern = '^%-%-%-(.-) ',

  -- Hooks to be applied at certain stage of document life cycle
  hooks = {
    block_pre = function() end,
    sections = {
      ['@class'] = function(lines) return lines end,
      ['@param'] = function(lines) return lines end,
      ['@private'] = function(lines) return lines end,
      ['@property'] = function(lines) return lines end,
      ['@return'] = function(lines) return lines end,
      ['@tag'] = function(lines) return lines end,
      ['@title'] = function(lines) return lines end,
      ['@text'] = function(lines) return lines end,
      ['@type'] = function(lines) return lines end,
      ['@usage'] = function(lines) return lines end,
    },
    block_post = function() end,
    file = function() end,
    doc = function() end,
  },
}
-- stylua: ignore end

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

    ['hooks.sections'] = { config.hooks.sections, 'table', true },
    ['hooks.sections.@class'] = { config.hooks.sections['@class'], 'function' },
    ['hooks.sections.@param'] = { config.hooks.sections['@param'], 'function' },
    ['hooks.sections.@private'] = { config.hooks.sections['@private'], 'function' },
    ['hooks.sections.@property'] = { config.hooks.sections['@property'], 'function' },
    ['hooks.sections.@return'] = { config.hooks.sections['@return'], 'function' },
    ['hooks.sections.@tag'] = { config.hooks.sections['@tag'], 'function' },
    ['hooks.sections.@text'] = { config.hooks.sections['@text'], 'function' },
    ['hooks.sections.@type'] = { config.hooks.sections['@type'], 'function' },
    ['hooks.sections.@usage'] = { config.hooks.sections['@usage'], 'function' },

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
