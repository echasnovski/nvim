-- TODO:
--
-- - Code:
--   - Decide on default view. I like `virtline`, but it has one downside: as
--     it uses extmark, input will be shown in all splits showing buffer.
--   - Use global config for `caret` and `hide` symbols.
--   - Make `hide` boolean to mean "hide input or not". It will use separately
--     configured `hide` symbol.
--
-- - Docs:
--
-- - Test:
--     - The input should still be going if there is an error in handler or
--       returned state is not valid.
--     - <C-w> should work with multibyte charaters.
--     - Already shown completion should be teared down if `opts.hide` is toggled.
--     - `default_complete` respects 'ignorecase' and 'smartcase'.

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
--- - `MiniInputAdded`  - added text during completion navigation.
--- - `MiniInputBorder` - border of a floating window.
--- - `MiniInputCaret`  - caret symbol shown in a prompt area.
--- - `MiniInputHide`   - input is hidden.
--- - `MiniInputHint`   - hints shown during completion navigation.
--- - `MiniInputNormal` - basic foreground/background.
--- - `MiniInputPrompt` - input prompt (intention of the input).
---@tag MiniInput

--- TODO
---
--- - On every new key call `handlers.key`.
--- - After processing all new keys (usually one), call handlers: `highlight`, `view`.
--- - <C-c> is hard coded to cancel the input (due to how |getcharstr()| works).
---
--- # State ~
--- *MiniInput-state*
---
--- TODO
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
---@text # Handlers ~
---
--- `config.handlers` defines functions ... .
---
--- TODO: Describe key query process. Handler order. When they are called:
--- once in the start, on every user key press, once at the end.
---
--- ## Key ~
---
--- Key handler process user key presses.
---
--- All registered keys follow the output of |getcharstr()|. Use |vim.keycode()|
--- to translate |key-notation| into key codes, like `vim.keycode('<BS>')`.
---
--- Takes `key` and `state` as arguments. Should either return new state or
--- modify input `state` in place.
---
--- Notes:
--- - Any change to `state.keys` or `state.secret` is ignored.
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
--- ## Complete ~
---
--- Computes suggestions for the current state based on given method.
---
--- # Hide ~
---
--- `config.hide` defines if and how to hide the input from the view.
--- By default no hiding is done. If set to string:
--- - The `view` handler is called with every input character replaced with `hide`.
--- - The `complete` and `highlight` handlers are not called.
---
--- Use empty string (`''`) to show no input characters (`view` handler can still
--- decide to show something indicating a hidden input).
---
--- Note: this does not guarantee a total security of the input, just that the
--- typed characters won't be shown on screen.
---
--- # Scope ~
---
--- `config.scope` is a string that defines an input scope. It is meant as an extra
--- information for handlers to tweak their behavior (like `view` position, etc.).
--- Possible values are: `"cursor"`, `"buffer"`, `"window"`, `"tabpage"`, `"editor"`.
---
--- The value from |MiniInput.config| is used as the default for |MiniInput.get()|.
MiniInput.config = {
  -- Functions that define how input process is processed
  handlers = {
    -- Handle every key press
    key = nil,

    -- Compute highlighting of current input
    highlight = nil,

    -- Show current input state
    view = nil,

    -- Compute completion candidates
    complete = nil,
  },

  -- How to hide the input from the view. No hiding by default.
  -- A string is used instead of every typed character.
  hide = nil,

  -- Default input scope
  -- One of "cursor", "buffer", "window", "tabpage", "editor"
  -- This allows customizing how input is shown depending on where it is
  -- needed. Like 'mini.ai' and 'mini.surround' would use "position", but
  -- `vim.ui.input` probably "editor".
  scope = 'editor',
}
--minidoc_afterlines_end

