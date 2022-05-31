return {
  h = function(...)
    local t = { 1, 2, 3 }
    local dots = { ... }
    return vim.tbl_filter(function(x)
      local ok, err = pcall(MiniTest.expect.equality, unpack(dots))
      error(err)
    end, t)
  end,

  new_child_neovim = function()
    local child = MiniTest.new_child_neovim()

    function child.setup()
      child.restart({ '-u', 'tests/minimal_init.vim' })

      -- Ensure new empty readable buffer
      -- NOTE: for some unimaginable reason this also speeds up test execution by
      -- factor of almost two (was 4:40 minutes; became 2:40 minutes)
      child.cmd('enew')

      -- Also work:
      -- child.cmd('tabedit')
      -- child.api.nvim_set_current_buf(child.api.nvim_create_buf(true, false))
      -- child.cmd('new')

      -- Don't work:
      -- - Having `enew` as last thing in 'scripts/minimal_init.vim'
      -- child.api.nvim_eval('1')
      -- vim.api.nvim_buf_set_lines(0, 0, -1, true, {})
      -- child.api.nvim_buf_delete(child.api.nvim_create_buf(true, true), {})
      -- child.cmd('vsplit')
    end

    function child.set_lines(arr, start, finish)
      if type(arr) == 'string' then
        arr = vim.split(arr, '\n')
      end

      child.api.nvim_buf_set_lines(0, start or 0, finish or -1, false, arr)
    end

    function child.get_lines(start, finish)
      return child.api.nvim_buf_get_lines(0, start or 0, finish or -1, false)
    end

    function child.set_cursor(line, column, win_id)
      child.api.nvim_win_set_cursor(win_id or 0, { line, column })
    end

    function child.get_cursor(win_id)
      return child.api.nvim_win_get_cursor(win_id or 0)
    end

    -- Work with 'mini.nvim':
    -- - `mini_load` - load with "normal" table config
    -- - `mini_load_strconfig` - load with "string" config, which is still a
    --   table but with string values. Final loading is done by constructing
    --   final string table. Needed to be used if one of the config entries is a
    --   function (as currently there is no way to communicate a function object
    --   through RPC).
    -- - `mini_unload` - unload module and revert common side effects.
    function child.mini_load(name, config)
      local lua_cmd = ([[require('mini.%s').setup(...)]]):format(name)
      child.lua(lua_cmd, { config })
    end

    function child.mini_load_strconfig(name, strconfig)
      local t = {}
      for key, val in pairs(strconfig) do
        table.insert(t, key .. ' = ' .. val)
      end
      local str = string.format('{ %s }', table.concat(t, ', '))

      local command = ([[require('mini.%s').setup(%s)]]):format(name, str)
      child.lua(command)
    end

    function child.mini_unload(name)
      local module_name = 'mini.' .. name
      local tbl_name = 'Mini' .. name:sub(1, 1):upper() .. name:sub(2)

      -- Unload Lua module
      child.lua(([[package.loaded['%s'] = nil]]):format(module_name))

      -- Remove global table
      child.lua(('_G[%s] = nil'):format(tbl_name))

      -- Remove autocmd group
      if child.fn.exists('#' .. tbl_name) == 1 then
        -- NOTE: having this in one line as `'augroup %s | au! | augroup END'`
        -- for some reason seemed to sometimes not execute `augroup END` part.
        -- That lead to a subsequent bare `au ...` calls to be inside `tbl_name`
        -- group, which gets empty after every `require(<module_name>)` call.
        child.cmd(('augroup %s'):format(tbl_name))
        child.cmd('au!')
        child.cmd('augroup END')
      end
    end

    return child
  end,
}
