-- TODO:
--
-- - Code:
--   - Decide if this needs events.
--
-- - Docs:
--
-- - Test:

--- *mini.input* Get user input
---
--- MIT License Copyright (c) 2026 Evgeni Chasnovski

--- Features:
---
--- - Get user input with full customizability of how keypresses are handled and
---   how the current state is shown.
---
--- - Built-in configurable views as floating window, virtual line, virtual text.
---
--- - Implementation is non-blocking but waits to return the input.
---
--- - Can work in any mode without requiring it to change.
---
--- - |vim.ui.input()| implementation. To adjust, use |MiniInput.ui_input()| or
---   save-restore `vim.ui.input` manually after calling |MiniInput.setup()|.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.input').setup({})` (replace `{}`
--- with your `config` table). It will create global Lua table `MiniInput` which
--- you can use for scripting or manually (with `:lua MiniInput.*`).
---
--- See |MiniInput.config| for `config` structure and default values.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.miniinput_config` which should have same structure as
--- `MiniInput.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons ~
---
--- - [folke/snacks.nvim#input](https://github.com/folke/snacks.nvim):
---     - Does not wait for user
---
--- - |input()|:
---     - ...
---
--- # Highlight groups ~
---
--- - `MiniInputBorder` - border of a floating window.
--- - `MiniInputNormal` - basic foreground/background.
--- - `MiniInputPrefix` - possible prefix shown in a prompt area.
--- - `MiniInputPrompt` - prompt of a floating window.
---@tag MiniInput

--- # General ~
---
--- ## Default value ~
---
--- `MiniInput.get({ input = { 'Default' } })`.
---
--- # View ~
---
--- ## No view ~
---
--- # Handler ~
---
--- ## Custom mappings ~
---@tag MiniInput-examples

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local

-- Module definition ==========================================================
MiniInput = {}
H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniInput.config|.
---
---@usage >lua
---   require('mini.input').setup() -- use default config
---   -- OR
---   require('mini.input').setup({}) -- replace {} with your config table
--- <
MiniInput.setup = function(config)
  -- Export module
  _G.MiniInput = MiniInput

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Create default highlighting
  H.create_default_hl()

  -- Set custom implementation
  vim.ui.input = MiniInput.ui_input
end

--- Defaults ~
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # View ~
---
--- # Handler ~
MiniInput.config = {
  -- Function to handle key presses
  -- TODO: Maybe find a better name
  handler = nil,

  -- Function to show the input state
  view = nil,
}
--minidoc_afterlines_end

--- Get input from the user
---@return string|nil User input if accepted or `nil` if canceled.
MiniInput.get = function(state, opts)
  H.check_type('state', state, 'table')
  state = H.state_new(vim.deepcopy(state))
  H.state_set(state, true)
  H.state.status = 'progress'

  -- TODO: Apply view
end

--- A |vim.ui.input()| implementation
---
--- Notes:
--- - Doesn't respect `opts.highlight` in favor of user controlled `config.view`.
---
---@usage To preserve original `vim.ui.input()`: >lua
---
---   local ui_input_orig = vim.ui.input
---   require('mini.input').setup()
---   vim.ui.input = ui_input_orig
--- <
MiniInput.ui_input = function(opts, on_confirm)
  opts = opts or {}
  local state = { completion = opts.completion, input = { opts.default }, prompt = opts.prompt }
  on_confirm(MiniInput.get(state))
end

--- Get current input state
---
--- It stores information about the current state of the user input.
--- Can be `nil` to indicate that there is no active user input.
---
--- During user input, it is a table with the following fields:
--- - <caret> `(number)` - current input position to modify output, i.e. new key will
---   be added at this (character, not byte) index.
--- - <completion> `(string|nil)` - same as in |input()|.
--- - <data> `(table)` - information to be reused during single input session.
--- - <input> `(table)` - string array with full history of keypresses from the user.
---   Each element is usually an output of |getcharstr()|, but can be any string
---   of any length (if set with |MiniInput.set_state()|).
---   Use `input[#input]` to get the latest key press.
--- - <output> `(string)` - current result of the user input.
--- - <prompt> `(string|nil)` - intention of the input.
--- - <secret> `(boolean)` - whether input session is for sensitive information
---   and should be hidden.
--- - <status> `(string)` - one of `"start"`, `"progress"`, `"accept"`, `"cancel"`.
---
---@return table|nil Current state if input is active, `nil` otherwise.
---
---@usage Together with |MiniInput.set_state()| can be used to perform educated
---   actions during user input. For example: >lua
---
---   -- TODO
--- <
MiniInput.get_state = function() return vim.deepcopy(H.state) end

--- Set current input state
---
---@param state table Parts of the state to be updated. See |MiniInput.get_state()|
---   for available fields. Notes:
---   - Field <input> is allowed to only be equal or appeend to current state.
---   - Field <secret> is ignored to be not allow overriding it.
---   - Field <status> can not be `"start"`, as it is set once by |MiniInput.get()|.
MiniInput.set_state = function(state)
  if H.state == nil then return end

  H.state_set(state, false)
  -- TODO: Apply view
end

--- Default key handler
MiniInput.default_handler = function(state, opts)
  -- TODO
end

--- View generators
---
--- This is a table with function elements. Call to actually get a view function.
MiniInput.gen_view = {}

--- Floating window view
MiniInput.gen_view.floating = function(opts)
  return function()
    -- TODO
  end
end

--- Virtual line view
MiniInput.gen_view.virtline = function(opts)
  return function()
    -- TODO
  end
end

--- Virtual text view
MiniInput.gen_view.virttext = function(opts)
  return function()
    -- TODO
  end
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniInput.config)

