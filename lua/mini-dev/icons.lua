--- TODO:
--- - Code:
---     - Think about the interface for default icons.
---       Maybe a separate "core" category with "default" icon?
---       Will also allow configuring something like "file", "directory", etc.
---
---     - Think about adding 'git_status' (for `git status` two character
---       outputs) category.
---
---     - Verify how icons look in popular terminal emulators.
---
---     - Check how default highlight groups look in popular color schemes.
---
---     - Think about adding `MiniIcons.list(category)` to list all explicitly
---       available icons.
---
---     - Add some popular plugin filetypes: from 'mini.nvim', from
---       'lazy.nvim', etc.
---
---     - Think about whether file/directory distinction is necessary.
---       Maybe instead have single "path" category?
---
---     - Go through "Features" list.
---
---     - Write 'nvim-tree/nvim-web-devicons' mocks.
---
--- - Docs:
---
---     - Suggest using Nerd Font at least version 3.0.0.
---
--- - Tests:
---     - Works for 'Cargo.lock' (uses exact case and not lower case).
---     - Works with files with no extension ('big-file')
---

--- *mini.icons* Icon provider
--- *MiniIcons*
---
--- MIT License Copyright (c) 2024 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Features:
---
--- - Provide icons with their highlighting via a single |MiniIcons.get()| for
---   various categories: filetype, file name, directory name, extension,
---   operating system, LSP kind. Icons can be overridden.
---
--- - Configurable styles (glyph, ascii, box/circle filled/outlined).
---
--- - Fixed set of highlight groups allowing to use colors from color scheme.
---
--- - Caching for maximum performance.
---
--- - Integration with |vim.filetype.add()| and |vim.filetype.match()|.
---
--- - Mocking methods of 'nvim-tree/nvim-web-devicons' for better integrations
---   with plugins outside 'mini.nvim'.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.icons').setup({})` (replace `{}` with
--- your `config` table). It will create global Lua table `MiniIcons` which you can use
--- for scripting or manually (with `:lua MiniIcons.*`).
---
--- See |MiniIcons.config| for `config` structure and default values.
---
--- # Comparisons ~
---
--- - 'nvim-tree/nvim-web-devicons':
---     - ...
---
--- # Highlight groups ~
---
--- Only the following set of highlight groups is used as icon highlight.
--- It is recommended that they all only define colored foreground:
---
--- * `MiniIconsAzure`  - azure.
--- * `MiniIconsBlue`   - blue.
--- * `MiniIconsCyan`   - cyan.
--- * `MiniIconsGreen`  - green.
--- * `MiniIconsGrey`   - grey.
--- * `MiniIconsOrange` - orange.
--- * `MiniIconsPurple` - purple.
--- * `MiniIconsRed`    - red.
--- * `MiniIconsYellow` - yellow.
---
--- To change any highlight group, modify it directly with |:highlight|.

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local
---@diagnostic disable:cast-local-type
---@diagnostic disable:undefined-doc-name
---@diagnostic disable:luadoc-miss-type-name

-- Module definition ==========================================================
MiniIcons = {}
H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniIcons.config|.
---
---@usage `require('mini.icons').setup({})` (replace `{}` with your `config` table).
MiniIcons.setup = function(config)
  -- Export module
  _G.MiniIcons = MiniIcons

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Create default highlighting
  H.create_default_hl()

  -- Clear cache
  H.cache = { extension = {}, filetype = {}, path = {}, os = {} }
end

--stylua: ignore
--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # Style ~
MiniIcons.config = {
  -- Icon style: 'glyph', 'ascii', 'box', 'circle', 'box-fill', 'circle-fill'
  style = 'glyph',

  -- Callable to provide custom output instead of built-in provider
  custom = nil,
}
--minidoc_afterlines_end

MiniIcons.get = function(category, name)
  if not (type(category) == 'string' and type(name) == 'string') then
    H.error('Both `category` and `name` should be string.')
  end

  name = category == 'path' and H.fs_basename(name) or name
  local cached = H.cache[category][name]
  if cached ~= nil then return cached[1], cached[2] end

  -- TODO: Incorporate custom icons

  local getter = H.get_impl[category]
  if getter == nil then H.error('Category ' .. vim.inspect(category) .. ' is not supported.') end
  local icon, hl = getter(name)
  if icon ~= nil and hl ~= nil then H.cache[category][name] = { icon, hl } end
  return icon, hl
end

MiniIcons.mock_nvim_web_devicons = function()
  local module = package.loaded['nvim-web-devicons'] or {}
  -- TODO
  module.get_icon = function(name, ext, opts)
    local icon, hl
    if type(name) == 'string' then
      icon, hl = MiniIcons.get('path', name)
    end
    if type(ext) == 'string' then
      icon, hl = MiniIcons.get('extension', ext)
    end
    return icon or '', hl or 'MiniIconsGrey'
  end
  package.loaded['nvim-web-devicons'] = module
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniIcons.config

-- Cache for `get()` output per category
H.cache = { extension = {}, filetype = {}, lsp_kind = {}, path = {}, os = {} }

-- Filetype icons. Keys are filetypes explicitly supported by Neovim
-- (i.e. present in `getcompletion('', 'filetype')` except technical ones).
-- Rough process of how glyphs and icons are chosen:
-- - Try to balance usage of highlight groups.
-- - Prefer using icons with from the following classes (in decreasing order of
--   preference):
--     - `nf-md-*` (their UTF codes seem to be more thought through). It is
--       also correctly has double width in Kitty.
--     - `nf-dev-*` (more supported devicons).
--     - `nf-seti-*` (more up to date extensions).
-- - If it is present in 'nvim-web-devicons', use its highlight group inferred
--   to have most similar hue (based on OKLCH color space with equally spaced
--   grid as in 'mini.hues' and chroma=3 for grey cutoff; with some manual
--   interventions).
-- - Sets that have same/close glyphs but maybe different highlights:
--     - Generic configuration filetypes (".*conf.*", ".*rc", if stated in
--       filetype file description, etc.) have same glyph.
--     - Assembly ("asm").
--     - SQL.
--     - Log files.
--     - Perl.
--     - HTML.
--     - CSV.
--     - Shell.
--     - Make / build system.
--     - Related to Internet/Web.
-- - For newly assigned icons prefer semantically close (first by filetype
--   origin, then by name) abstract icons with `nf-md-*` Nerd Font class.
-- - If no semantically close abstract icon present, use plain letter/digit
--   icon (based on the first character) with highlight groups picked randomly
--   to achieve overall balance (also try to minimize maximum number of
--   glyph-hl duplicates).

