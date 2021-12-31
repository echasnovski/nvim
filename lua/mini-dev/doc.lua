-- MIT License Copyright (c) 2021 Evgeni Chasnovski

-- Documentation ==============================================================
--- GENERATION OF HELP FILES FROM EMMYLUA-LIKE ANNOTATIONS
---
--- Key design ideas:
--- - Any consecutive lines with predefined prefix will be considered as
---   documentation block.
--- - Allow custom hooks at multiple conversion stages for more granular
---   management of output help file.
---
--- # Setup~
---
--- This module needs a setup with `require('mini.doc').setup({})`
--- (replace `{}` with your `config` table). It will create global Lua table
--- `MiniDoc` which you can use for scripting or manually (with
--- `:lua MiniDoc.*`).
---
--- Default `config`:
--- >
---   {
---   }
--- <
--- # Tips~
---
--- - Set up 'formatoptions' and 'formatlistpat'.
---
--- # Comparisons~
---
--- - 'tjdevries/tree-sitter-lua':
---
--- # Disabling~
---
--- To disable, set `g:minidoc_disable` (globally) or
--- `b:minidoc_disable` (for a buffer) to `v:true`.
---@tag MiniDoc mini.doc

-- General ideas
--
-- Data structures are basically arrays of other structures accompanied with
-- some fields (keys with data values) and methods (keys with function values):
-- - Section structure is an array of string lines describing one aspect
--   (determined by section id like '@param', '@return', '@text') of an
--   annotation subject. All lines will be used directly in help file.
-- - Block structure is an array of sections describing one annotation subject
--   like function, table, concept.
-- - File structure is an array of blocks describing certain file on disk.
--   Basically, file is split into consecutive blocks: annotation lines go
--   inside block, non-annotation - inside `block_afterlines` element of info.
-- - Doc structure is an array of files describing a final help file. Each
--   string line from section (when traversed in depth-first fashion) goes
--   directly into output file.
--
-- All structures have these keys:
-- - Fields:
--     - `info` - contains additional information about current structure.
--     - `parent` - table of parent structure (if exists).
--     - `parent_index` - index of this structure in its parent's array. Useful
--       for adding to parent another structure near current one.
--     - `type` - string with structure type (doc, file, block, section).
-- - Methods (use them as `x:method(args)`):
--     - `insert(self, [index,] child)` - insert `child` to `self` at position
--       `index` (optional; if not supplied, child will be appended to end).
--       Basically, a `table.insert()`, but adds `parent` and `parent_index`
--       fields to `child` while properly updating `self`.
--     - `remove(self [,index])` - remove from `self` element at position
--       `index`. Basically, a `table.remove()`, but properly updates `self`.
--     - `has_descendant(self, predicate)` - whether there is a descendant
--       (structure or string) for which `predicate` returns `true`. In case of
--       success also returns the first such descendant as second value.
--     - `has_lines(self)` - whether structure has any lines (even empty ones)
--       to be put in output file. For section structures this is equivalent to
--       `#self`, but more useful for higher order structures.
--     - `clear_lines(self)` - remove all lines from structure. As a result,
--       this structure won't contribute to output help file.
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
-- - Apply hooks (they should modify its input in place, which is possible due
--   to 'table nature' of all possible inputs):
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
--   strings") and write them to output file. Strings can have `\n` character
--   indicating start of new line.

-- Module definition ==========================================================
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

