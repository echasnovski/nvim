-- Comparisons:
-- - 'completion-nvim':
--     - Has timer activated on InsertEnter which does something every period
--       of time (makes LSP request, shows floating help). MiniCompletion
--       relies on Neovim's (Vim's) events.
-- - 'nvim-compe':
--     - Sends 'completionItem/resolve' for extra completion information. This
--       doesn't seem to be enough.
-- - Both:
--     - Can manage multiple configurable sources. MiniCompletion has only two:
--       LSP and fallback.
--     - Provide custom ways to filter completion suggestions. MiniCompletion
--       relies on Neovim's (which currently is equal to Vim's) filtering.

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
  MiniCompletion.lsp_triggers = config.lsp_triggers
  MiniCompletion.delay_completion = config.delay_completion
  MiniCompletion.delay_info = config.delay_info

  -- Setup module behavior
  vim.api.nvim_exec([[
    augroup MiniCompletion
      au!
      au InsertCharPre   * lua MiniCompletion.auto_complete()
      au CompleteChanged * lua MiniCompletion.auto_info()
      au InsertLeavePre  * lua MiniCompletion.stop_all()
      au CompleteDonePre * lua MiniCompletion.stop_all()
      au TextChangedI    * lua MiniCompletion.on_text_changed_i()
      au BufEnter        * set completefunc=v:lua.MiniCompletion.complete_lsp
    augroup END
  ]], false)

  -- Create a permanent buffer where documentation info will be displayed
  H.info.bufnr = vim.api.nvim_create_buf(false, true)
  vim.fn.setbufvar(H.info.bufnr, '&buftype', 'nofile')

  -- Setup mappings
  vim.api.nvim_set_keymap(
    'i', mappings.force, '<cmd>lua MiniCompletion.complete()<cr>',
    {noremap = true, silent = true}
  )
end

-- Module settings
---- Delay (debounce type, in ms) between character insert and triggering
---- completion
MiniCompletion.delay_completion = 100

---- Delay (debounce type, in ms) between focusing on completion item and
---- triggering floating info.
MiniCompletion.delay_info = 100

---- Characters per filetype which will retrigger LSP without fallback. Should
---- be a named table with name indicating filetype. Special name 'default'
---- means default lsp triggers for all LSP clients.
MiniCompletion.lsp_triggers = {default = {'.'}}

-- Module functionality
function MiniCompletion.auto_complete()
  H.timers.auto_complete:stop()

  local char_is_lsp_trigger = H.is_lsp_trigger(vim.v.char)
  if H.pumvisible() or
    not (H.is_char_keyword(vim.v.char) or char_is_lsp_trigger) then
    H.stop_complete()
    return
  end

  -- If character is purely lsp trigger, make new LSP request without fallback
  -- and forcing new completion
  if char_is_lsp_trigger then H.cancel_lsp() end
  H.cache.fallback, H.cache.force = not char_is_lsp_trigger, char_is_lsp_trigger

  -- Using delay (of debounce type) seems to actually improve user experience
  -- as it allows fast typing without many popups. Also useful when synchronous
  -- `<C-n>` completion blocks typing.
  H.timers.auto_complete:start(
    MiniCompletion.delay_completion, 0, vim.schedule_wrap(H.trigger)
  )
end

function MiniCompletion.complete(fallback, force)
  H.stop_complete()
  H.cache.fallback, H.cache.force = fallback or true, force or true
  H.trigger()
end

function MiniCompletion.auto_info()
  H.timers.auto_info:stop()

  -- Defer execution because of textlock during `CompleteChanged` event
  -- Don't stop timer when closing floating info because it is needed
  vim.defer_fn(function() H.close_floating_info(true) end, 0)

  -- Stop current LSP request that tries to get not current data
  H.cancel_lsp({'hover'})

  -- Update metadata before leaving to register a `CompleteChanged` event
  H.info.event = vim.v.event
  H.info.id = H.info.id + 1

  -- Don't event try to show info if nothing is selected in popup
  if vim.tbl_isempty(H.info.event.completed_item) then return end

  H.timers.auto_info:start(
    MiniCompletion.delay_info, 0, vim.schedule_wrap(H.show_floating_info)
  )
end

function MiniCompletion.stop_all()
  H.cache.popup_source = nil
  H.stop_complete()
  H.stop_info()
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

    local words = H.process_lsp_request_result(
      H.lsp.completion.result,
      function(single_result)
        return vim.lsp.util.text_document_completion_list_to_complete_items(single_result, base)
      end
    )

    H.lsp.completion.status = 'done'

    -- Maybe trigger fallback action
    if vim.tbl_isempty(words) and H.cache.fallback then
      H.trigger_fallback()
      return
    end

    -- Track from which source is current popup
    H.cache.popup_source = 'lsp'
    return words
  end
end

