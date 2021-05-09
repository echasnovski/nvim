" Add '""' and '"""' as comment symbols to be able to format comment block
" with `gq` and insert comment string when hitting <CR>.
set comments=:\"\"\",:\"\",:\"

set shiftwidth=2

" Don't add autopair to '"' but do add to '\''
call luaeval("MiniPairs.remap_quotes()")
