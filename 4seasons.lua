local minicolors = require('mini.colors')
local minihues = require('mini.hues')

_G.showcase_fg = function(bg, fg_l, fg_hue, accent, saturation)
  local fg = minicolors.convert({ l = fg_l, c = 2, h = fg_hue }, 'hex')
  local palette = minihues.make_palette({ background = bg, foreground = fg, accent = accent, saturation = saturation })
  vim.cmd('doautocmd ColorSchemePre')
  minihues.apply_palette(palette)
  vim.cmd('doautocmd ColorScheme')

  -- Create highlight groups for demo
  local hi = function(name, bg_color) vim.api.nvim_set_hl(0, name, { bg = palette[bg_color] }) end
  hi('FourSeasonsRed', 'red_bg')
  hi('FourSeasonsOrange', 'orange_bg')
  hi('FourSeasonsYellow', 'yellow_bg')
  hi('FourSeasonsGreen', 'green_bg')
  hi('FourSeasonsCyan', 'cyan_bg')
  hi('FourSeasonsAzure', 'azure_bg')
  hi('FourSeasonsBlue', 'blue_bg')
  hi('FourSeasonsPurple', 'purple_bg')

  vim.defer_fn(function()
    print(fg_hue)
    vim.cmd('redraw!')
    local ok, char = pcall(vim.fn.getcharstr)
    if not ok or char == '\27' then return end
    showcase_fg(bg, fg_l, fg_hue + (char == vim.keycode('<Left>') and -1 or 1), accent, saturation)
  end, 1)
end

_G.make_demo_buf = function()
  local buf_id = vim.fn.bufadd('4seasons-demo')
  vim.bo[buf_id].buflisted = true
  vim.bo[buf_id].buftype = 'nofile'
  local line = string.rep(' aaa ', 8)
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, { line, line })
  vim.api.nvim_set_current_buf(buf_id)

  local hl_groups = {
    'FourSeasonsRed',
    'FourSeasonsOrange',
    'FourSeasonsYellow',
    'FourSeasonsGreen',
    'FourSeasonsCyan',
    'FourSeasonsAzure',
    'FourSeasonsBlue',
    'FourSeasonsPurple',
  }

  local ns_id = vim.api.nvim_create_namespace('4seasons-demo')
  vim.api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)
  for i = 1, 8 do
    local col = 5 * (i - 1)
    vim.api.nvim_buf_set_extmark(buf_id, ns_id, 0, col, { end_row = 0, end_col = col + 4, hl_group = hl_groups[i] })
    vim.api.nvim_buf_set_extmark(buf_id, ns_id, 1, col, { end_row = 1, end_col = col + 4, hl_group = hl_groups[i] })
  end
end

-- showcase_fg('#11262d', 85, 270, 'azure', 'lowmedium') -- miniwinter
-- showcase_fg('#1c2617', 85, 180, 'green', 'medium')    -- minispring
-- showcase_fg('#27211e', 85, 90,  'yellow', 'medium')   -- minisummer
-- showcase_fg('#262029', 85, 360, 'red', 'lowmedium')   -- miniautumn