-- Current state of user input
H.state = nil

-- General purpose cache
H.cache = {}

-- Namespaces
H.ns_id = {
  view = vim.api.nvim_create_namespace('MiniInputView'),
}

-- Timers
H.timers = {
  getcharstr = vim.loop.new_timer(),
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('view', config.view, 'function', true)
  H.check_type('handler', config.handler, 'function', true)

  return config
end

H.apply_config = function(config) MiniInput.config = config end

H.create_default_hl = function()
  local hi = function(name, opts)
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end

  hi('MiniInputBorder', { link = 'FloatBorder' })
  hi('MiniInputNormal', { link = 'NormalFloat' })
  hi('MiniInputPrefix', { link = 'DiagnosticHint' })
  hi('MiniInputPrompt', { link = 'FloatTitle' })
end

H.get_config = function() return vim.tbl_deep_extend('force', MiniInput.config, vim.b.miniinput_config or {}) end

-- State ----------------------------------------------------------------------
H.state_new = function(state)
  state.caret = state.caret or 1
  state.data = state.data or {}
  state.input = state.input or {}
  state.output = state.output or ''
  if state.secret == nil then state.secret = false end
  state.status = 'start'
end

H.state_set = function(x, init)
  H.check_type('state', x, 'table')
  local new = vim.tbl_deep_extend('force', H.state, x)
  if not init then
    new.secret = H.state.secret
    new.status = new.status == 'start' and 'progress' or new.status
  end
  H.state_validate(new)

  -- TODO: Validate that `new.input` is equal or appends to `H.state.input`
  -- I.e. do not allow overriding history.

  -- TODO: If there is a new input, append it one by one with calling `handler`
  -- on each iteration.

  H.state = new
end

H.state_validate = function(x)
  H.check_type('state.caret', x.caret, 'number')
  H.check_type('state.completion', x.completion, 'string', true)
  H.check_type('state.data', x.data, 'table')
  if not H.islist(x.input) then H.error('`state.input` should be array') end
  for _, s in ipairs(x.input) do
    if type(s) ~= 'string' then H.error('`state.input` should be array of strings') end
  end
  H.check_type('state.output', x.output, 'string')
  H.check_type('state.prompt', x.output, 'string', true)
  H.check_type('state.secret', x.secret, 'boolean')
  if not (x.status == 'start' or x.status == 'progress' or x.status == 'accept' or x.status == 'cancel') then
    H.error('`state.status` should be one of "start", "progress", "accept", "cancel"')
  end
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.input) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.notify = function(msg, level_name, silent)
  if not silent then vim.notify('(mini.input) ' .. msg, vim.log.levels[level_name]) end
end

H.getcharstr = function(lmap)
  -- Ensure that redraws still happen
  H.timers.getcharstr:start(0, 10, H.redraw_scheduled)
  H.cache.is_in_getcharstr = true
  local ok, char = pcall(vim.fn.getcharstr)
  H.cache.is_in_getcharstr = nil
  H.timers.getcharstr:stop()

  -- Terminate if no input or on hard-coded <C-c>
  if not ok or char == '' or char == '\3' then return end
  -- Respect language mappings only if needed
  return vim.o.iminsert == 0 and char or (lmap[char] or char)
end

H.clamp = function(x, from, to) return math.min(math.max(x, from), to) end

H.is_valid_buf = function(buf_id) return type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id) end

H.is_valid_win = function(win_id) return type(win_id) == 'number' and vim.api.nvim_win_is_valid(win_id) end

H.is_valid_char = function(char) return vim.fn.strchars(char) == 1 and vim.fn.char2nr(char) > 31 end

H.win_close_safely = function(win_id)
  if H.is_valid_win(win_id) then vim.api.nvim_win_close(win_id, true) end
end

H.fit_to_width = function(text, width)
  local t_width = vim.fn.strchars(text)
  return t_width <= width and text or ('…' .. vim.fn.strcharpart(text, t_width - width + 1, width - 1))
end

-- TODO: Remove after compatibility with Neovim=0.9 is dropped
H.islist = vim.fn.has('nvim-0.10') == 1 and vim.islist or vim.tbl_islist

H.get_lmap = function()
  local lmap = {}
  for _, map in ipairs(vim.fn.maplist()) do
    -- NOTE: Account only for characters that resolve to proper query character
    local is_query_lmap = map.mode == 'l' and H.is_valid_char(map.rhs)
    if is_query_lmap then lmap[map.lhs] = map.rhs end
  end
  return lmap
end
if vim.fn.has('nvim-0.10') == 0 then H.get_lmap = function() return {} end end

return MiniInput
