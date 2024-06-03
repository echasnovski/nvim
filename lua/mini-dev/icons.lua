--- TODO:
--- - Code:
---     - Add main table for filetypes.
---
---     - Think about the interface for default icons.
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
-- (i.e. present in `vim.fn.getcompletion('', 'filetype')`).
-- Rough process of how glyphs and icons are chosen:
-- - Try to balance usage of highlight groups.
-- - If it is present in 'nvim-web-devicons', use its glyph with highlight
--   group inferred to have most similar hue (based on OKLCH color space with
--   equally spaced grid as in 'mini.hues' and chroma=3 for grey cutoff; with
--   some manual interventions).
-- - All "config" filetypes have same glyph.

-- Neovim filetype plugins
--stylua: ignore
H.filetype_icons = {
  ['8th']            = { glyph = '',  hl = 'MiniIcons'       },
  a2ps               = { glyph = '',  hl = 'MiniIcons'       },
  a65                = { glyph = '',  hl = 'MiniIcons'       },
  aap                = { glyph = '',  hl = 'MiniIcons'       },
  abap               = { glyph = '',  hl = 'MiniIcons'       },
  abaqus             = { glyph = '',  hl = 'MiniIcons'       },
  abc                = { glyph = '',  hl = 'MiniIcons'       },
  abel               = { glyph = '',  hl = 'MiniIcons'       },
  acedb              = { glyph = '',  hl = 'MiniIcons'       },
  ada                = { glyph = '',  hl = 'MiniIcons'       },
  aflex              = { glyph = '',  hl = 'MiniIcons'       },
  ahdl               = { glyph = '',  hl = 'MiniIcons'       },
  aidl               = { glyph = '',  hl = 'MiniIcons'       },
  alsaconf           = { glyph = '',  hl = 'MiniIcons'       },
  amiga              = { glyph = '',  hl = 'MiniIcons'       },
  aml                = { glyph = '',  hl = 'MiniIcons'       },
  ampl               = { glyph = '',  hl = 'MiniIcons'       },
  ant                = { glyph = '',  hl = 'MiniIcons'       },
  antlr              = { glyph = '',  hl = 'MiniIcons'       },
  apache             = { glyph = '',  hl = 'MiniIcons'       },
  apachestyle        = { glyph = '',  hl = 'MiniIcons'       },
  aptconf            = { glyph = '',  hl = 'MiniIcons'       },
  arch               = { glyph = '',  hl = 'MiniIcons'       },
  arduino            = { glyph = '', hl = 'MiniIconsAzure'  },
  art                = { glyph = '',  hl = 'MiniIcons'       },
  asciidoc           = { glyph = '',  hl = 'MiniIcons'       },
  asm                = { glyph = '',  hl = 'MiniIcons'       },
  asm68k             = { glyph = '',  hl = 'MiniIcons'       },
  asmh8300           = { glyph = '',  hl = 'MiniIcons'       },
  asn                = { glyph = '',  hl = 'MiniIcons'       },
  aspperl            = { glyph = '',  hl = 'MiniIcons'       },
  aspvbs             = { glyph = '',  hl = 'MiniIcons'       },
  asterisk           = { glyph = '',  hl = 'MiniIcons'       },
  asteriskvm         = { glyph = '',  hl = 'MiniIcons'       },
  astro              = { glyph = '',  hl = 'MiniIcons'       },
  atlas              = { glyph = '',  hl = 'MiniIcons'       },
  autodoc            = { glyph = '',  hl = 'MiniIcons'       },
  autohotkey         = { glyph = '',  hl = 'MiniIcons'       },
  autoit             = { glyph = '',  hl = 'MiniIcons'       },
  automake           = { glyph = '',  hl = 'MiniIcons'       },
  ave                = { glyph = '',  hl = 'MiniIcons'       },
  avra               = { glyph = '',  hl = 'MiniIcons'       },
  awk                = { glyph = '', hl = 'MiniIconsGrey'   },
  ayacc              = { glyph = '',  hl = 'MiniIcons'       },
  b                  = { glyph = '',  hl = 'MiniIcons'       },
  baan               = { glyph = '',  hl = 'MiniIcons'       },
  bash               = { glyph = '', hl = 'MiniIconsGreen'  },
  basic              = { glyph = '',  hl = 'MiniIcons'       },
  bc                 = { glyph = '',  hl = 'MiniIcons'       },
  bdf                = { glyph = '',  hl = 'MiniIcons'       },
  beamer             = { glyph = '',  hl = 'MiniIcons'       },
  bib                = { glyph = '󱉟', hl = 'MiniIconsYellow' },
  bindzone           = { glyph = '',  hl = 'MiniIcons'       },
  bitbake            = { glyph = '',  hl = 'MiniIcons'       },
  blank              = { glyph = '',  hl = 'MiniIcons'       },
  bp                 = { glyph = '',  hl = 'MiniIcons'       },
  bsdl               = { glyph = '',  hl = 'MiniIcons'       },
  bst                = { glyph = '',  hl = 'MiniIcons'       },
  btm                = { glyph = '',  hl = 'MiniIcons'       },
  bzl                = { glyph = '', hl = 'MiniIconsGreen'  },
  bzr                = { glyph = '',  hl = 'MiniIcons'       },
  c                  = { glyph = '', hl = 'MiniIconsBlue'   },
  cabal              = { glyph = '',  hl = 'MiniIcons'       },
  cabalconfig        = { glyph = '', hl = 'MiniIconsCyan'   },
  cabalproject       = { glyph = '',  hl = 'MiniIcons'       },
  calendar           = { glyph = '',  hl = 'MiniIcons'       },
  calender           = { glyph = '',  hl = 'MiniIcons'       },
  catalog            = { glyph = '',  hl = 'MiniIcons'       },
  cdl                = { glyph = '',  hl = 'MiniIcons'       },
  cdrdaoconf         = { glyph = '',  hl = 'MiniIcons'       },
  cdrtoc             = { glyph = '',  hl = 'MiniIcons'       },
  cf                 = { glyph = '',  hl = 'MiniIcons'       },
  cfg                = { glyph = '', hl = 'MiniIconsGrey'   },
  cgdbrc             = { glyph = '',  hl = 'MiniIcons'       },
  ch                 = { glyph = '',  hl = 'MiniIcons'       },
  chaiscript         = { glyph = '',  hl = 'MiniIcons'       },
  change             = { glyph = '',  hl = 'MiniIcons'       },
  changelog          = { glyph = '',  hl = 'MiniIcons'       },
  chaskell           = { glyph = '',  hl = 'MiniIcons'       },
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
  cmake              = { glyph = '', hl = 'MiniIconsGrey'   },
  cmakecache         = { glyph = '',  hl = 'MiniIcons'       },
  cmod               = { glyph = '',  hl = 'MiniIcons'       },
  cmusrc             = { glyph = '',  hl = 'MiniIcons'       },
  cobol              = { glyph = '⚙', hl = 'MiniIconsBlue'   },
  coco               = { glyph = '',  hl = 'MiniIcons'       },
  colortest          = { glyph = '',  hl = 'MiniIcons'       },
  conaryrecipe       = { glyph = '',  hl = 'MiniIcons'       },
  conf               = { glyph = '', hl = 'MiniIconsGrey'   },
  config             = { glyph = '', hl = 'MiniIconsCyan'   },
  confini            = { glyph = '',  hl = 'MiniIcons'       },
  context            = { glyph = '',  hl = 'MiniIcons'       },
  corn               = { glyph = '',  hl = 'MiniIcons'       },
  cpp                = { glyph = '', hl = 'MiniIconsAzure'  },
  crm                = { glyph = '',  hl = 'MiniIcons'       },
  crontab            = { glyph = '',  hl = 'MiniIcons'       },
  cs                 = { glyph = '󰌛', hl = 'MiniIconsGreen'  },
  csc                = { glyph = '',  hl = 'MiniIcons'       },
  csdl               = { glyph = '',  hl = 'MiniIcons'       },
  csh                = { glyph = '', hl = 'MiniIconsGrey'   },
  csp                = { glyph = '',  hl = 'MiniIcons'       },
  css                = { glyph = '', hl = 'MiniIconsAzure'  },
  csv                = { glyph = '', hl = 'MiniIconsGreen'  },
  csv_pipe           = { glyph = '',  hl = 'MiniIcons'       },
  csv_semicolon      = { glyph = '',  hl = 'MiniIcons'       },
  csv_whitespace     = { glyph = '',  hl = 'MiniIcons'       },
  cterm              = { glyph = '',  hl = 'MiniIcons'       },
  ctrlh              = { glyph = '',  hl = 'MiniIcons'       },
  cucumber           = { glyph = '',  hl = 'MiniIcons'       },
  cuda               = { glyph = '', hl = 'MiniIconsGreen'  },
  cupl               = { glyph = '',  hl = 'MiniIcons'       },
  cuplsim            = { glyph = '',  hl = 'MiniIcons'       },
  cvs                = { glyph = '',  hl = 'MiniIcons'       },
  cvsrc              = { glyph = '',  hl = 'MiniIcons'       },
  cweb               = { glyph = '',  hl = 'MiniIcons'       },
  cynlib             = { glyph = '',  hl = 'MiniIcons'       },
  cynpp              = { glyph = '',  hl = 'MiniIcons'       },
  d                  = { glyph = '', hl = 'MiniIconsGreen'  },
  dart               = { glyph = '', hl = 'MiniIconsBlue'   },
  datascript         = { glyph = '',  hl = 'MiniIcons'       },
  dcd                = { glyph = '',  hl = 'MiniIcons'       },
  dcl                = { glyph = '',  hl = 'MiniIcons'       },
  deb822sources      = { glyph = '',  hl = 'MiniIcons'       },
  debchangelog       = { glyph = '',  hl = 'MiniIcons'       },
  debcontrol         = { glyph = '',  hl = 'MiniIcons'       },
  debcopyright       = { glyph = '',  hl = 'MiniIcons'       },
  debsources         = { glyph = '',  hl = 'MiniIcons'       },
  def                = { glyph = '',  hl = 'MiniIcons'       },
  denyhosts          = { glyph = '',  hl = 'MiniIcons'       },
  dep3patch          = { glyph = '',  hl = 'MiniIcons'       },
  desc               = { glyph = '',  hl = 'MiniIcons'       },
  desktop            = { glyph = '', hl = 'MiniIconsPurple' },
  dictconf           = { glyph = '',  hl = 'MiniIcons'       },
  dictdconf          = { glyph = '',  hl = 'MiniIcons'       },
  diff               = { glyph = '', hl = 'MiniIconsGrey'   },
  dircolors          = { glyph = '',  hl = 'MiniIcons'       },
  dirpager           = { glyph = '',  hl = 'MiniIcons'       },
  diva               = { glyph = '',  hl = 'MiniIcons'       },
  django             = { glyph = '',  hl = 'MiniIcons'       },
  dns                = { glyph = '',  hl = 'MiniIcons'       },
  dnsmasq            = { glyph = '',  hl = 'MiniIcons'       },
  docbk              = { glyph = '',  hl = 'MiniIcons'       },
  docbksgml          = { glyph = '',  hl = 'MiniIcons'       },
  docbkxml           = { glyph = '',  hl = 'MiniIcons'       },
  dockerfile         = { glyph = '󰡨', hl = 'MiniIconsBlue'   },
  dosbatch           = { glyph = '', hl = 'MiniIconsGreen'  },
  dosini             = { glyph = '', hl = 'MiniIconsGrey'   },
  dot                = { glyph = '󱁉', hl = 'MiniIconsAzure'  },
  doxygen            = { glyph = '',  hl = 'MiniIcons'       },
  dracula            = { glyph = '',  hl = 'MiniIcons'       },
  dsl                = { glyph = '',  hl = 'MiniIcons'       },
  dtd                = { glyph = '',  hl = 'MiniIcons'       },
  dtml               = { glyph = '',  hl = 'MiniIcons'       },
  dtrace             = { glyph = '',  hl = 'MiniIcons'       },
  dts                = { glyph = '',  hl = 'MiniIcons'       },
  dune               = { glyph = '',  hl = 'MiniIcons'       },
  dylan              = { glyph = '',  hl = 'MiniIcons'       },
  dylanintr          = { glyph = '',  hl = 'MiniIcons'       },
  dylanlid           = { glyph = '',  hl = 'MiniIcons'       },
  ecd                = { glyph = '',  hl = 'MiniIcons'       },
  edif               = { glyph = '',  hl = 'MiniIcons'       },
  editorconfig       = { glyph = '', hl = 'MiniIconsGrey'   },
  eiffel             = { glyph = '',  hl = 'MiniIcons'       },
  elf                = { glyph = '',  hl = 'MiniIcons'       },
  elinks             = { glyph = '',  hl = 'MiniIcons'       },
  elixir             = { glyph = '', hl = 'MiniIconsPurple' },
  elm                = { glyph = '', hl = 'MiniIconsAzure'  },
  elmfilt            = { glyph = '',  hl = 'MiniIcons'       },
  erlang             = { glyph = '', hl = 'MiniIconsRed'    },
  eruby              = { glyph = '', hl = 'MiniIconsRed'    },
  esmtprc            = { glyph = '',  hl = 'MiniIcons'       },
  esqlc              = { glyph = '',  hl = 'MiniIcons'       },
  esterel            = { glyph = '',  hl = 'MiniIcons'       },
  eterm              = { glyph = '',  hl = 'MiniIcons'       },
  euphoria3          = { glyph = '',  hl = 'MiniIcons'       },
  euphoria4          = { glyph = '',  hl = 'MiniIcons'       },
  eviews             = { glyph = '',  hl = 'MiniIcons'       },
  exim               = { glyph = '',  hl = 'MiniIcons'       },
  expect             = { glyph = '',  hl = 'MiniIcons'       },
  exports            = { glyph = '',  hl = 'MiniIcons'       },
  falcon             = { glyph = '',  hl = 'MiniIcons'       },
  fan                = { glyph = '',  hl = 'MiniIcons'       },
  fasm               = { glyph = '',  hl = 'MiniIcons'       },
  fdcc               = { glyph = '',  hl = 'MiniIcons'       },
  fennel             = { glyph = '', hl = 'MiniIconsYellow' },
  fetchmail          = { glyph = '',  hl = 'MiniIcons'       },
  fgl                = { glyph = '',  hl = 'MiniIcons'       },
  fish               = { glyph = '', hl = 'MiniIconsGrey'   },
  flexwiki           = { glyph = '',  hl = 'MiniIcons'       },
  focexec            = { glyph = '',  hl = 'MiniIcons'       },
  form               = { glyph = '',  hl = 'MiniIcons'       },
  forth              = { glyph = '', hl = 'MiniIconsAzure'  },
  fortran            = { glyph = '󱈚', hl = 'MiniIconsPurple' },
  foxpro             = { glyph = '',  hl = 'MiniIcons'       },
  fpcmake            = { glyph = '',  hl = 'MiniIcons'       },
  framescript        = { glyph = '',  hl = 'MiniIcons'       },
  freebasic          = { glyph = '',  hl = 'MiniIcons'       },
  fstab              = { glyph = '',  hl = 'MiniIcons'       },
  fvwm               = { glyph = '',  hl = 'MiniIcons'       },
  fvwm2m4            = { glyph = '',  hl = 'MiniIcons'       },
  gdb                = { glyph = '',  hl = 'MiniIcons'       },
  gdmo               = { glyph = '',  hl = 'MiniIcons'       },
  gdresource         = { glyph = '',  hl = 'MiniIcons'       },
  gdscript           = { glyph = '',  hl = 'MiniIcons'       },
  gdshader           = { glyph = '',  hl = 'MiniIcons'       },
  gedcom             = { glyph = '',  hl = 'MiniIcons'       },
  gemtext            = { glyph = '',  hl = 'MiniIcons'       },
  gift               = { glyph = '',  hl = 'MiniIcons'       },
  git                = { glyph = '', hl = 'MiniIconsOrange' },
  gitattributes      = { glyph = '', hl = 'MiniIconsOrange' },
  gitcommit          = { glyph = '', hl = 'MiniIconsOrange' },
  gitconfig          = { glyph = '', hl = 'MiniIconsOrange' },
  gitignore          = { glyph = '', hl = 'MiniIconsOrange' },
  gitolite           = { glyph = '',  hl = 'MiniIcons'       },
  gitrebase          = { glyph = '',  hl = 'MiniIcons'       },
  gitsendemail       = { glyph = '',  hl = 'MiniIcons'       },
  gkrellmrc          = { glyph = '',  hl = 'MiniIcons'       },
  gnash              = { glyph = '',  hl = 'MiniIcons'       },
  gnuplot            = { glyph = '',  hl = 'MiniIcons'       },
  go                 = { glyph = '', hl = 'MiniIconsAzure'  },
  godoc              = { glyph = '',  hl = 'MiniIcons'       },
  gp                 = { glyph = '',  hl = 'MiniIcons'       },
  gpg                = { glyph = '',  hl = 'MiniIcons'       },
  gprof              = { glyph = '',  hl = 'MiniIcons'       },
  grads              = { glyph = '',  hl = 'MiniIcons'       },
  graphql            = { glyph = '', hl = 'MiniIconsRed'    },
  gretl              = { glyph = '',  hl = 'MiniIcons'       },
  groff              = { glyph = '',  hl = 'MiniIcons'       },
  groovy             = { glyph = '', hl = 'MiniIconsAzure'  },
  group              = { glyph = '',  hl = 'MiniIcons'       },
  grub               = { glyph = '',  hl = 'MiniIcons'       },
  gsp                = { glyph = '',  hl = 'MiniIcons'       },
  gtkrc              = { glyph = '', hl = 'MiniIconsGrey'   },
  gvpr               = { glyph = '',  hl = 'MiniIcons'       },
  gyp                = { glyph = '',  hl = 'MiniIcons'       },
  haml               = { glyph = '', hl = 'MiniIconsGrey'   },
  hamster            = { glyph = '',  hl = 'MiniIcons'       },
  hare               = { glyph = '',  hl = 'MiniIcons'       },
  haredoc            = { glyph = '',  hl = 'MiniIcons'       },
  haskell            = { glyph = '', hl = 'MiniIconsPurple' },
  haste              = { glyph = '',  hl = 'MiniIcons'       },
  hastepreproc       = { glyph = '',  hl = 'MiniIcons'       },
  hb                 = { glyph = '',  hl = 'MiniIcons'       },
  heex               = { glyph = '', hl = 'MiniIconsPurple' },
  help               = { glyph = '',  hl = 'MiniIcons'       },
  help_ru            = { glyph = '',  hl = 'MiniIcons'       },
  hercules           = { glyph = '',  hl = 'MiniIcons'       },
  hex                = { glyph = '', hl = 'MiniIconsBlue'   },
  hgcommit           = { glyph = '',  hl = 'MiniIcons'       },
  hitest             = { glyph = '',  hl = 'MiniIcons'       },
  hlsplaylist        = { glyph = '',  hl = 'MiniIcons'       },
  hog                = { glyph = '',  hl = 'MiniIcons'       },
  hollywood          = { glyph = '',  hl = 'MiniIcons'       },
  hostconf           = { glyph = '',  hl = 'MiniIcons'       },
  hostsaccess        = { glyph = '',  hl = 'MiniIcons'       },
  html               = { glyph = '', hl = 'MiniIconsOrange' },
  htmlcheetah        = { glyph = '',  hl = 'MiniIcons'       },
  htmldjango         = { glyph = '',  hl = 'MiniIcons'       },
  htmlm4             = { glyph = '',  hl = 'MiniIcons'       },
  htmlos             = { glyph = '',  hl = 'MiniIcons'       },
  hurl               = { glyph = '',  hl = 'MiniIcons'       },
  hyprlang           = { glyph = '',  hl = 'MiniIcons'       },
  i3config           = { glyph = '', hl = 'MiniIconsCyan'   },
  ia64               = { glyph = '',  hl = 'MiniIcons'       },
  ibasic             = { glyph = '',  hl = 'MiniIcons'       },
  icemenu            = { glyph = '',  hl = 'MiniIcons'       },
  icon               = { glyph = '',  hl = 'MiniIcons'       },
  idl                = { glyph = '',  hl = 'MiniIcons'       },
  idlang             = { glyph = '', hl = 'MiniIconsYellow' },
  indent             = { glyph = '',  hl = 'MiniIcons'       },
  inform             = { glyph = '',  hl = 'MiniIcons'       },
  initex             = { glyph = '',  hl = 'MiniIcons'       },
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
  java               = { glyph = '', hl = 'MiniIconsOrange' },
  javacc             = { glyph = '',  hl = 'MiniIcons'       },
  javascript         = { glyph = '', hl = 'MiniIconsYellow' },
  javascriptreact    = { glyph = '', hl = 'MiniIconsAzure'  },
  jess               = { glyph = '',  hl = 'MiniIcons'       },
  jgraph             = { glyph = '',  hl = 'MiniIcons'       },
  jj                 = { glyph = '',  hl = 'MiniIcons'       },
  jovial             = { glyph = '',  hl = 'MiniIcons'       },
  jproperties        = { glyph = '',  hl = 'MiniIcons'       },
  jq                 = { glyph = '',  hl = 'MiniIcons'       },
  json               = { glyph = '', hl = 'MiniIconsYellow' },
  json5              = { glyph = '', hl = 'MiniIconsYellow' },
  jsonc              = { glyph = '', hl = 'MiniIconsYellow' },
  jsonnet            = { glyph = '',  hl = 'MiniIcons'       },
  jsp                = { glyph = '',  hl = 'MiniIcons'       },
  julia              = { glyph = '', hl = 'MiniIconsPurple' },
  kconfig            = { glyph = '', hl = 'MiniIconsCyan'   },
  kivy               = { glyph = '',  hl = 'MiniIcons'       },
  kix                = { glyph = '',  hl = 'MiniIcons'       },
  kotlin             = { glyph = '', hl = 'MiniIconsBlue'   },
  krl                = { glyph = '',  hl = 'MiniIcons'       },
  kscript            = { glyph = '',  hl = 'MiniIcons'       },
  kwt                = { glyph = '',  hl = 'MiniIcons'       },
  lace               = { glyph = '',  hl = 'MiniIcons'       },
  latte              = { glyph = '',  hl = 'MiniIcons'       },
  lc                 = { glyph = '',  hl = 'MiniIcons'       },
  ld                 = { glyph = '',  hl = 'MiniIcons'       },
  ldapconf           = { glyph = '',  hl = 'MiniIcons'       },
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
  lisp               = { glyph = '',  hl = 'MiniIcons'       },
  lite               = { glyph = '',  hl = 'MiniIcons'       },
  litestep           = { glyph = '',  hl = 'MiniIcons'       },
  livebook           = { glyph = '',  hl = 'MiniIcons'       },
  logcheck           = { glyph = '',  hl = 'MiniIcons'       },
  loginaccess        = { glyph = '',  hl = 'MiniIcons'       },
  logindefs          = { glyph = '',  hl = 'MiniIcons'       },
  logtalk            = { glyph = '',  hl = 'MiniIcons'       },
  lotos              = { glyph = '',  hl = 'MiniIcons'       },
  lout               = { glyph = '',  hl = 'MiniIcons'       },
  lpc                = { glyph = '',  hl = 'MiniIcons'       },
  lprolog            = { glyph = 'λ', hl = 'MiniIconsOrange' },
  lscript            = { glyph = '',  hl = 'MiniIcons'       },
  lsl                = { glyph = '',  hl = 'MiniIcons'       },
  lsp_markdown       = { glyph = '',  hl = 'MiniIcons'       },
  lss                = { glyph = '',  hl = 'MiniIcons'       },
  lua                = { glyph = '', hl = 'MiniIconsAzure'  },
  luau               = { glyph = '',  hl = 'MiniIcons'       },
  lynx               = { glyph = '',  hl = 'MiniIcons'       },
  lyrics             = { glyph = '',  hl = 'MiniIcons'       },
  m3build            = { glyph = '',  hl = 'MiniIcons'       },
  m3quake            = { glyph = '',  hl = 'MiniIcons'       },
  m4                 = { glyph = '',  hl = 'MiniIcons'       },
  mail               = { glyph = '',  hl = 'MiniIcons'       },
  mailaliases        = { glyph = '',  hl = 'MiniIcons'       },
  mailcap            = { glyph = '',  hl = 'MiniIcons'       },
  make               = { glyph = '', hl = 'MiniIconsGrey'   },
  mallard            = { glyph = '',  hl = 'MiniIcons'       },
  man                = { glyph = '',  hl = 'MiniIcons'       },
  manconf            = { glyph = '',  hl = 'MiniIcons'       },
  manual             = { glyph = '',  hl = 'MiniIcons'       },
  maple              = { glyph = '',  hl = 'MiniIcons'       },
  markdown           = { glyph = '', hl = 'MiniIconsGrey'   },
  masm               = { glyph = '',  hl = 'MiniIcons'       },
  mason              = { glyph = '',  hl = 'MiniIcons'       },
  master             = { glyph = '',  hl = 'MiniIcons'       },
  matlab             = { glyph = '',  hl = 'MiniIcons'       },
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
  modconf            = { glyph = '',  hl = 'MiniIcons'       },
  model              = { glyph = '',  hl = 'MiniIcons'       },
  modsim3            = { glyph = '',  hl = 'MiniIcons'       },
  modula2            = { glyph = '',  hl = 'MiniIcons'       },
  modula3            = { glyph = '',  hl = 'MiniIcons'       },
  mojo               = { glyph = '',  hl = 'MiniIcons'       },
  monk               = { glyph = '',  hl = 'MiniIcons'       },
  moo                = { glyph = '',  hl = 'MiniIcons'       },
  mp                 = { glyph = '',  hl = 'MiniIcons'       },
  mplayerconf        = { glyph = '',  hl = 'MiniIcons'       },
  mrxvtrc            = { glyph = '',  hl = 'MiniIcons'       },
  msidl              = { glyph = '',  hl = 'MiniIcons'       },
  msmessages         = { glyph = '',  hl = 'MiniIcons'       },
  msql               = { glyph = '',  hl = 'MiniIcons'       },
  mupad              = { glyph = '',  hl = 'MiniIcons'       },
  murphi             = { glyph = '',  hl = 'MiniIcons'       },
  mush               = { glyph = '',  hl = 'MiniIcons'       },
  muttrc             = { glyph = '',  hl = 'MiniIcons'       },
  mysql              = { glyph = '',  hl = 'MiniIcons'       },
  n1ql               = { glyph = '',  hl = 'MiniIcons'       },
  named              = { glyph = '',  hl = 'MiniIcons'       },
  nanorc             = { glyph = '',  hl = 'MiniIcons'       },
  nasm               = { glyph = '',  hl = 'MiniIcons'       },
  nastran            = { glyph = '',  hl = 'MiniIcons'       },
  natural            = { glyph = '',  hl = 'MiniIcons'       },
  ncf                = { glyph = '',  hl = 'MiniIcons'       },
  neomuttrc          = { glyph = '',  hl = 'MiniIcons'       },
  netrc              = { glyph = '',  hl = 'MiniIcons'       },
  netrw              = { glyph = '',  hl = 'MiniIcons'       },
  nginx              = { glyph = '',  hl = 'MiniIcons'       },
  nim                = { glyph = '', hl = 'MiniIconsYellow' },
  ninja              = { glyph = '',  hl = 'MiniIcons'       },
  nix                = { glyph = '', hl = 'MiniIconsAzure'  },
  nosyntax           = { glyph = '',  hl = 'MiniIcons'       },
  nqc                = { glyph = '',  hl = 'MiniIcons'       },
  nroff              = { glyph = '',  hl = 'MiniIcons'       },
  nsis               = { glyph = '',  hl = 'MiniIcons'       },
  obj                = { glyph = '󰆧', hl = 'MiniIconsGrey'   },
  objc               = { glyph = '',  hl = 'MiniIcons'       },
  objcpp             = { glyph = '',  hl = 'MiniIcons'       },
  objdump            = { glyph = '',  hl = 'MiniIcons'       },
  obse               = { glyph = '',  hl = 'MiniIcons'       },
  ocaml              = { glyph = '', hl = 'MiniIconsOrange' },
  occam              = { glyph = '',  hl = 'MiniIcons'       },
  octave             = { glyph = '',  hl = 'MiniIcons'       },
  odin               = { glyph = '',  hl = 'MiniIcons'       },
  omnimark           = { glyph = '',  hl = 'MiniIcons'       },
  ondir              = { glyph = '',  hl = 'MiniIcons'       },
  opam               = { glyph = '',  hl = 'MiniIcons'       },
  openroad           = { glyph = '',  hl = 'MiniIcons'       },
  openscad           = { glyph = '', hl = 'MiniIconsYellow' },
  openvpn            = { glyph = '',  hl = 'MiniIcons'       },
  opl                = { glyph = '',  hl = 'MiniIcons'       },
  ora                = { glyph = '',  hl = 'MiniIcons'       },
  pacmanlog          = { glyph = '',  hl = 'MiniIcons'       },
  pamconf            = { glyph = '',  hl = 'MiniIcons'       },
  pamenv             = { glyph = '',  hl = 'MiniIcons'       },
  pandoc             = { glyph = '',  hl = 'MiniIcons'       },
  papp               = { glyph = '',  hl = 'MiniIcons'       },
  pascal             = { glyph = '',  hl = 'MiniIcons'       },
  passwd             = { glyph = '',  hl = 'MiniIcons'       },
  pbtxt              = { glyph = '',  hl = 'MiniIcons'       },
  pcap               = { glyph = '',  hl = 'MiniIcons'       },
  pccts              = { glyph = '',  hl = 'MiniIcons'       },
  pdf                = { glyph = '', hl = 'MiniIconsRed'    },
  perl               = { glyph = '', hl = 'MiniIconsAzure'  },
  pf                 = { glyph = '',  hl = 'MiniIcons'       },
  pfmain             = { glyph = '',  hl = 'MiniIcons'       },
  php                = { glyph = '', hl = 'MiniIconsPurple' },
  phtml              = { glyph = '',  hl = 'MiniIcons'       },
  pic                = { glyph = '',  hl = 'MiniIcons'       },
  pike               = { glyph = '',  hl = 'MiniIcons'       },
  pilrc              = { glyph = '',  hl = 'MiniIcons'       },
  pine               = { glyph = '',  hl = 'MiniIcons'       },
  pinfo              = { glyph = '',  hl = 'MiniIcons'       },
  plaintex           = { glyph = '', hl = 'MiniIconsGreen'  },
  pli                = { glyph = '',  hl = 'MiniIcons'       },
  plm                = { glyph = '',  hl = 'MiniIcons'       },
  plp                = { glyph = '',  hl = 'MiniIcons'       },
  plsql              = { glyph = '',  hl = 'MiniIcons'       },
  po                 = { glyph = '', hl = 'MiniIconsAzure'  },
  pod                = { glyph = '',  hl = 'MiniIcons'       },
  poefilter          = { glyph = '',  hl = 'MiniIcons'       },
  poke               = { glyph = '',  hl = 'MiniIcons'       },
  postscr            = { glyph = '', hl = 'MiniIconsYellow' },
  pov                = { glyph = '',  hl = 'MiniIcons'       },
  povini             = { glyph = '',  hl = 'MiniIcons'       },
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
  ps1xml             = { glyph = '',  hl = 'MiniIcons'       },
  psf                = { glyph = '',  hl = 'MiniIcons'       },
  psl                = { glyph = '',  hl = 'MiniIcons'       },
  ptcap              = { glyph = '',  hl = 'MiniIcons'       },
  purescript         = { glyph = '',  hl = 'MiniIcons'       },
  purifylog          = { glyph = '',  hl = 'MiniIcons'       },
  pymanifest         = { glyph = '',  hl = 'MiniIcons'       },
  pyrex              = { glyph = '',  hl = 'MiniIcons'       },
  python             = { glyph = '', hl = 'MiniIconsYellow' },
  python2            = { glyph = '',  hl = 'MiniIcons'       },
  qb64               = { glyph = '',  hl = 'MiniIcons'       },
  qf                 = { glyph = '',  hl = 'MiniIcons'       },
  qml                = { glyph = '',  hl = 'MiniIcons'       },
  quake              = { glyph = '',  hl = 'MiniIcons'       },
  quarto             = { glyph = '',  hl = 'MiniIcons'       },
  query              = { glyph = '', hl = 'MiniIconsGreen'  },
  r                  = { glyph = '󰟔', hl = 'MiniIconsBlue'   },
  racc               = { glyph = '',  hl = 'MiniIcons'       },
  racket             = { glyph = '',  hl = 'MiniIcons'       },
  radiance           = { glyph = '',  hl = 'MiniIcons'       },
  raku               = { glyph = '',  hl = 'MiniIcons'       },
  raml               = { glyph = '',  hl = 'MiniIcons'       },
  rapid              = { glyph = '',  hl = 'MiniIcons'       },
  rasi               = { glyph = '',  hl = 'MiniIcons'       },
  ratpoison          = { glyph = '',  hl = 'MiniIcons'       },
  rc                 = { glyph = '',  hl = 'MiniIcons'       },
  rcs                = { glyph = '',  hl = 'MiniIcons'       },
  rcslog             = { glyph = '',  hl = 'MiniIcons'       },
  readline           = { glyph = '',  hl = 'MiniIcons'       },
  rebol              = { glyph = '',  hl = 'MiniIcons'       },
  redif              = { glyph = '',  hl = 'MiniIcons'       },
  registry           = { glyph = '',  hl = 'MiniIcons'       },
  rego               = { glyph = '',  hl = 'MiniIcons'       },
  remind             = { glyph = '',  hl = 'MiniIcons'       },
  requirements       = { glyph = '',  hl = 'MiniIcons'       },
  rescript           = { glyph = '',  hl = 'MiniIcons'       },
  resolv             = { glyph = '',  hl = 'MiniIcons'       },
  reva               = { glyph = '',  hl = 'MiniIcons'       },
  rexx               = { glyph = '',  hl = 'MiniIcons'       },
  rfc_csv            = { glyph = '',  hl = 'MiniIcons'       },
  rfc_semicolon      = { glyph = '',  hl = 'MiniIcons'       },
  rhelp              = { glyph = '',  hl = 'MiniIcons'       },
  rib                = { glyph = '',  hl = 'MiniIcons'       },
  rmarkdown          = { glyph = '',  hl = 'MiniIcons'       },
  rmd                = { glyph = '', hl = 'MiniIconsAzure'  },
  rnc                = { glyph = '',  hl = 'MiniIcons'       },
  rng                = { glyph = '',  hl = 'MiniIcons'       },
  rnoweb             = { glyph = '',  hl = 'MiniIcons'       },
  robots             = { glyph = '',  hl = 'MiniIcons'       },
  roc                = { glyph = '',  hl = 'MiniIcons'       },
  routeros           = { glyph = '',  hl = 'MiniIcons'       },
  rpcgen             = { glyph = '',  hl = 'MiniIcons'       },
  rpl                = { glyph = '',  hl = 'MiniIcons'       },
  rrst               = { glyph = '',  hl = 'MiniIcons'       },
  rst                = { glyph = '',  hl = 'MiniIcons'       },
  rtf                = { glyph = '',  hl = 'MiniIcons'       },
  ruby               = { glyph = '', hl = 'MiniIconsRed'    },
  rust               = { glyph = '', hl = 'MiniIconsOrange' },
  samba              = { glyph = '',  hl = 'MiniIcons'       },
  sas                = { glyph = '',  hl = 'MiniIcons'       },
  sass               = { glyph = '', hl = 'MiniIconsRed'    },
  sather             = { glyph = '',  hl = 'MiniIcons'       },
  sbt                = { glyph = '', hl = 'MiniIconsOrange' },
  scala              = { glyph = '', hl = 'MiniIconsRed'    },
  scdoc              = { glyph = '',  hl = 'MiniIcons'       },
  scheme             = { glyph = '󰘧', hl = 'MiniIconsGrey'   },
  scilab             = { glyph = '',  hl = 'MiniIcons'       },
  screen             = { glyph = '',  hl = 'MiniIcons'       },
  scss               = { glyph = '', hl = 'MiniIconsRed'    },
  sd                 = { glyph = '',  hl = 'MiniIcons'       },
  sdc                = { glyph = '',  hl = 'MiniIcons'       },
  sdl                = { glyph = '',  hl = 'MiniIcons'       },
  sed                = { glyph = '',  hl = 'MiniIcons'       },
  sendpr             = { glyph = '',  hl = 'MiniIcons'       },
  sensors            = { glyph = '',  hl = 'MiniIcons'       },
  services           = { glyph = '',  hl = 'MiniIcons'       },
  setserial          = { glyph = '',  hl = 'MiniIcons'       },
  sexplib            = { glyph = '',  hl = 'MiniIcons'       },
  sgml               = { glyph = '',  hl = 'MiniIcons'       },
  sgmldecl           = { glyph = '',  hl = 'MiniIcons'       },
  sgmllnx            = { glyph = '',  hl = 'MiniIcons'       },
  sh                 = { glyph = '', hl = 'MiniIconsGrey'   },
  shada              = { glyph = '',  hl = 'MiniIcons'       },
  sicad              = { glyph = '',  hl = 'MiniIcons'       },
  sieve              = { glyph = '',  hl = 'MiniIcons'       },
  sil                = { glyph = '',  hl = 'MiniIcons'       },
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
  slpconf            = { glyph = '',  hl = 'MiniIcons'       },
  slpreg             = { glyph = '',  hl = 'MiniIcons'       },
  slpspi             = { glyph = '',  hl = 'MiniIcons'       },
  slrnrc             = { glyph = '',  hl = 'MiniIcons'       },
  slrnsc             = { glyph = '',  hl = 'MiniIcons'       },
  sm                 = { glyph = '',  hl = 'MiniIcons'       },
  smarty             = { glyph = '',  hl = 'MiniIcons'       },
  smcl               = { glyph = '',  hl = 'MiniIcons'       },
  smil               = { glyph = '',  hl = 'MiniIcons'       },
  smith              = { glyph = '',  hl = 'MiniIcons'       },
  sml                = { glyph = 'λ', hl = 'MiniIconsOrange' },
  snippets           = { glyph = '',  hl = 'MiniIcons'       },
  snnsnet            = { glyph = '',  hl = 'MiniIcons'       },
  snnspat            = { glyph = '',  hl = 'MiniIcons'       },
  snnsres            = { glyph = '',  hl = 'MiniIcons'       },
  snobol4            = { glyph = '',  hl = 'MiniIcons'       },
  solidity           = { glyph = '', hl = 'MiniIconsAzure'  },
  solution           = { glyph = '',  hl = 'MiniIcons'       },
  spec               = { glyph = '',  hl = 'MiniIcons'       },
  specman            = { glyph = '',  hl = 'MiniIcons'       },
  spice              = { glyph = '',  hl = 'MiniIcons'       },
  splint             = { glyph = '',  hl = 'MiniIcons'       },
  spup               = { glyph = '',  hl = 'MiniIcons'       },
  spyce              = { glyph = '',  hl = 'MiniIcons'       },
  sql                = { glyph = '', hl = 'MiniIconsGrey'   },
  sqlanywhere        = { glyph = '',  hl = 'MiniIcons'       },
  sqlforms           = { glyph = '',  hl = 'MiniIcons'       },
  sqlhana            = { glyph = '',  hl = 'MiniIcons'       },
  sqlinformix        = { glyph = '',  hl = 'MiniIcons'       },
  sqlj               = { glyph = '',  hl = 'MiniIcons'       },
  sqloracle          = { glyph = '',  hl = 'MiniIcons'       },
  sqr                = { glyph = '',  hl = 'MiniIcons'       },
  squid              = { glyph = '',  hl = 'MiniIcons'       },
  squirrel           = { glyph = '',  hl = 'MiniIcons'       },
  srec               = { glyph = '',  hl = 'MiniIcons'       },
  srt                = { glyph = '󰨖', hl = 'MiniIconsYellow' },
  ssa                = { glyph = '󰨖', hl = 'MiniIconsYellow' },
  sshconfig          = { glyph = '', hl = 'MiniIconsCyan'   },
  sshdconfig         = { glyph = '', hl = 'MiniIconsCyan'   },
  st                 = { glyph = '',  hl = 'MiniIcons'       },
  stata              = { glyph = '',  hl = 'MiniIcons'       },
  stp                = { glyph = '',  hl = 'MiniIcons'       },
  strace             = { glyph = '',  hl = 'MiniIcons'       },
  structurizr        = { glyph = '',  hl = 'MiniIcons'       },
  stylus             = { glyph = '',  hl = 'MiniIcons'       },
  sudoers            = { glyph = '',  hl = 'MiniIcons'       },
  svg                = { glyph = '󰜡', hl = 'MiniIconsYellow' },
  svn                = { glyph = '',  hl = 'MiniIcons'       },
  swayconfig         = { glyph = '', hl = 'MiniIconsCyan'   },
  swift              = { glyph = '', hl = 'MiniIconsOrange' },
  swiftgyb           = { glyph = '',  hl = 'MiniIcons'       },
  swig               = { glyph = '',  hl = 'MiniIcons'       },
  synload            = { glyph = '',  hl = 'MiniIcons'       },
  syntax             = { glyph = '',  hl = 'MiniIcons'       },
  sysctl             = { glyph = '',  hl = 'MiniIcons'       },
  systemd            = { glyph = '',  hl = 'MiniIcons'       },
  systemverilog      = { glyph = '󰍛', hl = 'MiniIconsGreen'  },
  tads               = { glyph = '', hl = 'MiniIconsAzure'  },
  tags               = { glyph = '',  hl = 'MiniIcons'       },
  tak                = { glyph = '',  hl = 'MiniIcons'       },
  takcmp             = { glyph = '',  hl = 'MiniIcons'       },
  takout             = { glyph = '',  hl = 'MiniIcons'       },
  tap                = { glyph = '',  hl = 'MiniIcons'       },
  tar                = { glyph = '',  hl = 'MiniIcons'       },
  taskdata           = { glyph = '',  hl = 'MiniIcons'       },
  taskedit           = { glyph = '',  hl = 'MiniIcons'       },
  tasm               = { glyph = '',  hl = 'MiniIcons'       },
  tcl                = { glyph = '󰛓', hl = 'MiniIconsBlue'   },
  tcsh               = { glyph = '',  hl = 'MiniIcons'       },
  template           = { glyph = '',  hl = 'MiniIcons'       },
  teraterm           = { glyph = '',  hl = 'MiniIcons'       },
  terminfo           = { glyph = '',  hl = 'MiniIcons'       },
  tex                = { glyph = '', hl = 'MiniIconsGreen'  },
  texinfo            = { glyph = '',  hl = 'MiniIcons'       },
  texmf              = { glyph = '',  hl = 'MiniIcons'       },
  text               = { glyph = '',  hl = 'MiniIcons'       },
  tf                 = { glyph = '',  hl = 'MiniIcons'       },
  tidy               = { glyph = '',  hl = 'MiniIcons'       },
  tilde              = { glyph = '',  hl = 'MiniIcons'       },
  tli                = { glyph = '',  hl = 'MiniIcons'       },
  tmux               = { glyph = '',  hl = 'MiniIcons'       },
  toml               = { glyph = '', hl = 'MiniIconsOrange' },
  tpp                = { glyph = '',  hl = 'MiniIcons'       },
  trasys             = { glyph = '',  hl = 'MiniIcons'       },
  treetop            = { glyph = '',  hl = 'MiniIcons'       },
  trustees           = { glyph = '',  hl = 'MiniIcons'       },
  tsalt              = { glyph = '',  hl = 'MiniIcons'       },
  tsscl              = { glyph = '',  hl = 'MiniIcons'       },
  tssgm              = { glyph = '',  hl = 'MiniIcons'       },
  tssop              = { glyph = '',  hl = 'MiniIcons'       },
  tsv                = { glyph = '',  hl = 'MiniIcons'       },
  tt2                = { glyph = '',  hl = 'MiniIcons'       },
  tt2html            = { glyph = '',  hl = 'MiniIcons'       },
  tt2js              = { glyph = '',  hl = 'MiniIcons'       },
  tutor              = { glyph = '',  hl = 'MiniIcons'       },
  typescript         = { glyph = '', hl = 'MiniIconsAzure'  },
  typescriptreact    = { glyph = '', hl = 'MiniIconsBlue'   },
  typst              = { glyph = '',  hl = 'MiniIcons'       },
  uc                 = { glyph = '',  hl = 'MiniIcons'       },
  uci                = { glyph = '',  hl = 'MiniIcons'       },
  udevconf           = { glyph = '',  hl = 'MiniIcons'       },
  udevperm           = { glyph = '',  hl = 'MiniIcons'       },
  udevrules          = { glyph = '',  hl = 'MiniIcons'       },
  uil                = { glyph = '',  hl = 'MiniIcons'       },
  unison             = { glyph = '',  hl = 'MiniIcons'       },
  updatedb           = { glyph = '',  hl = 'MiniIcons'       },
  upstart            = { glyph = '',  hl = 'MiniIcons'       },
  upstreamdat        = { glyph = '',  hl = 'MiniIcons'       },
  upstreaminstalllog = { glyph = '',  hl = 'MiniIcons'       },
  upstreamlog        = { glyph = '',  hl = 'MiniIcons'       },
  upstreamrpt        = { glyph = '',  hl = 'MiniIcons'       },
  urlshortcut        = { glyph = '',  hl = 'MiniIcons'       },
  usd                = { glyph = '',  hl = 'MiniIcons'       },
  usserverlog        = { glyph = '',  hl = 'MiniIcons'       },
  usw2kagtlog        = { glyph = '',  hl = 'MiniIcons'       },
  v                  = { glyph = '',  hl = 'MiniIcons'       },
  valgrind           = { glyph = '',  hl = 'MiniIcons'       },
  vb                 = { glyph = '',  hl = 'MiniIcons'       },
  vdf                = { glyph = '',  hl = 'MiniIcons'       },
  vera               = { glyph = '',  hl = 'MiniIcons'       },
  verilog            = { glyph = '󰍛', hl = 'MiniIconsGreen'  },
  verilogams         = { glyph = '',  hl = 'MiniIcons'       },
  vgrindefs          = { glyph = '',  hl = 'MiniIcons'       },
  vhdl               = { glyph = '󰍛', hl = 'MiniIconsGreen'  },
  vim                = { glyph = '', hl = 'MiniIconsGreen'  },
  viminfo            = { glyph = '',  hl = 'MiniIcons'       },
  vimnormal          = { glyph = '',  hl = 'MiniIcons'       },
  virata             = { glyph = '',  hl = 'MiniIcons'       },
  vmasm              = { glyph = '',  hl = 'MiniIcons'       },
  voscm              = { glyph = '',  hl = 'MiniIcons'       },
  vrml               = { glyph = '',  hl = 'MiniIcons'       },
  vroom              = { glyph = '',  hl = 'MiniIcons'       },
  vsejcl             = { glyph = '',  hl = 'MiniIcons'       },
  vue                = { glyph = '', hl = 'MiniIconsGreen'  },
  wat                = { glyph = '',  hl = 'MiniIcons'       },
  wdiff              = { glyph = '',  hl = 'MiniIcons'       },
  wdl                = { glyph = '',  hl = 'MiniIcons'       },
  web                = { glyph = '',  hl = 'MiniIcons'       },
  webmacro           = { glyph = '',  hl = 'MiniIcons'       },
  wget               = { glyph = '',  hl = 'MiniIcons'       },
  wget2              = { glyph = '',  hl = 'MiniIcons'       },
  whitespace         = { glyph = '',  hl = 'MiniIcons'       },
  winbatch           = { glyph = '',  hl = 'MiniIcons'       },
  wml                = { glyph = '',  hl = 'MiniIcons'       },
  wsh                = { glyph = '',  hl = 'MiniIcons'       },
  wsml               = { glyph = '',  hl = 'MiniIcons'       },
  wvdial             = { glyph = '',  hl = 'MiniIcons'       },
  xbl                = { glyph = '',  hl = 'MiniIcons'       },
  xcompose           = { glyph = '',  hl = 'MiniIcons'       },
  xdefaults          = { glyph = '',  hl = 'MiniIcons'       },
  xf86conf           = { glyph = '',  hl = 'MiniIcons'       },
  xhtml              = { glyph = '',  hl = 'MiniIcons'       },
  xinetd             = { glyph = '',  hl = 'MiniIcons'       },
  xkb                = { glyph = '',  hl = 'MiniIcons'       },
  xmath              = { glyph = '',  hl = 'MiniIcons'       },
  xml                = { glyph = '󰗀', hl = 'MiniIconsOrange' },
  xmodmap            = { glyph = '',  hl = 'MiniIcons'       },
  xpm                = { glyph = '',  hl = 'MiniIcons'       },
  xpm2               = { glyph = '',  hl = 'MiniIcons'       },
  xquery             = { glyph = '',  hl = 'MiniIcons'       },
  xs                 = { glyph = '',  hl = 'MiniIcons'       },
  xsd                = { glyph = '',  hl = 'MiniIcons'       },
  xslt               = { glyph = '',  hl = 'MiniIcons'       },
  xxd                = { glyph = '',  hl = 'MiniIcons'       },
  yacc               = { glyph = '',  hl = 'MiniIcons'       },
  yaml               = { glyph = '', hl = 'MiniIconsGrey'   },
  z8a                = { glyph = '',  hl = 'MiniIcons'       },
  zathurarc          = { glyph = '',  hl = 'MiniIcons'       },
  zig                = { glyph = '', hl = 'MiniIconsOrange' },
  zimbu              = { glyph = '',  hl = 'MiniIcons'       },
  zir                = { glyph = '',  hl = 'MiniIcons'       },
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
  ts = H.filetype_icons.typescript,
  r = H.filetype_icons.r,

  -- Not associated with filetype (not text file)
}

-- Path icons. Keys are mostly some popular file/directory basenames and the
-- ones which can conflict with icon detection through extension.
--stylua: ignore
H.path_icons = {
  Makefile = { glyph = '', hl = 'MiniIconsGrey' },
}

-- OS icons. Keys are at least for all icons from Nerd fonts (`nf-linux-*`).
-- Highlight groups are inferred to be aligned with 'nvim-web-devicons'.
--stylua: ignore
H.os_icons = {
  alma         = { glyph = '', hl = 'MiniIconsRed'    },
  alpine       = { glyph = '', hl = 'MiniIconsAzure'  },
  aosc         = { glyph = '', hl = 'MiniIconsRed'    },
  apple        = { glyph = '', hl = 'MiniIconsGrey'   },
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
    local ext = string.match(name, '%.([^%.]+)$'):lower()
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
  local res = {}
  for _, icon_data in pairs(H.filetype_icons) do
    res[icon_data.hl] = (res[icon_data.hl] or 0) + 1
  end
  return res
end

return MiniIcons