-- Neovim filetype plugins
--stylua: ignore
H.filetype_icons = {
  ['8th']            = { glyph = '󰭁', hl = 'MiniIconsYellow' },
  a2ps               = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  a65                = { glyph = '', hl = 'MiniIconsRed'    },
  aap                = { glyph = '󰫮', hl = 'MiniIconsOrange' },
  abap               = { glyph = '󰫮', hl = 'MiniIconsGreen'  },
  abaqus             = { glyph = '󰫮', hl = 'MiniIconsGreen'  },
  abc                = { glyph = '󰝚', hl = 'MiniIconsYellow' },
  abel               = { glyph = '󰫮', hl = 'MiniIconsAzure'  },
  acedb              = { glyph = '󰆼', hl = 'MiniIconsGrey'   },
  ada                = { glyph = '󱁷', hl = 'MiniIconsAzure'  },
  aflex              = { glyph = '󰫮', hl = 'MiniIconsCyan'   },
  ahdl               = { glyph = '󰫮', hl = 'MiniIconsRed'    },
  aidl               = { glyph = '󰫮', hl = 'MiniIconsYellow' },
  alsaconf           = { glyph = '󰒓', hl = 'MiniIconsPurple' },
  amiga              = { glyph = '󰫮', hl = 'MiniIconsCyan'   },
  aml                = { glyph = '󰫮', hl = 'MiniIconsPurple' },
  ampl               = { glyph = '󰫮', hl = 'MiniIconsOrange' },
  ant                = { glyph = '󰫮', hl = 'MiniIconsRed'    },
  antlr              = { glyph = '󰫮', hl = 'MiniIconsCyan'   },
  apache             = { glyph = '󰒓', hl = 'MiniIconsGreen'  },
  apachestyle        = { glyph = '󰒓', hl = 'MiniIconsGrey'   },
  aptconf            = { glyph = '󰒓', hl = 'MiniIconsOrange' },
  arch               = { glyph = '󰣇', hl = 'MiniIconsBlue'   },
  arduino            = { glyph = '', hl = 'MiniIconsAzure'  },
  art                = { glyph = '󰫮', hl = 'MiniIconsPurple' },
  asciidoc           = { glyph = '󰪶', hl = 'MiniIconsYellow' },
  asm                = { glyph = '', hl = 'MiniIconsPurple' },
  asm68k             = { glyph = '', hl = 'MiniIconsRed'    },
  asmh8300           = { glyph = '', hl = 'MiniIconsOrange' },
  asn                = { glyph = '󰫮', hl = 'MiniIconsBlue'   },
  aspperl            = { glyph = '', hl = 'MiniIconsBlue'   },
  aspvbs             = { glyph = '󰫮', hl = 'MiniIconsGreen'  },
  asterisk           = { glyph = '󰒓', hl = 'MiniIconsBlue'   },
  asteriskvm         = { glyph = '󰒓', hl = 'MiniIconsGrey'   },
  astro              = { glyph = '󰓎', hl = 'MiniIconsBlue'   },
  atlas              = { glyph = '󰫮', hl = 'MiniIconsAzure'  },
  autodoc            = { glyph = '󰪶', hl = 'MiniIconsGreen'  },
  autohotkey         = { glyph = '󰫮', hl = 'MiniIconsYellow' },
  autoit             = { glyph = '󰫮', hl = 'MiniIconsCyan'   },
  automake           = { glyph = '󱁤', hl = 'MiniIconsPurple' },
  ave                = { glyph = '󰫮', hl = 'MiniIconsGrey'   },
  avra               = { glyph = '', hl = 'MiniIconsPurple' },
  awk                = { glyph = '', hl = 'MiniIconsGrey'   },
  ayacc              = { glyph = '󰫮', hl = 'MiniIconsCyan'   },
  b                  = { glyph = '󰫯', hl = 'MiniIconsYellow' },
  baan               = { glyph = '󰫯', hl = 'MiniIconsOrange' },
  bash               = { glyph = '', hl = 'MiniIconsGreen'  },
  basic              = { glyph = '󰫯', hl = 'MiniIconsPurple' },
  bc                 = { glyph = '󰫯', hl = 'MiniIconsCyan'   },
  bdf                = { glyph = '󰛖', hl = 'MiniIconsRed'    },
  bib                = { glyph = '󱉟', hl = 'MiniIconsYellow' },
  bindzone           = { glyph = '󰫯', hl = 'MiniIconsCyan'   },
  bitbake            = { glyph = '󰃫', hl = 'MiniIconsOrange' },
  blank              = { glyph = '󰫯', hl = 'MiniIconsPurple' },
  bp                 = { glyph = '󰫯', hl = 'MiniIconsYellow' },
  bsdl               = { glyph = '󰫯', hl = 'MiniIconsPurple' },
  bst                = { glyph = '󰫯', hl = 'MiniIconsCyan'   },
  btm                = { glyph = '󰫯', hl = 'MiniIconsGreen'  },
  bzl                = { glyph = '', hl = 'MiniIconsGreen'  },
  bzr                = { glyph = '󰜘', hl = 'MiniIconsRed'    },
  c                  = { glyph = '󰙱', hl = 'MiniIconsBlue'   },
  cabal              = { glyph = '󰲒', hl = 'MiniIconsBlue'   },
  cabalconfig        = { glyph = '󰒓', hl = 'MiniIconsGrey'   },
  cabalproject       = { glyph = '󰫰', hl = 'MiniIconsBlue'   },
  calendar           = { glyph = '󰃵', hl = 'MiniIconsRed'    },
  catalog            = { glyph = '󰕲', hl = 'MiniIconsGrey'   },
  cdl                = { glyph = '󰫰', hl = 'MiniIconsOrange' },
  cdrdaoconf         = { glyph = '󰒓', hl = 'MiniIconsRed'    },
  cdrtoc             = { glyph = '󰠶', hl = 'MiniIconsRed'    },
  cf                 = { glyph = '󰫰', hl = 'MiniIconsRed'    },
  cfg                = { glyph = '󰒓', hl = 'MiniIconsBlue'   },
  cgdbrc             = { glyph = '󰒓', hl = 'MiniIconsRed'    },
  ch                 = { glyph = '󰫰', hl = 'MiniIconsCyan'   },
  chaiscript         = { glyph = '󰶞', hl = 'MiniIconsOrange' },
  change             = { glyph = '󰹳', hl = 'MiniIconsYellow'},
  changelog          = { glyph = '', hl = 'MiniIconsBlue'   },
  chaskell           = { glyph = '󰲒', hl = 'MiniIconsGreen'  },
  chatito            = { glyph = '󰫰', hl = 'MiniIconsCyan'   },
  checkhealth        = { glyph = '󰓙', hl = 'MiniIconsBlue'   },
  cheetah            = { glyph = '󰫰', hl = 'MiniIconsGrey'   },
  chicken            = { glyph = '󰫰', hl = 'MiniIconsRed'    },
  chill              = { glyph = '󰫰', hl = 'MiniIconsBlue'   },
  chordpro           = { glyph = '󰫰', hl = 'MiniIconsGreen'  },
  chuck              = { glyph = '󰫰', hl = 'MiniIconsBlue'   },
  cl                 = { glyph = '󰫰', hl = 'MiniIconsCyan'   },
  clean              = { glyph = '󰫰', hl = 'MiniIconsBlue'   },
  clipper            = { glyph = '󰫰', hl = 'MiniIconsPurple' },
  clojure            = { glyph = '', hl = 'MiniIconsGreen'  },
  cmake              = { glyph = '󱁤', hl = 'MiniIconsYellow' },
  cmakecache         = { glyph = '󱁤', hl = 'MiniIconsRed'    },
  cmod               = { glyph = '󰫰', hl = 'MiniIconsCyan'   },
  cmusrc             = { glyph = '󰒓', hl = 'MiniIconsRed'    },
  cobol              = { glyph = '󱌼', hl = 'MiniIconsBlue'   },
  coco               = { glyph = '󰫰', hl = 'MiniIconsRed'    },
  conaryrecipe       = { glyph = '󰫰', hl = 'MiniIconsGrey'   },
  conf               = { glyph = '󰒓', hl = 'MiniIconsGrey'   },
  config             = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  confini            = { glyph = '󰒓', hl = 'MiniIconsAzure'  },
  context            = { glyph = '', hl = 'MiniIconsGreen'  },
  corn               = { glyph = '󰞸', hl = 'MiniIconsYellow' },
  cpp                = { glyph = '󰙲', hl = 'MiniIconsAzure'  },
  crm                = { glyph = '󰫰', hl = 'MiniIconsGreen'  },
  crontab            = { glyph = '󰔠', hl = 'MiniIconsAzure'  },
  cs                 = { glyph = '󰌛', hl = 'MiniIconsGreen'  },
  csc                = { glyph = '󰫰', hl = 'MiniIconsBlue'   },
  csdl               = { glyph = '󰫰', hl = 'MiniIconsCyan'   },
  csh                = { glyph = '', hl = 'MiniIconsGrey'   },
  csp                = { glyph = '󰫰', hl = 'MiniIconsAzure'  },
  css                = { glyph = '󰌜', hl = 'MiniIconsAzure'  },
  csv                = { glyph = '', hl = 'MiniIconsGreen'  },
  csv_pipe           = { glyph = '', hl = 'MiniIconsAzure'  },
  csv_semicolon      = { glyph = '', hl = 'MiniIconsRed'    },
  csv_whitespace     = { glyph = '', hl = 'MiniIconsPurple' },
  cterm              = { glyph = '󰫰', hl = 'MiniIconsCyan'   },
  ctrlh              = { glyph = '󰫰', hl = 'MiniIconsOrange' },
  cucumber           = { glyph = '󰫰', hl = 'MiniIconsPurple' },
  cuda               = { glyph = '', hl = 'MiniIconsGreen'  },
  cupl               = { glyph = '󰫰', hl = 'MiniIconsOrange' },
  cuplsim            = { glyph = '󰫰', hl = 'MiniIconsPurple' },
  cvs                = { glyph = '󰜘', hl = 'MiniIconsGreen'  },
  cvsrc              = { glyph = '󰒓', hl = 'MiniIconsYellow' },
  cweb               = { glyph = '󰫰', hl = 'MiniIconsCyan'   },
  cynlib             = { glyph = '󰙲', hl = 'MiniIconsPurple' },
  cynpp              = { glyph = '󰙲', hl = 'MiniIconsYellow' },
  d                  = { glyph = '', hl = 'MiniIconsGreen'  },
  dart               = { glyph = '', hl = 'MiniIconsBlue'   },
  datascript         = { glyph = '󰫱', hl = 'MiniIconsGreen'  },
  dcd                = { glyph = '󰫱', hl = 'MiniIconsCyan'   },
  dcl                = { glyph = '󰫱', hl = 'MiniIconsAzure'  },
  deb822sources      = { glyph = '󰫱', hl = 'MiniIconsCyan'   },
  debchangelog       = { glyph = '', hl = 'MiniIconsBlue'   },
  debcontrol         = { glyph = '󰫱', hl = 'MiniIconsOrange' },
  debcopyright       = { glyph = '', hl = 'MiniIconsRed'    },
  debsources         = { glyph = '󰫱', hl = 'MiniIconsYellow' },
  def                = { glyph = '󰫱', hl = 'MiniIconsGrey'   },
  denyhosts          = { glyph = '󰒓', hl = 'MiniIconsGrey'   },
  dep3patch          = { glyph = '󰫱', hl = 'MiniIconsCyan'   },
  desc               = { glyph = '󰫱', hl = 'MiniIconsCyan'   },
  desktop            = { glyph = '󰍹', hl = 'MiniIconsPurple' },
  dictconf           = { glyph = '󰒓', hl = 'MiniIconsOrange' },
  dictdconf          = { glyph = '󰒓', hl = 'MiniIconsBlue'   },
  diff               = { glyph = '󰦓', hl = 'MiniIconsAzure'  },
  dircolors          = { glyph = '󰫱', hl = 'MiniIconsRed'    },
  dirpager           = { glyph = '󰙅', hl = 'MiniIconsYellow' },
  diva               = { glyph = '󰫱', hl = 'MiniIconsRed'    },
  django             = { glyph = '', hl = 'MiniIconsGreen'  },
  dns                = { glyph = '󰫱', hl = 'MiniIconsOrange' },
  dnsmasq            = { glyph = '󰫱', hl = 'MiniIconsGrey'   },
  docbk              = { glyph = '󰫱', hl = 'MiniIconsYellow' },
  docbksgml          = { glyph = '󰫱', hl = 'MiniIconsGrey'   },
  docbkxml           = { glyph = '󰫱', hl = 'MiniIconsGrey'   },
  dockerfile         = { glyph = '󰡨', hl = 'MiniIconsBlue'   },
  dosbatch           = { glyph = '󰯂', hl = 'MiniIconsGreen'  },
  dosini             = { glyph = '󰯂', hl = 'MiniIconsAzure'  },
  dot                = { glyph = '󱁉', hl = 'MiniIconsAzure'  },
  doxygen            = { glyph = '󰋘', hl = 'MiniIconsBlue'   },
  dracula            = { glyph = '󰭟', hl = 'MiniIconsGrey'   },
  dsl                = { glyph = '󰫱', hl = 'MiniIconsAzure'  },
  dtd                = { glyph = '󰫱', hl = 'MiniIconsCyan'   },
  dtml               = { glyph = '󰫱', hl = 'MiniIconsRed'    },
  dtrace             = { glyph = '󰫱', hl = 'MiniIconsRed'    },
  dts                = { glyph = '󰫱', hl = 'MiniIconsRed'    },
  dune               = { glyph = '', hl = 'MiniIconsGreen'  },
  dylan              = { glyph = '󰫱', hl = 'MiniIconsRed'    },
  dylanintr          = { glyph = '󰫱', hl = 'MiniIconsGrey'   },
  dylanlid           = { glyph = '󰫱', hl = 'MiniIconsOrange' },
  ecd                = { glyph = '󰫲', hl = 'MiniIconsPurple' },
  edif               = { glyph = '󰫲', hl = 'MiniIconsCyan'   },
  editorconfig       = { glyph = '', hl = 'MiniIconsGrey'   },
  eiffel             = { glyph = '󱕫', hl = 'MiniIconsYellow' },
  elf                = { glyph = '󰫲', hl = 'MiniIconsGreen'  },
  elinks             = { glyph = '󰒓', hl = 'MiniIconsOrange' },
  elixir             = { glyph = '', hl = 'MiniIconsPurple' },
  elm                = { glyph = '', hl = 'MiniIconsAzure'  },
  elmfilt            = { glyph = '󰫲', hl = 'MiniIconsBlue'   },
  erlang             = { glyph = '', hl = 'MiniIconsRed'    },
  eruby              = { glyph = '󰴭', hl = 'MiniIconsOrange' },
  esmtprc            = { glyph = '󰒓', hl = 'MiniIconsYellow' },
  esqlc              = { glyph = '󰆼', hl = 'MiniIconsGrey'   },
  esterel            = { glyph = '󰫲', hl = 'MiniIconsYellow' },
  eterm              = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  euphoria3          = { glyph = '󰫲', hl = 'MiniIconsRed'    },
  euphoria4          = { glyph = '󰫲', hl = 'MiniIconsYellow' },
  eviews             = { glyph = '󰫲', hl = 'MiniIconsCyan'   },
  exim               = { glyph = '󰒓', hl = 'MiniIconsPurple' },
  expect             = { glyph = '󰫲', hl = 'MiniIconsGrey'   },
  exports            = { glyph = '󰈇', hl = 'MiniIconsPurple' },
  falcon             = { glyph = '󱗆', hl = 'MiniIconsOrange' },
  fan                = { glyph = '󰫳', hl = 'MiniIconsAzure'  },
  fasm               = { glyph = '', hl = 'MiniIconsPurple' },
  fdcc               = { glyph = '󰫳', hl = 'MiniIconsBlue'   },
  fennel             = { glyph = '', hl = 'MiniIconsYellow' },
  fetchmail          = { glyph = '󰒓', hl = 'MiniIconsGrey'   },
  fgl                = { glyph = '󰫳', hl = 'MiniIconsCyan'   },
  fish               = { glyph = '', hl = 'MiniIconsGrey'   },
  flexwiki           = { glyph = '󰖬', hl = 'MiniIconsPurple' },
  focexec            = { glyph = '󰫳', hl = 'MiniIconsOrange' },
  form               = { glyph = '󰫳', hl = 'MiniIconsCyan'   },
  forth              = { glyph = '󰬽', hl = 'MiniIconsRed'    },
  fortran            = { glyph = '󱈚', hl = 'MiniIconsPurple' },
  foxpro             = { glyph = '󰫳', hl = 'MiniIconsGreen'  },
  fpcmake            = { glyph = '󱁤', hl = 'MiniIconsRed'    },
  framescript        = { glyph = '󰫳', hl = 'MiniIconsCyan'   },
  freebasic          = { glyph = '󰫳', hl = 'MiniIconsOrange' },
  fsharp             = { glyph = '', hl = 'MiniIconsBlue'   },
  fstab              = { glyph = '󰋊', hl = 'MiniIconsGrey'   },
  fvwm               = { glyph = '󰒓', hl = 'MiniIconsAzure'  },
  fvwm2m4            = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  gdb                = { glyph = '󰈺', hl = 'MiniIconsGrey'   },
  gdmo               = { glyph = '󰫴', hl = 'MiniIconsBlue'   },
  gdresource         = { glyph = '', hl = 'MiniIconsGreen'  },
  gdscript           = { glyph = '', hl = 'MiniIconsYellow' },
  gdshader           = { glyph = '', hl = 'MiniIconsPurple' },
  gedcom             = { glyph = '󰫴', hl = 'MiniIconsRed'    },
  gemtext            = { glyph = '󰪁', hl = 'MiniIconsAzure'  },
  gift               = { glyph = '󰹄', hl = 'MiniIconsRed'    },
  git                = { glyph = '󰊢', hl = 'MiniIconsOrange' },
  gitattributes      = { glyph = '󰊢', hl = 'MiniIconsYellow' },
  gitcommit          = { glyph = '󰊢', hl = 'MiniIconsGreen'  },
  gitconfig          = { glyph = '󰒓', hl = 'MiniIconsOrange' },
  gitignore          = { glyph = '󰊢', hl = 'MiniIconsPurple' },
  gitolite           = { glyph = '󰒓', hl = 'MiniIconsGreen'  },
  gitrebase          = { glyph = '󰊢', hl = 'MiniIconsAzure'  },
  gitsendemail       = { glyph = '󰊢', hl = 'MiniIconsBlue'   },
  gkrellmrc          = { glyph = '󰒓', hl = 'MiniIconsRed'    },
  gnash              = { glyph = '󰒓', hl = 'MiniIconsGreen'  },
  gnuplot            = { glyph = '󰺒', hl = 'MiniIconsPurple' },
  go                 = { glyph = '󰟓', hl = 'MiniIconsAzure'  },
  godoc              = { glyph = '󰟓', hl = 'MiniIconsOrange' },
  gp                 = { glyph = '󰫴', hl = 'MiniIconsCyan'   },
  gpg                = { glyph = '󰒓', hl = 'MiniIconsGrey'   },
  gprof              = { glyph = '󰫴', hl = 'MiniIconsAzure'  },
  grads              = { glyph = '󰫴', hl = 'MiniIconsPurple' },
  graphql            = { glyph = '󰡷', hl = 'MiniIconsRed'    },
  gretl              = { glyph = '󰫴', hl = 'MiniIconsCyan'   },
  groff              = { glyph = '󰫴', hl = 'MiniIconsYellow' },
  groovy             = { glyph = '', hl = 'MiniIconsAzure'  },
  group              = { glyph = '󰫴', hl = 'MiniIconsCyan'   },
  grub               = { glyph = '󰒓', hl = 'MiniIconsBlue'   },
  gsp                = { glyph = '󰫴', hl = 'MiniIconsYellow' },
  gtkrc              = { glyph = '󰒓', hl = 'MiniIconsAzure'  },
  gvpr               = { glyph = '󰫴', hl = 'MiniIconsBlue'   },
  gyp                = { glyph = '󰫴', hl = 'MiniIconsPurple' },
  haml               = { glyph = '󰅴', hl = 'MiniIconsGrey'   },
  hamster            = { glyph = '󰫵', hl = 'MiniIconsCyan'   },
  hare               = { glyph = '󰫵', hl = 'MiniIconsRed'    },
  haredoc            = { glyph = '󰪶', hl = 'MiniIconsGrey'   },
  haskell            = { glyph = '󰲒', hl = 'MiniIconsPurple' },
  haste              = { glyph = '󰫵', hl = 'MiniIconsYellow' },
  hastepreproc       = { glyph = '󰫵', hl = 'MiniIconsCyan'   },
  hb                 = { glyph = '󰫵', hl = 'MiniIconsGreen'  },
  heex               = { glyph = '', hl = 'MiniIconsPurple' },
  help               = { glyph = '󰋖', hl = 'MiniIconsPurple' },
  hercules           = { glyph = '󰫵', hl = 'MiniIconsRed'    },
  hex                = { glyph = '󰋘', hl = 'MiniIconsYellow' },
  hgcommit           = { glyph = '󰜘', hl = 'MiniIconsGrey'   },
  hlsplaylist        = { glyph = '󰲸', hl = 'MiniIconsOrange' },
  hog                = { glyph = '󰫵', hl = 'MiniIconsOrange' },
  hollywood          = { glyph = '󰓎', hl = 'MiniIconsYellow' },
  hostconf           = { glyph = '󰒓', hl = 'MiniIconsPurple' },
  hostsaccess        = { glyph = '󰒓', hl = 'MiniIconsOrange' },
  html               = { glyph = '󰌝', hl = 'MiniIconsOrange' },
  htmlcheetah        = { glyph = '󰌝', hl = 'MiniIconsYellow' },
  htmldjango         = { glyph = '󰌝', hl = 'MiniIconsGreen'  },
  htmlm4             = { glyph = '󰌝', hl = 'MiniIconsRed'    },
  htmlos             = { glyph = '󰌝', hl = 'MiniIconsAzure'  },
  hurl               = { glyph = '󰫵', hl = 'MiniIconsGreen'  },
  hyprlang           = { glyph = '', hl = 'MiniIconsCyan'   },
  i3config           = { glyph = '󰒓', hl = 'MiniIconsOrange' },
  ia64               = { glyph = '', hl = 'MiniIconsPurple' },
  ibasic             = { glyph = '󰫶', hl = 'MiniIconsOrange' },
  icemenu            = { glyph = '󰒓', hl = 'MiniIconsPurple' },
  icon               = { glyph = '󰫶', hl = 'MiniIconsGreen'  },
  idl                = { glyph = '󰫶', hl = 'MiniIconsRed'    },
  idlang             = { glyph = '󱗿', hl = 'MiniIconsYellow' },
  inform             = { glyph = '󰫶', hl = 'MiniIconsOrange' },
  initex             = { glyph = '', hl = 'MiniIconsGreen'  },
  initng             = { glyph = '󰫶', hl = 'MiniIconsAzure'  },
  inittab            = { glyph = '󰫶', hl = 'MiniIconsBlue'   },
  ipfilter           = { glyph = '󰒓', hl = 'MiniIconsAzure'  },
  ishd               = { glyph = '󰫶', hl = 'MiniIconsYellow' },
  iss                = { glyph = '󰏗', hl = 'MiniIconsBlue'   },
  ist                = { glyph = '󰫶', hl = 'MiniIconsCyan'   },
  j                  = { glyph = '󰫷', hl = 'MiniIconsAzure'  },
  jal                = { glyph = '󰫷', hl = 'MiniIconsCyan'   },
  jam                = { glyph = '󰫷', hl = 'MiniIconsCyan'   },
  jargon             = { glyph = '󰫷', hl = 'MiniIconsCyan'   },
  java               = { glyph = '󰬷', hl = 'MiniIconsOrange' },
  javacc             = { glyph = '󰬷', hl = 'MiniIconsRed'    },
  javascript         = { glyph = '󰌞', hl = 'MiniIconsYellow' },
  javascriptreact    = { glyph = '', hl = 'MiniIconsAzure'  },
  jess               = { glyph = '󰫷', hl = 'MiniIconsPurple' },
  jgraph             = { glyph = '󰫷', hl = 'MiniIconsGrey'   },
  jj                 = { glyph = '󱨎', hl = 'MiniIconsYellow' },
  jovial             = { glyph = '󰫷', hl = 'MiniIconsGrey'   },
  jproperties        = { glyph = '󰬷', hl = 'MiniIconsGreen'  },
  jq                 = { glyph = '󰘦', hl = 'MiniIconsBlue'   },
  json               = { glyph = '󰘦', hl = 'MiniIconsYellow' },
  json5              = { glyph = '󰘦', hl = 'MiniIconsOrange' },
  jsonc              = { glyph = '󰘦', hl = 'MiniIconsYellow' },
  jsonnet            = { glyph = '󰫷', hl = 'MiniIconsYellow' },
  jsp                = { glyph = '󰫷', hl = 'MiniIconsAzure'  },
  julia              = { glyph = '', hl = 'MiniIconsPurple' },
  just               = { glyph = '󰖷', hl = 'MiniIconsOrange' },
  kconfig            = { glyph = '󰒓', hl = 'MiniIconsPurple' },
  kivy               = { glyph = '󰫸', hl = 'MiniIconsBlue'   },
  kix                = { glyph = '󰫸', hl = 'MiniIconsRed'    },
  kotlin             = { glyph = '󱈙', hl = 'MiniIconsBlue'   },
  krl                = { glyph = '󰚩', hl = 'MiniIconsGrey'   },
  kscript            = { glyph = '󰫸', hl = 'MiniIconsGrey'   },
  kwt                = { glyph = '󰫸', hl = 'MiniIconsOrange' },
  lace               = { glyph = '󰫹', hl = 'MiniIconsCyan'   },
  latte              = { glyph = '󰅶', hl = 'MiniIconsOrange' },
  lc                 = { glyph = '󰫹', hl = 'MiniIconsRed'    },
  ld                 = { glyph = '󰫹', hl = 'MiniIconsPurple' },
  ldapconf           = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  ldif               = { glyph = '󰫹', hl = 'MiniIconsPurple' },
  less               = { glyph = '󰌜', hl = 'MiniIconsPurple' },
  lex                = { glyph = '󰫹', hl = 'MiniIconsOrange' },
  lftp               = { glyph = '󰒓', hl = 'MiniIconsYellow' },
  lhaskell           = { glyph = '', hl = 'MiniIconsPurple' },
  libao              = { glyph = '󰒓', hl = 'MiniIconsGrey'   },
  lifelines          = { glyph = '󰫹', hl = 'MiniIconsCyan'   },
  lilo               = { glyph = '󰒓', hl = 'MiniIconsAzure'  },
  limits             = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  liquid             = { glyph = '', hl = 'MiniIconsGreen'  },
  lisp               = { glyph = '', hl = 'MiniIconsGrey'   },
  lite               = { glyph = '󰫹', hl = 'MiniIconsCyan'   },
  litestep           = { glyph = '󰒓', hl = 'MiniIconsYellow' },
  livebook           = { glyph = '󰂾', hl = 'MiniIconsGreen'  },
  logcheck           = { glyph = '', hl = 'MiniIconsBlue'   },
  loginaccess        = { glyph = '󰒓', hl = 'MiniIconsPurple' },
  logindefs          = { glyph = '󰒓', hl = 'MiniIconsGreen'  },
  logtalk            = { glyph = '󰫹', hl = 'MiniIconsOrange' },
  lotos              = { glyph = '󰫹', hl = 'MiniIconsYellow' },
  lout               = { glyph = '󰫹', hl = 'MiniIconsCyan'   },
  lpc                = { glyph = '󰫹', hl = 'MiniIconsGrey'   },
  lprolog            = { glyph = '󰘧', hl = 'MiniIconsOrange' },
  lscript            = { glyph = '󰫹', hl = 'MiniIconsCyan'   },
  lsl                = { glyph = '󰫹', hl = 'MiniIconsYellow' },
  lsp_markdown       = { glyph = '󰍔', hl = 'MiniIconsGrey'   },
  lss                = { glyph = '󰫹', hl = 'MiniIconsAzure'  },
  lua                = { glyph = '󰢱', hl = 'MiniIconsAzure'  },
  luau               = { glyph = '󰢱', hl = 'MiniIconsGreen'  },
  lynx               = { glyph = '󰒓', hl = 'MiniIconsRed'    },
  lyrics             = { glyph = '󰫹', hl = 'MiniIconsOrange' },
  m3build            = { glyph = '󰫺', hl = 'MiniIconsGrey'   },
  m3quake            = { glyph = '󰫺', hl = 'MiniIconsGreen'  },
  m4                 = { glyph = '󰫺', hl = 'MiniIconsYellow' },
  mail               = { glyph = '󰇮', hl = 'MiniIconsRed'    },
  mailaliases        = { glyph = '󰇮', hl = 'MiniIconsOrange' },
  mailcap            = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  make               = { glyph = '󱁤', hl = 'MiniIconsGrey'   },
  mallard            = { glyph = '󰫺', hl = 'MiniIconsGrey'   },
  man                = { glyph = '󰗚', hl = 'MiniIconsYellow' },
  manconf            = { glyph = '󰒓', hl = 'MiniIconsPurple' },
  manual             = { glyph = '󰗚', hl = 'MiniIconsYellow' },
  maple              = { glyph = '󰲓', hl = 'MiniIconsRed'    },
  markdown           = { glyph = '󰍔', hl = 'MiniIconsGrey'   },
  masm               = { glyph = '', hl = 'MiniIconsPurple' },
  mason              = { glyph = '󰫺', hl = 'MiniIconsCyan'   },
  master             = { glyph = '󰫺', hl = 'MiniIconsOrange' },
  matlab             = { glyph = '󰿈', hl = 'MiniIconsOrange' },
  maxima             = { glyph = '󰫺', hl = 'MiniIconsGrey'   },
  mel                = { glyph = '󰫺', hl = 'MiniIconsAzure'  },
  mermaid            = { glyph = '󰫺', hl = 'MiniIconsCyan'   },
  meson              = { glyph = '󰫺', hl = 'MiniIconsBlue'   },
  messages           = { glyph = '󰍡', hl = 'MiniIconsBlue'   },
  mf                 = { glyph = '󰫺', hl = 'MiniIconsCyan'   },
  mgl                = { glyph = '󰫺', hl = 'MiniIconsCyan'   },
  mgp                = { glyph = '󰫺', hl = 'MiniIconsAzure'  },
  mib                = { glyph = '󰫺', hl = 'MiniIconsCyan'   },
  mix                = { glyph = '󰫺', hl = 'MiniIconsRed'    },
  mma                = { glyph = '󰘨', hl = 'MiniIconsAzure'  },
  mmix               = { glyph = '󰫺', hl = 'MiniIconsRed'    },
  mmp                = { glyph = '󰫺', hl = 'MiniIconsGrey'   },
  modconf            = { glyph = '󰒓', hl = 'MiniIconsOrange' },
  model              = { glyph = '󰫺', hl = 'MiniIconsGreen'  },
  modsim3            = { glyph = '󰫺', hl = 'MiniIconsCyan'   },
  modula2            = { glyph = '󰫺', hl = 'MiniIconsOrange' },
  modula3            = { glyph = '󰫺', hl = 'MiniIconsRed'    },
  mojo               = { glyph = '󰈸', hl = 'MiniIconsRed'    },
  monk               = { glyph = '󰫺', hl = 'MiniIconsCyan'   },
  moo                = { glyph = '󰫺', hl = 'MiniIconsYellow' },
  mp                 = { glyph = '󰫺', hl = 'MiniIconsAzure'  },
  mplayerconf        = { glyph = '󰒓', hl = 'MiniIconsAzure'  },
  mrxvtrc            = { glyph = '󰒓', hl = 'MiniIconsAzure'  },
  msidl              = { glyph = '󰫺', hl = 'MiniIconsPurple' },
  msmessages         = { glyph = '󰍡', hl = 'MiniIconsAzure'  },
  msql               = { glyph = '󰆼', hl = 'MiniIconsGrey'   },
  mupad              = { glyph = '󰫺', hl = 'MiniIconsCyan'   },
  murphi             = { glyph = '󰫺', hl = 'MiniIconsAzure'  },
  mush               = { glyph = '󰫺', hl = 'MiniIconsPurple' },
  muttrc             = { glyph = '󰒓', hl = 'MiniIconsAzure'  },
  mysql              = { glyph = '󰆼', hl = 'MiniIconsOrange' },
  n1ql               = { glyph = '󰫻', hl = 'MiniIconsYellow' },
  named              = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  nanorc             = { glyph = '󰒓', hl = 'MiniIconsYellow' },
  nasm               = { glyph = '', hl = 'MiniIconsPurple' },
  nastran            = { glyph = '󰫻', hl = 'MiniIconsRed'    },
  natural            = { glyph = '󰫻', hl = 'MiniIconsBlue'   },
  ncf                = { glyph = '󰫻', hl = 'MiniIconsYellow' },
  neomuttrc          = { glyph = '󰒓', hl = 'MiniIconsGreen'  },
  netrc              = { glyph = '󰒓', hl = 'MiniIconsRed'    },
  netrw              = { glyph = '󰙅', hl = 'MiniIconsBlue'   },
  nginx              = { glyph = '󰰓', hl = 'MiniIconsGreen'  },
  nim                = { glyph = '', hl = 'MiniIconsYellow' },
  ninja              = { glyph = '󰝴', hl = 'MiniIconsGrey'   },
  nix                = { glyph = '󱄅', hl = 'MiniIconsAzure'  },
  nqc                = { glyph = '󱊈', hl = 'MiniIconsYellow' },
  nroff              = { glyph = '󰫻', hl = 'MiniIconsCyan'   },
  nsis               = { glyph = '󰫻', hl = 'MiniIconsAzure'  },
  obj                = { glyph = '󰆧', hl = 'MiniIconsGrey'   },
  objc               = { glyph = '󰀵', hl = 'MiniIconsOrange' },
  objcpp             = { glyph = '󰀵', hl = 'MiniIconsOrange' },
  objdump            = { glyph = '󰫼', hl = 'MiniIconsCyan'   },
  obse               = { glyph = '󰫼', hl = 'MiniIconsBlue'   },
  ocaml              = { glyph = '', hl = 'MiniIconsOrange' },
  occam              = { glyph = '󱦗', hl = 'MiniIconsGrey'   },
  octave             = { glyph = '󱥸', hl = 'MiniIconsBlue'   },
  odin               = { glyph = '󰮔', hl = 'MiniIconsBlue'   },
  omnimark           = { glyph = '󰫼', hl = 'MiniIconsPurple' },
  ondir              = { glyph = '󰫼', hl = 'MiniIconsCyan'   },
  opam               = { glyph = '󰫼', hl = 'MiniIconsBlue'   },
  openroad           = { glyph = '󰫼', hl = 'MiniIconsOrange' },
  openscad           = { glyph = '', hl = 'MiniIconsYellow' },
  openvpn            = { glyph = '󰖂', hl = 'MiniIconsPurple' },
  opl                = { glyph = '󰫼', hl = 'MiniIconsPurple' },
  ora                = { glyph = '󰒓', hl = 'MiniIconsYellow' },
  pacmanlog          = { glyph = '', hl = 'MiniIconsBlue'   },
  pamconf            = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  pamenv             = { glyph = '󰒓', hl = 'MiniIconsYellow' },
  pandoc             = { glyph = '󰍔', hl = 'MiniIconsYellow' },
  papp               = { glyph = '', hl = 'MiniIconsAzure'  },
  pascal             = { glyph = '󱤊', hl = 'MiniIconsRed'    },
  passwd             = { glyph = '󰟵', hl = 'MiniIconsGrey'   },
  pbtxt              = { glyph = '󰦨', hl = 'MiniIconsAzure'  },
  pcap               = { glyph = '󰐪', hl = 'MiniIconsRed'    },
  pccts              = { glyph = '󰫽', hl = 'MiniIconsRed'    },
  pdf                = { glyph = '󰈦', hl = 'MiniIconsRed'    },
  perl               = { glyph = '', hl = 'MiniIconsAzure'  },
  pf                 = { glyph = '󰒓', hl = 'MiniIconsBlue'   },
  pfmain             = { glyph = '󰒓', hl = 'MiniIconsOrange' },
  php                = { glyph = '󰌟', hl = 'MiniIconsPurple' },
  phtml              = { glyph = '󰌟', hl = 'MiniIconsOrange' },
  pic                = { glyph = '', hl = 'MiniIconsPurple' },
  pike               = { glyph = '󰈺', hl = 'MiniIconsGrey'   },
  pilrc              = { glyph = '󰒓', hl = 'MiniIconsRed'    },
  pine               = { glyph = '󰇮', hl = 'MiniIconsRed'    },
  pinfo              = { glyph = '󰒓', hl = 'MiniIconsRed'    },
  plaintex           = { glyph = '', hl = 'MiniIconsGreen'  },
  pli                = { glyph = '󰫽', hl = 'MiniIconsRed'    },
  plm                = { glyph = '󰫽', hl = 'MiniIconsBlue'   },
  plp                = { glyph = '', hl = 'MiniIconsBlue'   },
  plsql              = { glyph = '󰆼', hl = 'MiniIconsOrange' },
  po                 = { glyph = '󰗊', hl = 'MiniIconsAzure'  },
  pod                = { glyph = '', hl = 'MiniIconsPurple' },
  poefilter          = { glyph = '󰫽', hl = 'MiniIconsAzure'  },
  poke               = { glyph = '󰫽', hl = 'MiniIconsPurple' },
  postscr            = { glyph = '', hl = 'MiniIconsYellow' },
  pov                = { glyph = '󰫽', hl = 'MiniIconsPurple' },
  povini             = { glyph = '󰒓', hl = 'MiniIconsBlue'   },
  ppd                = { glyph = '', hl = 'MiniIconsPurple' },
  ppwiz              = { glyph = '󰫽', hl = 'MiniIconsGrey'   },
  prescribe          = { glyph = '󰜆', hl = 'MiniIconsYellow' },
  prisma             = { glyph = '', hl = 'MiniIconsBlue'   },
  privoxy            = { glyph = '󰫽', hl = 'MiniIconsOrange' },
  procmail           = { glyph = '󰇮', hl = 'MiniIconsBlue'   },
  progress           = { glyph = '󰫽', hl = 'MiniIconsGreen'  },
  prolog             = { glyph = '', hl = 'MiniIconsYellow' },
  promela            = { glyph = '󰫽', hl = 'MiniIconsRed'    },
  proto              = { glyph = '', hl = 'MiniIconsRed'    },
  protocols          = { glyph = '󰖟', hl = 'MiniIconsOrange' },
  ps1                = { glyph = '󰨊', hl = 'MiniIconsBlue'   },
  ps1xml             = { glyph = '󰨊', hl = 'MiniIconsAzure'  },
  psf                = { glyph = '󰫽', hl = 'MiniIconsPurple' },
  psl                = { glyph = '󰫽', hl = 'MiniIconsAzure'  },
  ptcap              = { glyph = '󰐪', hl = 'MiniIconsRed'    },
  purescript         = { glyph = '', hl = 'MiniIconsGrey'   },
  purifylog          = { glyph = '', hl = 'MiniIconsBlue'   },
  pymanifest         = { glyph = '󰌠', hl = 'MiniIconsAzure'  },
  pyrex              = { glyph = '󰫽', hl = 'MiniIconsYellow' },
  python             = { glyph = '󰌠', hl = 'MiniIconsYellow' },
  python2            = { glyph = '󰌠', hl = 'MiniIconsGrey'   },
  qb64               = { glyph = '󰫾', hl = 'MiniIconsCyan'   },
  qf                 = { glyph = '󰝖', hl = 'MiniIconsAzure'  },
  qml                = { glyph = '󰫾', hl = 'MiniIconsAzure'  },
  quake              = { glyph = '󰒓', hl = 'MiniIconsBlue'   },
  quarto             = { glyph = '󰐗', hl = 'MiniIconsAzure'  },
  query              = { glyph = '󰐅', hl = 'MiniIconsGreen'  },
  r                  = { glyph = '󰟔', hl = 'MiniIconsBlue'   },
  racc               = { glyph = '󰫿', hl = 'MiniIconsYellow' },
  racket             = { glyph = '󰘧', hl = 'MiniIconsRed'    },
  radiance           = { glyph = '󰫿', hl = 'MiniIconsGrey'   },
  raku               = { glyph = '󱖉', hl = 'MiniIconsYellow' },
  raml               = { glyph = '󰫿', hl = 'MiniIconsCyan'   },
  rapid              = { glyph = '󰫿', hl = 'MiniIconsCyan'   },
  rasi               = { glyph = '󰫿', hl = 'MiniIconsOrange' },
  ratpoison          = { glyph = '󰒓', hl = 'MiniIconsGreen'  },
  rc                 = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  rcs                = { glyph = '󰫿', hl = 'MiniIconsYellow' },
  rcslog             = { glyph = '', hl = 'MiniIconsBlue'   },
  readline           = { glyph = '󰒓', hl = 'MiniIconsGrey'   },
  rebol              = { glyph = '󰫿', hl = 'MiniIconsBlue'   },
  redif              = { glyph = '󰫿', hl = 'MiniIconsOrange' },
  registry           = { glyph = '󰪶', hl = 'MiniIconsRed'    },
  rego               = { glyph = '󰫿', hl = 'MiniIconsPurple' },
  remind             = { glyph = '󰢌', hl = 'MiniIconsPurple' },
  requirements       = { glyph = '󱘎', hl = 'MiniIconsPurple' },
  rescript           = { glyph = '󰫿', hl = 'MiniIconsAzure'  },
  resolv             = { glyph = '󰒓', hl = 'MiniIconsGreen'  },
  reva               = { glyph = '󰫿', hl = 'MiniIconsGrey'   },
  rexx               = { glyph = '󰫿', hl = 'MiniIconsGreen'  },
  rfc_csv            = { glyph = '', hl = 'MiniIconsOrange' },
  rfc_semicolon      = { glyph = '', hl = 'MiniIconsRed'    },
  rhelp              = { glyph = '󰟔', hl = 'MiniIconsAzure'  },
  rib                = { glyph = '󰫿', hl = 'MiniIconsGreen'  },
  rmarkdown          = { glyph = '󰍔', hl = 'MiniIconsAzure'  },
  rmd                = { glyph = '󰍔', hl = 'MiniIconsAzure'  },
  rnc                = { glyph = '󰫿', hl = 'MiniIconsGreen'  },
  rng                = { glyph = '󰫿', hl = 'MiniIconsCyan'   },
  rnoweb             = { glyph = '󰟔', hl = 'MiniIconsGreen'  },
  robots             = { glyph = '󰚩', hl = 'MiniIconsGrey'   },
  roc                = { glyph = '󱗆', hl = 'MiniIconsPurple' },
  routeros           = { glyph = '󱂇', hl = 'MiniIconsGrey'   },
  rpcgen             = { glyph = '󰫿', hl = 'MiniIconsCyan'   },
  rpl                = { glyph = '󰫿', hl = 'MiniIconsCyan'   },
  rrst               = { glyph = '󰫿', hl = 'MiniIconsGreen'  },
  rst                = { glyph = '󰊄', hl = 'MiniIconsYellow' },
  rtf                = { glyph = '󰚞', hl = 'MiniIconsAzure'  },
  ruby               = { glyph = '󰴭', hl = 'MiniIconsRed'    },
  rust               = { glyph = '󱘗', hl = 'MiniIconsOrange' },
  samba              = { glyph = '󰒓', hl = 'MiniIconsGreen'  },
  sas                = { glyph = '󰱐', hl = 'MiniIconsAzure'  },
  sass               = { glyph = '󰟬', hl = 'MiniIconsRed'    },
  sather             = { glyph = '󰬀', hl = 'MiniIconsAzure'  },
  sbt                = { glyph = '', hl = 'MiniIconsOrange' },
  scala              = { glyph = '', hl = 'MiniIconsRed'    },
  scdoc              = { glyph = '󰪶', hl = 'MiniIconsAzure'  },
  scheme             = { glyph = '󰘧', hl = 'MiniIconsGrey'   },
  scilab             = { glyph = '󰂓', hl = 'MiniIconsYellow' },
  screen             = { glyph = '󰒓', hl = 'MiniIconsYellow' },
  scss               = { glyph = '󰟬', hl = 'MiniIconsRed'    },
  sd                 = { glyph = '󰬀', hl = 'MiniIconsGrey'   },
  sdc                = { glyph = '󰬀', hl = 'MiniIconsGreen'  },
  sdl                = { glyph = '󰬀', hl = 'MiniIconsRed'    },
  sed                = { glyph = '󰟥', hl = 'MiniIconsRed'    },
  sendpr             = { glyph = '󰆨', hl = 'MiniIconsBlue'   },
  sensors            = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  services           = { glyph = '󰖟', hl = 'MiniIconsGreen'  },
  setserial          = { glyph = '󰒓', hl = 'MiniIconsRed'    },
  sexplib            = { glyph = '', hl = 'MiniIconsYellow' },
  sgml               = { glyph = '󰬀', hl = 'MiniIconsRed'    },
  sgmldecl           = { glyph = '󰬀', hl = 'MiniIconsYellow' },
  sgmllnx            = { glyph = '󰬀', hl = 'MiniIconsGrey'   },
  sh                 = { glyph = '', hl = 'MiniIconsGrey'   },
  shada              = { glyph = '󰆼', hl = 'MiniIconsGrey'   },
  sicad              = { glyph = '󰬀', hl = 'MiniIconsPurple' },
  sieve              = { glyph = '󰈲', hl = 'MiniIconsOrange' },
  sil                = { glyph = '󰛥', hl = 'MiniIconsOrange' },
  simula             = { glyph = '󰬀', hl = 'MiniIconsPurple' },
  sinda              = { glyph = '󰬀', hl = 'MiniIconsYellow' },
  sindacmp           = { glyph = '󱒒', hl = 'MiniIconsRed'    },
  sindaout           = { glyph = '󰬀', hl = 'MiniIconsBlue'   },
  sisu               = { glyph = '󰬀', hl = 'MiniIconsCyan'   },
  skill              = { glyph = '󰬀', hl = 'MiniIconsGrey'   },
  sl                 = { glyph = '󰟽', hl = 'MiniIconsRed'    },
  slang              = { glyph = '󰬀', hl = 'MiniIconsYellow' },
  slice              = { glyph = '󰧻', hl = 'MiniIconsGrey'   },
  slint              = { glyph = '󰬀', hl = 'MiniIconsAzure'  },
  slpconf            = { glyph = '󰒓', hl = 'MiniIconsGrey'   },
  slpreg             = { glyph = '󰬀', hl = 'MiniIconsCyan'   },
  slpspi             = { glyph = '󰬀', hl = 'MiniIconsPurple' },
  slrnrc             = { glyph = '󰒓', hl = 'MiniIconsOrange' },
  slrnsc             = { glyph = '󰬀', hl = 'MiniIconsCyan'   },
  sm                 = { glyph = '󱃜', hl = 'MiniIconsBlue'   },
  smarty             = { glyph = '', hl = 'MiniIconsYellow' },
  smcl               = { glyph = '󰄨', hl = 'MiniIconsRed'    },
  smil               = { glyph = '󰬀', hl = 'MiniIconsOrange' },
  smith              = { glyph = '󰬀', hl = 'MiniIconsRed'    },
  sml                = { glyph = '󰘧', hl = 'MiniIconsOrange' },
  snnsnet            = { glyph = '󰖟', hl = 'MiniIconsGreen'  },
  snnspat            = { glyph = '󰬀', hl = 'MiniIconsGreen'  },
  snnsres            = { glyph = '󰬀', hl = 'MiniIconsBlue'   },
  snobol4            = { glyph = '󰬀', hl = 'MiniIconsCyan'   },
  solidity           = { glyph = '', hl = 'MiniIconsAzure'  },
  solution           = { glyph = '󰘐', hl = 'MiniIconsBlue'   },
  spec               = { glyph = '', hl = 'MiniIconsBlue'   },
  specman            = { glyph = '󰬀', hl = 'MiniIconsCyan'   },
  spice              = { glyph = '󰬀', hl = 'MiniIconsOrange' },
  splint             = { glyph = '󰙱', hl = 'MiniIconsGreen'  },
  spup               = { glyph = '󰬀', hl = 'MiniIconsOrange' },
  spyce              = { glyph = '󰬀', hl = 'MiniIconsRed'    },
  sql                = { glyph = '󰆼', hl = 'MiniIconsGrey'   },
  sqlanywhere        = { glyph = '󰆼', hl = 'MiniIconsAzure'  },
  sqlforms           = { glyph = '󰆼', hl = 'MiniIconsOrange' },
  sqlhana            = { glyph = '󰆼', hl = 'MiniIconsPurple' },
  sqlinformix        = { glyph = '󰆼', hl = 'MiniIconsBlue'   },
  sqlj               = { glyph = '󰆼', hl = 'MiniIconsGrey'   },
  sqloracle          = { glyph = '󰆼', hl = 'MiniIconsOrange' },
  sqr                = { glyph = '󰬀', hl = 'MiniIconsGrey'   },
  squid              = { glyph = '󰒓', hl = 'MiniIconsYellow' },
  squirrel           = { glyph = '', hl = 'MiniIconsGrey'   },
  srec               = { glyph = '󰍛', hl = 'MiniIconsAzure'  },
  srt                = { glyph = '󰨖', hl = 'MiniIconsYellow' },
  ssa                = { glyph = '󰨖', hl = 'MiniIconsOrange' },
  sshconfig          = { glyph = '󰒓', hl = 'MiniIconsGreen'  },
  sshdconfig         = { glyph = '󰒓', hl = 'MiniIconsPurple' },
  st                 = { glyph = '󰄚', hl = 'MiniIconsOrange' },
  stata              = { glyph = '󰝫', hl = 'MiniIconsRed'    },
  stp                = { glyph = '󰬀', hl = 'MiniIconsYellow' },
  strace             = { glyph = '󰬀', hl = 'MiniIconsPurple' },
  structurizr        = { glyph = '󰬀', hl = 'MiniIconsBlue'   },
  stylus             = { glyph = '󰴒', hl = 'MiniIconsGrey'   },
  sudoers            = { glyph = '󰒓', hl = 'MiniIconsGrey'   },
  svg                = { glyph = '󰜡', hl = 'MiniIconsYellow' },
  svn                = { glyph = '󰜘', hl = 'MiniIconsOrange' },
  swayconfig         = { glyph = '󰒓', hl = 'MiniIconsPurple' },
  swift              = { glyph = '󰛥', hl = 'MiniIconsOrange' },
  swiftgyb           = { glyph = '󰛥', hl = 'MiniIconsYellow' },
  swig               = { glyph = '󰬀', hl = 'MiniIconsGreen'  },
  sysctl             = { glyph = '󰒓', hl = 'MiniIconsOrange' },
  systemd            = { glyph = '', hl = 'MiniIconsGrey'   },
  systemverilog      = { glyph = '󰍛', hl = 'MiniIconsGreen'  },
  tads               = { glyph = '󱩼', hl = 'MiniIconsAzure'  },
  tags               = { glyph = '󰓻', hl = 'MiniIconsGreen'  },
  tak                = { glyph = '󰔏', hl = 'MiniIconsRed'    },
  takcmp             = { glyph = '󰔏', hl = 'MiniIconsGreen'  },
  takout             = { glyph = '󰔏', hl = 'MiniIconsBlue'   },
  tap                = { glyph = '󰬁', hl = 'MiniIconsAzure'  },
  tar                = { glyph = '󰬁', hl = 'MiniIconsCyan'   },
  taskdata           = { glyph = '󱒋', hl = 'MiniIconsPurple' },
  taskedit           = { glyph = '󰬁', hl = 'MiniIconsAzure'  },
  tasm               = { glyph = '', hl = 'MiniIconsPurple' },
  tcl                = { glyph = '󰛓', hl = 'MiniIconsRed'    },
  tcsh               = { glyph = '', hl = 'MiniIconsAzure'  },
  template           = { glyph = '󰬁', hl = 'MiniIconsGreen'  },
  teraterm           = { glyph = '󰅭', hl = 'MiniIconsGreen'  },
  terminfo           = { glyph = '', hl = 'MiniIconsGrey'   },
  tex                = { glyph = '', hl = 'MiniIconsGreen'  },
  texinfo            = { glyph = '', hl = 'MiniIconsAzure'  },
  texmf              = { glyph = '󰒓', hl = 'MiniIconsPurple' },
  text               = { glyph = '󰦨', hl = 'MiniIconsAzure'  },
  tf                 = { glyph = '󰒓', hl = 'MiniIconsBlue'   },
  tidy               = { glyph = '󰌝', hl = 'MiniIconsBlue'   },
  tilde              = { glyph = '󰜥', hl = 'MiniIconsRed'    },
  tli                = { glyph = '󰬁', hl = 'MiniIconsCyan'   },
  tmux               = { glyph = '󰒓', hl = 'MiniIconsGreen'  },
  toml               = { glyph = '', hl = 'MiniIconsOrange' },
  tpp                = { glyph = '󰐨', hl = 'MiniIconsPurple' },
  trasys             = { glyph = '󰬁', hl = 'MiniIconsBlue'   },
  treetop            = { glyph = '󰔱', hl = 'MiniIconsGreen'  },
  trustees           = { glyph = '󰬁', hl = 'MiniIconsPurple' },
  tsalt              = { glyph = '󰬁', hl = 'MiniIconsPurple' },
  tsscl              = { glyph = '󱣖', hl = 'MiniIconsGreen'  },
  tssgm              = { glyph = '󱣖', hl = 'MiniIconsYellow' },
  tssop              = { glyph = '󱣖', hl = 'MiniIconsGrey'   },
  tsv                = { glyph = '', hl = 'MiniIconsBlue'   },
  tt2                = { glyph = '', hl = 'MiniIconsAzure'  },
  tt2html            = { glyph = '', hl = 'MiniIconsOrange' },
  tt2js              = { glyph = '', hl = 'MiniIconsYellow' },
  tutor              = { glyph = '󱆀', hl = 'MiniIconsPurple' },
  typescript         = { glyph = '󰛦', hl = 'MiniIconsAzure'  },
  typescriptreact    = { glyph = '', hl = 'MiniIconsBlue'   },
  typst              = { glyph = '󰬛', hl = 'MiniIconsAzure'  },
  uc                 = { glyph = '󰬂', hl = 'MiniIconsGrey'   },
  uci                = { glyph = '󰒓', hl = 'MiniIconsRed'    },
  udevconf           = { glyph = '󰒓', hl = 'MiniIconsOrange' },
  udevperm           = { glyph = '󰬂', hl = 'MiniIconsOrange' },
  udevrules          = { glyph = '󰬂', hl = 'MiniIconsBlue'   },
  uil                = { glyph = '󰬂', hl = 'MiniIconsGrey'   },
  unison             = { glyph = '󰡉', hl = 'MiniIconsYellow' },
  updatedb           = { glyph = '󰒓', hl = 'MiniIconsGrey'   },
  upstart            = { glyph = '󰬂', hl = 'MiniIconsCyan'   },
  upstreamdat        = { glyph = '󰬂', hl = 'MiniIconsGreen'  },
  upstreaminstalllog = { glyph = '', hl = 'MiniIconsBlue'   },
  upstreamlog        = { glyph = '', hl = 'MiniIconsBlue'   },
  upstreamrpt        = { glyph = '󰬂', hl = 'MiniIconsYellow' },
  urlshortcut        = { glyph = '󰌷', hl = 'MiniIconsPurple' },
  usd                = { glyph = '󰻇', hl = 'MiniIconsAzure'  },
  usserverlog        = { glyph = '', hl = 'MiniIconsBlue'   },
  usw2kagtlog        = { glyph = '', hl = 'MiniIconsBlue'   },
  v                  = { glyph = '󰬃', hl = 'MiniIconsBlue'   },
  valgrind           = { glyph = '󰍛', hl = 'MiniIconsGrey'   },
  vb                 = { glyph = '󰛤', hl = 'MiniIconsPurple' },
  vdf                = { glyph = '󰬃', hl = 'MiniIconsCyan'   },
  vera               = { glyph = '󰬃', hl = 'MiniIconsCyan'   },
  verilog            = { glyph = '󰍛', hl = 'MiniIconsGreen'  },
  verilogams         = { glyph = '󰍛', hl = 'MiniIconsGreen'  },
  vgrindefs          = { glyph = '󰬃', hl = 'MiniIconsPurple' },
  vhdl               = { glyph = '󰍛', hl = 'MiniIconsGreen'  },
  vim                = { glyph = '', hl = 'MiniIconsGreen'  },
  viminfo            = { glyph = '', hl = 'MiniIconsBlue'   },
  virata             = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  vmasm              = { glyph = '', hl = 'MiniIconsPurple' },
  voscm              = { glyph = '󰬃', hl = 'MiniIconsCyan'   },
  vrml               = { glyph = '󰬃', hl = 'MiniIconsBlue'   },
  vroom              = { glyph = '', hl = 'MiniIconsOrange' },
  vsejcl             = { glyph = '󰬃', hl = 'MiniIconsCyan'   },
  vue                = { glyph = '󰡄', hl = 'MiniIconsGreen'  },
  wat                = { glyph = '', hl = 'MiniIconsPurple' },
  wdiff              = { glyph = '󰦓', hl = 'MiniIconsBlue'   },
  wdl                = { glyph = '󰬄', hl = 'MiniIconsGrey'   },
  web                = { glyph = '󰯊', hl = 'MiniIconsGrey'   },
  webmacro           = { glyph = '󰬄', hl = 'MiniIconsGreen'  },
  wget               = { glyph = '󰒓', hl = 'MiniIconsYellow' },
  wget2              = { glyph = '󰒓', hl = 'MiniIconsBlue'   },
  winbatch           = { glyph = '󰯂', hl = 'MiniIconsBlue'   },
  wml                = { glyph = '󰖟', hl = 'MiniIconsGreen'  },
  wsh                = { glyph = '󰯂', hl = 'MiniIconsPurple' },
  wsml               = { glyph = '󰬄', hl = 'MiniIconsAzure'  },
  wvdial             = { glyph = '󰒓', hl = 'MiniIconsAzure'  },
  xbl                = { glyph = '󰬅', hl = 'MiniIconsAzure'  },
  xcompose           = { glyph = '󰌌', hl = 'MiniIconsOrange' },
  xdefaults          = { glyph = '󰒓', hl = 'MiniIconsBlue'   },
  xf86conf           = { glyph = '󰒓', hl = 'MiniIconsAzure'  },
  xhtml              = { glyph = '󰌝', hl = 'MiniIconsOrange' },
  xinetd             = { glyph = '󰒓', hl = 'MiniIconsGreen'  },
  xkb                = { glyph = '󰌌', hl = 'MiniIconsPurple' },
  xmath              = { glyph = '󰬅', hl = 'MiniIconsYellow' },
  xml                = { glyph = '󰗀', hl = 'MiniIconsOrange' },
  xmodmap            = { glyph = '󰬅', hl = 'MiniIconsCyan'   },
  xpm                = { glyph = '󰍹', hl = 'MiniIconsYellow' },
  xpm2               = { glyph = '󰍹', hl = 'MiniIconsGreen'  },
  xquery             = { glyph = '󰗀', hl = 'MiniIconsAzure'  },
  xs                 = { glyph = '', hl = 'MiniIconsRed'    },
  xsd                = { glyph = '󰗀', hl = 'MiniIconsYellow' },
  xslt               = { glyph = '󰗀', hl = 'MiniIconsGreen'  },
  xxd                = { glyph = '󰬅', hl = 'MiniIconsBlue'   },
  yacc               = { glyph = '󰬆', hl = 'MiniIconsOrange' },
  yaml               = { glyph = '', hl = 'MiniIconsPurple' },
  z8a                = { glyph = '', hl = 'MiniIconsGrey'   },
  zathurarc          = { glyph = '󰒓', hl = 'MiniIconsRed'    },
  zig                = { glyph = '', hl = 'MiniIconsOrange' },
  zimbu              = { glyph = '󰬇', hl = 'MiniIconsGreen'  },
  zir                = { glyph = '', hl = 'MiniIconsOrange' },
  zserio             = { glyph = '󰬇', hl = 'MiniIconsGrey'   },
  zsh                = { glyph = '', hl = 'MiniIconsGreen'  },

  -- 'mini.nvim'
  ['minideps-confirm']   = { glyph = '', hl = 'MiniIconsOrange' },
  minifiles              = { glyph = '', hl = 'MiniIconsGreen' },
  ['minifiles-help']     = { glyph = '', hl = 'MiniIconsGreen' },
  mininotify             = { glyph = '', hl = 'MiniIconsYellow' },
  ['mininotify-history'] = { glyph = '', hl = 'MiniIconsYellow' },
  minipick               = { glyph = '', hl = 'MiniIconsCyan' },
  starter                = { glyph = '', hl = 'MiniIconsAzure' },

  -- TODO
  -- Lua plugins
  lazy = { glyph = '󰒲', hl = 'MiniIconsBlue' },
}

