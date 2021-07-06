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
    augroup END
  ]], false)

  -- Setup mappings
  vim.api.nvim_set_keymap(
    'i', mappings.force, '<cmd>lua MiniCompletion.force_complete()<cr>',
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
  if vim.fn.pumvisible() > 0 or
    not (H.is_char_keyword(vim.v.char) or char_is_lsp_trigger) then
    MiniCompletion.stop_trigger()
    return
  end

  -- If character is purely lsp trigger, make new LSP request without fallback
  if char_is_lsp_trigger then H.cancel_lsp_request() end
  H.do_fallback = not char_is_lsp_trigger

  -- Using delay (of debounce type) seems to actually improve user experience
  -- as it allows fast typing without many popups. Also useful when synchronous
  -- `<C-n>` completion blocks typing.
  H.timers.auto_complete:start(
    MiniCompletion.trigger_delay, 0, vim.schedule_wrap(H.trigger)
  )
end

function MiniCompletion.force_complete(fallback)
  MiniCompletion.stop_trigger()
  H.do_fallback = fallback or true
  H.trigger()
end

function MiniCompletion.stop_trigger()
  H.timers.auto_complete:stop()
  H.cancel_lsp_request()
  H.do_fallback = true
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
    if vim.tbl_isempty(words) and H.do_fallback then
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

H.do_fallback = true

function H.trigger()
  if vim.fn.mode() ~= 'i' then return end
  if H.has_lsp_clients() then
    H.trigger_lsp()
  elseif H.do_fallback then
    H.trigger_fallback()
  end
end

function H.trigger_lsp()
  if vim.api.nvim_buf_get_option(0, 'completefunc') ~= '' then
    H.feedkeys_in_insert(H.trigger_keys.usercompl)
  end
end

function H.trigger_fallback() H.feedkeys_in_insert(H.trigger_keys.ctrl_n) end

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

return MiniCompletion
