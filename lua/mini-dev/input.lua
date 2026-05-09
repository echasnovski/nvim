-- TODO:
--
-- - Code:
--
-- - Docs:
--
-- - Test:
--     - The input should be properly cancelled (as if user pressed `<C-c>`) if
--       there is an error (during handler application or from the outside
--       "registered" by `getcharstr`) and re-throw the error instead of
--       returning input.
--     - <C-w> should work with multibyte charaters.
--     - Already shown completion should be teared down if `opts.hide` is toggled.
--     - `default_complete` respects 'ignorecase' and 'smartcase'.
--     - `gen_view.uiline` works with custom view handler that sets different
--       styles per scope.
--     - `gen_view.virtual` with `style='above'|'below'` should always make virtual
--       line(s) and current line visible. Matters at the top and the bottom of
--       the window viewport. Should work:
--       - With and without present winbar.
--       - After scope has changed.
--       - For both above and below.
--       - Do not do extra scroll both on edge and next to the edge.
--     - `gen_view.virtual` with `style='inline'` should not move extmark
--       with default complete from buffer words.
--     - Views should work with double-width charactrs (like Japanese).
--     - Typing `<C-v><Tab>` should insert literal `\t`. Its display should
--       work in any built-in view (properly compute width).
--     - `state_to_chunks()` should fit into maximum width when there are
--       translated characters.

--- *mini.input* Get user input
---
--- MIT License Copyright (c) 2026 Evgeni Chasnovski

--- Features:
---
--- - Get user input with full customizability of how keypresses are handled and
---   how the current state is shown.
---
--- - Built-in configurable views as floating window, statusline/tabline/winbar,
---   virtual line/text.
---
--- - Implementation is non-blocking but waits to return the input. This makes it
---   work in any mode without requiring it to change.
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
--- *MiniInput-hl-groups*
---
--- - `MiniInputAdded`   - added text during completion navigation.
--- - `MiniInputBorder`  - border of a floating window.
--- - `MiniInputCaret`   - caret symbol shown in a prompt area.
--- - `MiniInputHide`    - input is hidden.
--- - `MiniInputHint`    - hints shown during completion navigation.
--- - `MiniInputNormal`  - basic foreground/background.
--- - `MiniInputPrompt`  - input prompt (intention of the input).
--- - `MiniInputSpecial` - special keys (like literal `\t`, `\n`, etc.) in input.
---@tag MiniInput

--- TODO
---
--- - On every new key call `handlers.key`.
--- - After processing all new keys (usually one), call handlers: `highlight`, `view`.
--- - <C-c> is hard coded to cancel the input (due to how |getcharstr()| works).
--- - If state has changed but its <complete> field has not, it is assumed that
---   completion is not active anymore and <complete> field is removed.
--- - State's <highlight> field is removed if and only if <input> has changed
---   after processing a key.
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
--- Use `opts.init_keys`: >lua
---
---   MiniInput.get({ init_keys = { 'Default' } })
--- <
--- ## Custom mappings ~
---
--- Override `handlers.key` in |MiniInput.config|: >lua
---
---   local key_handler = function(state, key)
---     -- <C-a> - move caret to start of line
---     if key == '\1' then
---       state.caret = 1
---     -- <S-BS> - clear all input
---     elseif key == vim.keycode('<S-BS>') then
---       state.input, state.caret = '', 1
---     else
---       -- IMPORTANT: Fall back to processing as usual
---       return MiniInput.default_key(state, key)
---     end
---   end
---
---   require('mini.input').setup({ handlers = { key = key_handler } })
--- <
--- ## Basic command line
---
--- An alternative |Command-line| with highlighting and completion: >lua
---
---   -- Construct reusable `MiniInput.get()` options
---   local cmdline_opts = { prompt = 'Command', scope = 'editor' }
---   -- - Highlight using bundled Vim tree-sitter parser
---   local highlight_vim = MiniInput.gen_highlight.treesitter('vim')
---   cmdline_opts.handlers = { highlight = highlight_vim }
---   -- - Complete as if it is Command line input
---   cmdline_opts.completion = 'cmdline'
---
---   -- Create a mapping for `:`
---   local input_cmdline = function()
---     local cmd = MiniInput.get(cmdline_opts)
---     if cmd ~= nil then vim.cmd(cmd) end
---   end
---   vim.keymap.set('n', ':', input_cmdline)
--- <
--- # Handlers ~
---
--- ## Key ~
---
--- Notes:
--- - The suggested approach is "if a `key` is special - act on it, otherwise -
---   insert it at caret as is".
--- - `key` can be any string. Like as part of `opts.init_keys` in |MiniInput.get()|
---   or pasting from a clipboard (|vim.paste()|).
--- - Would be called for anything registered via |getcharstr()|. This includes
---   key combos (<M-...>, <C-S-...>, etc.), mouse clicks and wheel scrolls.
---
--- Perform custom actions based on arbitrary conditions: >lua
---
---   local key_handler = function(state, key)
---     -- Adjust prompt and scope
---     state.opts.prompt = state.opts.prompt:gsub('[?:]%s*$', '')
---     -- - Override hard-coded "cursor" scope for `vim.lsp.buf.rename()`
---     if state.opts.prompt == 'New Name' then
---       state.opts.scope = 'editor'
---     end
---
---     -- Hide from view and history
---     if state.opts.prompt:find('[Pp]assword') ~= nil then
---       state.opts.hide = true
---     end
---
---     -- IMPORTANT: Process as usual
---     state = MiniInput.default_key(state, key) or state
---
---     -- Auto fill
---     if state.input == 'AF' then
---       state.input, state.status = 'Autofilled input', 'accept'
---     end
---   end
---   require('mini.input').setup({ handlers = { key = key_handler } })
--- <
--- ## View ~
---
--- Show no view: >lua
---
---   require('mini.input').setup({ handlers = { view = function() end } })
--- <
--- Compute initial style depending on scope: >lua
---
---   -- Precompute reference handlers
---   local input = require('mini.input')
---   local view_virtline = input.gen_view.virtual({ style = 'above' })
---   local view_tabline = input.gen_view.uiline({ style = 'tabline' })
---   local view_winbar = input.gen_view.uiline({ style = 'winbar' })
---   local view_handler = function(state)
---     -- Choose appropriate view handler based on current scope
---     -- NOTE: Needs extra code to support interactive change of scope
---     local scope, view = state.opts.scope, view_tabline
---     if scope == 'buffer' or scope == 'window' then view = view_winbar end
---     if scope == 'cursor' or scope == 'line' then view = view_virtline end
---     return view(state)
---   end
---
---   require('mini.input').setup({ handlers = { view = view_handler } })
--- <
--- Change symbols for caret and hidden input: see |MiniInput.gen_view|.
---@tag MiniInput-examples

---@alias __input_to_chunks - <to_chunks> `(function)` - a function that takes a `state` and `max_width`
---     arguments and returns an array of `{ text, hl }` chunks that fit into
---     `max_width` width. See |MiniInput.state_to_chunks()|.

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local

-- Module definition ==========================================================
local MiniInput = {}
local H = {}

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
  -- -- TODO: Remove after Neovim=0.9 support is dropped
  -- if vim.fn.has('nvim-0.10') == 0 then
  --   vim.notify(
  --     '(mini.input) Neovim<0.10 is soft deprecated (module works but is not supported).'
  --       .. " It will be deprecated after the next 'mini.nvim' release (module might not work)."
  --       .. ' Please update your Neovim version.'
  --   )
  -- end

  -- Export module
  _G.MiniInput = MiniInput

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands()

  -- Create default highlighting
  H.create_default_hl()

  -- Set custom implementation
  vim.ui.input = MiniInput.ui_input

  -- Adjust terminal emulator's pasting with active input
  H.adjust_vim_paste()
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
--- Compute highlight info about the current input. Takes `state` as input and
--- should set <highlight> field.
---
--- Notes:
--- - It is usually a good idea to append to an existing <highlight> table field
---   if it already exists. This makes it work more robustly when combining
---   highlights (like in |MiniInput.ui_input()|).
---
--- ## View ~
---
--- Example of view that uses |nvim_echo()| to show the input: >lua
---
---   local view_handler = function(state)
---     -- Process start and end of the input lifecycle
---     local is_start = state.status == 'start'
---     local is_end = state.status == 'accept' or state.status == 'cancel'
---     if is_start or is_end then vim.cmd('mode') end
---     if is_end then return end
---
---     -- Compute text-hl chunks and show them
---     local chunks = MiniInput.state_to_chunks(state, vim.v.echospace)
---     vim.api.nvim_echo(chunks, false, {})
---   end
---
---   require('mini.input').setup({ handlers = { view = view_handler } })
--- <
--- ## Complete ~
---
--- Computes suggestions for the current state based on given method.
---
--- # Scope ~
---
--- `config.scope` is a string that defines an input scope. It is meant as an extra
--- information for handlers to tweak their behavior (`view` style, etc.). Possible
--- values: `"cursor"`, `"line"`, `"buffer"`, `"window"`, `"tabpage"`, `"editor"`, `"project"`.
---
--- The value from |MiniInput.config| is used as the default for |MiniInput.get()|.
MiniInput.config = {
  -- Functions that define how input process is processed
  handlers = {
    -- Compute completion candidates
    complete = nil,

    -- Compute highlighting of current input
    highlight = nil,

    -- Handle input start, every key press, and input end
    key = nil,

    -- Show current input state
    view = nil,
  },

  -- Default input scope: cursor/line/buffer/window/tabpage/editor/project
  scope = 'editor',
}
--minidoc_afterlines_end