--- Get input from the user
---
--- Notes:
--- - Data about all non-hidden accepted input results (even for empty input) are
---   added to the history. Get the whole history with |MiniInput.get_history()|.
---
---@param opts table|nil Options. Possible fields:
---   - <completion> `(string)` - completion method. Default: `''` to use default
---     completion method of the `complete` handler.
---   - <handlers> `(table)` - same as in |MiniInput.config|.
---   - <hide> `(string)` - same as in |MiniInput.config|.
---   - <init_keys> `(table)` - array of string keys that are emulated before
---     asking for user input. Any strings are allowed, but using values that can
---     be an output of |getcharstr()| should be preferred. Default: `{}`.
---   - <prompt> `(string)` - intention of the input, same as in |input()|.
---     Default: `'Input'`.
---   - <scope> `(string)` - same as in |MiniInput.config|.
---
---@return string|nil User input if accepted or `nil` if canceled.
---
---@usage >lua
---   local input = MiniInput.get({
---     -- Intention of the input
---     prompt = 'New word',
---     -- The input is for something at cursor
---     scope = 'cursor',
---     -- Emulate pressing `a`, `<BS>`, and `b`
---     init_keys = { 'a', vim.keycode('<BS>'), 'b' },
---   })
--- <
MiniInput.get = function(opts)
  H.check_type('opts', opts, 'table', true)

  -- Only allow one input at a time
  if H.state ~= nil then return nil end

  local init_state = H.state_new(H.get_config(opts))
  H.state_set(init_state)

  H.handle_step(nil)
  if H.state_is_end() then return H.state_finish() end
  H.state.status = 'progress'

  for _, k in ipairs(H.state.opts.init_keys) do
    H.handle_step(k)
    if H.state_is_end() then return H.state_finish() end
  end

  local lmap = H.get_lmap()
  for _ = 1, 1000000 do
    local key = H.getcharstr(lmap)
    if key == nil then H.state.status = 'cancel' end
    H.handle_step(key)
    if H.state_is_end() then break end
  end

  return H.state_finish()
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
  -- TODO: Convert all other `vim.ui.input()` allowed fields
  local input_opts = { completion = opts.completion, init_keys = {}, prompt = opts.prompt }
  if type(opts.default) == 'string' then
    for i = 1, vim.fn.strchars(opts.default) do
      input_opts.init_keys[i] = vim.fn.strcharpart(opts.default, i - 1, 1)
    end
  end

  on_confirm(MiniInput.get(input_opts))
end

--- Get current input state
---
--- It stores information about the current state of the user input.
--- Can be `nil` to indicate that there is no active user input.
---
--- During user input, it is a table with the following fields:
--- - <caret> `(number)` - current input position to modify output, i.e. new key will
---   be added at this (character, not byte) index.
--- - <data> `(table)` - any information to be reused within same input session.
--- - <complete> `(table|nil)` - information about active completion navigation.
---   If present, it means that completion navigation is in action.
---   Its fields describe the state of navigation:
---     - <base> `(string)` - reference text to the left of caret at the start
---       of completion it uses to compute candidates. Can be empty string.
---     - <id> `(number)` - identfier of current completion item. Can be zero to
---       mean that the base is shown.
---     - <items> `(table)` - string array of completion candidates. May be empty.
---     - <method> `(string)` - completion method. Like `"default"`, `"history"`, etc.
--- - <input> `(string)` - current result of the user input. If the input is hidden,
---   every character is replaced with `opts.hide`.
--- - <prompt> `(string)` - intention of the input, same as in |input()|.
--- - <opts> `(table)` - input options, same as in |MiniInput.get()|.
--- - <status> `(string)` - one of `"start"`, `"progress"`, `"accept"`, `"cancel"`.
---
---@return table|nil Current state if input is active, `nil` otherwise.
MiniInput.get_state = function()
  if H.state == nil then return nil end
  local res = H.copy_tables(H.state)
  if type(res.opts.hide) == 'string' then res.input = string.rep(res.opts.hide, vim.fn.strchars(res.input)) end
  return res
end

