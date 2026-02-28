-- TODO:
--
-- - Code:
--   - Decide if this needs events.
--   - Decide about the degree to which to take "secret input".
--     The most realistic would be "it is possible to detect any secret
--     listener, but requires carful setup".
--     Probably, even that is not feasible since can not temporarily disable
--     external `vim.on_key` callbacks.
--   - Take extra care of handlers not modify in place the "true" state.
--     Probably, by adding dedicated `H.handle_{key,view,...}`.
--   - Decide on default view. I like `virtline`, but it has one downside: as
--     it uses extmark, input will be shown in all splits showing buffer.
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
--- - `MiniInputCaret`  - possible caret symbol shown in a prompt area.
--- - `MiniInputNormal` - basic foreground/background.
--- - `MiniInputPrefix` - possible prefix shown in a prompt area (like `:`).
---    TODO: Maybe rename to "suffix", as it is "prompt suffix"? Or rename
---    "prompt" to "title", since "prompt" in 'mini.pick' means "prefix + input + caret".
--- - `MiniInputPrompt` - input prompt (intention of the input).
--- - `MiniInputSecret` - secret input.
---@tag MiniInput

--- - On every new key call `handlers.key`.
--- - After processing all new keys (usually one), call handlers: `highlight`, `view`.
--- - <C-c> is hard coded to cancel the input (due to how |getcharstr()| works).
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
  local handlers = config.handlers
  state = H.state_new(vim.deepcopy(state))

  H.state_set(state, true, handlers.key)
  state = vim.deepcopy(H.state)
  local is_secret = state.secret

  -- TODO: Probably extract in a separate helper
  state = handlers.view(state) or state
  H.state.status = 'progress'

  local is_aborted, lmap = false, H.get_lmap()
  for _ = 1, 1000000 do
    if H.cache.is_force_stop_advance then break end
    local char = H.getcharstr(config.delay.async, lmap)
    if H.cache.is_force_stop_advance then break end

    table.insert(state.keys, char)
    if char == nil then state.status = 'cancel' end

    H.state_set(state, false, handlers.key)
    state = vim.deepcopy(H.state)
    state = handlers.view(state) or state

    if H.state_is_end(state) then break end
  end

  local res = H.state.status == 'accept' and H.state.input or nil
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
  local state = { completion_type = opts.completion, keys = { opts.default }, prompt = opts.prompt }
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

  -- TODO: Basically try to support all `:h c_CTRL-<KEY>`. In particular:
  -- `:h c_CTRL-K`, `:h c_CTRL-R`, `:h c_CTRL-V`.
  -- TODO: `<Down>` and `<Up>` should navigate through history that matches (by
  -- prefix) current input.
  -- TODO: `<Tab>` should compute and set completion candidates

  -- Fall back to adding a character at caret
  local caret, input = state.caret, state.input
  state.input = vim.fn.strcharpart(input, 0, caret - 1) .. key .. vim.fn.strcharpart(input, caret - 1)
  state.caret = caret + vim.fn.strchars(key)
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
  return function(state)
    -- TODO
  end
end

--- Notification view
MiniInput.gen_view.notify = function(opts)
  opts = vim.tbl_extend('force', { symbol_caret = '▏', symbol_prefix = ':' }, opts or {})
  local symbol_caret, symbol_prefix = opts.symbol_caret, opts.symbol_prefix

  return function(state)
    local caret, input, prompt = state.caret, state.input, state.prompt

    prompt = (prompt or ''):gsub('%s+$', '')
    if not vim.endswith(prompt, symbol_prefix) then prompt = prompt .. symbol_prefix end
    local input_left, input_right = vim.fn.strcharpart(input, 0, caret - 1), vim.fn.strcharpart(input, caret - 1)
    local msg = string.format('%s %s%s%s', prompt, input_left, symbol_caret, input_right)

    -- Fall back to regular `vim.notify` if no extra capabilities of 'mini.notify'
    if _G.MiniNotify == nil then
      vim.notify(msg)
      return
    end

    local id = state.data.progress_id
    if id == nil then
      state.data.progress_id = MiniNotify.add(msg, 'INFO', 'MiniInputNormal')
    else
      MiniNotify.update(state.data.progress_id, { msg = msg })
    end

    if H.state_is_end(state) then MiniNotify.remove(id) end
  end
end

