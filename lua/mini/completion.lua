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
  MiniCompletion.trigger_delay = config.trigger_delay

  -- Setup module behavior
  vim.api.nvim_exec([[
    augroup MiniCompletion
      au!
      au InsertCharPre  * lua MiniCompletion.auto_complete()
      au InsertLeavePre * lua MiniCompletion.stop_trigger()
      au BufEnter       * set completefunc=v:lua.MiniCompletion.complete_lsp
      au CompleteChanged * lua MiniCompletion.auto_float()
      au CompleteDonePre * lua MiniCompletion.track_complete_done()
      au TextChangedI * lua MiniCompletion.track_text_changed_i()
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
---- Delay (debounce type, in ms) between some user action (character insert,
---- etc.) and triggering something (completion, etc.) within this module.
MiniCompletion.trigger_delay = 100

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
    MiniCompletion.stop_trigger()
    return
  end

  -- If character is purely lsp trigger, make new LSP request without fallback
  -- and forcing new completion
  if char_is_lsp_trigger then H.cancel_lsp_request() end
  H.cache = {fallback = not char_is_lsp_trigger, force = char_is_lsp_trigger}

  -- Using delay (of debounce type) seems to actually improve user experience
  -- as it allows fast typing without many popups. Also useful when synchronous
  -- `<C-n>` completion blocks typing.
  H.timers.auto_complete:start(
    MiniCompletion.trigger_delay, 0, vim.schedule_wrap(H.trigger)
  )
end

function MiniCompletion.complete(fallback, force)
  MiniCompletion.stop_trigger()
  H.cache = {fallback = fallback or true, force = force or true}
  H.trigger()
end

function MiniCompletion.stop_trigger()
  H.timers.auto_complete:stop()
  H.cancel_lsp_request()
  H.cache = {fallback = true, force = false}
end

function MiniCompletion.complete_lsp(findstart, base)
  -- Early return
  if (not H.has_lsp_clients()) or H.lsp_request.status == 'sent' then
    if findstart == 1 then return -3 else return {} end
  end

  -- NOTE: having code for request inside this function enables its use
  -- directly with `<C-x><...>`.
  if H.lsp_request.status ~= 'received' then
    current_id = H.lsp_request.id + 1
    H.lsp_request.id = current_id
    H.lsp_request.status = 'sent'

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
      local is_current = H.lsp_request.id == current_id and H.lsp_request.status == 'sent'
      if not is_current then return end

      H.lsp_request.status = 'received'
      H.lsp_request.result = result

      -- Trigger LSP completion to take 'received' route
      H.trigger_lsp()
    end)

    -- Cache cancel function to disable requests when they are not needed
    H.lsp_request.cancel_fun = cancel_fun

    -- End completion and wait for LSP callback
    if findstart == 1 then return -3 else return {} end
  else
    if findstart == 1 then return H.get_completion_start() end

    local words = H.match_request_result(H.lsp_request.result, base)
    H.lsp_request.status = 'completed'

    -- Maybe trigger fallback action
    if vim.tbl_isempty(words) and H.cache.fallback then
      H.trigger_fallback()
      return
    end

    return words
  end
end

-- Helpers
---- Module default config
H.config = {
  trigger_delay = MiniCompletion.trigger_delay,
  lsp_triggers = MiniCompletion.lsp_triggers,
  mappings = {
    force = '<C-Space>' -- Force completion
  }
}

H.trigger_keys = {
  usercompl = vim.api.nvim_replace_termcodes('<C-x><C-u>', true, false, true),
  ctrl_n = vim.api.nvim_replace_termcodes('<C-g><C-g><C-n>', true, false, true),
}

H.timers = {auto_complete = vim.loop.new_timer()}

-- Table describing current LSP request. Structure:
-- - id: identifier (consecutive numbers).
-- - status: status. One of 'sent', 'received', 'completed', 'canceled'.
-- - result: result of request.
-- - cancel_fun: function which cancels current request.
H.lsp_request = {id = 0, status = nil, result = nil, cancel_fun = nil}

H.cache = {fallback = true, force = false}

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
  --   immediately) provided, request is marked as "completed".
  -- 210ms: LSP is triggered from second key press. As previous request is
  --   "completed", it will once make whole LSP request. Having check for
  --   visible popup should prevent here the call to complete-function.
  -- When `force` is `true` then presence of popup shouldn't matter.
  local no_popup = H.cache.force or (not H.pumvisible())
  if no_popup and has_complete then
    H.feedkeys_in_insert(H.trigger_keys.usercompl)
  end
end

function H.trigger_fallback()
  local no_popup = H.cache.force or (not H.pumvisible())
  if no_popup then
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

function H.cancel_lsp_request()
  if vim.tbl_contains({'sent', 'received'}, H.lsp_request.status) then
    if H.lsp_request.cancel_fun then H.lsp_request.cancel_fun() end
    H.lsp_request.status = 'canceled'
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

function H.match_request_result(request_result, base)
  if not request_result then return {} end

  local words = {}
  for _, item in pairs(request_result) do
    if not item.err and item.result then
      local matches = vim.lsp.util.text_document_completion_list_to_complete_items(item.result, base)
      vim.list_extend(words, matches)
    end
  end

  return words
end

H.info = {bufnr = nil, winnr = nil}

function MiniCompletion.auto_float()
  local event = vim.v.event
  local info_height = vim.o.pumheight
  local has_item_selected = event and not vim.tbl_isempty(event.completed_item)
  local enough_window_height = vim.fn.winheight(0) > info_height
  if not has_item_selected or not enough_window_height or event.height == 0 then
    -- Defer execution because of textlock during `CompleteChanged` event
    vim.defer_fn(H.close_float, 0)
    return
  end

  local opts = H.float_options(event)
  local text = event.completed_item.word

  -- Defer execution because of textlock during `CompleteChanged` event
  vim.defer_fn(
    function()
      H.close_float()
      vim.api.nvim_buf_set_lines(H.info.bufnr, 0, -1, false, {text})
      H.info.winnr = vim.api.nvim_open_win(H.info.bufnr, false, opts)
      vim.api.nvim_win_set_option(H.info.winnr, "wrap", true)
    end,
    0
  )
end

function H.float_options(event)
  local info_height = vim.o.pumheight
  local info_width = 4 * vim.o.pumwidth

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
    focusable = false,
    style = 'minimal'
  }
end

function H.close_float()
  if H.info.winnr then vim.api.nvim_win_close(H.info.winnr, true) end
  -- For some reason 'buftype' might be resetted. Ensure that buffer is scratch.
  vim.fn.setbufvar(H.info.bufnr, '&buftype', 'nofile')
  H.info.winnr = nil
end

function MiniCompletion.track_complete_done() H.close_float() end

function MiniCompletion.track_text_changed_i() H.close_float() end

return MiniCompletion
