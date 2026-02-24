-- TODO:
--
-- - Code:
--   - Decide if this needs events.
--   - Decide about the degree to which to take "secret input".
--     The most realistic would be "it is possible to detect any secret
--     listener, but requires carful setup".
--     Probably, even that is not feasible since can not temporarily disable
--     external `vim.on_key` callbacks.
--
-- - Docs:
--
-- - Test:
--     - The input should probably still be going if `state_set()` results in
--       an error due to incorrect input `state`.
--     - Key handler should be never allowed to change `state.keys`: initial
--       state setting in `get()`, regular key query process, external
--       `MiniInput.set_state()`.

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
--- - `MiniInputSecret` - secret input.
---@tag MiniInput

--- - On every new key call `handlers.key`.
--- - After processing all new keys (usually one), call handlers: `highlight`, `view`.
---@tag MiniInput-key-query-process

--- # General ~
---
--- ## Default value ~
---
--- `MiniInput.get({ input = { 'Default' } })`.
---
--- ## Custom mappings ~
---
--- # Handlers ~
---
--- ## Key ~
---
--- Key handler is called on every new item added to `keys`. It should be safe to
--- assume that `keys[#keys]` is the key that needs to be processed.
---
--- All registered keys follow the output of |getcharstr()|. Use |vim.keycode()|
--- to translate |key-notation| into key codes, like `vim.keycode('<BS>')`.
---
--- ## View ~
---
--- No view: >lua
---
--- <
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
---@text # Delay ~
---
--- `config.delay` defines plugin delays (in ms). All should be strictly positive.
---
--- `delay.async` is a delay between forcing asynchronous behavior. This usually
--- means making screen redraws when waiting for user's next key press.
--- Smaller values give smoother user experience at the cost of more computations.
---
--- # Handlers ~
---
--- `config.handlers` defines functions
---
--- ## Key ~
---
--- Key handler is called on every new item added to `keys`. It should be safe to
--- assume that `keys[#keys]` is the key that needs to be processed.
---
--- All registered keys follow the output of |getcharstr()|. Use |vim.keycode()|
--- to translate |key-notation| into key codes, like `vim.keycode('<BS>')`.
---
--- Takes `state` and `config` as arguments. Should either return new state or
--- modify input `state` in place.
---
--- Notes:
--- - Any change to `state.keys` or `state.secret` is ignored.
---
--- ## Complete ~
---
--- With default key handler only called after |'wildchar'| (<Tab> by default).
--- Computes and sets suggestions for the current state. It is up to view
--- handler to show these suggestions.
---
--- ## Highlight ~
---
--- Compute highlight info about the current input. Same as |input()-highlight|, but
--- takes whole current state as input.
---
--- ## View ~
---
--- No view: >lua
---
--- <
---
--- # Options ~
---
--- `config.options` contains some general purpose options.
---
--- `options.secret_char` is a string used as a replacement for each input character
--- during secret input. Use empty string `''` to not show secret input.
MiniInput.config = {
  -- Delays (in ms; should be at least 1)
  delay = {
    -- Delay between forcing asynchronous behavior
    async = 10,
  },

  -- Functions that define how input process is processed
  handlers = {
    -- Handle every key press
    key = nil,

    -- Compute completion candidates
    complete = nil,

    -- Compute highlighting of current input
    highlight = nil,

    -- Show current input state
    view = nil,
  },

  -- Options which control module behavior
  options = {
    -- Replacement character during secret input
    secret_char = '*',
  },
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
  H.check_type('state', state, 'table', true)
  H.check_type('opts', opts, 'table', true)

  -- Only allow one input at a time
  if H.state ~= nil then return nil end

  local config = H.get_config(opts)
  state = H.state_new(vim.deepcopy(state))

  H.state_set(state, true, config.handlers.key)
  local is_secret = H.state.secret
  H.state.status = 'progress'

  -- TODO: Apply view

  -- TODO: Advance key-query-process

  local res = H.state.input
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
--- - <data> `(table)` - any information to be reused within same input session.
--- - <hl_ranges> `(table|nil)` - array of ranges to highlight, same as the output
---   of |input()-highlight|.
--- - <input> `(string)` - current result of the user input.
--- - <keys> `(table)` - string array with full history of user keypresses.
---   Each element is usually a |getcharstr()| output. However, it is allowed
---   to be any string if set with |MiniInput.set_state()|.
---   Use `keys[#keys]` to get the latest key press.
--- - <prompt> `(string|nil)` - intention of the input, same as in |input()|.
--- - <secret> `(boolean)` - whether input session is for sensitive information
---   and should be hidden.
--- - <status> `(string)` - one of `"start"`, `"progress"`, `"accept"`, `"cancel"`.
---
---@return table|nil Current state if input is active, `nil` if it is secret or not active.
---
---@usage Together with |MiniInput.set_state()| can be used to perform educated
---   actions during user input. For example: >lua
---
---   -- TODO
--- <
MiniInput.get_state = function()
  if H.state == nil or H.state.secret then return nil end
  return vim.deepcopy(H.state)
end

--- Set current input state
---
--- Notes:
--- - No state is set if there is no active input or if the input is secret.
---
---@param state table Parts of the state to be updated. See |MiniInput.get_state()|
---   for available fields. Notes:
---   - Field <input> is allowed to only be equal or appeend to current state.
---   - Field <secret> is ignored to be not allow overriding it.
---   - Field <status> can not be `"start"`, as it is set once by |MiniInput.get()|.
MiniInput.set_state = function(state)
  if H.state == nil or H.state.secret then return nil end

  local config = H.get_config()
  H.state_set(state, false, config.handlers)
  -- TODO: Update view
end

--- Get input history
---
---@return table Array of all previous non-secret inputs (from earliest to latest).
MiniInput.get_history = function() return vim.deepcopy(H.history) end

--- Default key handler
---
--- Notes:
--- - All special keys (which are not expected to be added to the input) should
---   come as a separate `state.keys` entry. I.e. `{ 'x', '\r' }` and not `{ 'x\r' }`.
MiniInput.default_key = function(state, opts)
  local key = state.keys[#state.keys]

  local method = H.key_methods[key]
  if method ~= nil then return method(state) end
  table.insert(state.keys, key)

  -- TODO: Basically try to support all `:h c_CTRL-<KEY>`. In particular:
  -- `:h c_CTRL-K`, `:h c_CTRL-R`, `:h c_CTRL-V`.
  -- TODO: `<Down>` and `<Up>` should navigate through history that matches (by
  -- prefix) current input.
  -- TODO: `<Tab>` should compute and set completion candidates
end
local default_key_handler = MiniInput.default_key

MiniInput.default_complete = function(state)
  if state.secret then return state end
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

  H.check_type('delay', config.delay, 'table')
  H.check_type('delay.async', config.delay.async, 'number')

  H.check_type('handlers', config.handlers, 'table')
  H.check_type('handlers.key', config.handlers.key, 'function', true)
  H.check_type('handlers.highlight', config.handlers.highlight, 'function', true)
  H.check_type('handlers.view', config.handlers.view, 'function', true)

  H.check_type('options', config.options, 'table')
  H.check_type('options.secret_char', config.options.secret_char, 'string')

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
  hi('MiniInputSecret', { link = 'DiagnosticWarn' })
end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniInput.config, vim.b.miniinput_config or {}, config or {})
end

-- State ----------------------------------------------------------------------
H.state_new = function(state)
  state.caret = state.caret or 1
  state.data = state.data or {}
  state.input = state.input or ''
  state.keys = state.keys or {}
  if state.secret == nil then state.secret = false end
  state.status = 'start'
end

H.state_set = function(new, init, key_handler)
  H.check_type('state', new, 'table')
  local dummy = H.state_new({})
  local cur = vim.deepcopy(H.state) or dummy
  new = vim.tbl_deep_extend('force', cur, new)

  H.state_validate(new, cur)

  -- Do not allow to change `secret` to not compromise secret input
  if not init then new.secret = cur.secret end

  -- Force proper status
  new.status = init and 'start' or (new.status == 'start' and 'progress' or new.status)

  -- Process new keys
  key_handler = (key_handler == nil or new.secret) and default_key_handler or key_handler

  local cur_keys, new_keys = cur.keys, new.keys
  for i = #cur.keys + 1, #new_keys do
    table.insert(cur_keys, new_keys[i])
    new.keys = vim.deepcopy(cur_keys)

    new = key_handler(new) or new
    -- Ignore special fields
    new.secret, new.keys = cur.secret, cur_keys
    H.state_validate(new, dummy)
    if new.status == 'accept' or new.status == 'cancel' then break end
  end

  H.state = new
end

H.state_validate = function(x, cur)
  H.check_type('state.caret', x.caret, 'number')
  H.check_type('state.completion_type', x.completion_type, 'string', true)
  H.check_type('state.completion_items', x.completion_items, 'table', true)
  H.check_type('state.data', x.data, 'table')
  H.check_type('state.hl_ranges', x.hl_ranges, 'table', true)
  H.check_type('state.input', x.input, 'string')
  if not H.islist(x.keys) then H.error('`state.keys` should be array') end
  for i = 1, #x.keys do
    if type(x.keys[i]) ~= 'string' then H.error('`state.keys` should be array of strings') end
    if cur.keys[i] ~= nil and cur.keys[i] ~= x.keys[i] then H.error('`state.keys` overrides past keys') end
  end
  H.check_type('state.prompt', x.prompt, 'string', true)
  H.check_type('state.secret', x.secret, 'boolean')
  if not (x.status == 'start' or x.status == 'progress' or x.status == 'accept' or x.status == 'cancel') then
    H.error('`state.status` should be one of "start", "progress", "accept", "cancel"')
  end
end

H.state_hide_secret = function(state, config)
  if state == nil or not state.secret then return state end
  state.input = string.rep(config.options.secret_char, vim.fn.strchars(state.input))
  return state
end

-- Default key handler --------------------------------------------------------
H.key_methods = {}

local keycode = vim.keycode or function(s) return vim.api.nvim_replace_termcodes(s, true, true, true) end
H.key_methods['\r'] = function(state) state.status = 'accept' end
H.key_methods['\3'] = function(state) state.status = 'cancel' end
H.key_methods[keycode('<Esc>')] = function(state) state.status = 'cancel' end

H.key_methods[keycode('<Left>')] = function(state)
  state.caret = H.clamp(state.caret - 1, 1, vim.fn.strchars(state.input) + 1)
end
H.key_methods[keycode('<Right>')] = function(state)
  state.caret = H.clamp(state.caret + 1, 1, vim.fn.strchars(state.input) + 1)
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

H.getcharstr = function(delay_async, lmap)
  -- Ensure that redraws still happen
  H.timers.getcharstr:start(0, delay_async, H.redraw_scheduled)
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