--- Progress view
---
---@opts table|nil Options. Possible fields:
---   - <symbol_caret> `(string)` - string to use for caret.
---   - <symbol_prefix> `(string)` - string to use for prompt prefix.
MiniInput.gen_view.progress = function(opts)
  if vim.fn.has('nvim-0.12') == 0 then
    H.error("`progress` view requires Neovim>=0.12. Consider using `notify` view with 'mini.notify' set up.")
  end

  opts = vim.tbl_extend('force', { symbol_caret = '▏', symbol_prefix = ':' }, opts or {})
  local symbol_caret, symbol_prefix = opts.symbol_caret, opts.symbol_prefix

  return function(state)
    local caret, input, prompt, status = state.caret, state.input, state.prompt, state.status

    prompt = (prompt or ''):gsub('%s+$', '')
    if not vim.endswith(prompt, symbol_prefix) then prompt = prompt .. symbol_prefix end
    local input_left, input_right = vim.fn.strcharpart(input, 0, caret - 1), vim.fn.strcharpart(input, caret - 1)

    local progress_status = status == 'accept' and 'success' or (status == 'cancel' and 'cancel' or 'running')

    local chunks =
      { { input_left, 'MiniInputNormal' }, { symbol_caret, 'MiniInputCaret' }, { input_right, 'MiniInputNormal' } }
    chunks = H.normalize_chunks(chunks)

    local title = prompt:sub(-1) == ':' and prompt:sub(1, -2) or prompt
    local pr_opts = { id = state.data.progress_id, kind = 'progress', title = title, status = progress_status }
    state.data.progress_id = vim.api.nvim_echo(chunks, false, pr_opts)

    -- No "progress end" message as it is not needed and distracting with ui2
    local redraw_cmd = (status == 'accept' or status == 'cancel') and 'mode' or 'redraw'
    vim.cmd(redraw_cmd)
  end
end

--- Statusline view
MiniInput.gen_view.statusline = function(opts) return H.make_statusline_view('statusline', opts) end

--- Virtual line view
MiniInput.gen_view.virtline = function(opts)
  opts = vim.tbl_extend('force', { symbol_caret = '▏', symbol_prefix = ':' }, opts or {})
  local symbol_caret, symbol_prefix = opts.symbol_caret, opts.symbol_prefix

  return function(state)
    local caret, input, prompt, status = state.caret, state.input, state.prompt, state.status

    prompt = (prompt or ''):gsub('%s+$', '')
    local prefix = vim.endswith(prompt, symbol_prefix) and '' or symbol_prefix
    local input_left, input_right = vim.fn.strcharpart(input, 0, caret - 1), vim.fn.strcharpart(input, caret - 1)

    --stylua: ignore
    local chunks = H.normalize_chunks({
      { prompt, 'MiniInputPrompt' }, { prefix, 'MiniInputPrefix' }, { ' ', 'MiniInputNormal' },
      { input_left, 'MiniInputNormal' }, { symbol_caret, 'MiniInputCaret' }, { input_right, 'MiniInputNormal' },
      { string.rep(' ', vim.o.columns), 'MiniInputNormal' },
    })

    local cur_line, top_line = vim.fn.line('.'), vim.fn.line('w0')
    local extmark_opts = { id = state.data.extmark_id, virt_lines = { chunks }, virt_lines_above = true }
    state.data.extmark_id = vim.api.nvim_buf_set_extmark(0, H.ns_id.view, cur_line - 1, 0, extmark_opts)

    if H.state_is_end(state) then pcall(vim.api.nvim_buf_del_extmark, 0, H.ns_id.view, state.data.extmark_id) end

    -- Ensure that the line above is visible
    -- TODO: Still shows cursor on top of the virtual line if there is a scroll
    if cur_line == top_line then vim.cmd('normal! \25') end

    -- TODO: Make it still show full line if the window is scrolled horizontally
  end
end

--- Virtual text view
MiniInput.gen_view.virttext = function(opts)
  return function(state)
    -- TODO
  end
end

--- Winbar view
MiniInput.gen_view.winbar = function(opts) return H.make_statusline_view('winbar', opts) end

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
  hi('MiniInputCaret', { link = 'MiniInputPrompt' })
  hi('MiniInputNormal', { link = 'NormalFloat' })
  hi('MiniInputPrefix', { link = 'DiagnosticFloatingHint' })
  hi('MiniInputPrompt', { link = 'DiagnosticFloatingInfo' })
  hi('MiniInputSecret', { link = 'DiagnosticFloatingWarn' })
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
  return state
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