MiniDoc.config = {
  -- Lua string pattern to determine if line has documentation annotation.
  -- First capture group should describe possible section id.
  annotation_pattern = '^%-%-%-(%S*) ?',

  -- Hooks to be applied at certain stage of document life cycle. Should modify
  -- its input in place (and not return new one).
  hooks = {
    block_pre = function(b) end,
    sections = {
      ['@alias'] = function(s)
        H.register_alias(s)
        -- NOTE: don't use `s.parent:remove(s.parent_index)` here because it
        -- disrupts iteration over block's section during hook application
        -- (skips next section).
        s:clear_lines()
      end,
      ['@class'] = function(s)
        H.enclose_first_word(s, '{%1}')
        H.add_section_heading(s, 'Class')
      end,
      ['@eval'] = function(s)
        -- -- This seems like better alternative but there is actually no function
        -- -- `vim.api.nvim_exec_lua()` (despite having it inside `:help`)
        -- local output = vim.api.nvim_exec_lua(table.concat(s, '\n'), {['_section_'] = s})

        local src = 'lua << EOF\n' .. table.concat(s, '\n') .. '\nEOF'
        _G._minidoc_current_section = s
        -- `output` catches output of the code. Use `print()` to return lines.
        local output = vim.api.nvim_exec(src, true)
        _G._minidoc_current_section = nil

        s:clear_lines()
        s[1] = output
      end,
      ['@field'] = function(s)
        H.enclose_first_word(s, '{%1}')
        H.replace_aliases(s)
      end,
      ['@param'] = function(s)
        H.enclose_first_word(s, '{%1}')
        H.replace_aliases(s)
      end,
      ['@private'] = function(s)
        s.parent.info._is_private = true
      end,
      ['@return'] = function(s)
        H.enclose_first_word(s, '{%1}')
        H.replace_aliases(s)
        H.add_section_heading(s, 'Return')
      end,
      ['@tag'] = function(s)
        for i, _ in ipairs(s) do
          -- Enclose every word in `*`
          local n_tags = 0
          s[i], n_tags = s[i]:gsub('(%S+)', '%*%1%*')

          -- Right justify to width 78 in `help` filetype ('*' has width 0)
          local n_left = math.max(0, 78 - s[i]:len() + 2 * n_tags)
          local left = string.rep(' ', n_left)
          s[i] = ('%s%s'):format(left, s[i])
        end
      end,
      ['@text'] = function() end,
      ['@type'] = function() end,
      ['@usage'] = function(s)
        H.add_section_heading(s, 'Usage')
      end,
    },
    block_post = function(b)
      -- Remove block if it is private
      if b.info._is_private then
        b:clear_lines()
        return
      end

      local found_param, found_field = false, false
      H.apply_recursively(function(x)
        if not (type(x) == 'table' and x.type == 'section') then
          return
        end

        -- Add headings before first occurence of a section which type usually
        -- appear several times
        if not found_param and x.info.id == '@param' then
          H.add_section_heading(x, 'Parameters')
          found_param = true
        end
        if not found_field and x.info.id == '@field' then
          H.add_section_heading(x, 'Fields')
          found_field = true
        end

        -- Move all tag sections in the beginning. NOTE: due to depth-first
        -- nature, this approach will reverse order of tag sections if there
        -- are more than one; doesn't seem to be a big deal.
        if x.info.id == '@tag' then
          x.parent:remove(x.parent_index)
          x.parent:insert(1, x)
        end
      end, b)

      if b:has_lines() then
        b:insert(1, H.as_struct({ H.separator_block }, 'section'))
        b:insert(H.as_struct({ '' }, 'section'))
      end
    end,
    file = function(f)
      if f:has_lines() then
        f:insert(1, H.as_struct({ H.as_struct({ H.separator_file }, 'section') }, 'block'))
        f:insert(H.as_struct({ H.as_struct({ '' }, 'section') }, 'block'))
      end
    end,
    doc = function(d)
      d:insert(
        H.as_struct(
          { H.as_struct({ H.as_struct({ ' vim:tw=78:ts=8:noet:ft=help:norl:' }, 'section') }, 'block') },
          'file'
        )
      )
    end,
  },
}

