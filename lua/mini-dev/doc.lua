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

-- General ideas
--
-- Data structures are basically arrays of certain objects accompanied with
-- `info` field for information to carry with it:
-- - Section structure is an array of string lines describing one aspect
--   (determined by section id like '@param', '@return', '@text') of an
--   annotatation subject. All lines will be used directly in help file.
-- - Block structure is an array of sections describing one annotation subject
--   like function, table, concept.
-- - File structure is an array of blocks (possibly with empty section array
--   but) describing certain file on disk. Basically, file is split into
--   consecutive blocks: annotation lines go inside block, non-annotation -
--   inside `block_afterlines` element of info.
-- - Doc structure is an array of files describing a final help file. Each
--   string line from section (when traversed in depth-first fashion) goes
--   directly into output file.
--
-- Processing:
-- - Processing parameters are an array of input file paths and path to output
--   help file.
-- - Each file lines are processed top to bottom in order to create an array of
--   documentation blocks. Each line is tested on match to certain pattern
--   (`MiniDoc.config.annotation_pattern`) to determine if line is a part of
--   annotation (goes to "current block" after removing matched characters) or
--   not (goes to afterlines of "current block"). Also each matching pattern
--   should provide one capture group extracting section id.
-- - Each block lines are processed top to bottom. If line had captured section
--   id, it is a first line of "current section" (first block lines are allowed
--   to not specify section id; by default it is `@text`). All subsequent lines
--   without captured section id go into "current section". Output is a block
--   structure.
-- - Each block structure is processed by `MiniDoc.config.hooks.block_pre`.
--   This is a designated step for auto-generation of sections from descibed
--   annotation subject (like for sections with id `@tag`, `@type`).
-- - Each section structure is processed by corresponding (table key equals to
--   section id) `MiniDoc.config.hooks.sections` function. This is a step where
--   most of formatting should happen (like add `{}` to first word of `@param`
--   section, append empty line to section, etc.).
-- - Each block structure is processed by `MiniDoc.config.hooks.block_post`. This is
--   a step for processing block after formatting is done (like add first line
--   with `----` delimiter).
-- - Each file structure is processed by `MiniDoc.config.hooks.file`. This is a step
--   for adding any file-related data (like add first line with `====`
--   delimiter).
-- - Doc structure is processed by `MiniDoc.config.hooks.doc`. This is a step
--   for adding any helpfile-related data (maybe like table of contents).

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
  -- Pattern to determine if line has documentation annotation. First capture
  -- group should describe possible section id.
  annotation_pattern = '^%-%-%-(%S*) ?',

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

-- Default section id (assigned to annotation at block start)
H.default_section_id = '@text'

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

-- Parsing
function H.lines_to_blocks(lines)
  local matched_prev, matched_cur

  local res = {}
  local block_raw = { annotation = {}, section_id = {}, afterlines = {}, line_begin = 1 }

  for i, l in ipairs(lines) do
    local from, to, section_id = string.find(l, MiniDoc.config.annotation_pattern)
    matched_prev, matched_cur = matched_cur, from ~= nil

    if matched_cur then
      if not matched_prev then
        -- Finish current block
        block_raw.line_end = i - 1
        table.insert(res, H.raw_block_to_block(block_raw))

        -- Start new block
        block_raw = { annotation = {}, section_id = {}, afterlines = {}, line_begin = i }
      end

      -- Add annotation line without matched annotation pattern
      table.insert(block_raw.annotation, ('%s%s'):format(l:sub(0, from - 1), l:sub(to + 1)))

      -- Add section id (it is empty string in case of no section id capture)
      table.insert(block_raw.section_id, section_id)
    else
      -- Add afterline
      table.insert(block_raw.afterlines, l)
    end
  end
  block_raw.line_end = #lines
  table.insert(res, H.raw_block_to_block(block_raw))

  return res
end

function H.raw_block_to_block(block_raw)
  if #block_raw.annotation == 0 and #block_raw.afterlines == 0 then
    return nil
  end

  local res = {}

  local info = {
    type = 'block',
    block_afterlines = block_raw.afterlines,
    block_line_begin = block_raw.line_begin,
    block_line_end = block_raw.line_end,
  }
  local block_begin = info.block_line_begin

  local section_cur = {
    info = { type = 'section', section_id = H.default_section_id, section_line_begin = block_begin },
  }
  for i, ann_l in ipairs(block_raw.annotation) do
    local id = block_raw.section_id[i]
    if id ~= '' then
      -- Finish current section
      if #section_cur > 0 then
        section_cur.info.section_line_end = block_begin + i - 2
        table.insert(res, section_cur)
      end

      -- Start new section
      section_cur = { info = { type = 'section', section_id = id, section_line_begin = block_begin + i - 1 } }
    end
    table.insert(section_cur, ann_l)
  end
  if #section_cur > 0 then
    section_cur.info.section_line_end = block_begin + #block_raw.annotation - 1
    table.insert(res, section_cur)
  end

  res.info = info

  return res
end

-- Utilities
function H.read_file(path)
  local fp = assert(io.open(path))
  local contents = fp:read('*all')
  fp:close()

  return vim.split(contents, '\n')
end

_G.lines = H.read_file(vim.fn.fnamemodify('~/.config/nvim/lua/mini-dev/test-doc.lua', ':p'))

return MiniDoc
