if !exists('g:vscode')
  " Define spelling dictionaries
  set spelllang=en,ru
  " Set default manual spelling dictionary
  set spellfile=~/.nvim/spell/en.utf-8.add
  " Add spellcheck options for autocomplete
  set complete+=kspell
  " Use specific dictionaries
  set dictionary=~/.config/nvim/dict/english.txt
endif
