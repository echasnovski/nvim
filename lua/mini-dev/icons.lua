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

-- Filetype icons. Keys are at least filetypes explicitly supported by Neovim
-- (i.e. which have 'runtime/ftplugin' file in its source).
--stylua: ignore
H.filetype_icons = {
  -- Neovim filetype plugins
  ['8th']         = { glyph = '', hl = '' },
  a2ps            = { glyph = '', hl = '' },
  aap             = { glyph = '', hl = '' },
  abap            = { glyph = '', hl = '' },
  abaqus          = { glyph = '', hl = '' },
  ada             = { glyph = '', hl = '' },
  alsaconf        = { glyph = '', hl = '' },
  ant             = { glyph = '', hl = '' },
  apache          = { glyph = '', hl = '' },
  arch            = { glyph = '', hl = '' },
  arduino         = { glyph = '', hl = '' },
  art             = { glyph = '', hl = '' },
  asciidoc        = { glyph = '', hl = '' },
  asm             = { glyph = '', hl = '' },
  aspvbs          = { glyph = '', hl = '' },
  astro           = { glyph = '', hl = '' },
  automake        = { glyph = '', hl = '' },
  awk             = { glyph = '', hl = '' },
  bash            = { glyph = '', hl = '' },
  basic           = { glyph = '', hl = '' },
  bdf             = { glyph = '', hl = '' },
  bitbake         = { glyph = '', hl = '' },
  bp              = { glyph = '', hl = '' },
  bst             = { glyph = '', hl = '' },
  btm             = { glyph = '', hl = '' },
  bzl             = { glyph = '', hl = '' },
  c               = { glyph = '', hl = '' },
  calendar        = { glyph = '', hl = '' },
  cdrdaoconf      = { glyph = '', hl = '' },
  cfg             = { glyph = '', hl = '' },
  cgdbrc          = { glyph = '', hl = '' },
  ch              = { glyph = '', hl = '' },
  changelog       = { glyph = '', hl = '' },
  chatito         = { glyph = '', hl = '' },
  checkhealth     = { glyph = '', hl = '' },
  chicken         = { glyph = '', hl = '' },
  clojure         = { glyph = '', hl = '' },
  cmake           = { glyph = '', hl = '' },
  cobol           = { glyph = '', hl = '' },
  conf            = { glyph = '', hl = '' },
  config          = { glyph = '', hl = '' },
  confini         = { glyph = '', hl = '' },
  context         = { glyph = '', hl = '' },
  corn            = { glyph = '', hl = '' },
  cpp             = { glyph = '', hl = '' },
  crm             = { glyph = '', hl = '' },
  crontab         = { glyph = '', hl = '' },
  cs              = { glyph = '', hl = '' },
  csc             = { glyph = '', hl = '' },
  csh             = { glyph = '', hl = '' },
  css             = { glyph = '', hl = '' },
  cucumber        = { glyph = '', hl = '' },
  cvsrc           = { glyph = '', hl = '' },
  dart            = { glyph = '', hl = '' },
  deb822sources   = { glyph = '', hl = '' },
  debchangelog    = { glyph = '', hl = '' },
  debcontrol      = { glyph = '', hl = '' },
  debsources      = { glyph = '', hl = '' },
  denyhosts       = { glyph = '', hl = '' },
  desktop         = { glyph = '', hl = '' },
  dictconf        = { glyph = '', hl = '' },
  dictdconf       = { glyph = '', hl = '' },
  diff            = { glyph = '', hl = '' },
  dircolors       = { glyph = '', hl = '' },
  docbk           = { glyph = '', hl = '' },
  dockerfile      = { glyph = '', hl = '' },
  dosbatch        = { glyph = '', hl = '' },
  dosini          = { glyph = '', hl = '' },
  dtd             = { glyph = '', hl = '' },
  dtrace          = { glyph = '', hl = '' },
  dts             = { glyph = '', hl = '' },
  dune            = { glyph = '', hl = '' },
  eiffel          = { glyph = '', hl = '' },
  elinks          = { glyph = '', hl = '' },
  elixir          = { glyph = '', hl = '' },
  elm             = { glyph = '', hl = '' },
  erlang          = { glyph = '', hl = '' },
  eruby           = { glyph = '', hl = '' },
  eterm           = { glyph = '', hl = '' },
  expect          = { glyph = '', hl = '' },
  falcon          = { glyph = '', hl = '' },
  fennel          = { glyph = '', hl = '' },
  fetchmail       = { glyph = '', hl = '' },
  fish            = { glyph = '', hl = '' },
  flexwiki        = { glyph = '', hl = '' },
  forth           = { glyph = '', hl = '' },
  fortran         = { glyph = '', hl = '' },
  fpcmake         = { glyph = '', hl = '' },
  framescript     = { glyph = '', hl = '' },
  freebasic       = { glyph = '', hl = '' },
  fstab           = { glyph = '', hl = '' },
  fvwm            = { glyph = '', hl = '' },
  gdb             = { glyph = '', hl = '' },
  gdscript        = { glyph = '', hl = '' },
  gdshader        = { glyph = '', hl = '' },
  git             = { glyph = '', hl = '' },
  gitattributes   = { glyph = '', hl = '' },
  gitcommit       = { glyph = '', hl = '' },
  gitconfig       = { glyph = '', hl = '' },
  gitignore       = { glyph = '', hl = '' },
  gitrebase       = { glyph = '', hl = '' },
  gitsendemail    = { glyph = '', hl = '' },
  go              = { glyph = '', hl = '' },
  gpg             = { glyph = '', hl = '' },
  gprof           = { glyph = '', hl = '' },
  graphql         = { glyph = '', hl = '' },
  groovy          = { glyph = '', hl = '' },
  group           = { glyph = '', hl = '' },
  grub            = { glyph = '', hl = '' },
  gyp             = { glyph = '', hl = '' },
  haml            = { glyph = '', hl = '' },
  hamster         = { glyph = '', hl = '' },
  hare            = { glyph = '', hl = '' },
  haredoc         = { glyph = '', hl = '' },
  haskell         = { glyph = '', hl = '' },
  heex            = { glyph = '', hl = '' },
  help            = { glyph = '', hl = '' },
  hgcommit        = { glyph = '', hl = '' },
  hog             = { glyph = '', hl = '' },
  hostconf        = { glyph = '', hl = '' },
  hostsaccess     = { glyph = '', hl = '' },
  html            = { glyph = '', hl = '' },
  htmldjango      = { glyph = '', hl = '' },
  hurl            = { glyph = '', hl = '' },
  hyprlang        = { glyph = '', hl = '' },
  i3config        = { glyph = '', hl = '' },
  icon            = { glyph = '', hl = '' },
  indent          = { glyph = '', hl = '' },
  initex          = { glyph = '', hl = '' },
  ishd            = { glyph = '', hl = '' },
  j               = { glyph = '', hl = '' },
  java            = { glyph = '', hl = '' },
  javascript      = { glyph = '', hl = '' },
  javascriptreact = { glyph = '', hl = '' },
  jj              = { glyph = '', hl = '' },
  jproperties     = { glyph = '', hl = '' },
  jq              = { glyph = '', hl = '' },
  json            = { glyph = '', hl = '' },
  json5           = { glyph = '', hl = '' },
  jsonc           = { glyph = '', hl = '' },
  jsonnet         = { glyph = '', hl = '' },
  jsp             = { glyph = '', hl = '' },
  julia           = { glyph = '', hl = '' },
  kconfig         = { glyph = '', hl = '' },
  kotlin          = { glyph = '', hl = '' },
  kwt             = { glyph = '', hl = '' },
  ld              = { glyph = '', hl = '' },
  less            = { glyph = '', hl = '' },
  lftp            = { glyph = '', hl = '' },
  libao           = { glyph = '', hl = '' },
  limits          = { glyph = '', hl = '' },
  liquid          = { glyph = '', hl = '' },
  lisp            = { glyph = '', hl = '' },
  livebook        = { glyph = '', hl = '' },
  logcheck        = { glyph = '', hl = '' },
  loginaccess     = { glyph = '', hl = '' },
  logindefs       = { glyph = '', hl = '' },
  logtalk         = { glyph = '', hl = '' },
  lprolog         = { glyph = '', hl = '' },
  lua             = { glyph = '', hl = 'MiniIconsBlue' },
  luau            = { glyph = '', hl = '' },
  lynx            = { glyph = '', hl = '' },
  m3build         = { glyph = '', hl = '' },
  m3quake         = { glyph = '', hl = '' },
  m4              = { glyph = '', hl = '' },
  mail            = { glyph = '', hl = '' },
  mailaliases     = { glyph = '', hl = '' },
  mailcap         = { glyph = '', hl = '' },
  make            = { glyph = '', hl = '' },
  man             = { glyph = '', hl = '' },
  manconf         = { glyph = '', hl = '' },
  markdown        = { glyph = '', hl = '' },
  masm            = { glyph = '', hl = '' },
  matlab          = { glyph = '', hl = '' },
  mermaid         = { glyph = '', hl = '' },
  meson           = { glyph = '', hl = '' },
  mf              = { glyph = '', hl = '' },
  mma             = { glyph = '', hl = '' },
  modconf         = { glyph = '', hl = '' },
  modula2         = { glyph = '', hl = '' },
  modula3         = { glyph = '', hl = '' },
  mp              = { glyph = '', hl = '' },
  mplayerconf     = { glyph = '', hl = '' },
  mrxvtrc         = { glyph = '', hl = '' },
  msmessages      = { glyph = '', hl = '' },
  muttrc          = { glyph = '', hl = '' },
  nanorc          = { glyph = '', hl = '' },
  neomuttrc       = { glyph = '', hl = '' },
  netrc           = { glyph = '', hl = '' },
  nginx           = { glyph = '', hl = '' },
  nim             = { glyph = '', hl = '' },
  nix             = { glyph = '', hl = '' },
  nroff           = { glyph = '', hl = '' },
  nsis            = { glyph = '', hl = '' },
  objc            = { glyph = '', hl = '' },
  objdump         = { glyph = '', hl = '' },
  obse            = { glyph = '', hl = '' },
  ocaml           = { glyph = '', hl = '' },
  occam           = { glyph = '', hl = '' },
  octave          = { glyph = '', hl = '' },
  odin            = { glyph = '', hl = '' },
  ondir           = { glyph = '', hl = '' },
  openvpn         = { glyph = '', hl = '' },
  pamconf         = { glyph = '', hl = '' },
  pascal          = { glyph = '', hl = '' },
  passwd          = { glyph = '', hl = '' },
  pbtxt           = { glyph = '', hl = '' },
  pdf             = { glyph = '', hl = '' },
  perl            = { glyph = '', hl = '' },
  php             = { glyph = '', hl = '' },
  pinfo           = { glyph = '', hl = '' },
  plaintex        = { glyph = '', hl = '' },
  pod             = { glyph = '', hl = '' },
  poefilter       = { glyph = '', hl = '' },
  poke            = { glyph = '', hl = '' },
  postscr         = { glyph = '', hl = '' },
  prisma          = { glyph = '', hl = '' },
  procmail        = { glyph = '', hl = '' },
  prolog          = { glyph = '', hl = '' },
  protocols       = { glyph = '', hl = '' },
  ps1             = { glyph = '', hl = '' },
  ps1xml          = { glyph = '', hl = '' },
  purescript      = { glyph = '', hl = '' },
  pymanifest      = { glyph = '', hl = '' },
  pyrex           = { glyph = '', hl = '' },
  python          = { glyph = '', hl = '' },
  qb64            = { glyph = '', hl = '' },
  qf              = { glyph = '', hl = '' },
  qml             = { glyph = '', hl = '' },
  quake           = { glyph = '', hl = '' },
  quarto          = { glyph = '', hl = '' },
  query           = { glyph = '', hl = '' },
  r               = { glyph = '', hl = '' },
  racc            = { glyph = '', hl = '' },
  racket          = { glyph = '', hl = '' },
  raku            = { glyph = '', hl = '' },
  readline        = { glyph = '', hl = '' },
  registry        = { glyph = '', hl = '' },
  requirements    = { glyph = '', hl = '' },
  rescript        = { glyph = '', hl = '' },
  reva            = { glyph = '', hl = '' },
  rhelp           = { glyph = '', hl = '' },
  rmd             = { glyph = '', hl = '' },
  rnc             = { glyph = '', hl = '' },
  rnoweb          = { glyph = '', hl = '' },
  roc             = { glyph = '', hl = '' },
  routeros        = { glyph = '', hl = '' },
  rpl             = { glyph = '', hl = '' },
  rrst            = { glyph = '', hl = '' },
  rst             = { glyph = '', hl = '' },
  ruby            = { glyph = '', hl = '' },
  rust            = { glyph = '', hl = '' },
  sass            = { glyph = '', hl = '' },
  sbt             = { glyph = '', hl = '' },
  scala           = { glyph = '', hl = '' },
  scdoc           = { glyph = '', hl = '' },
  scheme          = { glyph = '', hl = '' },
  screen          = { glyph = '', hl = '' },
  scss            = { glyph = '', hl = '' },
  sed             = { glyph = '', hl = '' },
  sensors         = { glyph = '', hl = '' },
  services        = { glyph = '', hl = '' },
  setserial       = { glyph = '', hl = '' },
  sexplib         = { glyph = '', hl = '' },
  sgml            = { glyph = '', hl = '' },
  sh              = { glyph = '', hl = '' },
  shada           = { glyph = '', hl = '' },
  sieve           = { glyph = '', hl = '' },
  slint           = { glyph = '', hl = '' },
  slpconf         = { glyph = '', hl = '' },
  slpreg          = { glyph = '', hl = '' },
  slpspi          = { glyph = '', hl = '' },
  solidity        = { glyph = '', hl = '' },
  solution        = { glyph = '', hl = '' },
  spec            = { glyph = '', hl = '' },
  sql             = { glyph = '', hl = '' },
  ssa             = { glyph = '', hl = '' },
  sshconfig       = { glyph = '', hl = '' },
  sshdconfig      = { glyph = '', hl = '' },
  stylus          = { glyph = '', hl = '' },
  sudoers         = { glyph = '', hl = '' },
  svg             = { glyph = '', hl = '' },
  swayconfig      = { glyph = '', hl = '' },
  swift           = { glyph = '', hl = '' },
  swiftgyb        = { glyph = '', hl = '' },
  swig            = { glyph = '', hl = '' },
  sysctl          = { glyph = '', hl = '' },
  systemd         = { glyph = '', hl = '' },
  systemverilog   = { glyph = '', hl = '' },
  tap             = { glyph = '', hl = '' },
  tcl             = { glyph = '', hl = '' },
  tcsh            = { glyph = '', hl = '' },
  terminfo        = { glyph = '', hl = '' },
  tex             = { glyph = '', hl = '' },
  text            = { glyph = '', hl = '' },
  tidy            = { glyph = '', hl = '' },
  tmux            = { glyph = '', hl = '' },
  toml            = { glyph = '', hl = '' },
  treetop         = { glyph = '', hl = '' },
  tt2html         = { glyph = '', hl = '' },
  tutor           = { glyph = '', hl = '' },
  typescript      = { glyph = '', hl = '' },
  typescriptreact = { glyph = '', hl = '' },
  typst           = { glyph = '', hl = '' },
  uci             = { glyph = '', hl = '' },
  udevconf        = { glyph = '', hl = '' },
  udevperm        = { glyph = '', hl = '' },
  udevrules       = { glyph = '', hl = '' },
  unison          = { glyph = '', hl = '' },
  updatedb        = { glyph = '', hl = '' },
  urlshortcut     = { glyph = '', hl = '' },
  usd             = { glyph = '', hl = '' },
  v               = { glyph = '', hl = '' },
  vb              = { glyph = '', hl = '' },
  vdf             = { glyph = '', hl = '' },
  verilog         = { glyph = '', hl = '' },
  vhdl            = { glyph = '', hl = '' },
  vim             = { glyph = '', hl = '' },
  vroom           = { glyph = '', hl = '' },
  vue             = { glyph = '', hl = '' },
  wat             = { glyph = '', hl = '' },
  wget            = { glyph = '', hl = '' },
  wget2           = { glyph = '', hl = '' },
  xcompose        = { glyph = '', hl = '' },
  xdefaults       = { glyph = '', hl = '' },
  xf86conf        = { glyph = '', hl = '' },
  xhtml           = { glyph = '', hl = '' },
  xinetd          = { glyph = '', hl = '' },
  xml             = { glyph = '', hl = '' },
  xmodmap         = { glyph = '', hl = '' },
  xs              = { glyph = '', hl = '' },
  xsd             = { glyph = '', hl = '' },
  xslt            = { glyph = '', hl = '' },
  yaml            = { glyph = '', hl = '' },
  zathurarc       = { glyph = '', hl = '' },
  zig             = { glyph = '', hl = '' },
  zimbu           = { glyph = '', hl = '' },
  zsh             = { glyph = '', hl = '' },

  -- 'mini.nvim'
  minifiles              = { glyph = '󰒲', hl = 'MiniIconsGreen' },
  ['minifiles-help']     = { glyph = '󰒲', hl = 'MiniIconsGreen' },
  mininotify             = { glyph = '󰒲', hl = 'MiniIconsBlue' },
  ['mininotify-history'] = { glyph = '󰒲', hl = 'MiniIconsBlue' },
  minipick               = { glyph = '󰒲', hl = 'MiniIconsCyan' },
  starter                = { glyph = '󰒲', hl = 'MiniIconsYellow' },

  -- Lua plugins
  lazy = { glyph = '󰒲', hl = 'MiniIconsBlue' },
}