-- Extension icons
--stylua: ignore
H.extension_icons = {
  -- Popular extensions associated with supported filetype. Present to not have
  -- to rely on `vim.filetype.match()` in some cases (for performance or if it
  -- fails to compute filetype by filename and content only, like '.ts', '.h').
  -- Present only those which can be unambiguously detected from the extension.
  -- Value is string with filetype's name to inherit from its icon data
  asm   = 'asm',
  bib   = 'bib',
  bzl   = 'bzl',
  c     = 'c',
  cbl   = 'cobol',
  clj   = 'clojure',
  cpp   = 'cpp',
  cs    = 'cs',
  css   = 'css',
  csv   = 'csv',
  cu    = 'cuda',
  dart  = 'dart',
  diff  = 'diff',
  el    = 'lisp',
  elm   = 'elm',
  erl   = 'erlang',
  exs   = 'elixir',
  f90   = 'fortran',
  fish  = 'fish',
  fnl   = 'fennel',
  go    = 'go',
  h     = { glyph = '󰫵', hl = 'MiniIconsPurple' },
  hs    = 'haskell',
  htm   = 'html',
  html  = 'html',
  jav   = 'java',
  java  = 'java',
  jl    = 'julia',
  js    = 'javascript',
  json  = 'json',
  json5 = 'json5',
  kt    = 'kotlin',
  latex = 'tex',
  lua   = 'lua',
  md    = 'markdown',
  ml    = 'ocaml',
  mojo  = 'mojo',
  nim   = 'nim',
  nix   = 'nix',
  pdb   = 'prolog',
  pdf   = 'pdf',
  php   = 'php',
  purs  = 'purescript',
  py    = 'python',
  qmd   = 'quarto',
  r     = 'r',
  raku  = 'raku',
  rb    = 'ruby',
  rmd   = 'rmd',
  roc   = 'roc',
  rs    = 'rust',
  rst   = 'rst',
  scala = 'scala',
  sh    = 'bash',
  sol   = 'solidity',
  srt   = 'srt',
  ss    = 'scheme',
  ssa   = 'ssa',
  svg   = 'svg',
  swift = 'swift',
  toml  = 'toml',
  ts    = 'typescript',
  tsv   = 'tsv',
  -- Although there are some exact basename matches in `vim.filetype.match()`,
  -- it does not detect 'txt' extension as "text" in most cases.
  txt   = 'text',
  vim   = 'vim',
  vue   = 'vue',
  yaml  = 'yaml',
  yml   = 'yaml',
  zig   = 'zig',
  zsh   = 'zsh',

  -- Video
  ['3gp'] = { glyph = '󰈫', hl = 'MiniIconsYellow' },
  avi     = { glyph = '󰈫', hl = 'MiniIconsGrey'   },
  cast    = { glyph = '󰈫', hl = 'MiniIconsRed'    },
  m4v     = { glyph = '󰈫', hl = 'MiniIconsOrange' },
  mkv     = { glyph = '󰈫', hl = 'MiniIconsGreen'  },
  mov     = { glyph = '󰈫', hl = 'MiniIconsCyan'   },
  mp4     = { glyph = '󰈫', hl = 'MiniIconsAzure'  },
  mpeg    = { glyph = '󰈫', hl = 'MiniIconsPurple' },
  mpg     = { glyph = '󰈫', hl = 'MiniIconsPurple' },
  webm    = { glyph = '󰈫', hl = 'MiniIconsGrey'   },
  wmv     = { glyph = '󰈫', hl = 'MiniIconsBlue'   },

  -- Audio
  aac  = { glyph = '󰈣', hl = 'MiniIconsYellow' },
  aif  = { glyph = '󰈣', hl = 'MiniIconsCyan'   },
  flac = { glyph = '󰈣', hl = 'MiniIconsOrange' },
  m4a  = { glyph = '󰈣', hl = 'MiniIconsPurple' },
  mp3  = { glyph = '󰈣', hl = 'MiniIconsAzure'  },
  ogg  = { glyph = '󰈣', hl = 'MiniIconsGrey'   },
  snd  = { glyph = '󰈣', hl = 'MiniIconsRed'    },
  wav  = { glyph = '󰈣', hl = 'MiniIconsGreen'  },
  wma  = { glyph = '󰈣', hl = 'MiniIconsBlue'   },

  -- Image
  bmp  = { glyph = '󰈟', hl = 'MiniIconsGreen'  },
  eps  = { glyph = '', hl = 'MiniIconsRed'    },
  gif  = { glyph = '󰵸', hl = 'MiniIconsAzure'  },
  jpeg = { glyph = '󰈥', hl = 'MiniIconsOrange' },
  jpg  = { glyph = '󰈥', hl = 'MiniIconsOrange' },
  png  = { glyph = '󰸭', hl = 'MiniIconsPurple' },
  tif  = { glyph = '󰈟', hl = 'MiniIconsYellow' },
  tiff = { glyph = '󰈟', hl = 'MiniIconsYellow' },
  webp = { glyph = '󰈟', hl = 'MiniIconsBlue'   },

  -- Archives
  ["7z"] = { glyph = '󰗄', hl = 'MiniIconsBlue'   },
  bz     = { glyph = '󰗄', hl = 'MiniIconsOrange' },
  bz2    = { glyph = '󰗄', hl = 'MiniIconsOrange' },
  bz3    = { glyph = '󰗄', hl = 'MiniIconsOrange' },
  gz     = { glyph = '󰗄', hl = 'MiniIconsGrey'   },
  rar    = { glyph = '󰗄', hl = 'MiniIconsGreen'  },
  rpm    = { glyph = '󰗄', hl = 'MiniIconsRed'    },
  sit    = { glyph = '󰗄', hl = 'MiniIconsRed'    },
  tar    = { glyph = '󰗄', hl = 'MiniIconsCyan'   },
  tgz    = { glyph = '󰗄', hl = 'MiniIconsGrey'   },
  txz    = { glyph = '󰗄', hl = 'MiniIconsPurple' },
  xz     = { glyph = '󰗄', hl = 'MiniIconsGreen'  },
  z      = { glyph = '󰗄', hl = 'MiniIconsGrey'   },
  zip    = { glyph = '󰗄', hl = 'MiniIconsAzure'  },
  zst    = { glyph = '󰗄', hl = 'MiniIconsYellow' },

  -- Software
  doc  = { glyph = '󰈭', hl = 'MiniIconsAzure' },
  docm = { glyph = '󰈭', hl = 'MiniIconsAzure' },
  docx = { glyph = '󰈭', hl = 'MiniIconsAzure' },
  dot  = { glyph = '󰈭', hl = 'MiniIconsAzure' },
  dotx = { glyph = '󰈭', hl = 'MiniIconsAzure' },
  exe  = { glyph = '󰒔', hl = 'MiniIconsGrey'  },
  pps  = { glyph = '󰈨', hl = 'MiniIconsRed'   },
  ppsm = { glyph = '󰈨', hl = 'MiniIconsRed'   },
  ppsx = { glyph = '󰈨', hl = 'MiniIconsRed'   },
  ppt  = { glyph = '󰈨', hl = 'MiniIconsRed'   },
  pptm = { glyph = '󰈨', hl = 'MiniIconsRed'   },
  pptx = { glyph = '󰈨', hl = 'MiniIconsRed'   },
  xls  = { glyph = '󰈜', hl = 'MiniIconsGreen' },
  xlsm = { glyph = '󰈜', hl = 'MiniIconsGreen' },
  xlsx = { glyph = '󰈜', hl = 'MiniIconsGreen' },
  xlt  = { glyph = '󰈜', hl = 'MiniIconsGreen' },
  xltm = { glyph = '󰈜', hl = 'MiniIconsGreen' },
  xltx = { glyph = '󰈜', hl = 'MiniIconsGreen' },
}

