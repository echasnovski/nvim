-- MIT License Copyright (c) 2021 Evgeni Chasnovski
--
-- Lua module for *minimal* buffer removing (unshow, delete, wipeout), which
-- saves window layout (opposite to builtin Neovim's commands). This is mostly
-- a Lua implementation of
-- [bclose.vim](https://vim.fandom.com/wiki/Deleting_a_buffer_without_closing_the_window).
-- Other alternatives:
-- - [vim-bbye](https://github.com/moll/vim-bbye)
-- - [vim-sayonara](https://github.com/mhinz/vim-sayonara)
--
-- This module doesn't need to get activated, but it can be done to improve
-- usability. To activate, put this file somewhere into 'lua' folder and call
-- module's `setup()`. For example, put as 'lua/mini/bufremove.lua' and execute
-- `require('mini.bufremove').setup()` Lua code. It may have `config` argument
-- which should be a table overwriting default values using same structure.
--
-- Default `config`:
-- {
--   -- Whether to set Vim's settings for buffers (allow hidden buffers)
--   set_vim_settings = true
-- }
--
-- Features:
-- -  Which buffer to show in window(s) after its current buffer is removed is
--   decided by the algorithm:
--     - If alternate buffer (see `:h CTRL-^`) is listed (see `:h
--       buflisted()`), use it.
--     - If previous listed buffer (see `:h bprevious`) is different, use it.
--     - Otherwise create a scratch one with `vim.api.nvim_create_buf(true,
--       true)` and use it.
-- - Functions are described in their comments.

-- Module and its helper
local MiniBufremove = {}
local H = {}

-- Module setup
function MiniBufremove.setup(config)
  -- Export module
  _G.MiniBufremove = MiniBufremove

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)
end

-- Module config
MiniBufremove.config = {
  -- Whether to set Vim's settings for buffers
  set_vim_settings = true,
}

-- Module functionality
---- Delete buffer `buf_id` with `:bdelete` after unshowing it.
---- @param buf_id Identifier of a buffer to use (0 for current). Default: 0.
---- @param force Whether to ignore unsaved changes (using `!` version of
----   command). Default: false.
---- @return Boolean showing if operation was successful.
function MiniBufremove.delete(buf_id, force)
  return H.unshow_and_cmd(buf_id, force, 'bdelete')
end

---- Wipeout buffer `buf_id` with `:bwipeout` after unshowing it.
---- @param buf_id Identifier of a buffer to use (0 for current). Default: 0.
---- @param force Whether to ignore unsaved changes (using `!` version of
----   command). Default: false.
---- @return Boolean showing if operation was successful.
function MiniBufremove.wipeout(buf_id, force)
  return H.unshow_and_cmd(buf_id, force, 'bwipeout')
end

---- Stop showing buffer `buf_id` in all windows
---- @param buf_id Identifier of a buffer to use (0 for current). Default: 0.
---- @return Boolean showing if operation was successful.
function MiniBufremove.unshow(buf_id)
  buf_id = H.normalize_buf_id(buf_id)

  if not H.is_valid_id(buf_id, 'buffer') then
    return false
  end

  vim.tbl_map(MiniBufremove.unshow_in_window, vim.fn.win_findbuf(buf_id))

  return true
end

---- Stop showing current buffer of window `win_id`
---- @param win_id Identifier of a window to use (0 for current). Default: 0.
---- @return Boolean showing if operation was successful.
function MiniBufremove.unshow_in_window(win_id)
  win_id = (win_id == nil) and 0 or win_id

  if not H.is_valid_id(win_id, 'window') then
    return false
  end

  local cur_buf = vim.api.nvim_win_get_buf(win_id)

  -- Temporary use window `win_id` as current to have Vim's functions working
  vim.api.nvim_win_call(win_id, function()
    -- Try using alternate buffer
    local alt_buf = vim.fn.bufnr('#')
    if alt_buf ~= cur_buf and vim.fn.buflisted(alt_buf) == 1 then
      vim.api.nvim_win_set_buf(win_id, alt_buf)
      return
    end

    -- Try using previous buffer
    vim.cmd([[bprevious]])
    if cur_buf ~= vim.api.nvim_win_get_buf(win_id) then
      return
    end

    -- Create new listed scratch buffer
    local new_buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_win_set_buf(win_id, new_buf)
  end)

  return true
end

-- Helper data
---- Module default config
H.default_config = MiniBufremove.config

-- Helper functions
---- Settings
function H.setup_config(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({ set_vim_settings = { config.set_vim_settings, 'boolean' } })

  return config
end

function H.apply_config(config)
  MiniBufremove.config = config

  if config.set_vim_settings then
    vim.o.hidden = true -- Allow hidden buffers
  end
end

-- Removing implementation
function H.unshow_and_cmd(buf_id, force, cmd)
  buf_id = H.normalize_buf_id(buf_id)
  force = (force == nil) and false or force

  if not H.is_valid_id(buf_id, 'buffer') then
    return false
  end

  if not H.can_remove(buf_id, force, 'delete') then
    return false
  end

  -- Unshow buffer from all windows
  MiniBufremove.unshow(buf_id)

  -- Execute command
  local command = string.format('%s%s %d', cmd, force and '!' or '', buf_id)
  vim.cmd(command)

  return true
end

-- Utilities
function H.is_valid_id(x, type)
  local is_valid = false
  if type == 'buffer' then
    is_valid = vim.api.nvim_buf_is_valid(x)
  elseif type == 'window' then
    is_valid = vim.api.nvim_win_is_valid(x)
  end

  if not is_valid then
    H.notify(string.format('%s is not a valid %s id.', tostring(x), type))
  end
  return is_valid
end

---- Check if buffer can be removed with `MiniBufremove.fun_name` function
function H.can_remove(buf_id, force, fun_name)
  if force then
    return true
  end

  if vim.api.nvim_buf_get_option(buf_id, 'modified') then
    H.notify(
      string.format(
        'Buffer %d has unsaved changes. Use `MiniBufremove.%s(%d, true)` to force.',
        buf_id,
        fun_name,
        buf_id
      )
    )
    return false
  end
  return true
end

---- Compute 'true' buffer id (strictly positive integer). Treat `nil` and 0 as
---- current buffer.
function H.normalize_buf_id(buf_id)
  if buf_id == nil or buf_id == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return buf_id
end

function H.notify(msg)
  vim.notify(string.format('(mini.bufremove) %s', msg))
end

return MiniBufremove
