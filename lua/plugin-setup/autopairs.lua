local has_npairs, npairs = pcall(require, 'nvim-autopairs')
if not has_npairs then return end

npairs.setup()

-- Disable autopair of `"` in '.vim' files as it is a comment string
npairs.get_rule('"')
  :with_pair(function() return vim.bo.filetype ~= 'vim' end)
