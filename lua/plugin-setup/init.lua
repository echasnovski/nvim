-- Source all plugin configurations
local files = vim.fn.globpath('$HOME/.config/nvim/lua/plugin-setup/', '*.lua')

for _, f in pairs(vim.fn.split(files)) do
  if f:find('init%.lua$') == nil then vim.cmd('luafile ' .. f) end
end
