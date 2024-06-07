--- TODO:
--- - Code:
---     - Add main table for filetypes.
---
---     - Think about the interface for default icons.
---
---     - Verify how icons look in popular terminal emulators.
---
---     - Check how default highlight groups look in popular color schemes.
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
---   operating system. Icons can be overridden.
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
  -- TODO
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniIcons.config

-- Cache for `get()` output per category
H.cache = { extension = {}, filetype = {}, path = {}, os = {} }

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
-- - For newly assigned icons prefer using semantically close abstract icons
--   with `nf-md-*` Nerd Font class.
-- - If no semantically close abstract icon present, use variation of letter
--   icon (plain, full/outline circle/square) with highlight groups picked to
--   achieve overall balance.

-- Neovim filetype plugins
--stylua: ignore
H.filetype_icons = {
  ['8th']            = { glyph = '󰭁', hl = 'MiniIconsYellow' },
  a2ps               = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  a65                = { glyph = '', hl = 'MiniIconsRed'    },
  aap                = { glyph = '',  hl = 'MiniIcons'       },
  abap               = { glyph = '',  hl = 'MiniIcons'       },
  abaqus             = { glyph = '',  hl = 'MiniIcons'       },
  abc                = { glyph = '󰝚', hl = 'MiniIconsYellow' },
  abel               = { glyph = '',  hl = 'MiniIcons'       },
  acedb              = { glyph = '󰆼', hl = 'MiniIconsGrey'   },
  ada                = { glyph = '󱁷', hl = 'MiniIconsAzure'  },
  aflex              = { glyph = '',  hl = 'MiniIcons'       },
  ahdl               = { glyph = '',  hl = 'MiniIcons'       },
  aidl               = { glyph = '',  hl = 'MiniIcons'       },
  alsaconf           = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  amiga              = { glyph = '',  hl = 'MiniIcons'       },
  aml                = { glyph = '',  hl = 'MiniIcons'       },
  ampl               = { glyph = '',  hl = 'MiniIcons'       },
  ant                = { glyph = '',  hl = 'MiniIcons'       },
  antlr              = { glyph = '',  hl = 'MiniIcons'       },
  apache             = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  apachestyle        = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  aptconf            = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  arch               = { glyph = '󰣇', hl = 'MiniIconsBlue'   },
  arduino            = { glyph = '', hl = 'MiniIconsAzure'  },
  art                = { glyph = '',  hl = 'MiniIcons'       },
  asciidoc           = { glyph = '󰪶', hl = 'MiniIconsYellow' },
  asm                = { glyph = '', hl = 'MiniIconsPurple' },
  asm68k             = { glyph = '', hl = 'MiniIconsRed'    },
  asmh8300           = { glyph = '', hl = 'MiniIconsOrange' },
  asn                = { glyph = '',  hl = 'MiniIcons'       },
  aspperl            = { glyph = '', hl = 'MiniIconsBlue'   },
  aspvbs             = { glyph = '',  hl = 'MiniIcons'       },
  asterisk           = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  asteriskvm         = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  astro              = { glyph = '󰓎', hl = 'MiniIconsBlue'   },
  atlas              = { glyph = '',  hl = 'MiniIcons'       },
  autodoc            = { glyph = '󰪶', hl = 'MiniIconsGreen'  },
  autohotkey         = { glyph = '',  hl = 'MiniIcons'       },
  autoit             = { glyph = '',  hl = 'MiniIcons'       },
  automake           = { glyph = '', hl = 'MiniIconsPurple' },
  ave                = { glyph = '',  hl = 'MiniIcons'       },
  avra               = { glyph = '', hl = 'MiniIconsPurple' },
  awk                = { glyph = '', hl = 'MiniIconsGrey'   },
  ayacc              = { glyph = '',  hl = 'MiniIcons'       },
  b                  = { glyph = '',  hl = 'MiniIcons'       },
  baan               = { glyph = '',  hl = 'MiniIcons'       },
  bash               = { glyph = '', hl = 'MiniIconsGreen'  },
  basic              = { glyph = '',  hl = 'MiniIcons'       },
  bc                 = { glyph = '',  hl = 'MiniIcons'       },
  bdf                = { glyph = '󰛖', hl = 'MiniIconsRed'    },
  bib                = { glyph = '󱉟', hl = 'MiniIconsYellow' },
  bindzone           = { glyph = '',  hl = 'MiniIcons'       },
  bitbake            = { glyph = '',  hl = 'MiniIcons'       },
  blank              = { glyph = '',  hl = 'MiniIcons'       },
  bp                 = { glyph = '',  hl = 'MiniIcons'       },
  bsdl               = { glyph = '',  hl = 'MiniIcons'       },
  bst                = { glyph = '',  hl = 'MiniIcons'       },
  btm                = { glyph = '',  hl = 'MiniIcons'       },
  bzl                = { glyph = '', hl = 'MiniIconsGreen'  },
  bzr                = { glyph = '󰜘', hl = 'MiniIconsRed'    },
  c                  = { glyph = '󰙱', hl = 'MiniIconsBlue'   },
  cabal              = { glyph = '󰲒', hl = 'MiniIconsBlue'   },
  cabalconfig        = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  cabalproject       = { glyph = '',  hl = 'MiniIcons'       },
  calendar           = { glyph = '󰃵', hl = 'MiniIconsRed'    },
  catalog            = { glyph = '',  hl = 'MiniIcons'       },
  cdl                = { glyph = '',  hl = 'MiniIcons'       },
  cdrdaoconf         = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  cdrtoc             = { glyph = '󰠶', hl = 'MiniIconsRed'    },
  cf                 = { glyph = '',  hl = 'MiniIcons'       },
  cfg                = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  cgdbrc             = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  ch                 = { glyph = '',  hl = 'MiniIcons'       },
  chaiscript         = { glyph = '󰶞', hl = 'MiniIconsOrange' },
  change             = { glyph = '󰹳',  hl = 'MiniIconsYellow'},
  changelog          = { glyph = '', hl = 'MiniIconsBlue'   },
  chaskell           = { glyph = '󰲒', hl = 'MiniIconsGreen'  },
  chatito            = { glyph = '',  hl = 'MiniIcons'       },
  checkhealth        = { glyph = '󰓙', hl = 'MiniIconsBlue'   },
  cheetah            = { glyph = '',  hl = 'MiniIcons'       },
  chicken            = { glyph = '',  hl = 'MiniIcons'       },
  chill              = { glyph = '',  hl = 'MiniIcons'       },
  chordpro           = { glyph = '',  hl = 'MiniIcons'       },
  chuck              = { glyph = '',  hl = 'MiniIcons'       },
  cl                 = { glyph = '',  hl = 'MiniIcons'       },
  clean              = { glyph = '',  hl = 'MiniIcons'       },
  clipper            = { glyph = '',  hl = 'MiniIcons'       },
  clojure            = { glyph = '', hl = 'MiniIconsGreen'  },
  cmake              = { glyph = '', hl = 'MiniIconsYellow' },
  cmakecache         = { glyph = '', hl = 'MiniIconsRed'    },
  cmod               = { glyph = '',  hl = 'MiniIcons'       },
  cmusrc             = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  cobol              = { glyph = '⚙', hl = 'MiniIconsBlue'   },
  coco               = { glyph = '',  hl = 'MiniIcons'       },
  conaryrecipe       = { glyph = '',  hl = 'MiniIcons'       },
  conf               = { glyph = '󰒓', hl = 'MiniIconsGrey'   },
  config             = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  confini            = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  context            = { glyph = '', hl = 'MiniIconsGreen'  },
  corn               = { glyph = '󰞸', hl = 'MiniIconsYellow' },
  cpp                = { glyph = '󰙲', hl = 'MiniIconsAzure'  },
  crm                = { glyph = '',  hl = 'MiniIcons'       },
  crontab            = { glyph = '󰔠', hl = 'MiniIconsAzure'  },
  cs                 = { glyph = '󰌛', hl = 'MiniIconsGreen'  },
  csc                = { glyph = '',  hl = 'MiniIcons'       },
  csdl               = { glyph = '',  hl = 'MiniIcons'       },
  csh                = { glyph = '', hl = 'MiniIconsGrey'   },
  csp                = { glyph = '',  hl = 'MiniIcons'       },
  css                = { glyph = '󰌜', hl = 'MiniIconsAzure'  },
  csv                = { glyph = '', hl = 'MiniIconsGreen'  },
  csv_pipe           = { glyph = '', hl = 'MiniIconsAzure'  },
  csv_semicolon      = { glyph = '', hl = 'MiniIconsRed'    },
  csv_whitespace     = { glyph = '', hl = 'MiniIconsPurple' },
  cterm              = { glyph = '',  hl = 'MiniIcons'       },
  ctrlh              = { glyph = '',  hl = 'MiniIcons'       },
  cucumber           = { glyph = '',  hl = 'MiniIcons'       },
  cuda               = { glyph = '', hl = 'MiniIconsGreen'  },
  cupl               = { glyph = '',  hl = 'MiniIcons'       },
  cuplsim            = { glyph = '',  hl = 'MiniIcons'       },
  cvs                = { glyph = '󰜘', hl = 'MiniIconsGreen'  },
  cvsrc              = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  cweb               = { glyph = '',  hl = 'MiniIcons'       },
  cynlib             = { glyph = '󰙲', hl = 'MiniIconsPurple' },
  cynpp              = { glyph = '󰙲', hl = 'MiniIconsYellow' },
  d                  = { glyph = '', hl = 'MiniIconsGreen'  },
  dart               = { glyph = '', hl = 'MiniIconsBlue'   },
  datascript         = { glyph = '',  hl = 'MiniIcons'       },
  dcd                = { glyph = '',  hl = 'MiniIcons'       },
  dcl                = { glyph = '',  hl = 'MiniIcons'       },
  deb822sources      = { glyph = '',  hl = 'MiniIcons'       },
  debchangelog       = { glyph = '', hl = 'MiniIconsBlue'   },
  debcontrol         = { glyph = '',  hl = 'MiniIcons'       },
  debcopyright       = { glyph = '', hl = 'MiniIconsRed'    },
  debsources         = { glyph = '',  hl = 'MiniIcons'       },
  def                = { glyph = '',  hl = 'MiniIcons'       },
  denyhosts          = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  dep3patch          = { glyph = '',  hl = 'MiniIcons'       },
  desc               = { glyph = '',  hl = 'MiniIcons'       },
  desktop            = { glyph = '', hl = 'MiniIconsPurple' },
  dictconf           = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  dictdconf          = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  diff               = { glyph = '󰦓', hl = 'MiniIconsAzure'  },
  dircolors          = { glyph = '',  hl = 'MiniIcons'       },
  dirpager           = { glyph = '󰙅', hl = 'MiniIconsYellow' },
  diva               = { glyph = '',  hl = 'MiniIcons'       },
  django             = { glyph = '', hl = 'MiniIconsGreen'  },
  dns                = { glyph = '',  hl = 'MiniIcons'       },
  dnsmasq            = { glyph = '',  hl = 'MiniIcons'       },
  docbk              = { glyph = '',  hl = 'MiniIcons'       },
  docbksgml          = { glyph = '',  hl = 'MiniIcons'       },
  docbkxml           = { glyph = '',  hl = 'MiniIcons'       },
  dockerfile         = { glyph = '󰡨', hl = 'MiniIconsBlue'   },
  dosbatch           = { glyph = '󰒓', hl = 'MiniIconsGreen'  },
  dosini             = { glyph = '󰒓', hl = 'MiniIconsGrey'   },
  dot                = { glyph = '󱁉', hl = 'MiniIconsAzure'  },
  doxygen            = { glyph = '󰋘', hl = 'MiniIconsBlue'   },
  dracula            = { glyph = '󰭟', hl = 'MiniIconsGrey'   },
  dsl                = { glyph = '',  hl = 'MiniIcons'       },
  dtd                = { glyph = '',  hl = 'MiniIcons'       },
  dtml               = { glyph = '',  hl = 'MiniIcons'       },
  dtrace             = { glyph = '',  hl = 'MiniIcons'       },
  dts                = { glyph = '',  hl = 'MiniIcons'       },
  dune               = { glyph = '', hl = 'MiniIconsGreen'  },
  dylan              = { glyph = '',  hl = 'MiniIcons'       },
  dylanintr          = { glyph = '',  hl = 'MiniIcons'       },
  dylanlid           = { glyph = '',  hl = 'MiniIcons'       },
  ecd                = { glyph = '',  hl = 'MiniIcons'       },
  edif               = { glyph = '',  hl = 'MiniIcons'       },
  editorconfig       = { glyph = '', hl = 'MiniIconsGrey'   },
  eiffel             = { glyph = '󱕫', hl = 'MiniIconsYellow' },
  elf                = { glyph = '',  hl = 'MiniIcons'       },
  elinks             = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  elixir             = { glyph = '', hl = 'MiniIconsPurple' },
  elm                = { glyph = '', hl = 'MiniIconsAzure'  },
  elmfilt            = { glyph = '',  hl = 'MiniIcons'       },
  erlang             = { glyph = '', hl = 'MiniIconsRed'    },
  eruby              = { glyph = '', hl = 'MiniIconsRed'    },
  esmtprc            = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  esqlc              = { glyph = '󰆼', hl = 'MiniIconsGrey'   },
  esterel            = { glyph = '',  hl = 'MiniIcons'       },
  eterm              = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  euphoria3          = { glyph = '',  hl = 'MiniIcons'       },
  euphoria4          = { glyph = '',  hl = 'MiniIcons'       },
  eviews             = { glyph = '',  hl = 'MiniIcons'       },
  exim               = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  expect             = { glyph = '',  hl = 'MiniIcons'       },
  exports            = { glyph = '󰈇', hl = 'MiniIconsPurple' },
  falcon             = { glyph = '󱗆', hl = 'MiniIconsOrange' },
  fan                = { glyph = '',  hl = 'MiniIcons'       },
  fasm               = { glyph = '', hl = 'MiniIconsPurple' },
  fdcc               = { glyph = '',  hl = 'MiniIcons'       },
  fennel             = { glyph = '', hl = 'MiniIconsYellow' },
  fetchmail          = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  fgl                = { glyph = '',  hl = 'MiniIcons'       },
  fish               = { glyph = '', hl = 'MiniIconsGrey'   },
  flexwiki           = { glyph = '󰖬', hl = 'MiniIconsPurple' },
  focexec            = { glyph = '',  hl = 'MiniIcons'       },
  form               = { glyph = '',  hl = 'MiniIcons'       },
  forth              = { glyph = '󰬽', hl = 'MiniIconsRed'    },
  fortran            = { glyph = '󱈚', hl = 'MiniIconsPurple' },
  foxpro             = { glyph = '',  hl = 'MiniIcons'       },
  fpcmake            = { glyph = '', hl = 'MiniIconsRed'    },
  framescript        = { glyph = '',  hl = 'MiniIcons'       },
  freebasic          = { glyph = '',  hl = 'MiniIcons'       },
  fsharp             = { glyph = '', hl = 'MiniIconsBlue'   },
  fstab              = { glyph = '󰋊', hl = 'MiniIconsGrey'   },
  fvwm               = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  fvwm2m4            = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  gdb                = { glyph = '',  hl = 'MiniIcons'       },
  gdmo               = { glyph = '',  hl = 'MiniIcons'       },
  gdresource         = { glyph = '', hl = 'MiniIconsGreen'  },
  gdscript           = { glyph = '', hl = 'MiniIconsYellow' },
  gdshader           = { glyph = '', hl = 'MiniIconsPurple' },
  gedcom             = { glyph = '',  hl = 'MiniIcons'       },
  gemtext            = { glyph = '󰪁', hl = 'MiniIconsAzure'  },
  gift               = { glyph = '󰹄', hl = 'MiniIconsRed'    },
  git                = { glyph = '', hl = 'MiniIconsOrange' },
  gitattributes      = { glyph = '', hl = 'MiniIconsYellow' },
  gitcommit          = { glyph = '', hl = 'MiniIconsGreen'  },
  gitconfig          = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  gitignore          = { glyph = '', hl = 'MiniIconsPurple' },
  gitolite           = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  gitrebase          = { glyph = '', hl = 'MiniIconsAzure'  },
  gitsendemail       = { glyph = '', hl = 'MiniIconsBlue'   },
  gkrellmrc          = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  gnash              = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  gnuplot            = { glyph = '󰺒', hl = 'MiniIconsPurple' },
  go                 = { glyph = '󰟓', hl = 'MiniIconsAzure'  },
  godoc              = { glyph = '󰟓', hl = 'MiniIconsOrange' },
  gp                 = { glyph = '',  hl = 'MiniIcons'       },
  gpg                = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  gprof              = { glyph = '',  hl = 'MiniIcons'       },
  grads              = { glyph = '',  hl = 'MiniIcons'       },
  graphql            = { glyph = '󰡷', hl = 'MiniIconsRed'    },
  gretl              = { glyph = '',  hl = 'MiniIcons'       },
  groff              = { glyph = '',  hl = 'MiniIcons'       },
  groovy             = { glyph = '', hl = 'MiniIconsAzure'  },
  group              = { glyph = '',  hl = 'MiniIcons'       },
  grub               = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  gsp                = { glyph = '',  hl = 'MiniIcons'       },
  gtkrc              = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  gvpr               = { glyph = '',  hl = 'MiniIcons'       },
  gyp                = { glyph = '',  hl = 'MiniIcons'       },
  haml               = { glyph = '', hl = 'MiniIconsGrey'   },
  hamster            = { glyph = '',  hl = 'MiniIcons'       },
  hare               = { glyph = '',  hl = 'MiniIcons'       },
  haredoc            = { glyph = '',  hl = 'MiniIcons'       },
  haskell            = { glyph = '󰲒', hl = 'MiniIconsPurple' },
  haste              = { glyph = '',  hl = 'MiniIcons'       },
  hastepreproc       = { glyph = '',  hl = 'MiniIcons'       },
  hb                 = { glyph = '',  hl = 'MiniIcons'       },
  heex               = { glyph = '', hl = 'MiniIconsPurple' },
  help               = { glyph = '󰋖', hl = 'MiniIconsPurple' },
  hercules           = { glyph = '',  hl = 'MiniIcons'       },
  hex                = { glyph = '', hl = 'MiniIconsBlue'   },
  hgcommit           = { glyph = '',  hl = 'MiniIcons'       },
  hlsplaylist        = { glyph = '',  hl = 'MiniIcons'       },
  hog                = { glyph = '',  hl = 'MiniIcons'       },
  hollywood          = { glyph = '',  hl = 'MiniIcons'       },
  hostconf           = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  hostsaccess        = { glyph = '',  hl = 'MiniIcons'       },
  html               = { glyph = '󰌝', hl = 'MiniIconsOrange' },
  htmlcheetah        = { glyph = '󰌝', hl = 'MiniIconsOrange' },
  htmldjango         = { glyph = '󰌝', hl = 'MiniIconsGreen'  },
  htmlm4             = { glyph = '󰌝', hl = 'MiniIconsRed'    },
  htmlos             = { glyph = '󰌝', hl = 'MiniIconsOrange' },
  hurl               = { glyph = '',  hl = 'MiniIcons'       },
  hyprlang           = { glyph = '', hl = 'MiniIconsCyan'   },
  i3config           = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  ia64               = { glyph = '',  hl = 'MiniIcons'       },
  ibasic             = { glyph = '',  hl = 'MiniIcons'       },
  icemenu            = { glyph = '',  hl = 'MiniIcons'       },
  icon               = { glyph = '',  hl = 'MiniIcons'       },
  idl                = { glyph = '',  hl = 'MiniIcons'       },
  idlang             = { glyph = '', hl = 'MiniIconsYellow' },
  indent             = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  inform             = { glyph = '',  hl = 'MiniIcons'       },
  initex             = { glyph = '', hl = 'MiniIconsGreen'  },
  initng             = { glyph = '',  hl = 'MiniIcons'       },
  inittab            = { glyph = '',  hl = 'MiniIcons'       },
  ipfilter           = { glyph = '',  hl = 'MiniIcons'       },
  ishd               = { glyph = '',  hl = 'MiniIcons'       },
  iss                = { glyph = '',  hl = 'MiniIcons'       },
  ist                = { glyph = '',  hl = 'MiniIcons'       },
  j                  = { glyph = '',  hl = 'MiniIcons'       },
  jal                = { glyph = '',  hl = 'MiniIcons'       },
  jam                = { glyph = '',  hl = 'MiniIcons'       },
  jargon             = { glyph = '',  hl = 'MiniIcons'       },
  java               = { glyph = '󰬷', hl = 'MiniIconsOrange' },
  javacc             = { glyph = '󰬷', hl = 'MiniIconsRed'    },
  javascript         = { glyph = '󰌞', hl = 'MiniIconsYellow' },
  javascriptreact    = { glyph = '', hl = 'MiniIconsAzure'  },
  jess               = { glyph = '',  hl = 'MiniIcons'       },
  jgraph             = { glyph = '',  hl = 'MiniIcons'       },
  jj                 = { glyph = '',  hl = 'MiniIcons'       },
  jovial             = { glyph = '',  hl = 'MiniIcons'       },
  jproperties        = { glyph = '',  hl = 'MiniIcons'       },
  jq                 = { glyph = '󰘦', hl = 'MiniIconsBlue'   },
  json               = { glyph = '󰘦', hl = 'MiniIconsYellow' },
  json5              = { glyph = '󰘦', hl = 'MiniIconsOrange' },
  jsonc              = { glyph = '󰘦', hl = 'MiniIconsYellow' },
  jsonnet            = { glyph = '',  hl = 'MiniIcons'       },
  jsp                = { glyph = '',  hl = 'MiniIcons'       },
  julia              = { glyph = '', hl = 'MiniIconsPurple' },
  kconfig            = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  kivy               = { glyph = '',  hl = 'MiniIcons'       },
  kix                = { glyph = '',  hl = 'MiniIcons'       },
  kotlin             = { glyph = '󱈙', hl = 'MiniIconsBlue'   },
  krl                = { glyph = '',  hl = 'MiniIcons'       },
  kscript            = { glyph = '',  hl = 'MiniIcons'       },
  kwt                = { glyph = '',  hl = 'MiniIcons'       },
  lace               = { glyph = '',  hl = 'MiniIcons'       },
  latte              = { glyph = '',  hl = 'MiniIcons'       },
  lc                 = { glyph = '',  hl = 'MiniIcons'       },
  ld                 = { glyph = '',  hl = 'MiniIcons'       },
  ldapconf           = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  ldif               = { glyph = '',  hl = 'MiniIcons'       },
  less               = { glyph = '', hl = 'MiniIconsPurple' },
  lex                = { glyph = '',  hl = 'MiniIcons'       },
  lftp               = { glyph = '',  hl = 'MiniIcons'       },
  lhaskell           = { glyph = '', hl = 'MiniIconsPurple' },
  libao              = { glyph = '',  hl = 'MiniIcons'       },
  lifelines          = { glyph = '',  hl = 'MiniIcons'       },
  lilo               = { glyph = '',  hl = 'MiniIcons'       },
  limits             = { glyph = '',  hl = 'MiniIcons'       },
  liquid             = { glyph = '', hl = 'MiniIconsGreen'  },
  lisp               = { glyph = '', hl = 'MiniIconsGrey'   },
  lite               = { glyph = '',  hl = 'MiniIcons'       },
  litestep           = { glyph = '',  hl = 'MiniIcons'       },
  livebook           = { glyph = '',  hl = 'MiniIcons'       },
  logcheck           = { glyph = '', hl = 'MiniIconsBlue'   },
  loginaccess        = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  logindefs          = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  logtalk            = { glyph = '',  hl = 'MiniIcons'       },
  lotos              = { glyph = '',  hl = 'MiniIcons'       },
  lout               = { glyph = '',  hl = 'MiniIcons'       },
  lpc                = { glyph = '',  hl = 'MiniIcons'       },
  lprolog            = { glyph = 'λ', hl = 'MiniIconsOrange' },
  lscript            = { glyph = '',  hl = 'MiniIcons'       },
  lsl                = { glyph = '',  hl = 'MiniIcons'       },
  lsp_markdown       = { glyph = '󰍔', hl = 'MiniIconsGrey'   },
  lss                = { glyph = '',  hl = 'MiniIcons'       },
  lua                = { glyph = '󰢱', hl = 'MiniIconsAzure'  },
  luau               = { glyph = '',  hl = 'MiniIcons'       },
  lynx               = { glyph = '',  hl = 'MiniIcons'       },
  lyrics             = { glyph = '',  hl = 'MiniIcons'       },
  m3build            = { glyph = '',  hl = 'MiniIcons'       },
  m3quake            = { glyph = '',  hl = 'MiniIcons'       },
  m4                 = { glyph = '',  hl = 'MiniIcons'       },
  mail               = { glyph = '', hl = 'MiniIconsRed'    },
  mailaliases        = { glyph = '', hl = 'MiniIconsRed'    },
  mailcap            = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  make               = { glyph = '', hl = 'MiniIconsGrey'   },
  mallard            = { glyph = '',  hl = 'MiniIcons'       },
  man                = { glyph = '󰗚', hl = 'MiniIconsYellow' },
  manconf            = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  manual             = { glyph = '󰗚', hl = 'MiniIconsYellow' },
  maple              = { glyph = '󰲓', hl = 'MiniIconsRed'    },
  markdown           = { glyph = '󰍔', hl = 'MiniIconsGrey'   },
  masm               = { glyph = '', hl = 'MiniIconsPurple' },
  mason              = { glyph = '',  hl = 'MiniIcons'       },
  master             = { glyph = '',  hl = 'MiniIcons'       },
  matlab             = { glyph = '󰿈', hl = 'MiniIconsOrange' },
  maxima             = { glyph = '',  hl = 'MiniIcons'       },
  mel                = { glyph = '',  hl = 'MiniIcons'       },
  mermaid            = { glyph = '',  hl = 'MiniIcons'       },
  meson              = { glyph = '',  hl = 'MiniIcons'       },
  messages           = { glyph = '',  hl = 'MiniIcons'       },
  mf                 = { glyph = '',  hl = 'MiniIcons'       },
  mgl                = { glyph = '',  hl = 'MiniIcons'       },
  mgp                = { glyph = '',  hl = 'MiniIcons'       },
  mib                = { glyph = '',  hl = 'MiniIcons'       },
  mix                = { glyph = '',  hl = 'MiniIcons'       },
  mma                = { glyph = '',  hl = 'MiniIcons'       },
  mmix               = { glyph = '',  hl = 'MiniIcons'       },
  mmp                = { glyph = '',  hl = 'MiniIcons'       },
  modconf            = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  model              = { glyph = '',  hl = 'MiniIcons'       },
  modsim3            = { glyph = '',  hl = 'MiniIcons'       },
  modula2            = { glyph = '',  hl = 'MiniIcons'       },
  modula3            = { glyph = '',  hl = 'MiniIcons'       },
  mojo               = { glyph = '󰈸', hl = 'MiniIconsRed'    },
  monk               = { glyph = '',  hl = 'MiniIcons'       },
  moo                = { glyph = '',  hl = 'MiniIcons'       },
  mp                 = { glyph = '',  hl = 'MiniIcons'       },
  mplayerconf        = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  mrxvtrc            = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  msidl              = { glyph = '',  hl = 'MiniIcons'       },
  msmessages         = { glyph = '',  hl = 'MiniIcons'       },
  msql               = { glyph = '󰆼', hl = 'MiniIconsGrey'   },
  mupad              = { glyph = '',  hl = 'MiniIcons'       },
  murphi             = { glyph = '',  hl = 'MiniIcons'       },
  mush               = { glyph = '',  hl = 'MiniIcons'       },
  muttrc             = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  mysql              = { glyph = '󰆼', hl = 'MiniIconsOrange' },
  n1ql               = { glyph = '',  hl = 'MiniIcons'       },
  named              = { glyph = '',  hl = 'MiniIcons'       },
  nanorc             = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  nasm               = { glyph = '', hl = 'MiniIconsPurple' },
  nastran            = { glyph = '',  hl = 'MiniIcons'       },
  natural            = { glyph = '',  hl = 'MiniIcons'       },
  ncf                = { glyph = '',  hl = 'MiniIcons'       },
  neomuttrc          = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  netrc              = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  netrw              = { glyph = '󰙅', hl = 'MiniIconsBlue'   },
  nginx              = { glyph = '󰰓', hl = 'MiniIconsGreen'  },
  nim                = { glyph = '', hl = 'MiniIconsYellow' },
  ninja              = { glyph = '', hl = 'MiniIconsGrey'   },
  nix                = { glyph = '', hl = 'MiniIconsAzure'  },
  nqc                = { glyph = '',  hl = 'MiniIcons'       },
  nroff              = { glyph = '',  hl = 'MiniIcons'       },
  nsis               = { glyph = '',  hl = 'MiniIcons'       },
  obj                = { glyph = '󰆧', hl = 'MiniIconsGrey'   },
  objc               = { glyph = '', hl = 'MiniIconsOrange' },
  objcpp             = { glyph = '', hl = 'MiniIconsOrange' },
  objdump            = { glyph = '',  hl = 'MiniIcons'       },
  obse               = { glyph = '',  hl = 'MiniIcons'       },
  ocaml              = { glyph = '', hl = 'MiniIconsOrange' },
  occam              = { glyph = '',  hl = 'MiniIcons'       },
  octave             = { glyph = '󱥸', hl = 'MiniIconsBlue'   },
  odin               = { glyph = '󰮔', hl = 'MiniIconsBlue'   },
  omnimark           = { glyph = '',  hl = 'MiniIcons'       },
  ondir              = { glyph = '',  hl = 'MiniIcons'       },
  opam               = { glyph = '',  hl = 'MiniIcons'       },
  openroad           = { glyph = '',  hl = 'MiniIcons'       },
  openscad           = { glyph = '', hl = 'MiniIconsYellow' },
  openvpn            = { glyph = '󰖂', hl = 'MiniIconsPurple' },
  opl                = { glyph = '',  hl = 'MiniIcons'       },
  ora                = { glyph = '',  hl = 'MiniIcons'       },
  pacmanlog          = { glyph = '', hl = 'MiniIconsBlue'   },
  pamconf            = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  pamenv             = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  pandoc             = { glyph = '󰍔', hl = 'MiniIconsYellow' },
  papp               = { glyph = '', hl = 'MiniIconsAzure'  },
  pascal             = { glyph = '󱤊', hl = 'MiniIconsRed'    },
  passwd             = { glyph = '', hl = 'MiniIconsGrey'   },
  pbtxt              = { glyph = '', hl = 'MiniIconsAzure'  },
  pcap               = { glyph = '󰐪', hl = 'MiniIconsRed'    },
  pccts              = { glyph = '',  hl = 'MiniIcons'       },
  pdf                = { glyph = '', hl = 'MiniIconsRed'    },
  perl               = { glyph = '', hl = 'MiniIconsAzure'  },
  pf                 = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  pfmain             = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  php                = { glyph = '󰌟', hl = 'MiniIconsPurple' },
  phtml              = { glyph = '󰌟', hl = 'MiniIconsOrange' },
  pic                = { glyph = '', hl = 'MiniIconsPurple' },
  pike               = { glyph = '',  hl = 'MiniIcons'       },
  pilrc              = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  pine               = { glyph = '󰇮', hl = 'MiniIconsRed'    },
  pinfo              = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  plaintex           = { glyph = '', hl = 'MiniIconsGreen'  },
  pli                = { glyph = '',  hl = 'MiniIcons'       },
  plm                = { glyph = '',  hl = 'MiniIcons'       },
  plp                = { glyph = '', hl = 'MiniIconsBlue'   },
  plsql              = { glyph = '󰆼', hl = 'MiniIconsOrange' },
  po                 = { glyph = '', hl = 'MiniIconsAzure'  },
  pod                = { glyph = '', hl = 'MiniIconsPurple' },
  poefilter          = { glyph = '',  hl = 'MiniIcons'       },
  poke               = { glyph = '',  hl = 'MiniIcons'       },
  postscr            = { glyph = '', hl = 'MiniIconsYellow' },
  pov                = { glyph = '',  hl = 'MiniIcons'       },
  povini             = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  ppd                = { glyph = '',  hl = 'MiniIcons'       },
  ppwiz              = { glyph = '',  hl = 'MiniIcons'       },
  prescribe          = { glyph = '',  hl = 'MiniIcons'       },
  prisma             = { glyph = '', hl = 'MiniIconsBlue'   },
  privoxy            = { glyph = '',  hl = 'MiniIcons'       },
  procmail           = { glyph = '',  hl = 'MiniIcons'       },
  progress           = { glyph = '',  hl = 'MiniIcons'       },
  prolog             = { glyph = '', hl = 'MiniIconsYellow' },
  promela            = { glyph = '',  hl = 'MiniIcons'       },
  proto              = { glyph = '',  hl = 'MiniIcons'       },
  protocols          = { glyph = '',  hl = 'MiniIcons'       },
  ps1                = { glyph = '󰨊', hl = 'MiniIconsBlue'   },
  ps1xml             = { glyph = '󰨊', hl = 'MiniIconsBlue'   },
  psf                = { glyph = '',  hl = 'MiniIcons'       },
  psl                = { glyph = '',  hl = 'MiniIcons'       },
  ptcap              = { glyph = '󰐪', hl = 'MiniIconsRed'    },
  purescript         = { glyph = '', hl = 'MiniIconsGrey'   },
  purifylog          = { glyph = '', hl = 'MiniIconsBlue'   },
  pymanifest         = { glyph = '',  hl = 'MiniIcons'       },
  pyrex              = { glyph = '',  hl = 'MiniIcons'       },
  python             = { glyph = '󰌠', hl = 'MiniIconsYellow' },
  python2            = { glyph = '', hl = 'MiniIconsYellow' },
  qb64               = { glyph = '',  hl = 'MiniIcons'       },
  qf                 = { glyph = '󰝖', hl = 'MiniIconsAzure'  },
  qml                = { glyph = '',  hl = 'MiniIcons'       },
  quake              = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  quarto             = { glyph = '󰐗', hl = 'MiniIconsAzure'  },
  query              = { glyph = '', hl = 'MiniIconsGreen'  },
  r                  = { glyph = '󰟔', hl = 'MiniIconsBlue'   },
  racc               = { glyph = '',  hl = 'MiniIcons'       },
  racket             = { glyph = '',  hl = 'MiniIcons'       },
  radiance           = { glyph = '',  hl = 'MiniIcons'       },
  raku               = { glyph = '', hl = 'MiniIconsRed'    },
  raml               = { glyph = '',  hl = 'MiniIcons'       },
  rapid              = { glyph = '',  hl = 'MiniIcons'       },
  rasi               = { glyph = '',  hl = 'MiniIcons'       },
  ratpoison          = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  rc                 = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  rcs                = { glyph = '',  hl = 'MiniIcons'       },
  rcslog             = { glyph = '', hl = 'MiniIconsBlue'   },
  readline           = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  rebol              = { glyph = '',  hl = 'MiniIcons'       },
  redif              = { glyph = '',  hl = 'MiniIcons'       },
  registry           = { glyph = '', hl = 'MiniIconsRed'    },
  rego               = { glyph = '',  hl = 'MiniIcons'       },
  remind             = { glyph = '',  hl = 'MiniIcons'       },
  requirements       = { glyph = '󱘎', hl = 'MiniIconsPurple' },
  rescript           = { glyph = '',  hl = 'MiniIcons'       },
  resolv             = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  reva               = { glyph = '',  hl = 'MiniIcons'       },
  rexx               = { glyph = '',  hl = 'MiniIcons'       },
  rfc_csv            = { glyph = '', hl = 'MiniIconsOrange' },
  rfc_semicolon      = { glyph = '', hl = 'MiniIconsRed'    },
  rhelp              = { glyph = '󰟔', hl = 'MiniIconsAzure'  },
  rib                = { glyph = '',  hl = 'MiniIcons'       },
  rmarkdown          = { glyph = '󰍔', hl = 'MiniIconsAzure'  },
  rmd                = { glyph = '󰍔', hl = 'MiniIconsAzure'  },
  rnc                = { glyph = '',  hl = 'MiniIcons'       },
  rng                = { glyph = '',  hl = 'MiniIcons'       },
  rnoweb             = { glyph = '󰟔', hl = 'MiniIconsGreen'  },
  robots             = { glyph = '󰚩', hl = 'MiniIconsGrey'   },
  roc                = { glyph = '',  hl = 'MiniIcons'       },
  routeros           = { glyph = '',  hl = 'MiniIcons'       },
  rpcgen             = { glyph = '',  hl = 'MiniIcons'       },
  rpl                = { glyph = '',  hl = 'MiniIcons'       },
  rrst               = { glyph = '',  hl = 'MiniIcons'       },
  rst                = { glyph = '󰊄', hl = 'MiniIconsYellow' },
  rtf                = { glyph = '󰚞', hl = 'MiniIconsAzure'  },
  ruby               = { glyph = '󰴭', hl = 'MiniIconsRed'    },
  rust               = { glyph = '󱘗', hl = 'MiniIconsOrange' },
  samba              = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  sas                = { glyph = '',  hl = 'MiniIcons'       },
  sass               = { glyph = '󰟬', hl = 'MiniIconsRed'    },
  sather             = { glyph = '',  hl = 'MiniIcons'       },
  sbt                = { glyph = '', hl = 'MiniIconsOrange' },
  scala              = { glyph = '', hl = 'MiniIconsRed'    },
  scdoc              = { glyph = '󱔘', hl = 'MiniIconsYellow' },
  scheme             = { glyph = '󰘧', hl = 'MiniIconsGrey'   },
  scilab             = { glyph = '󰂓', hl = 'MiniIconsYellow' },
  screen             = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  scss               = { glyph = '', hl = 'MiniIconsRed'    },
  sd                 = { glyph = '',  hl = 'MiniIcons'       },
  sdc                = { glyph = '',  hl = 'MiniIcons'       },
  sdl                = { glyph = '',  hl = 'MiniIcons'       },
  sed                = { glyph = '󰟥', hl = 'MiniIconsRed'    },
  sendpr             = { glyph = '󰆨', hl = 'MiniIconsBlue'   },
  sensors            = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  services           = { glyph = '',  hl = 'MiniIcons'       },
  setserial          = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  sexplib            = { glyph = '', hl = 'MiniIconsYellow' },
  sgml               = { glyph = '',  hl = 'MiniIcons'       },
  sgmldecl           = { glyph = '',  hl = 'MiniIcons'       },
  sgmllnx            = { glyph = '',  hl = 'MiniIcons'       },
  sh                 = { glyph = '', hl = 'MiniIconsGrey'   },
  shada              = { glyph = '󰆼', hl = 'MiniIconsGrey'   },
  sicad              = { glyph = '',  hl = 'MiniIcons'       },
  sieve              = { glyph = '',  hl = 'MiniIcons'       },
  sil                = { glyph = '󰛥', hl = 'MiniIconsOrange' },
  simula             = { glyph = '',  hl = 'MiniIcons'       },
  sinda              = { glyph = '',  hl = 'MiniIcons'       },
  sindacmp           = { glyph = '',  hl = 'MiniIcons'       },
  sindaout           = { glyph = '',  hl = 'MiniIcons'       },
  sisu               = { glyph = '',  hl = 'MiniIcons'       },
  skill              = { glyph = '',  hl = 'MiniIcons'       },
  sl                 = { glyph = '',  hl = 'MiniIcons'       },
  slang              = { glyph = '',  hl = 'MiniIcons'       },
  slice              = { glyph = '',  hl = 'MiniIcons'       },
  slint              = { glyph = '',  hl = 'MiniIcons'       },
  slpconf            = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  slpreg             = { glyph = '',  hl = 'MiniIcons'       },
  slpspi             = { glyph = '',  hl = 'MiniIcons'       },
  slrnrc             = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  slrnsc             = { glyph = '',  hl = 'MiniIcons'       },
  sm                 = { glyph = '󱃜', hl = 'MiniIconsBlue'   },
  smarty             = { glyph = '',  hl = 'MiniIcons'       },
  smcl               = { glyph = '',  hl = 'MiniIcons'       },
  smil               = { glyph = '',  hl = 'MiniIcons'       },
  smith              = { glyph = '',  hl = 'MiniIcons'       },
  sml                = { glyph = 'λ', hl = 'MiniIconsOrange' },
  snnsnet            = { glyph = '',  hl = 'MiniIcons'       },
  snnspat            = { glyph = '',  hl = 'MiniIcons'       },
  snnsres            = { glyph = '',  hl = 'MiniIcons'       },
  snobol4            = { glyph = '',  hl = 'MiniIcons'       },
  solidity           = { glyph = '', hl = 'MiniIconsAzure'  },
  solution           = { glyph = '󰘐', hl = 'MiniIconsBlue'   },
  spec               = { glyph = '',  hl = 'MiniIcons'       },
  specman            = { glyph = '',  hl = 'MiniIcons'       },
  spice              = { glyph = '',  hl = 'MiniIcons'       },
  splint             = { glyph = '',  hl = 'MiniIcons'       },
  spup               = { glyph = '',  hl = 'MiniIcons'       },
  spyce              = { glyph = '',  hl = 'MiniIcons'       },
  sql                = { glyph = '󰆼', hl = 'MiniIconsGrey'   },
  sqlanywhere        = { glyph = '󰆼', hl = 'MiniIconsGrey'   },
  sqlforms           = { glyph = '󰆼', hl = 'MiniIconsOrange' },
  sqlhana            = { glyph = '󰆼', hl = 'MiniIconsGrey'   },
  sqlinformix        = { glyph = '󰆼', hl = 'MiniIconsGrey'   },
  sqlj               = { glyph = '󰆼', hl = 'MiniIconsGrey'   },
  sqloracle          = { glyph = '󰆼', hl = 'MiniIconsOrange' },
  sqr                = { glyph = '',  hl = 'MiniIcons'       },
  squid              = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  squirrel           = { glyph = '',  hl = 'MiniIcons'       },
  srec               = { glyph = '',  hl = 'MiniIcons'       },
  srt                = { glyph = '󰨖', hl = 'MiniIconsYellow' },
  ssa                = { glyph = '󰨖', hl = 'MiniIconsYellow' },
  sshconfig          = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  sshdconfig         = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  st                 = { glyph = '',  hl = 'MiniIcons'       },
  stata              = { glyph = '',  hl = 'MiniIcons'       },
  stp                = { glyph = '',  hl = 'MiniIcons'       },
  strace             = { glyph = '',  hl = 'MiniIcons'       },
  structurizr        = { glyph = '',  hl = 'MiniIcons'       },
  stylus             = { glyph = '',  hl = 'MiniIcons'       },
  sudoers            = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  svg                = { glyph = '󰜡', hl = 'MiniIconsYellow' },
  svn                = { glyph = '',  hl = 'MiniIcons'       },
  swayconfig         = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  swift              = { glyph = '󰛥', hl = 'MiniIconsOrange' },
  swiftgyb           = { glyph = '󰛥', hl = 'MiniIconsYellow' },
  swig               = { glyph = '',  hl = 'MiniIcons'       },
  sysctl             = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  systemd            = { glyph = '',  hl = 'MiniIcons'       },
  systemverilog      = { glyph = '󰍛', hl = 'MiniIconsGreen'  },
  tads               = { glyph = '', hl = 'MiniIconsAzure'  },
  tags               = { glyph = '󰓻', hl = 'MiniIconsGreen'  },
  tak                = { glyph = '',  hl = 'MiniIcons'       },
  takcmp             = { glyph = '',  hl = 'MiniIcons'       },
  takout             = { glyph = '',  hl = 'MiniIcons'       },
  tap                = { glyph = '',  hl = 'MiniIcons'       },
  tar                = { glyph = '',  hl = 'MiniIcons'       },
  taskdata           = { glyph = '',  hl = 'MiniIcons'       },
  taskedit           = { glyph = '',  hl = 'MiniIcons'       },
  tasm               = { glyph = '', hl = 'MiniIconsPurple' },
  tcl                = { glyph = '󰛓', hl = 'MiniIconsBlue'   },
  tcsh               = { glyph = '', hl = 'MiniIconsAzure'  },
  template           = { glyph = '',  hl = 'MiniIcons'       },
  teraterm           = { glyph = '',  hl = 'MiniIcons'       },
  terminfo           = { glyph = '', hl = 'MiniIconsGrey'   },
  tex                = { glyph = '', hl = 'MiniIconsGreen'  },
  texinfo            = { glyph = '', hl = 'MiniIconsGreen'  },
  texmf              = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  text               = { glyph = '', hl = 'MiniIconsAzure'  },
  tf                 = { glyph = '',  hl = 'MiniIcons'       },
  tidy               = { glyph = '󰌝', hl = 'MiniIconsBlue'   },
  tilde              = { glyph = '',  hl = 'MiniIcons'       },
  tli                = { glyph = '',  hl = 'MiniIcons'       },
  tmux               = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  toml               = { glyph = '', hl = 'MiniIconsOrange' },
  tpp                = { glyph = '󰐨', hl = 'MiniIconsPurple' },
  trasys             = { glyph = '',  hl = 'MiniIcons'       },
  treetop            = { glyph = '',  hl = 'MiniIcons'       },
  trustees           = { glyph = '',  hl = 'MiniIcons'       },
  tsalt              = { glyph = '',  hl = 'MiniIcons'       },
  tsscl              = { glyph = '',  hl = 'MiniIcons'       },
  tssgm              = { glyph = '',  hl = 'MiniIcons'       },
  tssop              = { glyph = '',  hl = 'MiniIcons'       },
  tsv                = { glyph = '', hl = 'MiniIconsBlue'   },
  tt2                = { glyph = '', hl = 'MiniIconsAzure'  },
  tt2html            = { glyph = '', hl = 'MiniIconsOrange' },
  tt2js              = { glyph = '', hl = 'MiniIconsYellow' },
  tutor              = { glyph = '󱆀', hl = 'MiniIconsPurple' },
  typescript         = { glyph = '󰛦', hl = 'MiniIconsAzure'  },
  typescriptreact    = { glyph = '', hl = 'MiniIconsBlue'   },
  typst              = { glyph = '󰬛', hl = 'MiniIconsAzure'  },
  uc                 = { glyph = '',  hl = 'MiniIcons'       },
  uci                = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  udevconf           = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  udevperm           = { glyph = '',  hl = 'MiniIcons'       },
  udevrules          = { glyph = '',  hl = 'MiniIcons'       },
  uil                = { glyph = '',  hl = 'MiniIcons'       },
  unison             = { glyph = '',  hl = 'MiniIcons'       },
  updatedb           = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  upstart            = { glyph = '',  hl = 'MiniIcons'       },
  upstreamdat        = { glyph = '',  hl = 'MiniIcons'       },
  upstreaminstalllog = { glyph = '', hl = 'MiniIconsBlue'   },
  upstreamlog        = { glyph = '', hl = 'MiniIconsBlue'   },
  upstreamrpt        = { glyph = '',  hl = 'MiniIcons'       },
  urlshortcut        = { glyph = '󰌷', hl = 'MiniIconsPurple' },
  usd                = { glyph = '',  hl = 'MiniIcons'       },
  usserverlog        = { glyph = '', hl = 'MiniIconsBlue'   },
  usw2kagtlog        = { glyph = '', hl = 'MiniIconsBlue'   },
  v                  = { glyph = '󰬃', hl = 'MiniIconsBlue'   },
  valgrind           = { glyph = '󰍛', hl = 'MiniIconsGrey'   },
  vb                 = { glyph = '󰛤', hl = 'MiniIconsPurple' },
  vdf                = { glyph = '',  hl = 'MiniIcons'       },
  vera               = { glyph = '',  hl = 'MiniIcons'       },
  verilog            = { glyph = '󰍛', hl = 'MiniIconsGreen'  },
  verilogams         = { glyph = '󰍛', hl = 'MiniIconsGreen'  },
  vgrindefs          = { glyph = '',  hl = 'MiniIcons'       },
  vhdl               = { glyph = '󰍛', hl = 'MiniIconsGreen'  },
  vim                = { glyph = '', hl = 'MiniIconsGreen'  },
  viminfo            = { glyph = '', hl = 'MiniIconsBlue'   },
  virata             = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  vmasm              = { glyph = '', hl = 'MiniIconsPurple' },
  voscm              = { glyph = '',  hl = 'MiniIcons'       },
  vrml               = { glyph = '',  hl = 'MiniIcons'       },
  vroom              = { glyph = '', hl = 'MiniIconsOrange' },
  vsejcl             = { glyph = '',  hl = 'MiniIcons'       },
  vue                = { glyph = '󰡄', hl = 'MiniIconsGreen'  },
  wat                = { glyph = '', hl = 'MiniIconsPurple' },
  wdiff              = { glyph = '󰦓', hl = 'MiniIconsBlue'   },
  wdl                = { glyph = '',  hl = 'MiniIcons'       },
  web                = { glyph = '',  hl = 'MiniIcons'       },
  webmacro           = { glyph = '',  hl = 'MiniIcons'       },
  wget               = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  wget2              = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  winbatch           = { glyph = '',  hl = 'MiniIcons'       },
  wml                = { glyph = '',  hl = 'MiniIcons'       },
  wsh                = { glyph = '', hl = 'MiniIconsBlue'   },
  wsml               = { glyph = '',  hl = 'MiniIcons'       },
  wvdial             = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  xbl                = { glyph = '',  hl = 'MiniIcons'       },
  xcompose           = { glyph = '',  hl = 'MiniIcons'       },
  xdefaults          = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  xf86conf           = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  xhtml              = { glyph = '󰌝', hl = 'MiniIconsOrange' },
  xinetd             = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  xkb                = { glyph = '',  hl = 'MiniIcons'       },
  xmath              = { glyph = '',  hl = 'MiniIcons'       },
  xml                = { glyph = '󰗀', hl = 'MiniIconsOrange' },
  xmodmap            = { glyph = '',  hl = 'MiniIcons'       },
  xpm                = { glyph = '',  hl = 'MiniIcons'       },
  xpm2               = { glyph = '',  hl = 'MiniIcons'       },
  xquery             = { glyph = '',  hl = 'MiniIcons'       },
  xs                 = { glyph = '', hl = 'MiniIconsRed'    },
  xsd                = { glyph = '󰗀', hl = 'MiniIconsYellow' },
  xslt               = { glyph = '󰗀', hl = 'MiniIconsGreen'  },
  xxd                = { glyph = '',  hl = 'MiniIcons'       },
  yacc               = { glyph = '',  hl = 'MiniIcons'       },
  yaml               = { glyph = '', hl = 'MiniIconsPurple' },
  z8a                = { glyph = '', hl = 'MiniIconsGrey'   },
  zathurarc          = { glyph = '󰒓', hl = 'MiniIconsCyan'   },
  zig                = { glyph = '', hl = 'MiniIconsOrange' },
  zimbu              = { glyph = '',  hl = 'MiniIcons'       },
  zir                = { glyph = '', hl = 'MiniIconsOrange' },
  zserio             = { glyph = '',  hl = 'MiniIcons'       },
  zsh                = { glyph = '', hl = 'MiniIconsGreen'  },
}

