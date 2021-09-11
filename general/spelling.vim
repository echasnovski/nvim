" Notes:
" - Vim should be able to automatically detect spelling files from 'spell/'
"   folder.
if !exists('g:vscode')
  " Define spelling dictionaries
  set spelllang=en,ru
  " Add spellcheck options for autocomplete
  set complete+=kspell
  " Use specific dictionaries
  set dictionary=$HOME/.config/nvim/misc/dict/english.txt

  " Treat parts of camelCase words as seprate words
  set spelloptions=camel
endif