-- LSP kind values (completion item, symbol, etc.) icons.
-- Use only `nf-cod-*` classes with "outline" look. Balance colors.
--stylua: ignore
H.lsp_kind_icons = {
  array         = { glyph = '', hl = 'MiniIconsOrange' },
  boolean       = { glyph = '', hl = 'MiniIconsOrange' },
  class         = { glyph = '', hl = 'MiniIconsPurple' },
  color         = { glyph = '', hl = 'MiniIconsRed'    },
  constant      = { glyph = '', hl = 'MiniIconsOrange' },
  constructor   = { glyph = '', hl = 'MiniIconsAzure'  },
  enum          = { glyph = '', hl = 'MiniIconsPurple' },
  enumMember    = { glyph = '', hl = 'MiniIconsYellow' },
  event         = { glyph = '', hl = 'MiniIconsRed'    },
  field         = { glyph = '', hl = 'MiniIconsYellow' },
  file          = { glyph = '', hl = 'MiniIconsBlue'   },
  folder        = { glyph = '', hl = 'MiniIconsBlue'   },
  ['function']  = { glyph = '', hl = 'MiniIconsAzure'  },
  interface     = { glyph = '', hl = 'MiniIconsPurple' },
  key           = { glyph = '', hl = 'MiniIconsYellow' },
  keyword       = { glyph = '', hl = 'MiniIconsCyan'   },
  method        = { glyph = '', hl = 'MiniIconsAzure'  },
  module        = { glyph = '', hl = 'MiniIconsPurple' },
  namespace     = { glyph = '', hl = 'MiniIconsRed'    },
  null          = { glyph = '', hl = 'MiniIconsGrey'   },
  number        = { glyph = '', hl = 'MiniIconsOrange' },
  object        = { glyph = '', hl = 'MiniIconsGrey'   },
  operator      = { glyph = '', hl = 'MiniIconsCyan'   },
  package       = { glyph = '', hl = 'MiniIconsPurple' },
  property      = { glyph = '', hl = 'MiniIconsYellow' },
  reference     = { glyph = '', hl = 'MiniIconsCyan'   },
  snippet       = { glyph = '', hl = 'MiniIconsGreen'  },
  string        = { glyph = '', hl = 'MiniIconsGreen'  },
  struct        = { glyph = '', hl = 'MiniIconsPurple' },
  text          = { glyph = '', hl = 'MiniIconsGreen'  },
  typeParameter = { glyph = '', hl = 'MiniIconsCyan'   },
  unit          = { glyph = '', hl = 'MiniIconsCyan'   },
  unknown       = { glyph = '', hl = 'MiniIconsGrey'   },
  value         = { glyph = '', hl = 'MiniIconsBlue'   },
  variable      = { glyph = '', hl = 'MiniIconsCyan'   },
}