-- Module functionality =======================================================
function MiniDoc.generate(input, output, opts)
  input = input or H.default_input()
  output = output or H.default_output()
  opts = vim.tbl_deep_extend('force', {}, opts or {})

  H.alias_registry = {}

  -- Parse input files
  local doc = H.new_struct('doc', { input = input, output = output, opts = opts })
  for _, path in ipairs(input) do
    local lines = H.file_read(path)
    local block_arr = H.lines_to_block_arr(lines)
    local file = H.new_struct('file', { path = path })
    for _, b in ipairs(block_arr) do
      file:insert(b)
    end

    doc:insert(file)
  end

  -- Apply hooks
  H.apply_hooks(doc)

  -- Gather string lines in depth-first fashion
  local help_lines = H.collect_strings(doc)

  -- Write helpfile
  H.file_write(output, help_lines)
  return doc
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniDoc.config

-- Default section id (assigned to annotation at block start)
H.default_section_id = '@text'

-- Alias registry. Keys are alias name, values - single string of alias
-- description with '\n' separating output lines.
H.alias_registry = {}

-- Structure separators
H.separator_block = string.rep('-', 78)
H.separator_file = string.rep('=', 78)

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
function H.setup_config(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    hooks = { config.hooks, 'table' },
    ['hooks.block_pre'] = { config.hooks.block_pre, 'function' },

    ['hooks.sections'] = { config.hooks.sections, 'table' },
    ['hooks.sections.@alias'] = { config.hooks.sections['@alias'], 'function' },
    ['hooks.sections.@class'] = { config.hooks.sections['@class'], 'function' },
    ['hooks.sections.@eval'] = { config.hooks.sections['@eval'], 'function' },
    ['hooks.sections.@field'] = { config.hooks.sections['@field'], 'function' },
    ['hooks.sections.@param'] = { config.hooks.sections['@param'], 'function' },
    ['hooks.sections.@private'] = { config.hooks.sections['@private'], 'function' },
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

-- Default documentation targets ----------------------------------------------
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
  return ('doc/%s.txt'):format(cur_dir)
end

-- Parsing --------------------------------------------------------------------
function H.lines_to_block_arr(lines)
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
      table.insert(block_raw.section_id, section_id or '')
    else
      -- Add afterline
      table.insert(block_raw.afterlines, l)
    end
  end
  block_raw.line_end = #lines
  table.insert(res, H.raw_block_to_block(block_raw))

  return res
end

-- Raw block structure is an intermediate step added for convenience. It is
-- a table with the following keys:
-- - `annotation` - lines (after removing matched annotation pattern) that were
--   parsed as annotation.
-- - `section_id` - array with length equal to `annotation` length with strings
--   captured as section id. Empty string of no section id was captured.
-- - Everything else is used as block info (like `afterlines`, etc.).
function H.raw_block_to_block(block_raw)
  if #block_raw.annotation == 0 and #block_raw.afterlines == 0 then
    return nil
  end

  local block = H.new_struct('block', {
    afterlines = block_raw.afterlines,
    line_begin = block_raw.line_begin,
    line_end = block_raw.line_end,
  })
  local block_begin = block.info.line_begin

  -- Parse raw block annotation lines from top to bottom. New section starts
  -- when section id is detected in that line.
  local section_cur = H.new_struct('section', { id = H.default_section_id, line_begin = block_begin })

  for i, annotation_line in ipairs(block_raw.annotation) do
    local id = block_raw.section_id[i]
    if id ~= '' then
      -- Finish current section
      if #section_cur > 0 then
        section_cur.info.line_end = block_begin + i - 2
        block:insert(section_cur)
      end

      -- Start new section
      section_cur = H.new_struct('section', { id = id, line_begin = block_begin + i - 1 })
    end

    section_cur:insert(annotation_line)
  end

  if #section_cur > 0 then
    section_cur.info.line_end = block_begin + #block_raw.annotation - 1
    block:insert(section_cur)
  end

  return block
end

-- Hooks ----------------------------------------------------------------------
function H.apply_hooks(doc)
  for _, file in ipairs(doc) do
    for _, block in ipairs(file) do
      MiniDoc.config.hooks.block_pre(block)

      for _, section in ipairs(block) do
        local hook = MiniDoc.config.hooks.sections[section.info.id]
        if hook ~= nil then
          hook(section)
        end
      end

      MiniDoc.config.hooks.block_post(block)
    end

    MiniDoc.config.hooks.file(file)
  end

  MiniDoc.config.hooks.doc(doc)
end

function H.register_alias(s)
  if #s == 0 then
    return
  end

  -- Remove first word (and its surrounding whitespace) while capturing it
  local alias_name
  s[1] = s[1]:gsub('%s*(%S+)%s*', function(x)
    alias_name = x
    return ''
  end, 1)
  if alias_name == nil then
    return
  end
  H.alias_registry[alias_name] = table.concat(s, '\n')
end

function H.replace_aliases(s)
  for i, _ in ipairs(s) do
    for alias_name, alias_desc in pairs(H.alias_registry) do
      s[i] = s[i]:gsub(vim.pesc(alias_name), alias_desc)
    end
  end
end

function H.add_section_heading(s, heading)
  if #s == 0 or s.type ~= 'section' then
    return
  end

  -- Add heading
  s:insert(1, ('%s~'):format(heading))
end

function H.enclose_first_word(s, pattern)
  if #s == 0 or s.type ~= 'section' then
    return
  end

  s[1] = s[1]:gsub('(%S*)', pattern, 1)
end

-- Work with structures -------------------------------------------------------
-- Constructor
function H.new_struct(struct_type, info)
  local output = {
    info = info or {},
    type = struct_type,
  }

  output.insert = function(self, index, child)
    if child == nil then
      child, index = index, #self + 1
    end

    if type(child) == 'table' then
      child.parent = self
      child.parent_index = index
    end

    table.insert(self, index, child)

    H.sync_parent_index(self)
  end

  output.remove = function(self, index)
    index = index or #self
    table.remove(self, index)

    H.sync_parent_index(self)
  end

  output.has_descendant = function(self, predicate)
    local bool_res, descendant = false, nil
    H.apply_recursively(function(x)
      if not bool_res and predicate(x) then
        bool_res = true
        descendant = x
      end
    end, self)
    return bool_res, descendant
  end

  output.has_lines = function(self)
    return self:has_descendant(function(x)
      return type(x) == 'string'
    end)
  end

  output.clear_lines = function(self)
    for i, x in ipairs(self) do
      if type(x) == 'string' then
        self[i] = nil
      else
        x:clear_lines()
      end
    end
  end

  return output
end

function H.sync_parent_index(x)
  for i, _ in ipairs(x) do
    if type(x[i]) == 'table' then
      x[i].parent_index = i
    end
  end
  return x
end

-- Converter (this ensures that children have proper parent-related data)
function H.as_struct(array, struct_type, info)
  local res = H.new_struct(struct_type, info)
  for _, x in ipairs(array) do
    res:insert(x)
  end
  return res
end

-- Utilities ------------------------------------------------------------------
function H.apply_recursively(f, x)
  f(x)

  if type(x) == 'table' then
    for _, t in ipairs(x) do
      H.apply_recursively(f, t)
    end
  end
end

function H.collect_strings(x)
  local res = {}
  H.apply_recursively(function(y)
    if type(y) == 'string' then
      -- Allow `\n` in strings
      table.insert(res, vim.split(y, '\n'))
    end
  end, x)
  -- Flatten to only have strings and not table of strings (from `vim.split`)
  return vim.tbl_flatten(res)
end

function H.file_read(path)
  local file = assert(io.open(path))
  local contents = file:read('*all')
  file:close()

  return vim.split(contents, '\n')
end

function H.file_write(path, lines)
  -- Ensure target directory exists
  local dir = vim.fn.fnamemodify(path, ':h')
  vim.fn.mkdir(dir, 'p')

  -- Write to file
  vim.fn.writefile(lines, path, 'b')
end

function H.is_whitespace(x)
  -- String is whitespace in 'help' filetype if it is seen as only whitespace
  return string.find(x, '^%s*$') ~= nil or x == '>' or x == '<'
end

_G.lines = H.file_read(vim.fn.fnamemodify('~/.config/nvim/lua/mini-dev/test-doc.lua', ':p'))

return MiniDoc
