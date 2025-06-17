-- Setup ======================================================================
require('mini.pick').setup({
  window = { config = { width = vim.o.columns, height = vim.o.lines } },
})
require('mini.extra').setup()

require('mini.icons').setup()
vim.cmd('colorscheme miniwinter')
vim.o.laststatus = 0
vim.o.showtabline = 0
vim.o.cmdheight = 0
vim.o.ignorecase = true
vim.o.smartcase = true

-- Pickers ====================================================================
local in_path = '/tmp/nvim/in-file'
local out_path = '/tmp/nvim/out-file'

local write_and_quit = function(path, lines)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
  vim.fn.writefile(lines, path)
  vim.cmd('qall!')
end

local source = {
  choose = function(item) write_and_quit(out_path, { item }) end,
  choose_marked = function(items) write_and_quit(out_path, items) end,
}

local show_with_icons = function(buf_id, items, query)
  MiniPick.default_show(buf_id, items, query, { show_icons = true })
end

_G.pick_file_cli = vim.schedule_wrap(function()
  MiniPick.builtin.files(nil, { source = source })
  vim.cmd('qall!')
end)

_G.pick_dir_cli = vim.schedule_wrap(function()
  -- Still use `rg` to ignore paths that should be ignored.
  -- Unfortunately, `rg` doesn't have `--directories` flag (by design, as out
  -- of scope). So manually extract directories.
  -- NOTE: This will omit empty directories (because `rg` will ignore it).
  local extract_directories = function(files)
    local dir_map = {}
    for _, f in ipairs(files) do
      dir_map[vim.fs.dirname(f)] = true
    end
    dir_map['.'] = nil
    local res = vim.tbl_keys(dir_map)
    table.sort(res)
    return res
  end

  local set_items_from_rg = function(rg_output)
    local files = vim.split(rg_output.stdout, '\n')
    local directories = extract_directories(files)
    MiniPick.set_picker_items(directories)
  end

  local items = function()
    local cmd = { 'rg', '--files', '--hidden', '--sort-files' }
    vim.system(cmd, nil, vim.schedule_wrap(set_items_from_rg))
  end

  local dir_source = vim.deepcopy(source)
  dir_source.name = 'Directories'
  dir_source.items = items
  dir_source.show = show_with_icons
  MiniPick.start({ source = dir_source })
  vim.cmd('qall!')
end)

_G.pick_from_file = vim.schedule_wrap(function()
  local items = vim.fn.readfile(in_path)
  local dir_source = vim.deepcopy(source)
  dir_source.name = 'Input items'
  dir_source.items = items
  MiniPick.start({ source = dir_source })
  vim.cmd('qall!')
end)
