-- MIT License Copyright (c) 2021 Evgeni Chasnovski
--
-- Custom *originally minimal* autocompletion Lua plugin. Key design ideas:
-- - Have a 'two-stage chain completion': first try to get completion items
--   from LSP client (if set up) and if no result, fallback on custom action.
-- - Managing completion is done as much with Neovim's built-in tools as
--   possible.
--
-- To activate, put this file somewhere into 'lua' folder and call module's
-- `setup()`. For example, put as 'lua/mini/completion.lua' and execute
-- `require('mini.completion').setup()` Lua code. It may have `config` argument
-- which should be a table overwriting default values using same structure.
--
-- Default `config`:
-- {
--   -- Delay (debounce type, in ms) between character insert and triggering
--   -- completion
--   delay_completion = 100,
--   -- Delay (debounce type, in ms) between focusing on completion item and
--   -- triggering its info.
--   delay_info = 100,
--   -- Delay (debounce type, in ms) between end of cursor movement and triggering
--   -- signature help.
--   delay_signature = 100,
--   -- Maximum dimensions of window for completion item info. Should have
--   -- 'height' and 'width' fields.
--   info_max_dim = {height = 25, width = 80},
--   -- Maximum dimensions of signature help. Should have 'height' and 'width'
--   -- fields.
--   signature_max_dim = {height = 25, width = 80},
--   -- Fallback action. It will always be run in Insert mode. To use Neovim's
--   -- built-in completion (see `:h ins-completion`), supply its mapping as
--   -- string. For example, to use 'whole lines' completion, supply '<C-x><C-l>'.
--   fallback_action = <function equivalent to '<C-n>'>,
--   mappings = {
--     force = '<C-Space>' -- Force completion
--   }
-- }
--
-- Features:
-- - Two-stage chain completion:
--     - First stage is implemented via `completefunc` (see `:h
--       'completefunc'`). It tries to get completion items from LSP client
--       (via 'textDocument/completion' request).
--     - If first stage resulted into no candidates, fallback action is
--       executed. The most tested actions are Neovim's built-in insert
--       completion (see `:h ins-completion`).
-- - Automatic display in floating window of completion item info and signature
--   help (with highlighting of active parameter if LSP server provides such
--   information).
-- - Automatic actions are done after some configurable amount of delay. This
--   reduces computational load and allows fast typing (completion and
--   signature help) and item selection (item info)
-- - Autoactions are triggered on Neovim's built-in events.
-- - User can force trigger via `MiniCompletion.complete()` which by default is
--   mapped to `<C-space>`.
-- - Highlighting of signature active parameter is done according to
--   `MiniCompletionActiveParameter` highlight group. By default, it is a plain
--   underline. To change this, modify it directly with `highlight
--   MiniCompletionActiveParameter` command.
--
-- Comparisons:
-- - 'completion-nvim':
--     - Has timer activated on InsertEnter which does something every period
--       of time (makes LSP request, shows floating help). MiniCompletion
--       relies on Neovim's (Vim's) events.
--     - Uses 'textDocument/hover' request to show completion item info.
--     - Doesn't have highlighting of active parameter in signature help.
-- - 'nvim-compe':
--     - More elaborate design which allows multiple sources. However, it
--       currently does not have 'opened buffers' source, which is very handy.
--     - Doesn't allow fallback action.
--     - Doesn't provide signature help.
-- - Both:
--     - Can manage multiple configurable sources. MiniCompletion has only two:
--       LSP and fallback.
--     - Provide custom ways to filter completion suggestions. MiniCompletion
--       relies on Neovim's (which currently is equal to Vim's) filtering.
--     - Currently use simple text wrapping in completion item window. This
--       module wraps by words (see `:h linebreak` and `:h breakat`).
--
-- Overall implementation design:
-- - Completion:
--     - On `InsertCharPre` event try to start auto completion. If needed,
--       start timer which after delay will start completion process. Stop this
--       timer if it is not needed.
--     - When timer is activated, first execute `completefunc` which tries LSP
--       completion by asynchronously sending LSP 'textDocument/completion'
--       request to all LSP clients. When all are done, execute callback which
--       processes results, stores them in LSP cache and rerun `completefunc`
--       which produces completion popup.
--     - If previous step didn't result into any completion, execute (in Insert
--       mode and if no popup) fallback action.
-- - Documentation:
--     - On `CompleteChanged` start auto info with similar to completion timer
--       pattern.
--     - If timer is activated, try these sources of item info:
--         - 'info' field of completion item (see `:h complete-items`).
--         - 'documentation' field of LSP's previously returned result.
--         - 'documentation' field in result of asynchronous
--           'completeItem/resolve' LSP request.
--     - If info doesn't consist only from whitespace, show floating window
--       with its content. Its dimensions and position are computed based on
--       current state of Neovim's data and content itself (which will be
--       displayed wrapped with `linebreak` option).
-- - Signature help (similar to item info):
--     - On `CursorMovedI` start auto signature (if there is any active LSP
--       client) with similar to completion timer pattern. Better event might
--       be `InsertCharPre` but there are issues with 'autopair-type' plugins.
--     - Check if character left to cursor is appropriate (')' or LSP's
--       signature help trigger characters). If not, do nothing.
--     - If timer is activated, send 'textDocument/signatureHelp' request to
--       all LSP clients. On callback, process their results and open floating
--       window (its characteristics are computed similar to item info). For
--       every LSP client it shows only active signature (in case there are
--       many).