--- Get input from the user
---
--- TODO: Some general words.
---
--- Data about all non-hidden accepted input results (even for empty input) are
--- added to the history. Get the whole history with |MiniInput.get_history()|.
---
--- `opts.hide` defines if input should be treated as hidden. Note: this does
--- not guarantee a total security of the input, only that the typed characters
--- are expected to not be shown on screen and not added to the history. If set:
--- - The `view` handler is expected to not directly show current input.
---   Like replace every character with pre-defined string or not show completely.
--- - The `complete` and `highlight` handlers are not called.
--- - Accepted input will not be added to the history.
---
---@param opts table|nil Options. Possible fields:
---   - <completion> `(string)` - completion method. Default: `''` to use default
---     completion method of the `complete` handler.
---   - <handlers> `(table)` - same as in |MiniInput.config|.
---   - <hide> `(boolean)` - whether to hide input. Default: `false`.
---   - <init_keys> `(table)` - array of string keys that are emulated before asking
---     for the user input. Using values that can be an output of |getcharstr()|
---     should be preferred, but a key handler should work with any string.
---     Default: `{}`.
---   - <prompt> `(string)` - intention of the input, same as in |input()|.
---     Default: `'Input'`.
---   - <scope> `(string)` - same as in |MiniInput.config|. Default: the value from
---     `MiniInput.config` except some hard coded exceptions:
---       - |vim.lsp.buf.rename()| will use "cursor" if no `new_name` is supplied.
---
---@return string|nil User input if accepted or `nil` if canceled.
---
---@usage >lua
---   local input = MiniInput.get({
---     -- Intention of the input
---     prompt = 'New value',
---     -- The input is for something at cursor
---     scope = 'cursor',
---     -- Emulate pressing `a`, `<BS>`, and `b`
---     init_keys = { 'a', vim.keycode('<BS>'), 'b' },
---   })
--- <
MiniInput.get = function(opts)
  H.check_type('opts', opts, 'table', true)
  opts = opts or {}
  opts.scope = opts.scope or (_G.MiniInput or {})._temp_default_scope

  -- Only allow one input at a time
  if H.state ~= nil then return nil end

  local init_state = H.state_new(H.get_config(opts))
  H.state_set(init_state)

  H.handle_step(nil)
  if H.state_is_end() then return H.state_finish() end
  H.state.status = 'progress'

  H.mock_key_input(H.state.opts.init_keys)

  local lmap = H.get_lmap()
  for _ = 1, 1000000 do
    local key = H.getcharstr(lmap)
    if key == nil then H.state.status = 'cancel' end
    if H.state_is_end() then break end
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
  local input_opts = { completion = opts.completion, init_keys = { opts.default }, prompt = opts.prompt }
  input_opts.handlers = { highlight = H.make_ui_select_hl_fun(opts.highlight) }

  on_confirm(MiniInput.get(input_opts))
end

--- Get current input state
---
--- It stores information about the current state of the user input.
--- Can be `nil` to indicate that there is no active user input.
---
--- During user input, it is a table with the following fields:
--- - <caret> `(number|nil)` - character index at which to modify input.
---   It is `nil` for hidden input.
--- - <complete> `(table|nil)` - information about active completion navigation.
---   If present, it means that completion navigation is in action.
---   Its fields describe the state of navigation:
---     - <base> `(string)` - reference text to the left of caret at the start
---       of completion it uses to compute candidates. Can be empty string.
---     - <id> `(number)` - identfier of current completion item. Can be zero to
---       mean that the base is shown. If not zero, it means that a `items[id]`
---       candidate is now shown to the left of caret as the part of the input.
---     - <items> `(table)` - string array of completion candidates. May be empty.
---     - <method> `(string)` - completion method. Like `"default"`, `"history"`, etc.
--- - <data> `(table)` - any information to be reused within same input session.
---   Note: present fields should not change to avoid surprising behavior.
--- - <highlight> `(table|nil)` - information about current input highlighting.
---   Should be an array of highlight ranges. They might be not ordered, overlap,
---   go outside of input width. It is up to the view handler to decide how to
---   interpret them. See |MiniInput.state_to_chunks()| for a helper.
---   Fields of a single highlight range:
---     - <from> `(number)` - character index (one-indexed) of range start.
---     - <to> `(number)` - character index (one-indexed) of range end (inclusive).
---       Should not be smaller than <from>. Can be |math.huge|.
---     - <hl> `(string)` - higlight group to use for highlighting.
--- - <input> `(string|nil)` - current user input or `nil` for hidden input.
--- - <opts> `(table)` - input options, same as in |MiniInput.get()|.
--- - <prompt> `(string)` - intention of the input, same as in |input()|.
--- - <status> `(string)` - one of `"start"`, `"progress"`, `"accept"`, `"cancel"`.
---
---@return table|nil Current state if input is active, `nil` otherwise.
MiniInput.get_state = function()
  if H.state == nil then return nil end
  local res = H.copy_tables(H.state)
  if res.opts.hide then
    res.input, res.caret = nil, nil
  end
  return res
end

--- Get input history
---
---@return table Array with data about all previous non-hidden inputs (from earliest
---   to latest). Each element is a table with the following fields:
---   - <cwd> `(string)` - |current-directory| at the time of input's end.
---   - <input> `(string)` - input result.
---   - <prompt> `(string)` - `opts.prompt` supplied in |MiniInput.get()|.
---   - <scope> `(string)` - `opts.scope` supplied in |MiniInput.get()|.
MiniInput.get_history = function() return vim.deepcopy(H.history) end

--- Set input history
---
---@param history table Array describing all previous inputs. Same structure
---   as |MiniInput.get_history()| output.
MiniInput.set_history = function(history)
  H.check_array_of('history', history, 'table')
  for i, h in ipairs(history) do
    local item = string.format('history[%d]', i)
    H.check_type(item .. '.cwd', h.cwd, 'string')
    H.check_type(item .. '.input', h.input, 'string')
    H.check_type(item .. '.prompt', h.prompt, 'string')
    H.check_one_of(item .. '.scope', h.scope, H.allowed_scopes)
  end

  H.history = vim.deepcopy(history)
end

--- Refresh active input
MiniInput.refresh = function()
  if H.state == nil then return end
  H.handle_step(nil)
  if H.state_is_end() then H.state_finish() end
end

--- Highlight generators
---
--- This is a table with function elements. Call to actually get a view function.
MiniInput.gen_highlight = {}

--- Highlight with tree-sitter
MiniInput.gen_highlight.treesitter = function(lang)
  local append_ts_hl_range = function(arr, line, tstree, tree)
    local query = tstree and vim.treesitter.query.get(tree:lang(), 'highlights')
    if query == nil then return end
    for capture, node in query:iter_captures(tstree:root(), line) do
      -- Ignore private captures
      if query.captures[capture]:sub(1, 1) ~= '_' then
        local _, from, _, to = node:range()
        local hl = string.format('@%s.%s', query.captures[capture], query.lang)
        from, to = vim.fn.charidx(line, from) + 1, vim.fn.charidx(line, to)
        if from <= to then table.insert(arr, { from = from, to = to, hl = hl }) end
      end
    end
  end

  return function(state)
    local line = state.input
    local ok, parser = pcall(vim.treesitter.get_string_parser, line, lang)
    if not ok or parser == nil then return end

    -- Traverse all trees and compute highlight ranges
    parser:parse(true)
    local highlight = {}
    parser:for_each_tree(function(tstree, tree) append_ts_hl_range(highlight, line, tstree, tree) end)

    state.highlight = highlight
  end
