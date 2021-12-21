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
-- - File structure is an array of blocks describing certain file on disk.
--   Basically, file is split into consecutive blocks: annotation lines go
--   inside block, non-annotation - inside `block_afterlines` element of info.
-- - Doc structure is an array of files describing a final help file. Each
--   string line from section (when traversed in depth-first fashion) goes
--   directly into output file.
--
-- Generating:
-- - Main parameters for help generation are an array of input file paths and
--   path to output help file.
-- - Parse all inputs:
--   - For each file, lines are processed top to bottom in order to create an
--     array of documentation blocks. Each line is tested on match to certain
--     pattern (`MiniDoc.config.annotation_pattern`) to determine if line is a
--     part of annotation (goes to "current block" after removing matched
--     characters) or not (goes to afterlines of "current block"). Also each
--     matching pattern should provide one capture group extracting section id.
--   - Each block's annotation lines are processed top to bottom. If line had
--     captured section id, it is a first line of "current section" (first
--     block lines are allowed to not specify section id; by default it is
--     `@text`). All subsequent lines without captured section id go into
--     "current section".
-- - Apply hooks:
--     - Each block structure is processed by `MiniDoc.config.hooks.block_pre`.
--       This is a designated step for auto-generation of sections from
--       descibed annotation subject (like sections with id `@tag`, `@type`).
--     - Each section structure is processed by corresponding
--       `MiniDoc.config.hooks.sections` function (table key equals to section
--       id). This is a step where most of formatting should happen (like wrap
--       first word of `@param` section with `{` and `}`, append empty line to
--       section, etc.).
--     - Each block structure is processed by
--       `MiniDoc.config.hooks.block_post`. This is a step for processing block
--       after formatting is done (like add first line with `----` delimiter).
--     - Each file structure is processed by `MiniDoc.config.hooks.file`. This
--       is a step for adding any file-related data (like add first line with
--       `====` delimiter).
--     - Doc structure is processed by `MiniDoc.config.hooks.doc`. This is a
--       step for adding any helpfile-related data (maybe like table of
--       contents).
-- - Collect all strings from sections in depth-first fashion (equivalent to
--   nested "for all files -> for all blocks -> for all sections -> for all
--   strings") and write them to output file.

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
  -- Lua string pattern to determine if line has documentation annotation.
  -- First capture group should describe possible section id.
  annotation_pattern = '^%-%-%-(%S*) ?',

  -- Hooks to be applied at certain stage of document life cycle
  hooks = {
    block_pre = function(b) return b end,
    sections = {
      ['@class']    = function(s) return s end,
      ['@param']    = function(s) return s end,
      ['@private']  = function(s) return s end,
      ['@property'] = function(s) return s end,
      ['@return']   = function(s) return s end,
      ['@tag']      = function(s) return s end,
      ['@title']    = function(s) return s end,
      ['@text']     = function(s) return s end,
      ['@type']     = function(s) return s end,
      ['@usage']    = function(s) return s end,
    },
    block_post = function(b) return b end,
    file = function(f) return f end,
    doc = function(d) return d end,
  },
}
-- stylua: ignore end

function MiniDoc.generate(input, output, opts)
  input = input or H.default_input()
  output = output or H.default_output()
  opts = vim.tbl_deep_extend('force', {}, opts or {})

  -- Parse input files
  local doc_info = { doc_input = input, doc_output = output, doc_opts = opts }
  local doc = vim.tbl_map(function(x)
    return H.parse_file(x, doc_info)
  end, input)
  doc.info = doc_info

  -- Apply hooks
  doc = H.apply_hooks(doc)

  -- Gather string lines in depth-first fashion
  local help_lines = H.collect_strings(doc)

  -- Write helpfile
  -- vim.fn.writefile(help_lines, output, 'b')
  return help_lines
end

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

-- Default documentation targets --
function H.default_input()
  -- Search in current and recursively in other directories for files with
  -- 'lua' extension
  local res = {}
  for _, dir_glob in ipairs({ '.', 'lua/**', 'after/**', 'colors/**' }) do
    local files = vim.fn.globpath(dir_glob, '*.lua', false, true)

    -- Use full paths
    files = vim.tbl_map(function(x)
      return vim.fn.fnamemodify(x, ':p')
    end, files)

    -- Put 'init.lua' first among files from same directory
    table.sort(files, function(a, b)
      if vim.fn.fnamemodify(a, ':h') == vim.fn.fnamemodify(b, ':h') then
        if vim.fn.fnamemodify(a, ':t') == 'init.lua' then
          return true
        end
        if vim.fn.fnamemodify(b, ':t') == 'init.lua' then
          return false
        end
      end

      return a < b
    end)
    table.insert(res, files)
  end

  return vim.tbl_flatten(res)
