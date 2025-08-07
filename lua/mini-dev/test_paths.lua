local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq, no_eq = helpers.expect, helpers.expect.equality, helpers.expect.no_equality
local new_set = MiniTest.new_set

local T = new_set({
  hooks = {
    pre_case = function() child.setup() end,
    post_once = child.stop,
  },
})

T['test packpath'] = function()
  local path_data = child.lua([[
    local function get_pack_dir()
      return vim.fs.joinpath(vim.fn.stdpath('data'), 'site')
    end

    local pack_dir = get_pack_dir()
    if not vim.tbl_contains(vim.opt.packpath:get(), pack_dir) then
      vim.opt.packpath:prepend(pack_dir)
    end

    return {
      pack_dir = pack_dir,
      pack_dir_2 = (vim.fn.stdpath('data') .. '/site'),
      packpath = vim.o.packpath,
    }
  ]])
  eq(path_data)
end

T['test manually different but same packpath entries'] = function()
  local path_data = child.lua([[
    local maybe_prepend = function(path)
      if not vim.tbl_contains(vim.opt.packpath:get(), path) then
        vim.opt.packpath:prepend(path)
      end
    end

    local pack_dir_1 = vim.fs.joinpath(vim.fn.stdpath('data'), 'site')
    local pack_dir_2 = vim.fn.stdpath('data') .. '/site'
    local pack_dir_3 = vim.fn.stdpath('data') .. '\\site'

    maybe_prepend(pack_dir_1)
    maybe_prepend(pack_dir_2)
    maybe_prepend(pack_dir_3)

    return {
      pack_dir_1 = pack_dir_1,
      pack_dir_2 = pack_dir_2,
      pack_dir_3 = pack_dir_3,
      packpath = vim.o.packpath,
    }
  ]])
  eq(path_data)
end

return T