end

--- View generators
---
--- This is a table with function elements. Call to actually get a view function.
---
--- Notes:
--- - Multiline input (i.e. containing newline character `\n`) is shown as
---   a single line.
---
--- Each element accepts `to_chunks` option. It is a function that takes
--- a `state` and `max_width` arguments and returns an array of `{ text, hl }`
--- chunks that fit into `max_width` width.
---
--- This is a way to adjust how input is shown. Like caret/hide symbols, etc.
--- By default uses |MiniInput.state_to_chunks()|, which also means:
--- - All special characters (like literal `\t`, `\n`, etc.) will be translated
---   via |keytrans()|.
---
--- Example: >lua
---
---   local input = require('mini.input')
---
---   -- Adjust how state is converted to text-hl chunks
---   local to_chunks_opts = { symbol_caret = '_', symbol_hide = '*' }
---   local to_chunks = function(state, max_width)
---     return MiniInput.state_to_chunks(state, max_width, to_chunks_opts)
---   end
---
---   -- Supply custom `to_chunks` as an option
---   local view_opts = { to_chunks = to_chunks }
---   input.setup({ handlers = { view = input.gen_view.floatwin(view_opts) } })
--- <
MiniInput.gen_view = {}

--- Floating window view
---
--- TODO:
--- - How config computation for different scopes is done.
---
--- Notes:
--- - Always computes config with `relative="editor"` and `anchor="NW"`.
--- - Computes width taking into account caret symbol and a completion hint.
---
---@param opts table|nil Options. Possible fields:
---   - <adjust_config> `(function)` - function to adjust default config. Will be
---     called with two arguments: current input state (|MiniInput.get_state()|)
---     and a window config computed based on `opts.style`. Should return
---     an adjusted window config.
---     Default: `function(state, config) return config end`.
---
---   - <style> `(string)` - a two-character description of how window to be shown.
---     Default: `"BL"`.
---
---       First character describes vertical position:
---       - `"T"` - top window border will be at scope's top border.
---       - `"M"` - middle between top and bottom window borders will be at the
---         middle of scope's top and bottom borders.
---       - `"B"` - bottom window border will be at scope's bottom border.
---
---       Second character describes horizontal position:
---       - `"L"` - left window border will be at scope's left border.
---       - `"M"` - middle between left and right window borders will be at the
---         middle of scope's left and right borders.
---       - `"R"` - right window border will be at scope's right border.
---
---   __input_to_chunks
---
---@usage >lua
---   local input = require('mini.input')
---
---   -- Choose initial style based on the scope
---   local view_topmiddle = input.gen_view.floatwin({ style = 'TM' })
---   local view_bottomleft = input.gen_view.floatwin({ style = 'BL' })
---   local view_handler = function(state)
---     local scope, view = state.opts.scope, view_topmiddle
---     if scope == 'cursor' or scope == 'line' then view = view_bottomleft end
---     return view(state)
---   end
---
---   input.setup({ handlers = { view = view_handler } })
--- <
MiniInput.gen_view.floatwin = function(opts)
  local default_opts = { style = 'BL' }
  default_opts.adjust_config = function(_, config) return config end
  local default_to_chunks_opts = { include_prompt = false, include_hint = false }
  default_opts.to_chunks = function(state, max_width)
    return MiniInput.state_to_chunks(state, max_width, default_to_chunks_opts)
  end
  opts = vim.tbl_extend('force', default_opts, opts or {})
  H.check_type('opts.adjust_config', opts.adjust_config, 'callable')
  H.check_one_of('opts.style', opts.style, { 'TL', 'TM', 'TR', 'ML', 'MM', 'MR', 'BL', 'BM', 'BR' })
  H.check_type('opts.to_chunks', opts.to_chunks, 'callable')

  -- Change style in vertical-horizontal order
  local next_styles =
    { BL = 'ML', ML = 'TL', TL = 'BM', BM = 'MM', MM = 'TM', TM = 'BR', BR = 'MR', MR = 'TR', TR = 'BL' }

  return function(state)
    if H.state_is_end(state) then
      pcall(vim.api.nvim_win_close, state.data.floating_win_id, true)
      pcall(vim.api.nvim_buf_delete, state.data.floating_buf_id, { force = true })
      return
    end
    local style, _ = H.handle_view_style(state, opts.style, next_styles)

    -- Try to fit all chunks first, but later still truncate to window width
    local winborder = vim.fn.exists('+winborder') == 0 and '' or vim.o.winborder
    default_to_chunks_opts = { include_prompt = winborder == 'none', include_hint = winborder == 'none' }
    local chunks = H.get_chunks(opts, state)
    local default_config = H.default_floatwin_config(state, style, H.get_chunks_width(chunks))
    local config = opts.adjust_config(state, default_config)
    chunks = H.get_chunks(opts, state, config.width)

    H.ensure_floatwin_buf(state, chunks)
    H.ensure_floatwin_win(state, config)
  end
end

--- UI line (statusline, tabline, winbar) view
---
---@param opts table|nil Options. Possible fields:
---   - <style> `(string)` - which UI line to use. One of `"statusline"`,
---     `"tabline"`, `"winbar"`. Default: `"statusline"`.
---
---   __input_to_chunks
---
---@usage >lua
---   local input = require('mini.input')
---
---   -- Choose initial style based on the scope
---   local view_tabline = input.gen_view.uiline({ style = 'tabline' })
---   local view_winbar = input.gen_view.uiline({ style = 'winbar' })
---   local view_handler = function(state)
---     local scope, view = state.opts.scope, view_winbar
---     if scope == 'tabpage' or scope == 'editor' or scope == 'project' then
---       view = view_tabline
---     end
---     return view(state)
---   end
---
---   input.setup({ handlers = { view = view_handler } })
--- <
MiniInput.gen_view.uiline = function(opts)
  opts = vim.tbl_extend('force', { style = 'statusline', to_chunks = MiniInput.state_to_chunks }, opts or {})
  H.check_one_of('opts.style', opts.style, { 'statusline', 'tabline', 'winbar' })
  H.check_type('opts.to_chunks', opts.to_chunks, 'callable')

  local next_styles = { statusline = 'winbar', winbar = 'tabline', tabline = 'statusline' }
  local escape_stl = function(x) return (x:gsub('%%', '%%%%')) end

  return function(state)
    local style, style_is_new = H.handle_view_style(state, opts.style, next_styles)
    H.uiline_handle_option_values(state, style_is_new)
    if H.state_is_end(state) then return end

    local max_width = style == 'tabline' and vim.o.columns or vim.fn.winwidth(0)
    local chunks = H.get_chunks(opts, state, max_width)
    local parts = vim.tbl_map(function(c) return '%#' .. escape_stl(c[2]) .. '#' .. escape_stl(c[1]) end, chunks)
    local uiline_value = table.concat(parts) .. '%#MiniInputNormal#'

    local opt = style == 'tabline' and vim.o or vim.wo
    opt[style] = uiline_value
    if style == 'statusline' and vim.o.laststatus < 2 then vim.o.laststatus = 2 end
    if style == 'tabline' and vim.o.showtabline < 2 then vim.o.showtabline = 2 end
  end
end