-- Helpers
---- Module default config
H.config = {
  delay_completion = MiniCompletion.delay_completion,
  delay_info = MiniCompletion.delay_info,
  lsp_triggers = MiniCompletion.lsp_triggers,
  mappings = {
    force = '<C-Space>' -- Force completion
  }
}

H.trigger_keys = {
  usercompl = vim.api.nvim_replace_termcodes('<C-x><C-u>', true, false, true),
  ctrl_n = vim.api.nvim_replace_termcodes('<C-g><C-g><C-n>', true, false, true),
}

H.timers = {auto_complete = vim.loop.new_timer(), auto_info = vim.loop.new_timer()}

-- Table describing state of all used LSP requests. Structure:
-- - id: identifier (consecutive numbers).
-- - status: status. One of 'sent', 'received', 'done', 'canceled'.
-- - result: result of request.
-- - cancel_fun: function which cancels current request.
H.lsp = {
  completion = {id = 0, status = nil, result = nil, cancel_fun = nil},
  hover      = {id = 0, status = nil, result = nil, cancel_fun = nil}
}

H.cache = {fallback = true, force = false, popup_source = nil}

function H.trigger()
  if vim.fn.mode() ~= 'i' then return end
  if H.has_lsp_clients() then
    H.trigger_lsp()
  elseif H.cache.fallback then
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
  local no_popup = H.cache.force or (not H.pumvisible())
  if no_popup and has_complete then
    H.feedkeys_in_insert(H.trigger_keys.usercompl)
  end
end

function H.trigger_fallback()
  local no_popup = H.cache.force or (not H.pumvisible())
  if no_popup then
    -- Track from which source is current popup
    H.cache.popup_source = 'fallback'
    H.feedkeys_in_insert(H.trigger_keys.ctrl_n)
  end
end

function H.has_lsp_clients() return not vim.tbl_isempty(vim.lsp.buf_get_clients()) end

function H.is_char_keyword(char)
  -- Using Vim's `match()` and `keyword` enables respecting Cyrillic letters
  return vim.fn.match(char, '[[:keyword:]]') >= 0
end

function H.is_lsp_trigger(char)
  local ft = vim.bo.filetype
  local lsp_triggers = MiniCompletion.lsp_triggers
  local triggers = lsp_triggers[ft] or
    lsp_triggers.default or
    H.config.lsp_triggers.default

  return vim.tbl_contains(triggers, char)
end

function H.stop_complete()
  H.timers.auto_complete:stop()
  H.cancel_lsp({'completion'})
  H.cache.fallback, H.cache.force = true, false
end

function H.stop_info()
  -- Id update is needed to notify that all previous work is not current
  H.info.id = H.info.id + 1
  H.timers.auto_info:stop()
  H.cancel_lsp({'hover'})
  H.close_floating_info()
end

function H.cancel_lsp(names)
  names = names or {'completion', 'hover'}
  for _, n in pairs(names) do
    if vim.tbl_contains({'sent', 'received'}, H.lsp[n].status) then
      if H.lsp[n].cancel_fun then H.lsp[n].cancel_fun() end
      H.lsp[n].status = 'canceled'
    end
  end
end

function H.feedkeys_in_insert(key)
  if vim.fn.mode() == 'i' then vim.fn.feedkeys(key) end
end

function H.pumvisible() return vim.fn.pumvisible() > 0 end

function H.get_completion_start()
  -- Compute start position of latest keyword (as in `vim.lsp.omnifunc`)
  local pos = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_get_current_line()
  local line_to_cursor = line:sub(1, pos[2])
  return vim.fn.match(line_to_cursor, '\\k*$')
end

function H.process_lsp_request_result(request_result, processor)
  if not request_result then return {} end

  local res = {}
  for _, item in pairs(request_result) do
    if not item.err and item.result then
      vim.list_extend(res, processor(item.result))
    end
  end

  return res
end

H.info = {bufnr = nil, event = nil, id = 0, lines = nil, winnr = nil}

function H.show_floating_info()
  local event = H.info.event
  if not event then return end

  -- Try first to take lines from LSP request result.
  local lines
  if H.lsp.hover.status == 'received' then
    -- Output floating info comes from first valid request result
    lines = H.process_lsp_request_result(
      H.lsp.hover.result,
      function(single_result)
        if not single_result.contents then return {} end
        local res = vim.lsp.util.convert_input_to_markdown_lines(single_result.contents)
        return vim.lsp.util.trim_empty_lines(res)
      end
    )

    H.lsp.hover.status = 'done'
  else
    lines = H.floating_info_lines(H.info.id)
  end

  -- Don't show anything if there is nothing to show
  if not lines or H.is_whitespace(lines) then return end

  -- Add `lines` to info buffer
  vim.lsp.util.stylize_markdown(H.info.bufnr, lines, {})

  -- Compute floating window options
  local opts = H.floating_info_options()

  -- Defer execution because of textlock during `CompleteChanged` event
  vim.defer_fn(
    function()
      -- Ensure that window doesn't open when it shouldn't be
      if not (H.pumvisible() and vim.fn.mode() == 'i') then return end

      H.info.winnr = vim.api.nvim_open_win(H.info.bufnr, false, opts)
      vim.api.nvim_win_set_option(H.info.winnr, "wrap", true)
    end,
    0
  )
