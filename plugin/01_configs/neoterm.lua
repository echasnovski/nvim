-- Enable bracketed paste
vim.g.neoterm_bracketed_paste = 1

-- Default python REPL
vim.g.neoterm_repl_python = 'ipython'

-- Default R REPL
vim.g.neoterm_repl_r = 'radian'

-- Don't add extra call to REPL when sending
vim.g.neoterm_direct_open_repl = 1

-- Open terminal to the right by default
vim.g.neoterm_default_mod = 'vertical'

-- Go into insert mode when terminal is opened
vim.g.neoterm_autoinsert = 1

-- Scroll to recent command when it is executed
vim.g.neoterm_autoscroll = 1

-- Change default shell to zsh (if it is installed)
if vim.fn.executable('zsh') == 1 then
  vim.g.neoterm_shell = 'zsh'
end