--- Virtual text view
---
---@param opts table|nil Options. Possible fields:
---   - <style> `(string)` - how to display virtual text. One of `"above"`, `"below"`,
---     `"inline"`. Default: `"above"`.
---
---   __input_to_chunks
---
---@usage >lua
---   -- Choose different initial style
---   local input = require('mini.input')
---   local view_handler = input.gen_view.virtual({ style = 'inline' })
---   input.setup({ handlers = { view = view_handler } })
--- <
MiniInput.gen_view.virtual = function(opts)
  opts = vim.tbl_extend('force', { style = 'above', to_chunks = MiniInput.state_to_chunks }, opts or {})

  H.check_one_of('opts.style', opts.style, { 'above', 'below', 'inline' })
  H.check_type('opts.to_chunks', opts.to_chunks, 'callable')

  local ns_id = H.ns_id.view
  local next_styles = { above = 'below', below = 'inline', inline = 'above' }

  return function(state)
    -- Cleanup
    local buf_id, extmark_id = vim.api.nvim_get_current_buf(), state.data.extmark_id
    if H.state_is_end(state) then
      pcall(vim.api.nvim_buf_del_extmark, state.data.buf_id, ns_id, extmark_id)
      return
    end
    local ok_extmark = pcall(vim.api.nvim_get_extmark_by_id, state.data.buf_id, ns_id, extmark_id, {})
    if not (buf_id == state.data.buf_id and ok_extmark) then
      pcall(vim.api.nvim_buf_del_extmark, state.data.buf_id, ns_id, extmark_id)
    end
    state.data.buf_id = buf_id

    local style, style_is_new = H.handle_view_style(state, opts.style, next_styles)
    local is_virtline = style == 'above' or style == 'below'

    -- Get chunks
    local win_info = H.get_curwin_info()
    local max_width = win_info.width - win_info.textoff
    local chunks = H.get_chunks(opts, state, max_width)
    local chunks_width = H.get_chunks_width(chunks)
    if is_virtline and chunks_width < max_width then
      table.insert(chunks, { string.rep(' ', max_width - chunks_width), 'MiniInputNormal' })
    end

    -- Set
    local extmark_opts = { id = state.data.extmark_id }
    if is_virtline then
      extmark_opts.virt_lines = { chunks }
      extmark_opts.virt_lines_above = style == 'above'
    else
      extmark_opts.virt_text = chunks
      extmark_opts.virt_text_pos = 'inline'
    end
    local cur_pos = vim.api.nvim_win_get_cursor(0)
    state.data.extmark_id = vim.api.nvim_buf_set_extmark(0, ns_id, cur_pos[1] - 1, cur_pos[2], extmark_opts)

    -- Ensure that both current and virtual lines are visible
    if is_virtline and (state.status == 'start' or style_is_new) then
      local win_line, win_height = vim.fn.winline(), vim.fn.winheight(0)
      if win_line == 1 and style == 'above' then vim.cmd('normal! \25') end
      -- With 'above' the cursor line is moved down, with 'below' - no move
      -- local is_below_screen = style == 'above' and win_line > win_height or win_line >= win_height
      local is_below_screen = (win_line - (style == 'above' and 1 or 0)) >= win_height
      if is_below_screen then vim.cmd('normal! \5') end
    end
  end
end