end

function H.default_output()
  local cur_dir = vim.fn.fnamemodify(vim.loop.cwd(), ':t:r')
  return ('doc/%s'):format(cur_dir)
end

-- Parsing --
function H.parse_file(file_path, doc_info)
  local lines = H.read_file(file_path)
  local file_info = H.new_info({ file_path = file_path }, doc_info)

  -- File structure is an array of block structures with `info` field
  local file = H.lines_to_blocks(lines, file_info)
  file.info = file_info
  return file
end

function H.lines_to_blocks(lines, file_info)
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
        table.insert(res, H.raw_block_to_block(block_raw, file_info))

        -- Start new block
        block_raw = { annotation = {}, section_id = {}, afterlines = {}, line_begin = i }
      end

      -- Add annotation line without matched annotation pattern
      table.insert(block_raw.annotation, ('%s%s'):format(l:sub(0, from - 1), l:sub(to + 1)))

      -- Add section id (it is empty string in case of no section id capture)
      table.insert(block_raw.section_id, section_id or '')
    else
      -- Add afterline
      table.insert(block_raw.afterlines, l)
    end
  end
  block_raw.line_end = #lines
  table.insert(res, H.raw_block_to_block(block_raw, file_info))

  return res
end

-- Raw block structure is an intermediate step added for convenience. It is
-- a table with the following keys:
-- - `annotation` - lines (after removing matched annotation pattern) that were
--   parsed as annotation.
-- - `section_id` - array with length equal to `annotation` length with strings
--   captured as section id. Empty string of no section id was captured.
-- - Everything else is used as block info (like `afterlines`, etc.).
function H.raw_block_to_block(block_raw, file_info)
  if #block_raw.annotation == 0 and #block_raw.afterlines == 0 then
    return nil
  end

  local block = {}
  block.info = H.new_info({
    type = 'block',
    block_afterlines = block_raw.afterlines,
    block_line_begin = block_raw.line_begin,
    block_line_end = block_raw.line_end,
  }, file_info)
  local block_begin = block.info.block_line_begin

  -- Parse raw block annotation lines from top to bottom. New section starts
  -- when section id is detected in that line.
  local section_cur = {
    info = H.new_info(
      { type = 'section', section_id = H.default_section_id, section_line_begin = block_begin },
      block.info
    ),
  }

  for i, ann_l in ipairs(block_raw.annotation) do
    local id = block_raw.section_id[i]
    if id ~= '' then
      -- Finish current section
      if #section_cur > 0 then
        section_cur.info.section_line_end = block_begin + i - 2
        table.insert(block, section_cur)
      end

      -- Start new section
      section_cur = {
        info = H.new_info({ type = 'section', section_id = id, section_line_begin = block_begin + i - 1 }, block.info),
      }
    end

    table.insert(section_cur, ann_l)
  end

  if #section_cur > 0 then
    section_cur.info.section_line_end = block_begin + #block_raw.annotation - 1
    table.insert(block, section_cur)
  end

  return block
end

-- Hooks --
function H.apply_hooks(doc)
  local new_doc = { info = doc.info }

  for _, file in ipairs(doc) do
    local new_file = { info = file.info }

    for _, block in ipairs(file) do
      block = MiniDoc.config.hooks.block_pre(block)

      local new_block = { info = block.info }

      for _, section in ipairs(block) do
        local hook = MiniDoc.config.hooks.sections[section.info.section_id]
        local new_section = hook ~= nil and hook(section) or section
        table.insert(new_block, new_section)
      end

      new_block = MiniDoc.config.hooks.block_post(new_block)
      table.insert(new_file, new_block)
    end

    new_file = MiniDoc.config.hooks.file(new_file)
    table.insert(new_doc, new_file)
  end

  new_doc = MiniDoc.config.hooks.doc(new_doc)

  return new_doc
end

-- Utilities --
function H.apply_recursively(f, x, into)
  f(x, into)

  if type(x) == 'table' then
    for _, t in ipairs(x) do
      into = H.apply_recursively(f, t, into)
    end
  end

  return into
end

function H.collect_strings(x)
  return H.apply_recursively(function(y, into)
    if type(y) == 'string' then
      table.insert(into, y)
    end
    return into
  end, x, {})
end

function H.read_file(path)
  local fp = assert(io.open(path))
  local contents = fp:read('*all')
  fp:close()

  return vim.split(contents, '\n')
end

function H.new_info(values, larger_info)
  -- return setmetatable(values, { __index = larger_info })
  return vim.tbl_extend('force', larger_info or {}, values or {})
end

_G.lines = H.read_file(vim.fn.fnamemodify('~/.config/nvim/lua/mini-dev/test-doc.lua', ':p'))

return MiniDoc