H.state_is_end = function(state) return state.status == 'accept' or state.status == 'cancel' end

-- Default key handler --------------------------------------------------------
H.key_methods = {}

local keycode = vim.keycode or function(s) return vim.api.nvim_replace_termcodes(s, true, true, true) end
H.key_methods['\r'] = function(state) state.status = 'accept' end
H.key_methods[keycode('<Esc>')] = function(state) state.status = 'cancel' end
H.key_methods[keycode('<BS>')] = function(state)
  local caret, input = state.caret, state.input
  if caret <= 1 then return end
  state.input = vim.fn.strcharpart(input, 0, caret - 2) .. vim.fn.strcharpart(input, caret - 1)
  state.caret = caret - 1
end
H.key_methods[keycode('<C-w>')] = function(state)
  local caret, input = state.caret, state.input
  if caret <= 1 then return end
  local left = vim.fn.strcharpart(input, 0, caret - 1)
  local left_to = vim.fn.match(left, '[[:keyword:]]\\+$')
  if left_to < 0 then left_to = vim.fn.match(left, '[^[:keyword:]]\\+$') end
  state.input = vim.fn.strcharpart(left, 0, left_to) .. vim.fn.strcharpart(input, caret - 1)
  state.caret = H.clamp(left_to + 1, 1, vim.fn.strchars(state.input) + 1)
end
H.key_methods[keycode('<C-u>')] = function(state)
  state.input = vim.fn.strcharpart(state.input, state.caret - 1)
  state.caret = 1
end
H.key_methods[keycode('<Left>')] = function(state)
  state.caret = H.clamp(state.caret - 1, 1, vim.fn.strchars(state.input) + 1)
end
H.key_methods[keycode('<Right>')] = function(state)
  state.caret = H.clamp(state.caret + 1, 1, vim.fn.strchars(state.input) + 1)
end

-- Views ----------------------------------------------------------------------
H.make_statusline_view = function(target, opts)
  opts = vim.tbl_extend('force', { symbol_caret = '▏', symbol_prefix = ':' }, opts or {})
  local symbol_caret, symbol_prefix = opts.symbol_caret, opts.symbol_prefix

  return function(state)
    local win_id, win_id_prev = vim.api.nvim_get_current_win(), state.data.win_id

    if win_id_prev ~= win_id then
      if H.is_valid_win(win_id_prev) then vim.wo[win_id_prev][target] = state.data[target] end
      state.data.win_id, state.data[target] = win_id, vim.wo[win_id][target]
      state.data.laststatus = vim.o.laststatus
    end

    local caret, input, prompt = state.caret, state.input, state.prompt
    prompt = (prompt or ''):gsub('%s+$', '')
    local prefix = vim.endswith(prompt, symbol_prefix) and '' or symbol_prefix
    local input_left, input_right = vim.fn.strcharpart(input, 0, caret - 1), vim.fn.strcharpart(input, caret - 1)

    --stylua: ignore
    local chunks = {
      { prompt, 'MiniInputPrompt' }, { prefix, 'MiniInputPrefix' }, { ' ', 'MiniInputNormal' },
      { input_left, 'MiniInputNormal' }, { symbol_caret, 'MiniInputCaret' }, { input_right, 'MiniInputNormal' },
    }
    vim.wo[win_id][target] = table.concat(H.normalize_chunks(chunks, 'statusline')) .. '%#MiniInputNormal#'

    -- Ensure that statusline is shown
    if target == 'statusline' and vim.o.laststatus < 2 then vim.o.laststatus = 2 end

    -- Cleanup
    if H.state_is_end(state) then
      vim.wo[win_id][target] = state.data[target]
      vim.o.laststatus = state.data.laststatus
    end
  end
end

H.normalize_chunks = function(chunks, output)
  local res = {}
  for _, c in ipairs(chunks) do
    if c == 'string' then c = { c } end
    c[2] = c[2] or 'MiniInputNormal'
    local part = output == 'statusline' and string.format('%%#%s#%s', c[2], c[1]) or c
    if c[1] ~= '' then table.insert(res, part) end
  end
  return res
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

H.redraw_scheduled = vim.schedule_wrap(function() vim.cmd('redraw') end)

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