-- Module and its helper
local MiniCompletion = {}
local H = {}

-- Module setup
function MiniCompletion.setup(config)
  -- Export module
  _G.MiniCompletion = MiniCompletion

  -- Setup config
  config = setmetatable(config or {}, {__index = H.config})
  mappings = setmetatable(config.mappings, {__index = H.config.mappings})

  -- Apply settings
  H.apply_settings(config)

  -- Setup module behavior
  vim.api.nvim_exec([[
    augroup MiniCompletion
      au!
      au InsertCharPre   * lua MiniCompletion.auto_complete()
      au CompleteChanged * lua MiniCompletion.auto_info()
      au CursorMovedI    * lua MiniCompletion.auto_signature()
      au InsertLeavePre  * lua MiniCompletion.stop()
      au CompleteDonePre * lua MiniCompletion.stop({'complete', 'info'})
      au TextChangedI    * lua MiniCompletion.on_text_changed_i()
      au BufEnter        * set completefunc=v:lua.MiniCompletion.complete_lsp
    augroup END
  ]], false)

  -- Setup mappings
  vim.api.nvim_set_keymap(
    'i', mappings.force, '<cmd>lua MiniCompletion.complete()<cr>',
    {noremap = true, silent = true}
  )

  -- Create highlighting
  vim.api.nvim_exec([[
    hi MiniCompletionActiveParameter term=underline cterm=underline gui=underline
  ]], false)
end

-- Module settings
---- Delay (debounce type, in ms) between character insert and triggering
---- completion
MiniCompletion.delay_completion = 100

---- Delay (debounce type, in ms) between focusing on completion item and
---- triggering its info.
MiniCompletion.delay_info = 100

---- Delay (debounce type, in ms) between end of cursor movement and triggering
---- signature help.
MiniCompletion.delay_signature = 100

---- Maximum dimensions of window for completion item info. Should have
---- 'height' and 'width' fields.
MiniCompletion.info_max_dim = {height = 25, width = 80}

---- Maximum dimensions of signature help. Should have 'height' and 'width'
---- fields.
MiniCompletion.signature_max_dim = {height = 25, width = 80}

---- Fallback action. It will always be run in Insert mode. To use Neovim's
---- built-in completion (see `:h ins-completion`), supply its mapping as
---- string. For example, to use 'whole lines' completion, supply '<C-x><C-l>'.
MiniCompletion.fallback_action = function()
  vim.api.nvim_feedkeys(H.keys.ctrl_n, 'n', false)
end

-- Module functionality
function MiniCompletion.auto_complete()
  H.complete.timer:stop()

  -- Don't do anything if popup is visible
  if H.pumvisible() then
    -- Keep completion source as it is needed all time when popup is visible
    H.stop_complete(true)
    return
  end

  -- Stop everything if inserted character is not appropriate
  local char_is_trigger = H.is_lsp_trigger(vim.v.char, 'completion')
  if not (H.is_char_keyword(vim.v.char) or char_is_trigger) then
    H.stop_complete(false)
    return
  end

  -- If character is purely lsp trigger, make new LSP request without fallback
  -- and force new completion
  if char_is_trigger then H.cancel_lsp() end
  H.complete.fallback, H.complete.force = not char_is_trigger, char_is_trigger

  -- Using delay (of debounce type) seems to actually improve user experience
  -- as it allows fast typing without many popups. Also useful when synchronous
  -- `<C-n>` completion blocks typing.
  H.complete.timer:start(
    MiniCompletion.delay_completion, 0, vim.schedule_wrap(H.trigger)
  )
