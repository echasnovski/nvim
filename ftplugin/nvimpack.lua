local ns = vim.api.nvim_create_namespace('nvim.pack.confirm')
vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)

local priority = 100
local hi_range = function(lnum, start_col, end_col, hl, pr)
  local opts = { end_row = lnum - 1, end_col = end_col, hl_group = hl, priority = pr or priority }
  vim.api.nvim_buf_set_extmark(0, ns, lnum - 1, start_col, opts)
end

local h2_hl = nil

local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
for i, l in ipairs(lines) do
  local cur_group = l:match('^# (%S+)')
  local cur_info = l:match('^Path: +') or l:match('^Source: +') or l:match('^State[^:]*: +')
  if cur_group ~= nil then
    -- Header 1
    hi_range(i, 0, l:len(), 'PackTitle')
    h2_hl = 'PackTitle' .. cur_group
  elseif l:find('^## (.+)$') ~= nil then
    -- Header 2
    hi_range(i, 0, l:len(), h2_hl)
  elseif cur_info ~= nil then
    -- Plugin info
    local end_col = l:match('(). +%b()$') or l:len()
    hi_range(i, cur_info:len(), end_col, 'PackInfo')

    -- Plugin state after update
    local col = l:match('() %b()$') or l:len()
    hi_range(i, col, l:len(), 'PackHint')
  elseif l:match('^[<>] ') then
    -- Change log
    local hl_group = 'PackChange' .. (l:sub(1, 1) == '>' and 'Added' or 'Removed')
    hi_range(i, 0, l:len(), hl_group)

    -- Messages with breaking changes
    local col = l:match('│() %S+!:') or l:match('│() %S+%b()!:') or l:len()
    hi_range(i, col, l:len(), 'PackMsgBreaking', priority + 1)
  elseif l:match('^• ') then
    -- Available newer versions
    hi_range(i, 4, l:len(), 'PackHint')
  end
end