-- Add those in `H.filetype_icons` after it is finished
--stylua: ignore
H.other_filetype_icons = {
  -- 'mini.nvim'
  ['minideps-confirm']   = { glyph = '', hl = 'MiniIconsAzure' },
  minifiles              = { glyph = '', hl = 'MiniIconsGreen' },
  ['minifiles-help']     = { glyph = '', hl = 'MiniIconsGreen' },
  mininotify             = { glyph = '', hl = 'MiniIconsYellow' },
  ['mininotify-history'] = { glyph = '', hl = 'MiniIconsYellow' },
  minipick               = { glyph = '', hl = 'MiniIconsCyan' },
  starter                = { glyph = '', hl = 'MiniIconsAzure' },

  -- Lua plugins
  lazy = { glyph = '󰒲', hl = 'MiniIconsBlue' },
}

-- Extension icons. Keys are mostly for extensions which are either:
-- - Popular (to improve performance).
-- - Don't have good support in `vim.filetype.match()`:
--     - Isn't associated with (text) filetype: docx, gif, etc.
--     - Fails to recognize filetype by filename and content only (like '.ts').
--stylua: ignore
H.extension_icons = {
  -- Popular and associated with filetype (for performance)
  fs   = H.filetype_icons.fsharp,
  lock = { glyph = '󰌾', hl = 'MiniIconsRed'   },
  log  = { glyph = '', hl = 'MiniIconsAzure' },
  r    = H.filetype_icons.r,
  ts   = H.filetype_icons.typescript,

  -- Not associated with filetype (not text file)
}

