local has_wk, wk = pcall(require, 'which-key')
if not has_wk then
  return
end

wk.setup({
  plugins = {
    marks = true,
    registers = true,
    spelling = false,
    presets = {
      operators = false,
      motions = false,
      text_objects = false,
      windows = true,
      nav = true,
      z = true,
      g = true,
    },
  },
  window = { padding = { 0, 0, 0, 0 } },
  layout = { height = { min = 1, max = 10 } },
})

-- Mappings should already be done at this point. Set up 'which-key' only with
-- mapping names.
local function tree_remove_cmd(tree)
  return vim.tbl_map(function(t)
    if type(t) ~= 'table' then
      return t
    end

    -- If command's name is present, return it
    if type(t[2]) == 'string' then return t[2] end

    -- Otherwise further traverse tree
    return tree_remove_cmd(t)
  end, tree)
end

-- Use
wk.register(tree_remove_cmd(_G.leader_nmap), { mode = 'n', prefix = '<leader>' })
wk.register(tree_remove_cmd(_G.leader_xmap), { mode = 'x', prefix = '<leader>' })