end

function H.floating_info_lines(info_id)
  -- Try to use 'info' field of completion item
  local completed_item = H.info.event ~= nil and H.info.event.completed_item or {}
  local text = completed_item.info or ''

  if not H.is_whitespace(text) then
    -- Use `<text></text>` to be properly processed by `stylize_markdown()`
    local lines = {'<text>'}
    for _, l in pairs(H.split_lines(text)) do table.insert(lines, l) end
    table.insert(lines, '</text>')
    return lines
  end

  -- Finally, try LSP request to retrieve info lines (if popup is from LSP)
  if H.cache.popup_source ~= 'lsp' then return nil end

  local bufnr = vim.api.nvim_get_current_buf()
  local params = vim.lsp.util.make_position_params()

  local current_id = H.lsp.hover.id + 1
  H.lsp.hover.id = current_id
  H.lsp.hover.status = 'sent'

  -- WARN Currently there is an issue with using 'textDocument/hover'.
  -- It makes request for the text that is shown in buffer and not for the item
  -- in popup. Those are the same if completion popup is navigated with
  -- `<C-n>/<C-p>`. But using arrows (`<Down>/<Up>`) don't change text in
  -- buffer while still triggering `CompleteChanged`. This means that request
  -- is done for the wrong item.
  -- Using distinction between arros and <C-n> might be even a good thing **if
  -- there is no LSP request when using arrows**.
  -- Possible half-solutions that I currently managed to find:
  -- - Use counter for `TextChangedP` events and track similar counter for
  --   showing floating info. If they differ, it means that text was currently
  --   updated in `CompleteChanged` (needs `defer_fn(..., 0)` in `auto_info`
  --   because `CompleteChanged` seems to trigger before `TextChangedP`).
  --   Currently seems a little bit complicated but the most appropriate.
  -- - Don't close window on `CompleteChanged` ('solution' which seems to be
  --   used in `completion-nvim`). But it still makes LSP requests (albeit a
  --   probably "cached and fast" ones)
  -- - Use `completionItem/resolve` instead of `textDocument/hover` (like in
  --   `nvim-compe`). Small changes are needed (`params` should be
  --   `H.info.event.completed_item.user_data.nvim.lsp.completion_item` and
  --   use different result postprocessing). However, this gives way less
  --   information and doesn't seem to be that widespread as
  --   'textDocument/hover'.
  cancel_fun = vim.lsp.buf_request_all(bufnr, 'textDocument/hover', params, function(result)
    -- Don't do anything if there is other LSP request in action
    if not H.is_lsp_current('hover', current_id) then return end

    H.lsp.hover.status = 'received'

    -- Don't do anything if completion item was changed
    if H.info.id ~= info_id then return end

    -- Here `result` should not be `nil` or recursion will happen
    if not result then return end
    H.lsp.hover.result = result
    H.show_floating_info()
  end)

  H.lsp.hover.cancel_fun = cancel_fun

  return nil
end

function H.floating_info_options()
  -- Compute dimensions based on lines to be displayed
  local lines = vim.api.nvim_buf_get_lines(H.info.bufnr, 0, -1, {})
  ---- Height
  local info_height = math.min(#lines, 25)
  ---- Width. This may be not entirely correct as `lines` can be in markdown
  local max_width = 0
  for _, l in pairs(lines) do if #l > max_width then max_width = #l end end
  local info_width = math.min(max_width, 80)

  -- Compute position
  local event = H.info.event
  local pum_left = event.col
  local pum_right = event.col + event.width + (event.scrollbar and 1 or 0)

  local space_left, space_right = pum_left, vim.o.columns - pum_right

  local anchor, col, space
  -- Decide side at which floating info will be displayed
  if info_width <= space_right or space_left <= space_right then
    anchor, col, space = 'NW', pum_right, space_right
  else
    anchor, col, space = 'NE', pum_left, space_left
  end

  -- Possibly adjust floating window width to fit screen
  info_width = math.min(info_width, space)

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

function H.close_floating_info(keep_timer)
  if not keep_timer then H.timers.auto_info:stop() end

  if H.info.winnr then vim.api.nvim_win_close(H.info.winnr, true) end
  H.info.winnr = nil

  -- For some reason 'buftype' might be reset. Ensure that buffer is scratch.
  vim.fn.setbufvar(H.info.bufnr, '&buftype', 'nofile')
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

function H.is_lsp_current(name, id)
  return H.lsp[name].id == id and H.lsp[name].status == 'sent'
end

function H.split_lines(s)
  if type(s) ~= 'string' then return nil end
  local lines = {}
  for l in s:gmatch("[^\r\n]+") do table.insert(lines, l) end
  return lines
end

return MiniCompletion
