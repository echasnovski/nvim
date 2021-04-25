local ok, trouble = pcall(require, 'trouble')
if not ok then return end

trouble.setup{
  auto_fold = true
}