--- Get input history
---
---@return table Array with data about all previous non-hidden inputs (from earliest
---   to latest). Each element is a table with the following fields:
---   - <input> `(string)` - input result.
---   - <prompt> `(string)` - `opts.prompt` supplied in |MiniInput.get()|.
---   - <scope> `(string)` - `opts.scope` supplied in |MiniInput.get()|.
MiniInput.get_history = function() return vim.deepcopy(H.history) end

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
  opts = vim.tbl_extend('force', { symbol_caret = '▏' }, opts or {})
  local symbol_caret = opts.symbol_caret

  return function(state)
    local caret, input, prompt = state.caret, state.input, state.opts.prompt

    prompt = (prompt or ''):gsub('%s+$', '')
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
MiniInput.gen_view.progress = function(opts)
  if vim.fn.has('nvim-0.12') == 0 then
    H.error("`progress` view requires Neovim>=0.12. Consider using `notify` view with 'mini.notify' set up.")
  end

  opts = vim.tbl_extend('force', { symbol_caret = '▏' }, opts or {})
  local symbol_caret = opts.symbol_caret

  return function(state)
    local caret, input, prompt, status = state.caret, state.input, state.opts.prompt, state.status

    prompt = (prompt or ''):gsub('%s+$', '')
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
  opts = vim.tbl_extend('force', { symbol_caret = '▏' }, opts or {})
  local symbol_caret = opts.symbol_caret

  return function(state)
    local caret, input, prompt, status = state.caret, state.input, state.opts.prompt, state.status

    prompt = (prompt or ''):gsub('%s+$', '')
    local input_left, input_right = vim.fn.strcharpart(input, 0, caret - 1), vim.fn.strcharpart(input, caret - 1)

    -- TODO: Make it part of a general `state_to_chunks(state, width)` that:
    -- - Makes sure that it focuses on cursor if the input is too wide.
    --   Inclusing splicing possible `state.highlight` ranges.
    -- - Adds completion hint to the right of the caret.
    local prompt_hl = state.opts.hide and 'MiniInputHide' or 'MiniInputPrompt'
    --stylua: ignore
    local chunks_raw = {
      { prompt, prompt_hl }, { ' ', 'MiniInputNormal' },
      { input_left, 'MiniInputNormal' }, { symbol_caret, 'MiniInputCaret' }, { input_right, 'MiniInputNormal' },
      { string.rep(' ', vim.o.columns), 'MiniInputNormal' },
    }
    if state.complete ~= nil then
      local pad = input_right == '' and '' or ' '
      local hint = string.format(' (%d/%d)%s', state.complete.id, #state.complete.items, pad)
      table.insert(chunks_raw, #chunks_raw, { hint, 'MiniInputHint' })
    end
    local chunks = H.normalize_chunks(chunks_raw)

    local cur_line, top_line = vim.fn.line('.'), vim.fn.line('w0')
    local extmark_opts = { id = state.data.extmark_id, virt_lines = { chunks }, virt_lines_above = true }
    state.data.extmark_id = vim.api.nvim_buf_set_extmark(0, H.ns_id.view, cur_line - 1, 0, extmark_opts)

    if H.state_is_end(state) then pcall(vim.api.nvim_buf_del_extmark, 0, H.ns_id.view, state.data.extmark_id) end

    -- Ensure that the line above is visible
    -- TODO: Still shows cursor on top of the virtual line if there is a scroll
    if cur_line == top_line then vim.cmd('normal! \25') end
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

--- Default key handler
---
--- Emulates most of |Command-line-mode| editing (|cmdline-editing|):
--- - Accept: <CR>.
--- - Cancel: <Esc>.
--- - Move caret:
---     - <Left>, <Right> - one character to left / right.
---     - <S-Left>, <S-Right> - one word to left / right.
---     - <C-b>, <C-e> (if no completion) - to start / end of input.
--- - Delete:
---     - <BS> / <C-h> - to caret's left.
---     - <Del> - at caret.
---     - <C-u> - from start to caret. As |c_CTRL-U|.
---     - <C-w> - contiguous keyword or non-keyword to caret's left. As |c_CTRL-W|.
--- - Insert at caret:
---     - <C-k> - digraph based on the next two pressed keys. As |c_CTRL-K|.
---     - <C-r> - content of a register. As |c_CTRL-R| including support for
---       special <C-a>, <C-f>, <C-l>, <C-w> keys for a register.
---     - <C-v>, <C-q> - next key literally. As |c_CTRL-V| and |i_CTRL-V_digit|
---       (all digits must be typed in full).
--- - Completion:
---     - <Tab>, <S-Tab> - initiate completion based on input method and navigate.
---     - <C-n>, <C-p>, <Up>, <Down> - initiate history completion and navigate.
---     - <C-e> - stop completion.
--- - Miscellaneous:
---     - <C-x> - toggle hide/unhide of the input.
--- - If a key is not special, it is inserted at caret as is.
MiniInput.default_key = function(state, key)
  if key == nil then return end
  local method = H.key_methods[key] or function(s) H.insert_at_caret(s, key) end
  method(state)
end

--- Default highlight handler
MiniInput.default_highlight = function(state)
  if state.opts.hide then return end
  -- TODO:
  -- - Should highlight input parts added during completion
  --   navigation with 'MiniInputAdded'.
end

--- Default view handler
MiniInput.default_view = function(state)
  -- TODO
end

--- Default complete handler
MiniInput.default_complete = function(state, method)
  if state.opts.hide then return end
  if method == 'history' then return H.complete_history(state) end
  method = method or ''

  local caret, input = state.caret, state.input
  local text = vim.fn.strcharpart(input, 0, caret - 1)
  local base_start = vim.fn.match(text, '[[:keyword:]]*$')
  local base = vim.fn.strcharpart(text, base_start)

  if method == '' then
    state.complete = { items = H.complete_buf_words(base), base = base }
    return
  end

  local pat = method == 'cmdline' and vim.fn.strcharpart(input, 0, caret - 1) or base
  local ok, items = pcall(vim.fn.getcompletion, pat, state.opts.completion)
  if not ok then return end
  if ok then state.complete = { items = items, base = base } end
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

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('handlers', config.handlers, 'table')
  H.check_type('handlers.complete', config.handlers.complete, 'function', true)
  H.check_type('handlers.highlight', config.handlers.highlight, 'function', true)
  H.check_type('handlers.key', config.handlers.key, 'function', true)
  H.check_type('handlers.view', config.handlers.view, 'function', true)

  H.check_type('hide', config.hide, 'string', true)
  H.check_type('scope', config.scope, 'string')

  return config
end

H.apply_config = function(config) MiniInput.config = config end

H.create_default_hl = function()
  local hi = function(name, opts)
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end

  hi('MiniInputAdded', { link = 'DiagnosticFloatingOk' })
  hi('MiniInputBorder', { link = 'FloatBorder' })
  hi('MiniInputCaret', { link = 'MiniInputPrompt' })
  hi('MiniInputHide', { link = 'DiagnosticFloatingWarn' })
  hi('MiniInputHint', { link = 'DiagnosticFloatingHint' })
  hi('MiniInputNormal', { link = 'NormalFloat' })
  hi('MiniInputPrompt', { link = 'DiagnosticFloatingInfo' })
end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniInput.config, vim.b.miniinput_config or {}, config or {})
end

-- State ----------------------------------------------------------------------
H.state_new = function(opts)
  opts.completion = opts.completion or ''
  opts.handlers.complete = opts.handlers.complete or MiniInput.default_complete
  opts.handlers.highlight = opts.handlers.highlight or MiniInput.default_highlight
  opts.handlers.key = opts.handlers.key or MiniInput.default_key
  opts.handlers.view = opts.handlers.view or MiniInput.default_view
  -- Allow `opts.hide` to be `nil` to mean "don't hide"
  opts.init_keys = opts.init_keys or {}
  opts.prompt = opts.prompt or 'Input'

  return { caret = 1, data = {}, input = '', opts = opts, status = 'start' }
end

H.state_set = function(new)
  local ok, msg = pcall(H.state_validate, new)
  if not ok then return H.notify(msg, 'WARN') end
  H.state = H.copy_tables(new)
end

H.state_validate = function(x, cur)
  H.check_type('state.caret', x.caret, 'number')
  H.check_type('state.data', x.data, 'table')
  H.check_type('state.input', x.input, 'string')

  if x.complete ~= nil then
    H.check_type('state.complete', x.complete, 'table')
    H.check_type('state.complete.base', x.complete.base, 'string')
    H.check_array_of('state.complete.items', x.complete.items, 'string')
    H.check_type('state.complete.id', x.complete.id, 'number')
  end

  H.check_type('state.opts.handlers.complete', x.opts.handlers.complete, 'function')
  H.check_type('state.opts.handlers.highlight', x.opts.handlers.highlight, 'function')
  H.check_type('state.opts.handlers.key', x.opts.handlers.key, 'function')
  H.check_type('state.opts.handlers.view', x.opts.handlers.view, 'function')

  H.check_type('state.opts.hide', x.opts.hide, 'string', true)

  H.check_array_of('state.opts.init_keys', x.opts.init_keys, 'string')

  H.check_type('state.opts.prompt', x.opts.prompt, 'string')

  H.check_one_of('state.opts.scope', x.opts.scope, { 'cursor', 'buffer', 'window', 'tabpage', 'editor' })

  H.check_one_of('state.status', x.status, { 'start', 'progress', 'accept', 'cancel' })
end

H.state_finish = function()
  local opts = vim.deepcopy(H.state.opts)
  local res = H.state.status == 'accept' and H.state.input or nil
  H.handle_step(nil)
  H.state = nil

  if res ~= nil and not opts.hide then
    table.insert(H.history, { input = res, prompt = opts.prompt, scope = opts.scope })
  end
  return res
end

H.state_is_end = function() return H.state.status == 'accept' or H.state.status == 'cancel' end

-- Handlers -------------------------------------------------------------------
H.handle_step = function(key)
  -- Stop handling keys past the end of the input
  if key ~= nil and H.state_is_end() then return end

  -- Track complete to check for a teardown (if navigation is not active).
  -- TODO: This doesn't quite work if there are zero matches: second press for
  -- completion navigation cancels it.
  local state = H.copy_tables(H.state)
  local complete = vim.deepcopy(H.state.complete)
  H.apply_handler('key', key)
  local is_complete_teardown = vim.deep_equal(complete, H.state.complete) and not vim.deep_equal(state, H.state)
  if is_complete_teardown then H.state.complete = nil end

  H.apply_handler('highlight')
  H.apply_handler('view')
  H.schedule_redraw()
end

H.apply_handler = function(name, arg)
  local state, input = H.copy_tables(H.state), nil
  if name == 'complete' and state.opts.hide then return end

  if name ~= 'key' and type(state.opts.hide) == 'string' then
    input = state.input
    state.input = string.rep(state.opts.hide, vim.fn.strchars(input))
  end

  local ok, res = pcall(state.opts.handlers[name], state, arg)
  if not ok then return H.notify('Error applying `' .. name .. '` handler: ' .. res) end

  local new_state = res or state
  new_state.input = input or new_state.input or state.input
  if name == 'complete' and type(new_state.complete) == 'table' then
    new_state.complete.id = 0
    new_state.complete.method = arg
  end
  H.state_set(new_state)
end

-- Default key handler --------------------------------------------------------
H.key_methods = {}

H.keycode = vim.fn.has('nvim-0.10') == 1 and vim.keycode
  or function(s) return vim.api.nvim_replace_termcodes(s, true, true, true) end
local k = H.keycode

-- General
H.key_methods[k('<CR>')] = function(state) state.status = 'accept' end
H.key_methods[k('<Esc>')] = function(state) state.status = 'cancel' end

-- Caret movement
H.key_methods[k('<Left>')] = function(state) state.caret = H.clamp(state.caret - 1, 1, vim.fn.strchars(state.input) + 1) end
H.key_methods[k('<Right>')] = function(state)
  state.caret = H.clamp(state.caret + 1, 1, vim.fn.strchars(state.input) + 1)
end
H.key_methods[k('<S-Left>')] = function(state)
  local caret, input = state.caret, state.input
  local to = H.match_keyword_chars(input, caret, 'left')
  state.caret = H.clamp(to + 1, 1, vim.fn.strchars(state.input) + 1)
end
H.key_methods[k('<S-Right>')] = function(state)
  local caret, input = state.caret, state.input
  local to = H.match_keyword_chars(input, caret, 'right')
  state.caret = H.clamp(to + 1, 1, vim.fn.strchars(state.input) + 1)
end
H.key_methods[k('<C-b>')] = function(state) state.caret = 1 end
H.key_methods[k('<C-e>')] = function(state)
  if state.complete == nil then
    state.caret = vim.fn.strchars(state.input) + 1
    return
  end
  H.advance_state_complete(state, -state.complete.id)
  state.complete = nil
end

-- Delete
H.key_methods[k('<BS>')] = function(state)
  local caret, input = state.caret, state.input
  if caret <= 1 then return end
  state.input = vim.fn.strcharpart(input, 0, caret - 2) .. vim.fn.strcharpart(input, caret - 1)
  state.caret = caret - 1
end
H.key_methods[k('<C-h>')] = H.key_methods[k('<BS>')]
H.key_methods[k('<Del>')] = function(state)
  local caret, input = state.caret, state.input
  if caret > vim.fn.strchars(input) then return end
  state.input = vim.fn.strcharpart(input, 0, caret - 1) .. vim.fn.strcharpart(input, caret)
end
H.key_methods[k('<C-u>')] = function(state)
  state.input = vim.fn.strcharpart(state.input, state.caret - 1)
  state.caret = 1
end
H.key_methods[k('<C-w>')] = function(state)
  local caret, input = state.caret, state.input
  local left_to = H.match_keyword_chars(input, caret, 'left')
  state.input = vim.fn.strcharpart(input, 0, left_to) .. vim.fn.strcharpart(input, caret - 1)
  state.caret = H.clamp(left_to + 1, 1, vim.fn.strchars(state.input) + 1)
end

-- Special insert
H.key_methods[k('<C-k>')] = function(state)
  local ok, new = pcall(vim.fn.digraph_get, H.getcharstr_many(2))
  if not ok then return end
  H.insert_at_caret(state, new)
end

H.key_methods[k('<C-r>')] = function(state)
  -- Get register content
  local register = H.getcharstr()
  if register == nil then return end
  -- - Mimic some "insert object under cursor" behavior of Command-line mode
  local reg_content
  local expand_var = ({ ['\1'] = '<cWORD>', ['\6'] = '<cfile>', ['\23'] = '<cword>' })[register]
  if expand_var then reg_content = vim.fn.expand(expand_var) end
  if register == '\f' then reg_content = vim.fn.getline('.') end
  if reg_content == nil then
    local has_register, r = pcall(vim.fn.getreg, register)
    reg_content = has_register and r or ''
  end

  H.insert_at_caret(state, reg_content)
end

H.key_methods[k('<C-q>')] = function(state)
  local char = H.getcharstr()
  if char == nil then return end

  -- See `:h i_CTRL-V_digit`
  if char:find('^[%doOxXuU]$') ~= nil then
    local ok, new_text = pcall(vim.fn.nr2char, H.get_ctrl_v_digits(char))
    if ok then H.insert_at_caret(state, new_text) end
    return
  end

  local ok, new_text = pcall(vim.fn.keytrans, char)
  if not ok or (ok and new_text:find('^<C%-.>$') ~= nil and char:len() == 1) then new_text = char end
  H.insert_at_caret(state, new_text)
end
H.key_methods[k('<C-v>')] = H.key_methods[k('<C-q>')]

-- History navigation
H.key_methods[k('<Up>')] = function(state)
  if not H.init_state_complete(state, 'history') then return end
  H.advance_state_complete(state, -1)
end
H.key_methods[k('<Down>')] = function(state)
  if not H.init_state_complete(state, 'history') then return end
  H.advance_state_complete(state, 1)
end
H.key_methods[k('<C-n>')] = H.key_methods[k('<Down>')]
H.key_methods[k('<C-p>')] = H.key_methods[k('<Up>')]

-- Completion navigation
H.key_methods[k('<Tab>')] = function(state)
  if not H.init_state_complete(state, state.opts.completion) then return end
  H.advance_state_complete(state, 1)
end
H.key_methods[k('<S-Tab>')] = function(state)
  if not H.init_state_complete(state, state.opts.completion) then return end
  H.advance_state_complete(state, -1)
end

-- Miscellaneous
H.key_methods[k('<C-x>')] = function(state)
  if type(state.opts.hide) == 'string' then
    state.data.hide_orig = state.opts.hide
    state.opts.hide = nil
    return
  end
  state.opts.hide = state.data.hide_orig or '*'
  state.data.hide_orig = nil
end

H.insert_at_caret = function(state, new_text)
  local caret, input = state.caret, state.input
  state.input = vim.fn.strcharpart(input, 0, caret - 1) .. new_text .. vim.fn.strcharpart(input, caret - 1)
  state.caret = caret + vim.fn.strchars(new_text)
end

H.match_keyword_chars = function(input, caret, side)
  local text = side == 'left' and vim.fn.strcharpart(input, 0, caret - 1) or vim.fn.strcharpart(input, caret - 1)
  local pat_keyword = side == 'left' and '[[:keyword:]]\\+$' or '^[[:keyword:]]\\+\\zs'
  local pat_non_keyword = side == 'left' and '[^[:keyword:]]\\+$' or '^[^[:keyword:]]\\+\\zs'

  local res = math.max(vim.fn.match(text, pat_keyword), vim.fn.match(text, pat_non_keyword), 0)
  return vim.fn.charidx(text, res) + (side == 'left' and 0 or (caret - 1))
end

H.get_ctrl_v_digits = function(submode)
  if submode:find('^%d$') then
    local rest = H.getcharstr_many(2)
    return tonumber(rest ~= nil and (submode .. rest) or nil)
  end
  if submode == 'o' or submode == 'O' then return tonumber(H.getcharstr_many(3), 8) end
  local n_chars = submode == 'U' and 8 or (submode == 'u' and 4 or 2)
  return tonumber(H.getcharstr_many(n_chars), 16)
end

H.init_state_complete = function(state, method)
  if state.complete == nil then H.apply_handler('complete', method) end
  state.complete = H.state.complete
  return type(state.complete) == 'table' and #state.complete.items > 0
end

H.advance_state_complete = function(state, increment)
  local old_id, base = state.complete.id, state.complete.base
  local old = state.complete.items[old_id] or base
  local new_id = (old_id + increment) % (#state.complete.items + 1)
  local new = state.complete.items[new_id] or base
  state.complete.id = new_id

  -- Replace currently shown candidate with the new one
  local caret, input = state.caret, state.input
  local old_len = vim.fn.strchars(old)
  state.input = vim.fn.strcharpart(input, 0, caret - old_len - 1) .. new .. vim.fn.strcharpart(input, caret - 1)
  state.caret = caret + (vim.fn.strchars(new) - old_len)
end

-- Default complete handler ---------------------------------------------------
H.complete_history = function(state)
  local base = vim.fn.strcharpart(state.input, 0, state.caret - 1)
  local raw, matched, seen = MiniInput.get_history(), {}, {}
  -- TODO: Filter first prefix+scope+prompt matches, then prefix+scope, then by
  -- prefix
  for i = #raw, 1, -1 do
    local val = raw[i].input
    if not seen[val] and vim.startswith(val, base) and val ~= base then table.insert(matched, val) end
    seen[val] = true
  end
  local items, n = {}, #matched
  for i = 1, #raw do
    items[n - i + 1] = matched[i]
  end
  state.complete = { base = base, items = items }
end

H.complete_buf_words = function(base)
  -- Do not match all words for performance reasons
  if base == '' then return {} end

  -- Get keywords in current buffer that fuzzy match base
  local pattern_parts = {}
  for i = 1, vim.fn.strchars(base) do
    table.insert(pattern_parts, vim.fn.strcharpart(base, i - 1, 1))
  end
  -- NOTE: This looks hacky, but it is very fast in common cases and already
  -- respects 'ignorecase' and 'smartcase'
  local pattern = '\\V\\k\\*' .. table.concat(pattern_parts, '\\k\\*') .. '\\k\\*'
  vim.g._miniinput_matches = {}

  local cache_hlsearch = vim.v.hlsearch
  local search_cmd = 'silent! keeppatterns %s/' .. pattern .. '/\\=add(g:_miniinput_matches, submatch(0))/gn'
  vim.cmd(search_cmd)
  -- Here `vim.v` doesn't work: https://github.com/neovim/neovim/issues/25294
  vim.cmd('let v:hlsearch=' .. cache_hlsearch)
  local matches = vim.g._miniinput_matches
  vim.g._miniinput_matches = nil

  -- Compute final unique matches sorted by how good fuzzy match is
  local uniq, seen = {}, { [base] = true }
  for _, m in ipairs(matches) do
    if not seen[m] then table.insert(uniq, m) end
    seen[m] = true
  end
  return vim.fn.matchfuzzy(uniq, base)
end

-- Views ----------------------------------------------------------------------
H.make_statusline_view = function(target, opts)
  opts = vim.tbl_extend('force', { symbol_caret = '▏' }, opts or {})
  local symbol_caret = opts.symbol_caret

  return function(state)
    local win_id, win_id_prev = vim.api.nvim_get_current_win(), state.data.win_id

    if win_id_prev ~= win_id then
      if H.is_valid_win(win_id_prev) then vim.wo[win_id_prev][target] = state.data[target] end
      state.data.win_id, state.data[target] = win_id, vim.wo[win_id][target]
      state.data.laststatus = vim.o.laststatus
    end

    local caret, input, prompt = state.caret, state.input, state.opts.prompt
    prompt = (prompt or ''):gsub('%s+$', '')
    local input_left, input_right = vim.fn.strcharpart(input, 0, caret - 1), vim.fn.strcharpart(input, caret - 1)

    -- TODO: Make sure that it focuses on cursor if the input is too wide
    local prompt_hl = state.opts.hide and 'MiniInputHide' or 'MiniInputPrompt'
    --stylua: ignore
    local chunks = {
      { prompt, prompt_hl }, { ' ', 'MiniInputNormal' },
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

H.check_one_of = function(name, x, choices)
  if vim.tbl_contains(choices, x) then return end
  local choices_string = table.concat(vim.tbl_map(vim.inspect, choices), ', ')
  local msg = string.format('`%s` should be one of %s', name, choices_string)
  H.error(msg)
end

H.check_array_of = function(name, x, ref_type)
  if not H.islist(x) then H.error('`' .. name .. '` should be array') end
  for i, k in ipairs(x) do
    if type(k) ~= ref_type then H.error('`' .. name .. '` items should be ' .. name) end
  end
end

H.notify = function(msg, level_name, silent)
  if not silent then vim.notify('(mini.input) ' .. msg, vim.log.levels[level_name]) end
end

H.schedule_redraw = vim.schedule_wrap(function() vim.cmd('redraw') end)

H.getcharstr = function(lmap)
  local ok, char = pcall(vim.fn.getcharstr, -1, { cursor = 'hide' })

  -- Terminate if no input or on hard-coded <C-c>
  if not ok or char == '' or char == '\3' then return end
  -- Respect language mappings only if needed
  return vim.o.iminsert == 0 and char or ((lmap or {})[char] or char)
end

H.getcharstr_many = function(n)
  local res = {}
  for i = 1, n do
    res[i] = H.getcharstr()
    if res[i] == nil then return nil end
  end
  return table.concat(res)
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

-- A copy of `vim.deepcopy()` that doesn't error on userdata and threads
H.copy_tables = function(x) return type(x) == 'table' and vim.tbl_map(H.copy_tables, x) or x end

return MiniInput
