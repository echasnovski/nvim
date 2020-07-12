" Use more convenient (for me) exclusive visual selection
set selection=exclusive

" Russian keyboard mappings
set langmap=ё№йцукенгшщзхъфывапролджэячсмитьбюЁЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ;`#qwertyuiop[]asdfghjkl\\;'zxcvbnm\\,.~QWERTYUIOP{}ASDFGHJKL:\\"ZXCVBNM<>

nmap Ж :
" yank
nmap Н Y
nmap з p
nmap ф a
nmap щ o
nmap г u
nmap З P

" Leader key
let mapleader = "\<Space>"

" Arguments for 'targets.vim' plugin
let g:targets_aiAI = 'a  i'

if exists('g:vscode')
	" Mappings for code commenting
	xmap gc  <Plug>VSCodeCommentary
	nmap gc  <Plug>VSCodeCommentary
	omap gc  <Plug>VSCodeCommentary
	nmap gcc <Plug>VSCodeCommentaryLine

	" Workaround for executing visual selection in VS Code (for example, in Python interactive window)
	function! s:vsCodeExecLineOrSelection(cur_mode, vscode_command)
	    if a:cur_mode == "normal"
		" Visually select current line
		normal! V
		let visualmode = "V"
	    else
		" My guess is that this is probably needed because visual selection is 'reset' before function is called
		normal! gv
		let visualmode = visualmode()
	    endif

	    if visualmode == "V"
		let startLine = line("v")
		let endLine = line(".")
		call VSCodeNotifyRange(a:vscode_command, startLine, endLine, 1)
	    else
		let startPos = getpos("'<")
		let endPos = getpos("'>")
		" Here selection `viw` works as expected (executing whole word) only in case `selection` is set to `exclusive`.
		call VSCodeNotifyRangePos(a:vscode_command, startPos[1], endPos[1], startPos[2], endPos[2], 1)
	    endif

	    " Escape to normal mode and go to start of next line (line following selection). This also removes visual selection of VS Code.
            " Waiting for 100ms is negligible from user perspective but seems to be crucial when working remotely. If absend, following commands seem to execute before sending range to remote computer which upon delivery will execute the wrong range (usually a single line after desired selection).
            sleep 100m
	    execute "normal! \<esc>`\>"
	    if line(".") == line("$")
		" If cursor is at the last line of a file, create next and move to it
		execute "normal! o\<esc>"
	    else
		execute "normal! j^"
	    endif
	endfunction

	xnoremap <silent> <Leader>p :<C-u>call <SID>vsCodeExecLineOrSelection("visual", "python.datascience.execSelectionInteractive")<CR>
	nnoremap <silent> <Leader>p :<C-u>call <SID>vsCodeExecLineOrSelection("normal", "python.datascience.execSelectionInteractive")<CR>

	xnoremap <silent> <Leader>r :<C-u>call <SID>vsCodeExecLineOrSelection("visual", "r.runSelection")<CR>
	nnoremap <Leader>r :<C-u>call VSCodeCall("r.runSelection")<CR>
endif