end

function MiniCompletion.complete(fallback, force)
  H.stop_complete()
  H.complete.fallback, H.complete.force = fallback or true, force or true
  H.trigger()
end

function MiniCompletion.auto_info()
  H.info.timer:stop()

  -- Defer execution because of textlock during `CompleteChanged` event
  -- Don't stop timer when closing info window because it is needed
  vim.defer_fn(function() H.close_action_window(H.info, true) end, 0)

  -- Stop current LSP request that tries to get not current data
  H.cancel_lsp({'resolve'})

  -- Update metadata before leaving to register a `CompleteChanged` event
  H.info.event = vim.v.event
  H.info.id = H.info.id + 1

  -- Don't event try to show info if nothing is selected in popup
  if vim.tbl_isempty(H.info.event.completed_item) then return end

  H.info.timer:start(
    MiniCompletion.delay_info, 0, vim.schedule_wrap(H.show_info_window)
  )
end

function MiniCompletion.auto_signature()
  H.signature.timer:stop()
  if not H.has_lsp_clients() then return end

  local left_char = H.get_left_char()
  local char_is_trigger = left_char == ')' or H.is_lsp_trigger(left_char, 'signature')
  if not char_is_trigger then return end

  H.signature.timer:start(
    MiniCompletion.delay_signature, 0, vim.schedule_wrap(function()
      -- Having closing inside timer callback enables "fixed" window effect if
      -- trigger character and its followup are typed fast enough
      H.close_action_window(H.signature)
      H.show_signature()
    end)
  )
end

function MiniCompletion.stop(actions)
  actions = actions or {'complete', 'info', 'signature'}
  for _, n in pairs(actions) do H.stop_actions[n]() end
end

function MiniCompletion.on_text_changed_i()
  -- Stop 'info' processes in case no complete event is triggered but popup is
  -- not visible. See https://github.com/neovim/neovim/issues/15077
  H.stop_info()
end