-- Path icons. Keys are mostly some popular file/directory basenames and the
-- ones which can conflict with icon detection through extension.
--stylua: ignore
H.path_icons = {
  -- TODO: Add more
  ['init.lua'] = { glyph = '', hl = 'MiniIconsGreen'  },
  LICENSE      = { glyph = '', hl = 'MiniIconsYellow' },
}

-- OS icons. Keys are at least for all icons from Nerd fonts (`nf-linux-*`).
-- Highlight groups are inferred to be aligned with 'nvim-web-devicons'.
--stylua: ignore
H.os_icons = {
  alma         = { glyph = '', hl = 'MiniIconsRed'    },
  alpine       = { glyph = '', hl = 'MiniIconsAzure'  },
  aosc         = { glyph = '', hl = 'MiniIconsRed'    },
  apple        = { glyph = '', hl = 'MiniIconsGrey'   },
  arch         = { glyph = '󰣇', hl = 'MiniIconsAzure'  },
  archcraft    = { glyph = '', hl = 'MiniIconsCyan'   },
  archlabs     = { glyph = '', hl = 'MiniIconsGrey'   },
  arcolinux    = { glyph = '', hl = 'MiniIconsBlue'   },
  artix        = { glyph = '', hl = 'MiniIconsAzure'  },
  biglinux     = { glyph = '', hl = 'MiniIconsAzure'  },
  centos       = { glyph = '', hl = 'MiniIconsRed'    },
  crystallinux = { glyph = '', hl = 'MiniIconsPurple' },
  debian       = { glyph = '', hl = 'MiniIconsRed'    },
  deepin       = { glyph = '', hl = 'MiniIconsAzure'  },
  devuan       = { glyph = '', hl = 'MiniIconsGrey'   },
  elementary   = { glyph = '', hl = 'MiniIconsAzure'  },
  endeavour    = { glyph = '', hl = 'MiniIconsPurple' },
  fedora       = { glyph = '', hl = 'MiniIconsBlue'   },
  freebsd      = { glyph = '', hl = 'MiniIconsRed'    },
  garuda       = { glyph = '', hl = 'MiniIconsBlue'   },
  gentoo       = { glyph = '󰣨', hl = 'MiniIconsPurple' },
  guix         = { glyph = '', hl = 'MiniIconsYellow' },
  hyperbola    = { glyph = '', hl = 'MiniIconsGrey'   },
  illumos      = { glyph = '', hl = 'MiniIconsRed'    },
  kali         = { glyph = '', hl = 'MiniIconsBlue'   },
  kdeneon      = { glyph = '', hl = 'MiniIconsCyan'   },
  kubuntu      = { glyph = '', hl = 'MiniIconsAzure'  },
  linux        = { glyph = '', hl = 'MiniIconsGrey'   },
  locos        = { glyph = '', hl = 'MiniIconsYellow' },
  lxle         = { glyph = '', hl = 'MiniIconsGrey'   },
  mageia       = { glyph = '', hl = 'MiniIconsAzure'  },
  manjaro      = { glyph = '', hl = 'MiniIconsGreen'  },
  mint         = { glyph = '󰣭', hl = 'MiniIconsGreen'  },
  mxlinux      = { glyph = '', hl = 'MiniIconsGrey'   },
  nixos        = { glyph = '', hl = 'MiniIconsAzure'  },
  openbsd      = { glyph = '', hl = 'MiniIconsYellow' },
  opensuse     = { glyph = '', hl = 'MiniIconsGreen'  },
  parabola     = { glyph = '', hl = 'MiniIconsBlue'   },
  parrot       = { glyph = '', hl = 'MiniIconsAzure'  },
  pop_os       = { glyph = '', hl = 'MiniIconsAzure'  },
  postmarketos = { glyph = '', hl = 'MiniIconsGreen'  },
  puppylinux   = { glyph = '', hl = 'MiniIconsGrey'   },
  qubesos      = { glyph = '', hl = 'MiniIconsBlue'   },
  raspberry_pi = { glyph = '', hl = 'MiniIconsRed'    },
  redhat       = { glyph = '󱄛', hl = 'MiniIconsOrange' },
  rocky        = { glyph = '', hl = 'MiniIconsCyan'   },
  sabayon      = { glyph = '', hl = 'MiniIconsGrey'   },
  slackware    = { glyph = '', hl = 'MiniIconsBlue'   },
  solus        = { glyph = '', hl = 'MiniIconsBlue'   },
  tails        = { glyph = '', hl = 'MiniIconsPurple' },
  trisquel     = { glyph = '', hl = 'MiniIconsBlue'   },
  ubuntu       = { glyph = '', hl = 'MiniIconsOrange' },
  vanillaos    = { glyph = '', hl = 'MiniIconsYellow' },
  void         = { glyph = '', hl = 'MiniIconsCyan'   },
  windows      = { glyph = '', hl = 'MiniIconsAzure'  },
  xerolinux    = { glyph = '', hl = 'MiniIconsBlue'   },
  zorin        = { glyph = '', hl = 'MiniIconsAzure'  }
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  vim.validate({
    style = { config.style, 'string' },
    override = { config.override, 'function', true },
  })

  return config
end

H.apply_config = function(config) MiniIcons.config = config end

--stylua: ignore
H.create_default_hl = function()
  local hi = function(name, opts)
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end

  hi('MiniIconsAzure', { link = 'Function' })
  hi('MiniIconsBlue', { link = 'DiagnosticInfo' })
  hi('MiniIconsCyan', { link = 'DiagnosticHint' })
  hi('MiniIconsGreen', { link = 'DiagnosticOk' })
  hi('MiniIconsGrey', {})
  hi('MiniIconsOrange', { link = 'DiagnosticWarn' })
  hi('MiniIconsPurple', { link = 'Constant' })
  hi('MiniIconsRed', { link = 'DiagnosticError' })
  hi('MiniIconsYellow', { link = 'DiagnosticWarn' })
end

-- Getters --------------------------------------------------------------------
H.get_from_extension = function(ext, full_basename)
  local icon_data = H.extension_icons[ext]
  if type(icon_data) == 'string' then return MiniIcons.get('filetype', icon_data) end
  if icon_data ~= nil then return H.finalize_icon(icon_data, ext), icon_data.hl end
end

H.get_impl = {
  extension = function(name)
    local icon, hl = H.get_from_extension(name)
    if icon ~= nil then return icon, hl end

    -- Fall back to built-in filetype matching using generic filename
    local ft = vim.filetype.match({ filename = 'aaa.' .. name, contents = { '' } })
    if ft ~= nil then return MiniIcons.get('filetype', ft) end
  end,

  filetype = function(name)
    local icon_data = H.filetype_icons[name]
    if icon_data ~= nil then return H.finalize_icon(icon_data, name), icon_data.hl end
  end,

  lsp_kind = function(name)
    local icon_data = H.lsp_kind_icons[name]
    if icon_data ~= nil then return H.finalize_icon(icon_data, name), icon_data.hl end
  end,

  os = function(name)
    local icon_data = H.os_icons[name]
    if icon_data ~= nil then return H.finalize_icon(icon_data, name), icon_data.hl end
  end,

  path = function(name)
    local icon_data = H.path_icons[name]
    if icon_data ~= nil then return H.finalize_icon(icon_data, name), icon_data.hl end

    -- Try using custom extensions first before for better speed (as
    -- `vim.filetype.match()` is relatively slow to be called many times; like 0.1 ms)
    local dot = string.find(name, '%..', 2)
    if dot == nil then return end
    while dot ~= nil do
      local ext = name:sub(dot + 1):lower()

      local cached = H.cache.extension[ext]
      if cached ~= nil then return cached[1], cached[2] end

      local icon, hl = H.get_from_extension(ext, name)
      -- NOTE: don't set cache for found extension because it might be a result
      -- of an exact basename match and not proper icon for extension as whole
      if icon ~= nil then return icon, hl end

      dot = string.find(name, '%..', dot + 1)
    end

    -- Fall back to built-in filetype matching using generic filename
    local ft = vim.filetype.match({ filename = name, contents = { '' } })
    if ft ~= nil then return MiniIcons.get('filetype', ft) end
  end,
}

-- Styles ---------------------------------------------------------------------
H.finalize_icon = function(icon_data, name)
  local style = MiniIcons.config.style
  return style == 'glyph' and icon_data.glyph or (style == 'ascii' and name:sub(1, 1):upper() or '???')
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.icons) %s', msg), 0) end