-- Extension icons. Keys are mostly for extensions which are either popular or
-- don't have good support in `vim.filetype.match()` (usually failing to
-- recognize filetype by filename and content only).
--stylua: ignore
H.extension_icons = {
  ts = { glyph = '', hl = 'MiniIconsBlue' },
}

-- Path icons. Keys are mostly some popular file/directory basenames and the
-- ones which can conflict with icon detection through extension.
--stylua: ignore
H.path_icons = {
  Makefile = { glyph = '', hl = 'MiniIconsGrey' },
}

-- OS icons. Keys are at least for all icons from Nerd fonts (`nf-linux-*`).
--stylua: ignore
H.os_icons = {
  alma         = { glyph = '', hl = '' },
  alpine       = { glyph = '', hl = '' },
  aosc         = { glyph = '', hl = '' },
  apple        = { glyph = '', hl = '' },
  arch         = { glyph = '󰣇', hl = '' },
  archcraft    = { glyph = '', hl = '' },
  archlabs     = { glyph = '', hl = '' },
  arcolinux    = { glyph = '', hl = '' },
  artix        = { glyph = '', hl = '' },
  biglinux     = { glyph = '', hl = '' },
  centos       = { glyph = '', hl = '' },
  crystallinux = { glyph = '', hl = '' },
  debian       = { glyph = '', hl = '' },
  deepin       = { glyph = '', hl = '' },
  devuan       = { glyph = '', hl = '' },
  elementary   = { glyph = '', hl = '' },
  endeavour    = { glyph = '', hl = '' },
  fedora       = { glyph = '', hl = '' },
  freebsd      = { glyph = '', hl = '' },
  garuda       = { glyph = '', hl = '' },
  gentoo       = { glyph = '󰣨', hl = '' },
  guix         = { glyph = '', hl = '' },
  hyperbola    = { glyph = '', hl = '' },
  illumos      = { glyph = '', hl = '' },
  kali         = { glyph = '', hl = '' },
  kdeneon      = { glyph = '', hl = '' },
  kubuntu      = { glyph = '', hl = '' },
  linux        = { glyph = '', hl = '' },
  locos        = { glyph = '', hl = '' },
  lxle         = { glyph = '', hl = '' },
  mageia       = { glyph = '', hl = '' },
  manjaro      = { glyph = '', hl = '' },
  mint         = { glyph = '󰣭', hl = '' },
  mxlinux      = { glyph = '', hl = '' },
  nixos        = { glyph = '', hl = '' },
  openbsd      = { glyph = '', hl = '' },
  opensuse     = { glyph = '', hl = '' },
  parabola     = { glyph = '', hl = '' },
  parrot       = { glyph = '', hl = '' },
  pop_os       = { glyph = '', hl = '' },
  postmarketos = { glyph = '', hl = '' },
  puppylinux   = { glyph = '', hl = '' },
  qubesos      = { glyph = '', hl = '' },
  raspberry_pi = { glyph = '', hl = '' },
  redhat       = { glyph = '󱄛', hl = '' },
  rocky        = { glyph = '', hl = '' },
  sabayon      = { glyph = '', hl = '' },
  slackware    = { glyph = '', hl = '' },
  solus        = { glyph = '', hl = '' },
  tails        = { glyph = '', hl = '' },
  trisquel     = { glyph = '', hl = '' },
  ubuntu       = { glyph = '', hl = '' },
  vanillaos    = { glyph = '', hl = '' },
  void         = { glyph = '', hl = '' },
  windows      = { glyph = '', hl = '' },
  xerolinux    = { glyph = '', hl = '' },
  zorin        = { glyph = '', hl = '' },
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
    local ext = string.match(name, '%.([^%.]+)$')
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

return MiniIcons