--- Default key handler
---
--- Emulates most of |Command-line-mode| editing (|cmdline-editing|):
--- - Accept: <CR>. To insert literal newline, type `<C-j>`.
--- - Cancel: <Esc>.
--- - Move caret:
---     - <Left>, <Right> - one character to left / right.
---     - <M-h>, <M-l> - one character to left / right.
---     - <S-Left>, <S-Right> - one word to left / right.
---     - <C-b>, <C-e> (if no completion) - to start / end of input.
---     - <Home>, <End> - to start / end of input.
--- - Delete:
---     - <BS> / <C-h> - to caret's left. If `opts.autopair` is enabled, also delete
---       a character to caret's right if it forms a respected character pair.
---       See "Autopair" entry.
---     - <Del> - at caret.
---     - <C-u> - from start to caret. As |c_CTRL-U|.
---     - <C-w> - contiguous keyword or non-keyword to caret's left. As |c_CTRL-W|.
--- - Insert at caret:
---     - <C-k> - digraph based on the next two pressed keys. As |c_CTRL-K|.
---     - <C-r> - content of a register. As |c_CTRL-R| including support for
---       special <C-a>, <C-f>, <C-l>, <C-w> keys for a register.
---     - <C-v>, <C-q> - next key literally. As |c_CTRL-V| and |i_CTRL-V_digit|
---       (all digits must be typed in full).
--- - Autopair (if `opts.autopair` is set) is similar to |mini.pairs|:
---     - Opening characters `(`, `[`, `{` always insert a `()`, `[]`, `{}` pair and places
---       caret inside of it.
---     - Closing characters `)`, `]`, `}` move caret to the right if there is the same
---       character to the right.
---     - Closeopen character `'`, `"`, <`> perfom "close" action if possible and
---       "open" action if not.
---     - In all cases press <C-v> before special character to insert it verbatim.
--- - Completion:
---     - <Tab>, <S-Tab> - initiate completion based on input method and navigate.
---       Note: type `<C-v><Tab>` to insert literat `\t`.
---     - <C-n>, <C-p>, <Up>, <Down> - initiate history completion and navigate.
---     - <C-e> - stop completion.
--- - Miscellaneous:
---     - <C-o> - change scope of the input. Cycles through all available ones.
---     - <C-s> - change view style. Works only with |MiniInput.gen_view| view
---       handlers. Cycles through all available ones.
---     - <C-x> - toggle hide/unhide of the input.
--- - Special keys (combo, mouse, but not whitespace) not listed above - ignored.
---   Anything else (even more than a single character) - inserted at caret.
---
---@param state table TODO
---@param key string|nil A key to process.
---@param opts table|nil Options. Possible fields:
---   - <autopair> `(boolean)` - whether perform add autopair. Default: `false`.
MiniInput.default_key = function(state, key, opts)
  opts = opts or {}
  if key == nil or H.state_is_end(state) then return end
  if opts.autopair and H.key_methods_autopair[key] ~= nil then return H.key_methods_autopair[key](state) end
  if H.key_methods[key] ~= nil then return H.key_methods[key](state, opts) end
  if H.is_special_char(key) then return end
  H.insert_at_caret(state, key)
end

--- Default highlight handler
MiniInput.default_highlight = function(state)
  if H.state_is_end(state) then return end

  -- Only show characters added during completion navigation
  if state.complete == nil then return end

  local cur_item = state.complete.items[state.complete.id]
  local pos = vim.fn.matchfuzzypos({ cur_item }, state.complete.base)[2][1]
  if pos == nil then return end

  -- Matches are increasing character zero-based indexes. Highlight ranges
  -- between them, including start and end edges.
  local cur_item_width = vim.fn.strchars(cur_item)
  table.insert(pos, 1, -1)
  table.insert(pos, cur_item_width)
  local offset, ranges = state.caret - cur_item_width - 1, {}
  for i = 2, #pos do
    if pos[i] - pos[i - 1] > 1 then
      local from = offset + pos[i - 1] + 1
      local to = offset + pos[i] - 1
      table.insert(ranges, { from = from + 1, to = to + 1, hl = 'MiniInputAdded' })
    end
  end

  -- Respect maybe already present <highlight>
  state.highlight = state.highlight or {}
  vim.list_extend(state.highlight, ranges)
end

--- Default view handler
---
--- Same as |MiniInput.gen_view.floatwin()| with default options.
MiniInput.default_view = function(state) end -- Generated later

--- Default complete handler
---
--- TODO: general words
--- TODO: completion methods (`"history"`, `""`, anything from |getcompletion()|).
---
---@param state table Current state. See |MiniInput.get_statee()|.
---@param method string Completion method.
---@param opts table|nil Options. Possible fields:
---   - <precise_history> `(boolean)` - whether for `method='history'` try to match
---     only entries that have <cwd> as |current-directory|, same <scope> and
---     <prompt> as in current state. Default: `true`.
---
---@usage >lua
---   -- Do not match history precisely
---   local complete_opts = { precise_history = false }
---   local complete_handler = function(state, method)
---     return MiniInput.default_complete(state, method, complete_opts)
---   end
---   require('mini.input').setup({ handlers = { complete = complete_handler } })
--- <
MiniInput.default_complete = function(state, method, opts)
  opts = vim.tbl_extend('force', { precise_history = true }, opts or {})

  if H.state_is_end(state) then return end
  if method == 'history' then return H.complete_history(state, opts.precise_history) end
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

--- Convert state into text-hl chunks
---
--- - Treat `state.highlight` elements in increasing priority, i.e. later ones
---   are placed "on top" of the previous ones if they overlap.
--- - Uses pre-determined module's highlight groups.
MiniInput.state_to_chunks = function(state, max_width, opts)
  H.state_validate(state)
  H.check_type('max_width', max_width, 'number', true)
  local default_opts = { keytrans = true, include_prompt = true, include_hint = true }
  default_opts.symbol_caret = '▏'
  default_opts.symbol_hide = '•'
  opts = vim.tbl_extend('force', default_opts, opts or {})
  H.check_type('opts.keytrans', opts.keytrans, 'boolean')
  H.check_type('opts.include_prompt', opts.include_prompt, 'boolean')
  H.check_type('opts.include_hint', opts.include_hint, 'boolean')
  H.check_type('opts.symbol_caret', opts.symbol_caret, 'string')
  H.check_type('opts.symbol_hide', opts.symbol_hide, 'string')

  -- Precompute state data
  local hide, symbol_hide = state.opts.hide, opts.symbol_hide
  local input = hide and string.rep(symbol_hide, vim.fn.strchars(state.input)) or state.input
  local caret = (hide and vim.fn.strchars(symbol_hide) or 1) * (state.caret - 1) + 1

  -- Compute input chunks to left and right of caret
  local max_to = vim.fn.strchars(input)
  local hl_ranges = { { from = 1, to = max_to, hl = 'MiniInputNormal' } }
  for _, range in ipairs(state.highlight or {}) do
    hl_ranges = H.insert_hl_range(hl_ranges, max_to, range.from, range.to, range.hl)
  end

  local input_chunks = {}
  for i, r in ipairs(hl_ranges) do
    input_chunks[i] = { vim.fn.strcharpart(input, r.from - 1, r.to - r.from + 1), r.hl }
  end
  local input_chunks_left, input_chunks_right = H.split_chunks_at(input_chunks, caret - 1)

  -- Compute chunks in specific order:
  -- prompt - input_left - caret - complete_hint - input_right
  local chunks, keytrans = {}, opts.keytrans
  if opts.include_prompt and state.opts.prompt ~= '' then
    local prompt = vim.trim(state.opts.prompt)
    local prompt_hl = hide and 'MiniInputHide' or 'MiniInputPrompt'
    local new = { { prompt, prompt_hl }, { ' ', 'MiniInputNormal' } }
    H.append_chunks(chunks, new, keytrans)
  end

  H.append_chunks(chunks, input_chunks_left, keytrans)

  if opts.symbol_caret ~= '' then H.append_chunks(chunks, { { opts.symbol_caret, 'MiniInputCaret' } }, keytrans) end
  local caret_offset = H.get_chunks_width(chunks)

  if opts.include_hint and state.complete ~= nil then
    local hint = string.format('(%d/%d)', state.complete.id, #state.complete.items)
    H.append_chunks(chunks, { { hint, 'MiniInputHint' } }, keytrans)
  end

  H.append_chunks(chunks, input_chunks_right, keytrans)

  return H.fit_chunks_to_width(chunks, max_width, caret_offset)
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniInput.config)

-- Current state of user input
H.state = nil

-- History of inputs
H.history = {}

-- Supported scopes
H.allowed_scopes = { 'cursor', 'line', 'buffer', 'window', 'tabpage', 'editor', 'project' }

-- Various cache
H.cache = { error = nil }

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

  H.check_type('scope', config.scope, 'string')

  return config
end

H.apply_config = function(config)
  MiniInput.config = config

  -- Ensure clear history
  H.history = {}

  -- Ensure default scope for some core functions
  -- NOTE: Use `vim.schedule` to not load `vim.lsp` during startup
  vim.schedule(function() vim.lsp.buf.rename = H.mock_lsp_buf_rename(vim.lsp.buf.rename) end)
end

H.create_autocommands = function()
  local gr = vim.api.nvim_create_augroup('MiniInput', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = gr, pattern = pattern, callback = callback, desc = desc })
  end

  au('VimResized', '*', function() MiniInput.refresh() end, 'Refresh on resize')
  au('ColorScheme', '*', H.create_default_hl, 'Ensure colors')
end

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
  hi('MiniInputSpecial', { link = 'DiagnosticFloatingWarn' })
end

H.adjust_vim_paste = function()
  local paste_orig = vim.paste
  vim.paste = function(lines, phase)
    if MiniInput.get_state() == nil then return paste_orig(lines, phase) end
    if phase ~= -1 then
      H.notify('There is no streaming paste support. Use `<C-r>+` or `<C-r>*`.', 'HINT')
      return paste_orig(lines, phase)
    end
    H.mock_key_input({ table.concat(lines, '\n') })
  end
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
  if opts.hide == nil then opts.hide = false end
  opts.init_keys = opts.init_keys or {}
  opts.prompt = opts.prompt or 'Input'
  -- opts.scope should already be precomputed

  return { caret = 1, data = {}, input = '', opts = opts, status = 'start' }
end

H.state_set = function(new)
  local ok, msg = pcall(H.state_validate, new)
  if not ok then return H.cache_error(msg) end
  H.state = H.copy_tables(new)
end

H.state_validate = function(x)
  H.check_type('state.caret', x.caret, 'number')
  H.check_type('state.data', x.data, 'table')
  H.check_type('state.input', x.input, 'string')
  H.check_one_of('state.status', x.status, { 'start', 'progress', 'accept', 'cancel' })

  if not (1 <= x.caret and x.caret <= (vim.fn.strchars(x.input) + 1)) then
    H.error('`state.caret` should be between 1 and input width plus 1')
  end

  if x.complete ~= nil then
    H.check_type('state.complete', x.complete, 'table')
    H.check_type('state.complete.base', x.complete.base, 'string')
    H.check_array_of('state.complete.items', x.complete.items, 'string')
    H.check_type('state.complete.id', x.complete.id, 'number')
  end

  if x.highlight ~= nil then
    H.check_array_of('state.highlight', x.highlight, 'table')
    for i, h in ipairs(x.highlight) do
      local item = string.format('state.highlight[%d]', i)
      H.check_type(item .. '.from', h.from, 'number')
      H.check_type(item .. '.to', h.to, 'number')
      H.check_type(item .. '.hl', h.hl, 'string')
      if h.from > h.to then H.error(string.format('%s.from is bigger than %s.to', item, item)) end
    end
  end

  H.check_type('state.opts.handlers.complete', x.opts.handlers.complete, 'function')
  H.check_type('state.opts.handlers.highlight', x.opts.handlers.highlight, 'function')
  H.check_type('state.opts.handlers.key', x.opts.handlers.key, 'function')
  H.check_type('state.opts.handlers.view', x.opts.handlers.view, 'function')
  H.check_type('state.opts.hide', x.opts.hide, 'boolean')
  H.check_array_of('state.opts.init_keys', x.opts.init_keys, 'string')
  H.check_type('state.opts.prompt', x.opts.prompt, 'string')
  H.check_one_of('state.opts.scope', x.opts.scope, H.allowed_scopes)
end

H.state_finish = function()
  if H.cache.is_in_getcharstr then return vim.api.nvim_feedkeys('\3', 't', true) end

  H.handle_step(nil)

  local res = H.state.status == 'accept' and H.state.input or nil
  local err, opts = H.cache.error, vim.deepcopy(H.state.opts)
  H.state, H.cache = nil, {}
  (_G.MiniInput or {})._temp_default_scope = nil

  if err ~= nil then H.error(err) end

  if res ~= nil and not opts.hide then
    local hist = { input = res, prompt = opts.prompt, scope = opts.scope, cwd = vim.fn.getcwd() }
    table.insert(H.history, hist)
  end
  return res
end

H.state_is_end = function(state)
  state = state or H.state
  return state.status == 'accept' or state.status == 'cancel'
end

H.mock_lsp_buf_rename = function(f)
  return function(new_name, opts)
    if new_name == nil then (_G.MiniInput or {})._temp_default_scope = 'cursor' end
    return f(new_name, opts)
  end
end

-- Handlers -------------------------------------------------------------------
H.handle_step = function(key, skip_redraw)
  local state = H.copy_tables(H.state)
  H.apply_handler('key', key)

  -- Stop completion if there was something outside completion navigation
  local is_complete_stop = vim.deep_equal(state.complete, H.state.complete) and not vim.deep_equal(state, H.state)
  if is_complete_stop then H.state.complete = nil end

  -- Stop previous highlighting if something changed outside of caret
  local caret = H.state.caret
  H.state.caret, state.caret = nil, nil
  if not vim.deep_equal(state, H.state) then H.state.highlight = nil end
  H.state.caret = caret

  H.apply_handler('highlight')
  H.apply_handler('view')
  if not skip_redraw then H.redraw() end
end

H.apply_handler = function(name, arg)
  local state, input = H.copy_tables(H.state), nil
  if state.opts.hide and (name == 'highlight' or name == 'complete') then return end

  local ok, res = pcall(state.opts.handlers[name], state, arg)
  if not ok then return H.cache_error('Error applying `' .. name .. '` handler: ' .. res) end

  local new_state = res or state
  if name == 'complete' and type(new_state.complete) == 'table' then
    new_state.complete.id = 0
    new_state.complete.method = arg
  end
  H.state_set(new_state)
end

H.mock_key_input = function(keys)
  if type(keys) ~= 'table' then return end
  for _, k in ipairs(keys) do
    H.handle_step(k, true)
    if H.state_is_end() then return H.state_finish() end
  end
  H.redraw()
end

-- Default key handler --------------------------------------------------------
H.key_methods = {}

H.keycode = vim.fn.has('nvim-0.10') == 1 and vim.keycode
  or function(s) return vim.api.nvim_replace_termcodes(s, true, true, true) end
local kc = H.keycode

-- General
H.key_methods[kc('<CR>')] = function(state, _) state.status = 'accept' end
H.key_methods[kc('<Esc>')] = function(state, _) state.status = 'cancel' end

-- Caret movement
H.key_methods[kc('<Left>')] = function(state, _)
  state.caret = H.clamp(state.caret - 1, 1, vim.fn.strchars(state.input) + 1)
end
H.key_methods[kc('<Right>')] = function(state, _)
  state.caret = H.clamp(state.caret + 1, 1, vim.fn.strchars(state.input) + 1)
end
H.key_methods[kc('<M-h>')] = H.key_methods[kc('<Left>')]
H.key_methods[kc('<M-l>')] = H.key_methods[kc('<Right>')]
H.key_methods[kc('<S-Left>')] = function(state, _)
  local caret, input = state.caret, state.input
  local to = H.match_keyword_chars(input, caret, 'left')
  state.caret = H.clamp(to + 1, 1, vim.fn.strchars(state.input) + 1)
end
H.key_methods[kc('<S-Right>')] = function(state, _)
  local caret, input = state.caret, state.input
  local to = H.match_keyword_chars(input, caret, 'right')
  state.caret = H.clamp(to + 1, 1, vim.fn.strchars(state.input) + 1)
end
H.key_methods[kc('<C-b>')] = function(state, _) state.caret = 1 end
H.key_methods[kc('<C-e>')] = function(state, _)
  if state.complete == nil then
    state.caret = vim.fn.strchars(state.input) + 1
    return
  end
  H.advance_state_complete(state, -state.complete.id)
  state.complete = nil
end
H.key_methods[kc('<Home>')] = H.key_methods[kc('<C-b>')]
H.key_methods[kc('<End>')] = function(state, _) state.caret = vim.fn.strchars(state.input) + 1 end

-- Delete
H.key_methods[kc('<BS>')] = function(state, opts)
  local caret, input = state.caret, state.input
  if caret <= 1 then return end
  local right_offset = (opts.autopair and H.is_inside_pair(state)) and 1 or 0
  state.input = vim.fn.strcharpart(input, 0, caret - 2) .. vim.fn.strcharpart(input, caret - 1 + right_offset)
  state.caret = caret - 1
end
H.key_methods[kc('<C-h>')] = H.key_methods[kc('<BS>')]
H.key_methods[kc('<Del>')] = function(state, _)
  local caret, input = state.caret, state.input
  if caret > vim.fn.strchars(input) then return end
  state.input = vim.fn.strcharpart(input, 0, caret - 1) .. vim.fn.strcharpart(input, caret)
end
H.key_methods[kc('<C-u>')] = function(state, _)
  state.input = vim.fn.strcharpart(state.input, state.caret - 1)
  state.caret = 1
end
H.key_methods[kc('<C-w>')] = function(state, _)
  local caret, input = state.caret, state.input
  local left_to = H.match_keyword_chars(input, caret, 'left')
  state.input = vim.fn.strcharpart(input, 0, left_to) .. vim.fn.strcharpart(input, caret - 1)
  state.caret = H.clamp(left_to + 1, 1, vim.fn.strchars(state.input) + 1)
end

-- Special insert
H.key_methods[kc('<C-k>')] = function(state, _)
  local ok, new = pcall(vim.fn.digraph_get, H.getcharstr_many(2))
  if not ok then return end
  H.insert_at_caret(state, new)
end

H.key_methods[kc('<C-r>')] = function(state, _)
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

H.key_methods[kc('<C-q>')] = function(state, _)
  local char = H.getcharstr()
  if char == nil then return end

  -- See `:h i_CTRL-V_digit`
  if char:find('^[%doOxXuU]$') ~= nil then
    local ok, new_text = pcall(vim.fn.nr2char, H.get_ctrl_v_digits(char))
    if ok then H.insert_at_caret(state, new_text) end
    return
  end

  local ok, new_text = pcall(vim.fn.keytrans, char)
  if not ok or (ok and vim.fn.char2nr(char) <= 31) then new_text = char end
  H.insert_at_caret(state, new_text)
end
H.key_methods[kc('<C-v>')] = H.key_methods[kc('<C-q>')]

-- History navigation
H.key_methods[kc('<Up>')] = function(state, _)
  if not H.init_state_complete(state, 'history') then return end
  H.advance_state_complete(state, -1)
end
H.key_methods[kc('<Down>')] = function(state, _)
  if not H.init_state_complete(state, 'history') then return end
  H.advance_state_complete(state, 1)
end
H.key_methods[kc('<C-n>')] = H.key_methods[kc('<Down>')]
H.key_methods[kc('<C-p>')] = H.key_methods[kc('<Up>')]

-- Completion navigation
H.key_methods[kc('<Tab>')] = function(state, _)
  if not H.init_state_complete(state, state.opts.completion) then return end
  H.advance_state_complete(state, 1)
end
H.key_methods[kc('<S-Tab>')] = function(state, _)
  if not H.init_state_complete(state, state.opts.completion) then return end
  H.advance_state_complete(state, -1)
end

-- Miscellaneous
H.key_methods[kc('<C-o>')] = function(state, _)
  local new_scope, n = state.opts.scope, #H.allowed_scopes
  for i, s in ipairs(H.allowed_scopes) do
    if s == state.opts.scope then new_scope = H.allowed_scopes[i % n + 1] end
  end
  state.opts.scope = new_scope
end
H.key_methods[kc('<C-s>')] = function(state, _) state.data.new_style = (state.data.next_styles or {})[state.data.style] end
H.key_methods[kc('<C-x>')] = function(state, _) state.opts.hide = not state.opts.hide end

-- Autopair keys
H.key_methods_autopair = {}
H.key_methods_autopair['('] = function(state) H.autopair_open(state, '()') end
H.key_methods_autopair['['] = function(state) H.autopair_open(state, '[]') end
H.key_methods_autopair['{'] = function(state) H.autopair_open(state, '{}') end
H.key_methods_autopair[')'] = function(state) H.autopair_close(state, ')') end
H.key_methods_autopair[']'] = function(state) H.autopair_close(state, ']') end
H.key_methods_autopair['}'] = function(state) H.autopair_close(state, '}') end
H.key_methods_autopair['"'] = function(state) H.autopair_closeopen(state, '""', '"') end
H.key_methods_autopair["'"] = function(state) H.autopair_closeopen(state, "''", "'") end
H.key_methods_autopair['`'] = function(state) H.autopair_closeopen(state, '``', '`') end

-- Local helpers
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
  if H.state_is_end() then return end
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

H.autopair_open = function(state, pair)
  H.insert_at_caret(state, pair)
  state.caret = state.caret - 1
end

H.autopair_close = function(state, close_char)
  local is_before_close = vim.fn.strcharpart(state.input, state.caret - 1, 1) == close_char
  if is_before_close then state.caret = state.caret + 1 end
  if not is_before_close then H.insert_at_caret(state, close_char) end
end

H.autopair_closeopen = function(state, pair, close_char)
  local is_before_close = vim.fn.strcharpart(state.input, state.caret - 1, 1) == close_char
  if is_before_close then H.autopair_close(state, close_char) end
  if not is_before_close then H.autopair_open(state, pair) end
end

H.is_inside_pair = function(state)
  local neigh = vim.fn.strcharpart(state.input, state.caret - 2, 2)
  return ({ ['()'] = true, ['[]'] = true, ['{}'] = true, ['""'] = true, ["''"] = true, ['``'] = true })[neigh] ~= nil
end

-- Default complete handler ---------------------------------------------------
H.complete_history = function(state, precise_history)
  local cwd, scope, prompt = vim.fn.getcwd(), state.opts.scope, state.opts.prompt
  local is_precise = function(h) return h.cwd == cwd and h.scope == scope and h.prompt == prompt end
  if not precise_history then is_precise = function(x) return true end end

  local base = vim.fn.strcharpart(state.input, 0, state.caret - 1)
  local is_match = function(x) return vim.startswith(x, base) and x ~= base end

  local raw, matched, seen = MiniInput.get_history(), {}, {}
  for i = #raw, 1, -1 do
    local val = raw[i].input
    if not seen[val] and is_match(val) and is_precise(raw[i]) then table.insert(matched, val) end
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

  local cache_hlsearch, cache_cursor = vim.v.hlsearch, vim.api.nvim_win_get_cursor(0)
  local search_cmd = 'silent! keeppatterns %s/' .. pattern .. '/\\=add(g:_miniinput_matches, submatch(0))/gn'
  vim.cmd(search_cmd)
  -- Here `vim.v` doesn't work: https://github.com/neovim/neovim/issues/25294
  vim.cmd('let v:hlsearch=' .. cache_hlsearch)
  vim.api.nvim_win_set_cursor(0, cache_cursor)
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
H.handle_view_style = function(state, init_style, next_styles)
  if state.status == 'start' then state.data.next_styles = next_styles end
  local style_is_new = state.data.new_style ~= state.data.style
  state.data.style = state.data.new_style or state.data.style or init_style
  state.data.new_style = nil
  return state.data.style, style_is_new
end

H.default_floatwin_config = function(state, style, target_width)
  local ver, hor = style:sub(1, 1), style:sub(2, 2)

  local has_tabline = vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)
  local has_statusline = vim.o.laststatus > 0
  local max_height = vim.o.lines - vim.o.cmdheight - (has_tabline and 1 or 0) - (has_statusline and 1 or 0)
  local max_width = vim.o.columns

  -- Compute window config
  local winborder = vim.fn.exists('+winborder') == 0 and '' or vim.o.winborder
  local border = winborder == '' and 'single' or nil
  local no_border = winborder == 'none'

  local title_text = ' ' .. vim.trim(state.opts.prompt) .. ' '
  local width = H.clamp(target_width, vim.fn.strchars(title_text), max_width)
  local height = 1
  local width_offset = no_border and 0 or 2
  local height_offset = no_border and 0 or 2

  local config =
    { relative = 'editor', anchor = 'NW', border = border, style = 'minimal', noautocmd = true, zindex = 251 }

  -- Compute position and dimensions based on scope
  local ref_rect = { row = has_tabline and 1 or 0, col = 0, width = max_width, height = max_height }
  local scope = state.opts.scope
  if not (scope == 'editor' or scope == 'tabpage' or scope == 'project') then
    -- NOTE: use window for "cursor" as it works when called from command line
    local wininfo = H.get_curwin_info()
    local winrow, wincol, winwidth, winheight = wininfo.winrow - 1, wininfo.wincol - 1, wininfo.width, wininfo.height
    ref_rect = { row = winrow, col = wincol, width = winwidth, height = winheight }

    -- - Nudges to not cover cursor if not 'center'
    local row_nudge = (ver == 'T' and 1 or ver == 'B' and -1 or 0)
    local col_nudge = (hor == 'L' and 1 or hor == 'R' and -1 or 0)

    if scope == 'cursor' then
      local cur_row = winrow + vim.fn.winline() - 1 + row_nudge
      local cur_col = wincol + vim.fn.wincol() - 1 + col_nudge
      ref_rect = { row = cur_row, col = cur_col, width = 1, height = 1 }
    end
    if scope == 'line' then
      local cur_row = winrow + vim.fn.winline() - 1 + row_nudge
      local cur_col = wincol + wininfo.textoff
      ref_rect = { row = cur_row, col = cur_col, width = winwidth - wininfo.textoff, height = 1 }
    end

    -- Ensure floating window does not go outside of reference rectangle
    if scope ~= 'cursor' then width = H.clamp(width, 1, ref_rect.width - width_offset) end
  end

  local ver_coef = ver == 'T' and 0 or (ver == 'M' and 0.5 or 1)
  local hor_coef = hor == 'L' and 0 or (hor == 'M' and 0.5 or 1)

  config.row = ref_rect.row + math.floor(ver_coef * (ref_rect.height - height - height_offset))
  config.col = ref_rect.col + math.floor(hor_coef * (ref_rect.width - width - width_offset))
  config.height = height
  config.width = width

  -- Set title and footer
  if no_border then return config end

  local title_hl = state.opts.hide and 'MiniInputHide' or 'MiniInputPrompt'
  config.title = { { H.fit_to_width(title_text, config.width), title_hl } }
  config.title_pos = 'left'
  if vim.fn.has('nvim-0.10') == 1 then
    local footer_text = ''
    if state.complete ~= nil then footer_text = string.format(' %d/%d ', state.complete.id, #state.complete.items) end
    config.footer = { { H.fit_to_width(footer_text, config.width), 'MiniInputHint' } }
    config.footer_pos = 'right'
  end

  return config
end

H.ensure_floatwin_buf = function(state, chunks)
  local buf_id = state.data.floating_buf_id
  if H.is_valid_buf(buf_id) then
    vim.api.nvim_buf_clear_namespace(buf_id, H.ns_id.view, 0, -1)
  else
    buf_id = vim.api.nvim_create_buf(false, true)
    H.set_buf_name(buf_id, 'content')
    vim.bo[buf_id].filetype = 'miniinput'
    state.data.floating_buf_id = buf_id
  end

  local text_arr, extmark_data, cur_len = {}, {}, 0
  for _, ch in ipairs(chunks) do
    table.insert(text_arr, ch[1])
    local new_len = cur_len + ch[1]:len()
    table.insert(extmark_data, { cur_len, { end_row = 0, end_col = new_len, hl_group = ch[2] } })
    cur_len = new_len
  end

  -- Show input as a single line with special chars taken care of
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, { H.get_chunks_text(chunks) })
  for _, ext in ipairs(extmark_data) do
    pcall(vim.api.nvim_buf_set_extmark, buf_id, H.ns_id.view, 0, ext[1], ext[2])
  end
end

H.ensure_floatwin_win = function(state, config)
  local buf_id = state.data.floating_buf_id
  local win_id = state.data.floating_win_id
  if H.is_valid_win(win_id) then
    config.noautocmd = nil
    vim.api.nvim_win_set_config(win_id, config)
  else
    win_id = vim.api.nvim_open_win(buf_id, false, config)
    vim.wo[win_id].winhighlight = 'NormalFloat:MiniInputNormal,FloatBorder:MiniInputBorder'
    vim.wo[win_id].list = vim.go.list
    vim.wo[win_id].listchars = vim.go.listchars
    vim.wo[win_id].wrap = false
    state.data.floating_win_id = win_id
  end

  return win_id
end

H.uiline_handle_option_values = function(state, style_was_changed)
  local win_id = vim.api.nvim_get_current_win()
  local needs_reset = win_id ~= state.data.win_id or style_was_changed
  if not (H.state_is_end(state) or needs_reset) then return end

  -- Unset all previously set option values
  H.uiline_unset_option_value(state, 'laststatus')
  H.uiline_unset_option_value(state, 'showtabline')
  H.uiline_unset_option_value(state, 'statusline', win_id)
  H.uiline_unset_option_value(state, 'tabline')
  H.uiline_unset_option_value(state, 'winbar', win_id)

  if not needs_reset then return end

  -- Cache all necessary values
  state.data.laststatus = vim.o.laststatus
  state.data.showtabline = vim.o.showtabline
  state.data.statusline = vim.wo.statusline
  state.data.tabline = vim.o.tabline
  state.data.winbar = vim.wo.winbar

  state.data.win_id = win_id
end

H.uiline_unset_option_value = function(state, option_name, win_id)
  local option_opts = { scope = win_id ~= nil and 'local' or nil, win = win_id }
  local cur_val = vim.api.nvim_get_option_value(option_name, option_opts)
  if cur_val == state.data[option_name] then return end
  pcall(vim.api.nvim_set_option_value, option_name, state.data[option_name], option_opts)
end

-- Chunks ---------------------------------------------------------------------
H.get_chunks = function(opts, state, max_width)
  local res = opts.to_chunks(state, max_width)

  -- Validate
  local name = string.format('opts.to_chunks(state, %s)', vim.inspect(max_width))
  H.check_array_of(name, res, 'table')
  for i, ch in ipairs(res) do
    local item = string.format('%s[%d]', name, i)
    H.check_type(item .. '[1]', ch[1], 'string')
    H.check_type(item .. '[2]', ch[2], 'string')
  end

  return res
end

H.append_chunks = function(arr, new, keytrans)
  if not keytrans then return vim.list_extend(arr, new) end

  -- Sanitaize chunks for view to display special keys in special way
  for _, ch in ipairs(new) do
    for s, special in string.gmatch(ch[1], '(%C*)(%c?)') do
      if s ~= '' then table.insert(arr, { s, ch[2] }) end
      if special ~= '' then table.insert(arr, { vim.fn.keytrans(special), 'MiniInputSpecial' }) end
    end
  end
end

-- Split chunks at character index
-- All chunks for text to the left of and including `at` index go to left.
-- The rest - to right. Split chunk if `at` is in between.
---@private
H.split_chunks_at = function(chunks, at)
  local left, right, cur_width = {}, {}, 0
  for _, ch in ipairs(chunks) do
    local w = vim.fn.strchars(ch[1])
    local to_left, to_right = at - cur_width, cur_width + w - at
    cur_width = cur_width + w

    if to_right <= 0 then table.insert(left, ch) end
    if to_left <= 0 then table.insert(right, ch) end
    if to_left > 0 and to_right > 0 then
      table.insert(left, { vim.fn.strcharpart(ch[1], 0, to_left), ch[2] })
      table.insert(right, { vim.fn.strcharpart(ch[1], to_left), ch[2] })
    end
  end

  return left, right
end

H.fit_chunks_to_width = function(chunks, width, center_offset)
  local chunks_width = H.get_chunks_width(chunks)
  if width == nil or chunks_width < width then return chunks end

  -- Show center while showing as much as possible to left and right
  local right = math.min(chunks_width, math.floor(center_offset + 0.5 * width))
  local left = math.max(1, right - width + 1)
  right = left + math.min(width, chunks_width) - 1

  local res, _ = H.split_chunks_at(chunks, right)
  _, res = H.split_chunks_at(res, left - 1)
  return res
end

H.get_chunks_text = function(chunks)
  return table.concat(vim.tbl_map(function(ch) return ch[1] end, chunks))
end

H.get_chunks_width = function(chunks) return vim.fn.strchars(H.get_chunks_text(chunks)) end

-- Highlight ranges -----------------------------------------------------------
--- Add new proper highlight range on top of an array of ranges that don't
--- intersect and are orderd from left to right.
---@private
H.insert_hl_range = function(arr, max_to, from, to, hl)
  -- Insert only proper range that fits constraints
  if from == nil or to == nil or to < 1 or from > max_to then return arr end
  from, to = H.clamp(from, 1, max_to), H.clamp(to, 1, max_to)
  if from > to then return arr end

  local res, was_inserted = {}, false
  for _, cur in ipairs(arr) do
    -- No overlap
    if cur.to < from or to < cur.from then table.insert(res, cur) end
    -- Overlap with outside left part of current
    if cur.from < from and from <= cur.to then table.insert(res, { from = cur.from, to = from - 1, hl = cur.hl }) end
    -- Overlap
    if from <= cur.to and cur.from <= to and not was_inserted then
      table.insert(res, { from = from, to = to, hl = hl })
      was_inserted = true
    end
    -- Overlap with outside right part of current
    if cur.from <= to and to < cur.to then table.insert(res, { from = to + 1, to = cur.to, hl = cur.hl }) end
  end
  if not was_inserted then table.insert(res, { from = from, to = to, hl = hl }) end
  return res
end

H.make_ui_select_hl_fun = function(hl_fun)
  if not vim.is_callable(hl_fun) then return end

  local hl_handler = H.get_config().handlers.highlight or MiniInput.default_highlight
  return function(state)
    local input = state.input
    local hl_ranges = hl_fun(input)
    H.check_array_of('opts.highlight(...)', hl_ranges, 'table')

    -- Convert to 'mini.input' ranges: named fields, 1-based char indexes
    local highlight = {}
    for i, r in ipairs(hl_ranges) do
      if type(r[1]) == 'number' and type(r[2]) == 'number' and type(r[3]) == 'string' then
        highlight[i] = { from = vim.fn.charidx(input, r[1]) + 1, to = vim.fn.charidx(input, r[2]), hl = r[3] }
      end
    end
    state.highlight = highlight

    -- Combine with user-defined handler, like to show added completion chars
    hl_handler(state)
  end
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
    if type(k) ~= ref_type then H.error('Every `' .. name .. '` item should be ' .. ref_type) end
  end
end

H.set_buf_name = function(buf_id, name) vim.api.nvim_buf_set_name(buf_id, 'miniinput://' .. buf_id .. '/' .. name) end

H.notify = function(msg, level_name) vim.notify('(mini.input) ' .. msg, vim.log.levels[level_name]) end

H.getcharstr = function(lmap)
  H.cache.is_in_getcharstr = true
  local ok, char = H.safe_fn_getcharstr()
  H.cache.is_in_getcharstr = nil

  -- Cache possible error if it doesn't come from pressing <C-c>
  if not ok and char ~= 'Keyboard interrupt' then H.cache_error(char) end

  -- Terminate if no input or on hard-coded <C-c>
  if not ok or char == '' or char == '\3' then return end

  -- Respect language mappings only if needed
  return vim.o.iminsert == 0 and char or ((lmap or {})[char] or char)
end

-- TODO: Remove after compatibility with Neovim=0.10 is dropped
H.safe_fn_getcharstr = function() return pcall(vim.fn.getcharstr, -1, { cursor = 'hide' }) end
if vim.fn.has('nvim-0.11') == 0 then H.safe_fn_getcharstr = function() return pcall(vim.fn.getcharstr) end end

H.getcharstr_many = function(n)
  local res = {}
  for i = 1, n do
    res[i] = H.getcharstr()
    if res[i] == nil then return nil end
  end
  return table.concat(res)
end

H.is_special_char = function(x)
  -- Remove allowed character that are specially translated
  x = x:gsub('[%s<]', '')
  return vim.fn.keytrans(x) ~= x
end

H.cache_error = function(msg)
  if H.state == nil or H.cache.error ~= nil then return end
  H.cache.error = H.cache.error or msg
  H.state.status = 'cancel'
end

H.redraw = function() vim.cmd('redraw!') end

H.clamp = function(x, from, to) return math.min(math.max(x, from), to) end

H.is_valid_buf = function(buf_id) return type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id) end

H.is_valid_win = function(win_id) return type(win_id) == 'number' and vim.api.nvim_win_is_valid(win_id) end

H.is_valid_char = function(char) return vim.fn.strchars(char) == 1 and vim.fn.char2nr(char) > 31 end

H.get_curwin_info = function() return vim.fn.getwininfo(vim.api.nvim_get_current_win())[1] end

H.fit_to_width = function(text, width)
  local t_width = vim.fn.strchars(text)
  return t_width <= width and text or ('…' .. vim.fn.strcharpart(text, t_width - width + 1, width - 1))
end

-- TODO: Remove after compatibility with Neovim=0.9 is dropped
H.islist = vim.fn.has('nvim-0.10') == 1 and vim.islist or vim.tbl_islist

H.get_lmap = function()
  local lmap = {}
  for _, map in ipairs(vim.fn.maplist()) do
    -- NOTE: Account only for characters that resolve to proper input character
    local is_query_lmap = map.mode == 'l' and H.is_valid_char(map.rhs)
    if is_query_lmap then lmap[map.lhs] = map.rhs end
  end
  return lmap
end
if vim.fn.has('nvim-0.10') == 0 then H.get_lmap = function() return {} end end

-- A copy of `vim.deepcopy()` that doesn't error on userdata and threads
H.copy_tables = function(x) return type(x) == 'table' and vim.tbl_map(H.copy_tables, x) or x end

MiniInput.default_view = MiniInput.gen_view.floatwin()
return MiniInput
