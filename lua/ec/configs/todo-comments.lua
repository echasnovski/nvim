require('todo-comments').setup({
  signs = false,
  highlight = {
    before = '',
    keyword = 'bg',
    after = '',
    -- Match without the extra colon
    pattern = [[.*<(KEYWORDS)\s*]],
  },
  search = {
    -- Match without the extra colon
    pattern = [[\b(KEYWORDS)\b]],
  },
})
