vim.g.startify_session_dir = '~/.config/nvim/session'

vim.g.startify_lists = {
  { type = 'sessions', header = { '   Sessions' } },
  { type = 'bookmarks', header = { '   Bookmarks' } },
}

vim.g.startify_bookmarks = { { n = '~/.config/nvim/' } }

vim.g.startify_custom_header = 'startify#pad(startify#fortune#boxed())'
vim.g.startify_fortune_use_unicode = 1

vim.g.startify_skiplist = { 'COMMIT_EDITMSG' }

vim.g.startify_session_autoload = 1
vim.g.startify_session_persistence = 1