H.notify = function(msg, level_name) vim.notify('(mini.icons) ' .. msg, vim.log.levels[level_name]) end

H.fs_basename = function(x) return vim.fn.fnamemodify(x:sub(-1, -1) == '/' and x:sub(1, -2) or x, ':t') end
if vim.loop.os_uname().sysname == 'Windows_NT' then
  H.fs_basename = function(x)
    local last = x:sub(-1, -1)
    return vim.fn.fnamemodify((last == '/' or last == '\\') and x:sub(1, -2) or x, ':t')
  end
end

-- local n = 1000
-- H.bench_icons = function()
--   local start_time = vim.loop.hrtime()
--   for i = 1, n do
--     MiniIcons.get('path', 'aaa_' .. i .. '.lua')
--   end
--   return 0.000001 * (vim.loop.hrtime() - start_time) / n
-- end
-- H.bench_devicons = function()
--   local get_icon = require('nvim-web-devicons').get_icon
--   local start_time = vim.loop.hrtime()
--   for i = 1, n do
--     get_icon('aaa_' .. i .. '.lua', nil, { default = false })
--   end
--   return 0.000001 * (vim.loop.hrtime() - start_time) / n
-- end

_G.count_ft_hl = function()
  local res = { total = 0 }
  for _, icon_data in pairs(H.filetype_icons) do
    res[icon_data.hl] = (res[icon_data.hl] or 0) + 1
    res.total = res.total + 1
  end
  return res
end

_G.count_ft_icons = function()
  local res = {}
  for ft, icon_data in pairs(H.filetype_icons) do
    local icon_letters = res[icon_data.glyph] or {}
    local letter = ft:sub(1, 1)
    icon_letters[letter] = (icon_letters[letter] or 0) + 1
    res[icon_data.glyph] = icon_letters
  end
  return res
end

-- _G.replace_random_match = function(new_val)
--   local n = math.random(300, 500)
--   vim.fn.setreg('z', new_val)
--   vim.cmd('normal ' .. n .. 'nvgn"zP')
-- end

return MiniIcons
