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

  -- Setup module behavior
  vim.api.nvim_exec([[
    augroup MiniCompletion
      au!
      au InsertCharPre  * lua MiniCompletion.auto_complete()
      au InsertLeavePre * lua MiniCompletion.dont_trigger()
      au BufEnter       * set completefunc=v:lua.MiniCompletion.completefunc
    augroup END
  ]], false)

  -- Setup mappings
  vim.api.nvim_set_keymap(
    'i', mappings.force, '<cmd>lua MiniCompletion.force_complete()<cr>',
    {noremap = true, silent = true}
  )
end

function MiniCompletion.auto_complete()
  H.timers.auto_complete:stop()

  if H.pumvisible() or (not H.is_char_triggerable(vim.v.char)) then
    return
  end

  -- Using delay seems to actually improve user experience as it allows fast
  -- typing without many popups. Also useful when synchronous `<C-n>`
  -- completion blocks typing.
  H.timers.auto_complete:start(100, 0, vim.schedule_wrap(H.trigger))
end

function MiniCompletion.force_complete()
  H.trigger()
end

function MiniCompletion.dont_trigger()
  H.timers.auto_complete:stop()
  H.cache_lsp = {}
end

function MiniCompletion.completefunc(findstart, base)
  local n_clients = H.n_lsp_clients()
  if n_clients == 0 then
    if findstart == 1 then return -1 else return {} end
  end

  -- Behave differently if called directly from user or as a result of a
  -- LSP callback
  if vim.tbl_isempty(H.cache_lsp) then
    -- If cache is empty, make LSP request and quit

    -- Prefix to filter completion suggestion should be computed on first call
    _, prefix = H.completion_info()
    local bufnr = vim.api.nvim_get_current_buf()
    local params = vim.lsp.util.make_position_params()

    H.cache_lsp = {n_clients = n_clients, n_answers = 0, words = {}}

    -- NOTE: it is CRUCIAL to make LSP request on the first call to
    -- 'complete-function' (as in Vim's help). This is due to the fact that
    -- cursor line and position are different on the first and second calls to
    -- 'complete-function'. For example, when calling this function at the end
    -- of the line '  he', cursor position on the second call will be
    -- (<linenum>, 4) and line will be '  he' but on the second call -
    -- (<linenum>, 2) and '  ' (because 2 is a column of completion start).
    -- This request is executed on first call because it returns `-3` on first
    -- call (which means cancel and leave completion mode).
    vim.lsp.buf_request(bufnr, 'textDocument/completion', params, function(err, _, result)
      -- Empty cache table means that completion is already not needed
      if vim.tbl_isempty(H.cache_lsp) then return end
      H.cache_lsp.n_answers = H.cache_lsp.n_answers + 1

      if err or not result or vim.fn.mode() ~= "i" then return end

      local matches = vim.lsp.util.text_document_completion_list_to_complete_items(result, prefix)
      vim.list_extend(H.cache_lsp.words, matches)

      -- Trigger this function when each request is done
      H.trigger_lsp()
    end)

    -- End completion and wait for LSP callbacks
    if findstart == 1 then return -3 else return {} end
  else
    -- If cache is not empty (this function is executed as a result of LSP
    -- callback), use cache on second call
    if findstart == 1 then
      completion_start, _ = H.completion_info()
      return completion_start
    else
      local res = H.cache_lsp.words

      -- If all clients answered, clear cache and mayby trigger fallback action
      if H.cache_lsp.n_answers == H.cache_lsp.n_clients then
        H.cache_lsp = {}
        if vim.tbl_isempty(res) then
          H.trigger_fallback()
          return
        end
      end

      return res
    end
  end
end

-- Helpers
---- Module default config
H.config = {
  mappings = {
    force = '<C-Space>' -- Force completion
  }
}

H.trigger_keys = {
  usercompl = vim.api.nvim_replace_termcodes('<C-x><C-u>', true, false, true),
  ctrl_n = vim.api.nvim_replace_termcodes('<C-g><C-g><C-n>', true, false, true),
}

H.timers = {auto_complete = vim.loop.new_timer()}

H.cache_lsp = {}

function H.trigger()
  if vim.fn.mode() ~= 'i' then return end
  if H.n_lsp_clients() > 0 then
    H.trigger_lsp()
  else
    H.trigger_fallback()
  end
end

function H.trigger_lsp()
  if vim.api.nvim_buf_get_option(0, 'completefunc') ~= '' then
    H.feedkeys_in_insert(H.trigger_keys.usercompl)
  end
end

function H.trigger_fallback()
  H.feedkeys_in_insert(H.trigger_keys.ctrl_n)
end

function H.pumvisible() return vim.fn.pumvisible() ~= 0 end

function H.n_lsp_clients()
  local n = 0
  for _, _ in pairs(vim.lsp.buf_get_clients()) do n = n + 1 end
  return n
end

function H.is_char_triggerable(char)
  -- Using Vim's `match()` and `keyword` enables respecting Cyrillic letters
  return vim.fn.match(char, '[[:keyword:]|.|:]') >= 0
end

function H.feedkeys_in_insert(key)
  if vim.fn.mode() == 'i' then vim.fn.feedkeys(key) end
end

function H.completion_info()
  -- Compute start position of latest prefix and prefix itself
  local pos = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_get_current_line()
  local line_to_cursor = line:sub(1, pos[2])
  local completion_start = vim.fn.match(line_to_cursor, '\\k*$')
  local prefix = line_to_cursor:sub(completion_start+1)

  return completion_start, prefix
end

return MiniCompletion