function MiniCompletion.complete_lsp(findstart, base)
  -- Early return
  if (not H.has_lsp_clients()) or H.lsp.completion.status == 'sent' then
    if findstart == 1 then return -3 else return {} end
  end

  -- NOTE: having code for request inside this function enables its use
  -- directly with `<C-x><...>`.
  if H.lsp.completion.status ~= 'received' then
    current_id = H.lsp.completion.id + 1
    H.lsp.completion.id = current_id
    H.lsp.completion.status = 'sent'

    local bufnr = vim.api.nvim_get_current_buf()
    local params = vim.lsp.util.make_position_params()

    -- NOTE: it is CRUCIAL to make LSP request on the first call to
    -- 'complete-function' (as in Vim's help). This is due to the fact that
    -- cursor line and position are different on the first and second calls to
    -- 'complete-function'. For example, when calling this function at the end
    -- of the line '  he', cursor position on the second call will be
    -- (<linenum>, 4) and line will be '  he' but on the second call -
    -- (<linenum>, 2) and '  ' (because 2 is a column of completion start).
    -- This request is executed only on first call because it returns `-3` on
    -- first call (which means cancel and leave completion mode).
    -- NOTE: using `buf_request_all()` (instead of `buf_request()`) to easily
    -- handle possible fallback and to have all completion suggestions be
    -- filtered with one `base` in the other route of this function. Anyway,
    -- the most common situation is with one attached LSP client.
    cancel_fun = vim.lsp.buf_request_all(bufnr, 'textDocument/completion', params, function(result)
      if not H.is_lsp_current('completion', current_id) then return end

      H.lsp.completion.status = 'received'
      H.lsp.completion.result = result

      -- Trigger LSP completion to take 'received' route
      H.trigger_lsp()
    end)

    -- Cache cancel function to disable requests when they are not needed
    H.lsp.completion.cancel_fun = cancel_fun

    -- End completion and wait for LSP callback
    if findstart == 1 then return -3 else return {} end
  else
    if findstart == 1 then return H.get_completion_start() end

    local words = H.process_lsp_response(
      H.lsp.completion.result,
      function(response)
        return vim.lsp.util.text_document_completion_list_to_complete_items(response, base)
      end
    )

    H.lsp.completion.status = 'done'

    -- Maybe trigger fallback action
    if vim.tbl_isempty(words) and H.complete.fallback then
      H.trigger_fallback()
      return
    end

    -- Track from which source is current popup
    H.complete.source = 'lsp'
    return words
  end
end

-- Helper data
---- Module default config
H.config = {
  delay_completion = MiniCompletion.delay_completion,
  delay_info = MiniCompletion.delay_info,
  delay_signature = MiniCompletion.delay_signature,
  info_max_dim = MiniCompletion.info_max_dim,
  signature_max_dim = MiniCompletion.signature_max_dim,
  fallback_action = MiniCompletion.fallback_action,
  mappings = {
    force = '<C-Space>' -- Force completion
  }
}

---- Commonly used key sequences
H.keys = {
  usercompl = vim.api.nvim_replace_termcodes('<C-x><C-u>', true, false, true),
  ctrl_n = vim.api.nvim_replace_termcodes('<C-g><C-g><C-n>', true, false, true),
}

---- Table describing state of all used LSP requests. Structure:
---- - id: identifier (consecutive numbers).
---- - status: status. One of 'sent', 'received', 'done', 'canceled'.
---- - result: result of request.
---- - cancel_fun: function which cancels current request.
H.lsp = {
  completion = {id = 0, status = nil, result = nil, cancel_fun = nil},
  resolve    = {id = 0, status = nil, result = nil, cancel_fun = nil},
  signature  = {id = 0, status = nil, result = nil, cancel_fun = nil}
}

---- Cache for completion
H.complete = {fallback = true, force = false, source = nil, timer = vim.loop.new_timer()}

---- Cache for completion item info
H.info = {bufnr = nil, event = nil, id = 0, timer = vim.loop.new_timer(), winnr = nil}

---- Cache for signature help
H.signature = {bufnr = nil, timer = vim.loop.new_timer(), winnr = nil}

-- Helper functions
---- Settings
function H.apply_settings(config)
  local is_max_dim = function(x)
    if type(x) ~= 'table' then return false end
    local keys = vim.tbl_keys(x)
    return vim.tbl_contains(keys, 'height') and vim.tbl_contains(keys, 'width')
  end
  local max_dim_msg = 'table with \'height\' and \'width\' fields'

  vim.validate({
    delay_completion = {config.delay_completion, 'number'},
    delay_info = {config.delay_info, 'number'},
    delay_signature = {config.delay_signature, 'number'},
    info_max_dim = {config.info_max_dim, is_max_dim, max_dim_msg},
    signature_max_dim = {config.signature_max_dim, is_max_dim, max_dim_msg},
    fallback_action = {
      config.fallback_action,
      function(x) return type(x) == 'function' or type(x) == 'string' end,
      'function or string'
    }
  })

  MiniCompletion.delay_completion = config.delay_completion
  MiniCompletion.delay_info = config.delay_info
  MiniCompletion.delay_signature = config.delay_signature
  MiniCompletion.info_max_dim = config.info_max_dim
  MiniCompletion.signature_max_dim = config.signature_max_dim

  if type(config.fallback_action) == 'string' then
    MiniCompletion.fallback_action = H.make_ins_fallback(config.fallback_action)
  else
    MiniCompletion.fallback_action = config.fallback_action
  end
end

function H.make_ins_fallback(keys)
  local trigger_keys = vim.api.nvim_replace_termcodes(
    -- Having `<C-g><C-g>` also (for some mysterious reason) helps to avoid
    -- some weird behavior. For example, if `keys = '<C-x><C-l>'` then Neovim
    -- starts new line when there is no suggestions.
    '<C-g><C-g>' .. keys, true, false, true
  )
  return function() vim.api.nvim_feedkeys(trigger_keys, 'n', false) end
end

---- Triggers
function H.trigger()
  if vim.fn.mode() ~= 'i' then return end
  if H.has_lsp_clients() then
    H.trigger_lsp()
  elseif H.complete.fallback then
    H.trigger_fallback()
  end
end

function H.trigger_lsp()
  local has_complete = vim.api.nvim_buf_get_option(0, 'completefunc') ~= ''
  -- Check for popup visibility is needed to reduce flickering.
  -- Possible issue timeline (with 100ms delay with set up LSP):
  -- 0ms: Key is pressed.
  -- 100ms: LSP is triggered from first key press.
  -- 110ms: Another key is pressed.
  -- 200ms: LSP callback is processed, triggers complete-function which
  --   processes "received" LSP request.
  -- 201ms: LSP request is processed, completion is (should be almost
  --   immediately) provided, request is marked as "done".
  -- 210ms: LSP is triggered from second key press. As previous request is
  --   "done", it will once make whole LSP request. Having check for visible
  --   popup should prevent here the call to complete-function.
  -- When `force` is `true` then presence of popup shouldn't matter.
  local no_popup = H.complete.force or (not H.pumvisible())
  if no_popup and has_complete and vim.fn.mode() == 'i' then
    vim.api.nvim_feedkeys(H.keys.usercompl, 'n', false)
  end
end

function H.trigger_fallback()
  local no_popup = H.complete.force or (not H.pumvisible())
  if no_popup and vim.fn.mode() == 'i' then
    -- Track from which source is current popup
    H.complete.source = 'fallback'
    MiniCompletion.fallback_action()
  end
end

---- Stop actions
function H.stop_complete(keep_source)
  H.complete.timer:stop()
  H.cancel_lsp({'completion'})
  H.complete.fallback, H.complete.force = true, false
  if not keep_source then H.complete.source = nil end
end

function H.stop_info()
  -- Id update is needed to notify that all previous work is not current
  H.info.id = H.info.id + 1
  H.info.timer:stop()
  H.cancel_lsp({'resolve'})
  H.close_action_window(H.info)
end

function H.stop_signature()
  H.signature.timer:stop()
  H.cancel_lsp({'signature'})
  H.close_action_window(H.signature)
end

H.stop_actions = {
  complete = H.stop_complete, info = H.stop_info, signature = H.stop_signature
}

---- LSP
function H.has_lsp_clients() return not vim.tbl_isempty(vim.lsp.buf_get_clients()) end

function H.is_lsp_trigger(char, type)
  local triggers
  local providers = {
    completion = 'completionProvider',
    signature = 'signatureHelpProvider'
  }

  for _, client in pairs(vim.lsp.buf_get_clients()) do
    triggers = H.table_get(
      client,
      {'server_capabilities', providers[type], 'triggerCharacters'}
    )
    if vim.tbl_contains(triggers or {}, char) then return true end
  end
  return false
end

function H.cancel_lsp(names)
  names = names or {'completion', 'resolve', 'signature'}
  for _, n in pairs(names) do
    if vim.tbl_contains({'sent', 'received'}, H.lsp[n].status) then
      if H.lsp[n].cancel_fun then H.lsp[n].cancel_fun() end
      H.lsp[n].status = 'canceled'
    end
  end
end

function H.process_lsp_response(request_result, processor)
  if not request_result then return {} end

  local res = {}
  for _, item in pairs(request_result) do
    if not item.err and item.result then
      vim.list_extend(res, processor(item.result) or {})
    end
  end

  return res
end

function H.is_lsp_current(name, id)
  return H.lsp[name].id == id and H.lsp[name].status == 'sent'
end

---- Completion item info
function H.show_info_window()
  local event = H.info.event
  if not event then return end

  -- Try first to take lines from LSP request result.
  local lines
  if H.lsp.resolve.status == 'received' then
    lines = H.process_lsp_response(
      H.lsp.resolve.result,
      function(response)
        if not response.documentation then return {} end
        local res = vim.lsp.util.convert_input_to_markdown_lines(response.documentation)
        return vim.lsp.util.trim_empty_lines(res)
      end
    )

    H.lsp.resolve.status = 'done'
  else
    lines = H.info_window_lines(H.info.id)
  end

  -- Don't show anything if there is nothing to show
  if not lines or H.is_whitespace(lines) then return end

  -- If not already, create a permanent buffer where info will be
  -- displayed. For some reason, it is important to have it created not in
  -- `setup()` because in that case there is a small flash (which is really a
  -- brief open of window at screen top, focus on it, and its close) on the
  -- first show of info window.
  H.ensure_buffer(H.info, 'MiniCompletion:floating-info')

  -- Add `lines` to info buffer. Use `wrap_at` to have proper width of
  -- 'non-UTF8' section separators.
  vim.lsp.util.stylize_markdown(
    H.info.bufnr, lines, {wrap_at = MiniCompletion.info_max_dim.width}
  )

  -- Compute floating window options
  local opts = H.info_window_options()

  -- Defer execution because of textlock during `CompleteChanged` event
  vim.defer_fn(
    function()
      -- Ensure that window doesn't open when it shouldn't be
      if not (H.pumvisible() and vim.fn.mode() == 'i') then return end
      H.open_action_window(H.info, opts)
    end,
    0
  )
end

function H.info_window_lines(info_id)
  -- Try to use 'info' field of Neovim's completion item
  local completed_item = H.table_get(H.info, {"event", "completed_item"}) or {}
  local text = completed_item.info or ''

  if not H.is_whitespace(text) then
    -- Use `<text></text>` to be properly processed by `stylize_markdown()`
    local lines = {'<text>'}
    vim.list_extend(lines, vim.split(text, '\n', false))
    table.insert(lines, '</text>')
    return lines
  end

  -- If popup is not from LSP then there is nothing more to do
  if H.complete.source ~= 'lsp' then return nil end

  -- Try to get documentation from LSP's initial completion result
  local lsp_completion_item = H.table_get(
    completed_item, {'user_data', 'nvim', 'lsp', 'completion_item'}
  )
  ---- If there is no LSP's completion item, then there is no point to proceed
  ---- as it should serve as parameters to LSP request
  if not lsp_completion_item then return end
  local doc = lsp_completion_item.documentation
  if doc then
    local lines = vim.lsp.util.convert_input_to_markdown_lines(doc)
    return vim.lsp.util.trim_empty_lines(lines)
  end

  -- Finally, try request to resolve current completion to add documentation
  local bufnr = vim.api.nvim_get_current_buf()
  local params = lsp_completion_item

  local current_id = H.lsp.resolve.id + 1
  H.lsp.resolve.id = current_id
  H.lsp.resolve.status = 'sent'

  cancel_fun = vim.lsp.buf_request_all(bufnr, 'completionItem/resolve', params, function(result)
    -- Don't do anything if there is other LSP request in action
    if not H.is_lsp_current('resolve', current_id) then return end

    H.lsp.resolve.status = 'received'

    -- Don't do anything if completion item was changed
    if H.info.id ~= info_id then return end

    H.lsp.resolve.result = result
    H.show_info_window()
  end)

  H.lsp.resolve.cancel_fun = cancel_fun

  return nil
end

function H.info_window_options()
  -- Compute dimensions based on lines to be displayed
  local lines = vim.api.nvim_buf_get_lines(H.info.bufnr, 0, -1, {})
  local info_height, info_width = H.floating_dimensions(
    lines,
    MiniCompletion.info_max_dim.height,
    MiniCompletion.info_max_dim.width
  )

  -- Compute position
  local event = H.info.event
  local left_to_pum = event.col - 1
  local right_to_pum = event.col + event.width + (event.scrollbar and 1 or 0)

  local space_left, space_right = left_to_pum, vim.o.columns - right_to_pum

  local anchor, col, space
  -- Decide side at which info window will be displayed
  if info_width <= space_right or space_left <= space_right then
    anchor, col, space = 'NW', right_to_pum, space_right
  else
    anchor, col, space = 'NE', left_to_pum, space_left
  end

  -- Possibly adjust floating window dimensions to fit screen
  if space < info_width then
    info_height, info_width = H.floating_dimensions(
      lines, MiniCompletion.info_max_dim.height, space
    )
  end

  return {
    relative = 'editor',
    anchor = anchor,
    row = event.row,
    col = col,
    width = info_width,
    height = info_height,
    focusable = true,
    style = 'minimal'
  }
end

---- Signature help
function H.show_signature()
  -- If there is no received LSP result, make request and exit
  if H.lsp.signature.status ~= 'received' then
    current_id = H.lsp.signature.id + 1
    H.lsp.signature.id = current_id
    H.lsp.signature.status = 'sent'

    local bufnr = vim.api.nvim_get_current_buf()
    local params = vim.lsp.util.make_position_params()

    cancel_fun = vim.lsp.buf_request_all(bufnr, 'textDocument/signatureHelp', params, function(result)
      if not H.is_lsp_current('signature', current_id) then return end

      H.lsp.signature.status = 'received'
      H.lsp.signature.result = result

      -- Trigger `show_signature` again to take 'received' route
      H.show_signature()
    end)

    -- Cache cancel function to disable requests when they are not needed
    H.lsp.signature.cancel_fun = cancel_fun

    return
  end

  -- Make lines to show in floating window
  local lines, hl_ranges = H.signature_lines()
  H.lsp.signature.status = 'done'

  -- Don't show anything if there is nothing to show
  if not lines or H.is_whitespace(lines) then return end

  -- If not already, create a permanent buffer for signature
  H.ensure_buffer(H.signature, 'MiniCompletion:signature-help')

  -- Make markdown code block
  table.insert(lines, 1, '```' .. vim.bo.filetype)
  table.insert(lines, '```')

  -- Add `lines` to signature buffer. Use `wrap_at` to have proper width of
  -- 'non-UTF8' section separators.
  vim.lsp.util.stylize_markdown(
    H.signature.bufnr, lines, {wrap_at = MiniCompletion.signature_max_dim.width}
  )

  -- Add highlighting of active parameter
  for i, hl_range in ipairs(hl_ranges) do
    if not vim.tbl_isempty(hl_range) and hl_range.first and hl_range.last then
      vim.api.nvim_buf_add_highlight(
        H.signature.bufnr,
        -1,
        'MiniCompletionActiveParameter',
        i - 1,
        hl_range.first,
        hl_range.last
      )
    end
  end

  -- Compute floating window options
  local opts = H.signature_opts()

  -- Ensure that window doesn't open when it shouldn't be
  if vim.fn.mode() == 'i' then H.open_action_window(H.signature, opts) end
end

function H.signature_lines()
  local signature_data = H.process_lsp_response(
    H.lsp.signature.result, H.process_signature_response
  )
  -- Each line is a single-line active signature string from one attached LSP
  -- client. Each highlight range is a table which indicates (if not empty)
  -- what parameter to highlight for every LSP client's signature string.
  local lines, hl_ranges = {}, {}
  for _, t in pairs(signature_data) do
    -- `t` is allowed to be an empty table (in which case nothing is added) or
    -- a table with two entries. This ensures that `hl_range`'s integer index
    -- points to an actual line in future buffer.
    table.insert(lines, t.label)
    table.insert(hl_ranges, t.hl_range)
  end

  return lines, hl_ranges
end

function H.process_signature_response(response)
  if not response.signatures or vim.tbl_isempty(response.signatures) then return {} end

  -- Get active signature (based on textDocument/signatureHelp specification)
  local signature_id = response.activeSignature or 0
  ---- This is according to specification: "If ... value lies outside ...
  ---- defaults to zero"
  local n_signatures = vim.tbl_count(response.signatures or {})
  if signature_id < 0 or signature_id >= n_signatures then signature_id = 0 end
  local signature = response.signatures[signature_id + 1]

  -- Get displayed signature label
  local signature_label = signature.label

  -- Get start and end of active parameter (for highlighting)
  local hl_range = {}
  local n_params = vim.tbl_count(signature.parameters or {})
  local has_params = signature.parameters and n_params > 0

  ---- Take values in this order because data inside signature takes priority
  local parameter_id = signature.activeParameter or response.activeParameter or 0
  local param_id_inrange = 0 <= parameter_id and parameter_id < n_params

  ---- Computing active parameter only when parameter id is inside bounds is not
  ---- strictly based on specification, as currently (v3.16) it says to treat
  ---- out-of-bounds value as first parameter. However, some clients seems to
  ---- use those values to indicate that nothing needs to be highlighted.
  ---- Sources:
  ---- https://github.com/microsoft/pyright/pull/1876
  ---- https://github.com/microsoft/language-server-protocol/issues/1271
  if has_params and param_id_inrange then
    local param_label = signature.parameters[parameter_id + 1].label

    -- Compute highlight range based on type of supplied parameter label: can
    -- be string label which should be a part of signature label or direct start
    -- (inclusive) and end (exclusive) range values
    local first, last = nil, nil
    if type(param_label) == 'string' then
      first, last = signature_label:find(vim.pesc(param_label))
      -- Make zero-indexed and end-exclusive
      if first then first, last = first - 1, last end
    elseif type(param_label) == 'table' then
      first, last = unpack(param_label)
    end
    if first then hl_range = {first = first, last = last} end
  end

  -- Return nested table because this will be a second argument of
  -- `vim.list_extend()` and the whole inner table is a target value here.
  return {{label = signature_label, hl_range = hl_range}}
end

function H.signature_opts()
  local lines = vim.api.nvim_buf_get_lines(H.signature.bufnr, 0, -1, {})
  local height, width = H.floating_dimensions(
    lines,
    MiniCompletion.signature_max_dim.height,
    MiniCompletion.signature_max_dim.width
  )
  return vim.lsp.util.make_floating_popup_options(width, height, {})
end

---- Helpers for floating windows
function H.ensure_buffer(cache, name)
  if cache.bufnr then return end

  cache.bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(cache.bufnr, name)
  -- Make this buffer a scratch (can close without saving)
  vim.fn.setbufvar(cache.bufnr, '&buftype', 'nofile')
end

------ @return height, width
function H.floating_dimensions(lines, max_height, max_width)
  -- Simulate how lines will look in window with `wrap` and `linebreak`.
  -- This is not 100% accurate (mostly when multibyte characters are present
  -- manifesting into empty space at bottom), but does the job
  local lines_wrap = {}
  for _, l in pairs(lines) do
    vim.list_extend(lines_wrap, H.wrap_line(l, max_width))
  end
  -- Height is a number of wrapped lines truncated to maximum height
  local height = math.min(#lines_wrap, max_height)

  -- Width is a maximum width of the first `height` wrapped lines truncated to
  -- maximum width
  local width = 0
  local l_width
  for i, l in ipairs(lines_wrap) do
    -- Use `strdisplaywidth()` to account for 'non-UTF8' characters
    l_width = vim.fn.strdisplaywidth(l)
    if i <= height and width < l_width then width = l_width end
  end
  ---- It should already be less that that because of wrapping, so this is
  ---- "just in case"
  width = math.min(width, max_width)

  return height, width
end

function H.open_action_window(cache, opts)
  cache.winnr = vim.api.nvim_open_win(cache.bufnr, false, opts)
  vim.api.nvim_win_set_option(cache.winnr, "wrap", true)
  vim.api.nvim_win_set_option(cache.winnr, "linebreak", true)
  vim.api.nvim_win_set_option(cache.winnr, "breakindent", false)
end

function H.close_action_window(cache, keep_timer)
  if not keep_timer then cache.timer:stop() end

  if cache.winnr then vim.api.nvim_win_close(cache.winnr, true) end
  cache.winnr = nil

  -- For some reason 'buftype' might be reset. Ensure that buffer is scratch.
  if cache.bufnr then vim.fn.setbufvar(cache.bufnr, '&buftype', 'nofile') end
end

---- Various helpers
function H.is_char_keyword(char)
  -- Using Vim's `match()` and `keyword` enables respecting Cyrillic letters
  return vim.fn.match(char, '[[:keyword:]]') >= 0
end

function H.pumvisible() return vim.fn.pumvisible() > 0 end

function H.get_completion_start()
  -- Compute start position of latest keyword (as in `vim.lsp.omnifunc`)
  local pos = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_get_current_line()
  local line_to_cursor = line:sub(1, pos[2])
  return vim.fn.match(line_to_cursor, '\\k*$')
end

function H.is_whitespace(s)
  if type(s) == 'string' then return s:find('^%s*$') end
  if type(s) == 'table' then
    for _, val in pairs(s) do
      if not H.is_whitespace(val) then return false end
    end
    return true
  end
  return false
end

------ Simulate spliting single line `l` like how it would look inside window
------ with `wrap` and `linebreak` set to `true`
function H.wrap_line(l, width)
  local breakat_pattern = '[' .. vim.o.breakat .. ']'
  local res = {}

  local break_id, break_match, width_id
  -- Use `strdisplaywidth()` to account for 'non-UTF8' characters
  while vim.fn.strdisplaywidth(l) > width do
    -- Simulate wrap by looking at breaking character from end of current break
    width_id = vim.str_byteindex(l, width)
    break_match = vim.fn.match(l:sub(1, width_id):reverse(), breakat_pattern)
    -- If no breaking character found, wrap at whole width
    break_id = width_id - (break_match < 0 and 0 or break_match)
    table.insert(res, l:sub(1, break_id))
    l = l:sub(break_id + 1)
  end
  table.insert(res, l)

  return res
end

function H.table_get(t, id)
  if type(id) ~= 'table' then return H.table_get(t, {id}) end
  local res = t
  for _, i in pairs(id) do
    success, res = pcall(function() return res[i] end)
    if not (success and res) then return nil end
  end
  return res
end

function H.get_left_char()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]

  return string.sub(line, col, col)
end

return MiniCompletion