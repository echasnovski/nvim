local ok, todo = pcall(require, 'todo-comments')
if not ok then return end

todo.setup{
  highlight = {
    before = "",
    keyword = "bg",
    after = ""
  },
  pattern = "(KEYWORDS)"
}
