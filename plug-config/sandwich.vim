" Respect '.' symbol in function names
let g:sandwich#magicchar#f#patterns = [
\   {
\     'header' : '\<\%(\h\k*\.\)*\h\k*',
\     'bra'    : '(',
\     'ket'    : ')',
\     'footer' : '',
\   },
\ ]
