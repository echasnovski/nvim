-- TODO:
--
-- - Code:
--   - Decide if this needs events.
--
-- - Docs:
--
-- - Test:
--     - The input should probably still be going if `state_set()` results in
--       an error due to incorrect input `state`.

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
--- Handler is called on every new item added to stream. It should be safe to
--- assume that `stream[#stream]` is the key handler needs to process.
---
--- Key stream follows Neovim's |key-notation|. To get exact translation of
--- a special key combo, type `:echo keytrans(getcharstr())`, press <CR> followed
--- by the combo in question. The printed value is the one used in stream (except
--- `<` which is used as is). This also includes some common pitfalls:
--- - <C-J>   is shown as <NL>.
--- - <C-S-J> is shown as <S-NL>.
--- - <C-M-J> is shown as <M-NL>.
---
--- ## Custom mappings ~
---
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
---
--- Notes:
--- - All non-secret input results (even empty strings) are added to history.
---   Get the whole history with |MiniInput.get_history()|.
---
---@return string|nil User input if accepted or `nil` if canceled.
MiniInput.get = function(state, opts)
  H.check_type('state', state, 'table')

  local config = H.get_config()
  state = H.state_new(vim.deepcopy(state))

  H.state_set(state, true, config.handler)
  local is_secret = H.state.secret
  H.state.status = 'progress'

  -- TODO: Apply view

  -- TODO: Advance key-query-process

  local res = H.state.result
  H.state = nil
  if res ~= nil and not is_secret then table.insert(H.history, res) end

  return res
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
  local state = { completion_type = opts.completion, input = { opts.default }, prompt = opts.prompt }
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
--- - <completion_type> `(string|nil)` - same as `completion` in |input()|.
--- - <completion_items> `table|nil` - array of completion suggestions at caret.
--- - <data> `(table)` - any information to be reused during single input session.
--- - <prompt> `(string|nil)` - intention of the input, same as in |input()|.
--- - <result> `(string)` - current result of the user input.
--- - <secret> `(boolean)` - whether input session is for sensitive information
---   and should be hidden.
--- - <status> `(string)` - one of `"start"`, `"progress"`, `"accept"`, `"cancel"`.
--- - <stream> `(table)` - string array with full history of user keypresses.
---   Each element is usually a |getcharstr()| output "translated" with |keytrans()|,
---   i.e. special keys look like `'<CR>'`, `'<Space>'`, `'<C-U>'`, etc.
---   However, it is allowed to be any string if set with |MiniInput.set_state()|.
---   Use `stream[#stream]` to get the latest key press.
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

  local config = H.get_config()
  H.state_set(state, false, config.handler)
  -- TODO: Update view
end

--- Get input history
---
---@return table Array of all previous non-secret inputs (from earliest to latest).
MiniInput.get_history = function() return vim.deepcopy(H.history) end

--- Default key handler
MiniInput.default_handler = function(state, opts)
  -- TODO: Basically try to support all `:h c_CTRL-<KEY>`. In particular:
  -- `:h c_CTRL-K`, `:h c_CTRL-R`, `:h c_CTRL-V`.
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

-- History of inputs
H.history = {}

-- Various cache
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
  state.result = state.result or ''
  if state.secret == nil then state.secret = false end
  state.status = 'start'
  state.stream = state.stream or {}
end

H.state_set = function(new, init, handler)
  H.check_type('state', new, 'table')
  local cur = H.state or H.state_new({})
  new = vim.tbl_deep_extend('force', cur, new)

  -- Do not allow to change `secret` to not show secret input
  if not init then new.secret = cur.secret end

  -- Force proper status
  new.status = init and 'start' or (new.status == 'start' and 'progress' or new.status)

  H.state_validate(new, cur)

  -- Call key handler on every new stream input.
  -- TODO: If there is a new input, append it one by one with calling `handler`
  -- on each iteration.
  -- TODO: Maybe forbid handler to modify some special fields (i.e. manually
  -- transfer them unchanged to the new state in this iteractive process)?
  -- Like <secret> (to not un-secret the input) and <stream> (to not have
  -- infinite recursion like problems). All other fields are reasonable to
  -- allow to set.

  H.state = new
end

H.state_validate = function(x, cur)
  H.check_type('state.caret', x.caret, 'number')
  H.check_type('state.completion_type', x.completion_type, 'string', true)
  H.check_type('state.completion_items', x.completion_items, 'table', true)
  H.check_type('state.data', x.data, 'table')
  H.check_type('state.prompt', x.prompt, 'string', true)
  H.check_type('state.result', x.result, 'string')
  H.check_type('state.secret', x.secret, 'boolean')
  if not (x.status == 'start' or x.status == 'progress' or x.status == 'accept' or x.status == 'cancel') then
    H.error('`state.status` should be one of "start", "progress", "accept", "cancel"')
  end
  if not H.islist(x.stream) then H.error('`state.stream` should be array') end
  for i = 1, #x.stream do
    if type(x.stream[i]) ~= 'string' then H.error('`state.stream` should be array of strings') end
    if cur.stream[i] ~= nil and cur.stream[i] ~= x.stream[i] then H.error('`state.stream` overrides past stream') end
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

H.keytrans = function(x)
  return x ~= nil and vim.fn.keytrans(x) or nil
  -- if x == nil then return nil end
  -- local res = vim.fn.keytrans(x):gsub('<NL>', '<C-J>'):gsub('<S%-NL>', '<C-S-J>'):gsub('<M%-NL>', '<C-M-J>')
  -- return (res:gsub('<lt>', '<'))
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