-- Path icons. Keys are mostly some popular file/directory basenames and the
-- ones which can conflict with icon detection through extension.
--stylua: ignore
H.path_icons = {
  makefile = H.filetype_icons.make,
  license = { glyph = '', hl = 'MiniIconsYellow' },
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
  linux        = { glyph = '', hl = 'MiniIconsGrey'   },
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
H.get_impl = {
  extension = function(name)
    if type(name) ~= 'string' then H.error('Extension name should be string.') end
    -- Also try for somewhat common cases of extension equal to filetype. All
    -- cases breaking this assumptions should be added to `extension_icons`.
    local icon_data = H.extension_icons[name] or H.filetype_icons[name]
    if icon_data ~= nil then return H.finalize_icon(icon_data, name), icon_data.hl end

    -- Fall back to built-in matching
    local ft = vim.filetype.match({ filename = 'aaa.' .. name, contents = { '' } })
    if ft ~= nil then return MiniIcons.get('filetype', ft) end
  end,

  filetype = function(name)
    if type(name) ~= 'string' then H.error('Filetype name should be string.') end
    local icon_data = H.filetype_icons[name]
    if icon_data ~= nil then return H.finalize_icon(icon_data, name), icon_data.hl end
  end,

  path = function(name)
    if type(name) ~= 'string' then H.error('Path should be string.') end
    local basename = vim.fn.fnamemodify(name, ':t'):lower()
    local icon_data = H.path_icons[basename]
    if icon_data ~= nil then return H.finalize_icon(icon_data, name), icon_data.hl end

    -- Try raw extension first for better speed (as `vim.filetype.match()` is
    -- relatively slow to be called many times; like 0.1 ms)
    local ext = (string.match(name, '%.([^%.]+)$') or ''):lower()
    icon_data = H.extension_icons[ext] or H.filetype_icons[ext]
    if icon_data ~= nil then return H.finalize_icon(icon_data, name), icon_data.hl end

    -- Fall back to built-in matching
    local ft = vim.filetype.match({ filename = basename, contents = { '' } })
    if ft ~= nil then return MiniIcons.get('filetype', ft) end
  end,

  os = function(name)
    if type(name) ~= 'string' then H.error('Operating system name should be string.') end
    local icon_data = H.os_icons[name]
    if icon_data ~= nil then return H.finalize_icon(icon_data, name), icon_data.hl end
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

return MiniIcons
