local M = {}
local H = {}

-- Helper to print Lua objects in command line
function M.put(...)
  local objects = {}
  -- Not using `{...}` because it removes `nil` input
  for i = 1, select('#', ...) do
    local v = select(i, ...)
    table.insert(objects, vim.inspect(v))
  end

  print(table.concat(objects, '\n'))

  return ...
end

-- Helper to print Lua objects in current buffer
function M.put_text(...)
  local objects = {}
  -- Not using `{...}` because it removes `nil` input
  for i = 1, select('#', ...) do
    local v = select(i, ...)
    table.insert(objects, vim.inspect(v))
  end

  local lines = vim.split(table.concat(objects, '\n'), '\n')
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  vim.fn.append(lnum, lines)

  return ...
end

-- Execute `f` once and time how long it took
-- @param f Function which execution to benchmark
-- @param ... Arguments when calling `f`
-- @return duration, output Duration (in seconds; up to microseconds) and
--   output of function execution
function M.bench_time(f, ...)
  local start_sec, start_usec = vim.loop.gettimeofday()
  local output = f(...)
  local end_sec, end_usec = vim.loop.gettimeofday()
  local duration = (end_sec - start_sec) + 0.000001 * (end_usec - start_usec)

  return duration, output
end

-- Fuzzy filtering and matching
--
-- `fuzzy_match()` reduces a list of `cadidates` to those matching the `word`.
-- By default it also sorts the output from best to worst matching. Its design
-- is mainly focused on `fuzzy typing completion` use case.
--
-- The current approach is a slightly modified and simplified version of FZF's
-- fast (version 1) algorithm. It is mainly designed for speed sacrificing
-- small amount of match precision. Core ideas:
-- - Word and candidate are matched only if all of word's letters appear in
--   candidate in the same order. The exact matching of word's letters to
--   candidate ones is done in two steps:
--     - Find word's first letter starting from candidate's left and looking
--       forward. Then find word's second letter after the first match, and so
--       on. Candidate is matched if word's last letter is found.
--     - In case of a match, improve it: starting from candidate's match for
--       word's last letter, find word's second to last letter looking
--       backward, and so on. This step tries to improve match for cases like
--       `word='time', candidate='get_time'`: without it word's 't' will be
--       matched with candidate's third letter when in practice fifth letter is
--       more appropriate.
-- - Sorting is done based on comparing candidate's matching of word's letters.
--   It has the following logic (with examples for `word = 'time'`):
--     - Tighter match is more favourable (measured by 'index of last letter'
--       minus 'index of first letter'). So '_time' is a better match than
--       't_ime'. NOTE: due to the fact that currently only one "match
--       improvement" is done, this rule might not always hold. For example,
--       't__ime__time' is a worse match than `t_ime`, despite the fact that it
--       contains an exact word (which didn't end up being matched).
--     - In case of equally tight matches, the one starting earlier is better.
--       So 'time_a' is better than 'a_time'.
--     - In case of equally tight and early matches, the one having more
--       letters matched earlier is better. This is measured by the sum of
--       candidate's matched letter indexes. So 'tim_e' is better than 't_ime'.
--     - If previous steps can't decide a better candidate, the one with lower
--       table index is better. This preserves input ordering of candidates.
--
-- NOTE: currently doesn't work with multibyte symbols.
--
-- @param candidates Lua array of strings inside of which word will be searched
-- @param word String which will be searched
-- @param sort (default: `true`) Whether to sort output candidates from best to
-- worst match
-- @param case_sensitive (default: `false`) Whether search is case sensitive.
-- @return matched_candidates, matched_indexes Arrays of matched candidates and
--   their indexes in original input.
function M.fuzzy_match(candidates, word, sort, case_sensitive)
  sort = sort or true
  case_sensitive = case_sensitive or false

  local matches = H.fuzzy_filter_impl(word, candidates, case_sensitive)
  if sort then
    table.sort(matches, H.fuzzy_compare)
  end

  return H.matches_to_tuple(matches)
end

-- Fuzzy matching for `MiniCompletion.lsp_completion.process_items`
function M.fuzzy_process_lsp_items(items, base, sort, case_sensitive)
  -- Extract completion words from items
  local words = vim.tbl_map(function(x)
    if type(x.textEdit) == 'table' and x.textEdit.newText then
      return x.textEdit.newText
    end
    return x.insertText or x.label or ''
  end, items)

  -- Fuzzy match
  local _, match_inds = M.fuzzy_match(words, base, sort, case_sensitive)
  return vim.tbl_map(function(i)
    return items[i]
  end, match_inds)
end

function H.fuzzy_filter_impl(word, candidates, case_sensitive)
  local insensitive = not case_sensitive

  -- Precompute a table of word's letters
  local n_word = #word
  local letters = {}
  for i = 1, n_word do
    letters[i] = word:sub(i, i)
  end

  local res = {}
  local cand_to_match, let_i, match, pos_last
  for i, cand in ipairs(candidates) do
    -- Make early decision of "not matched" if number of word's letters is
    -- bigger than number of candidate's letters
    if n_word <= #cand then
      cand_to_match = insensitive and cand:lower() or cand
      pos_last, let_i = 0, 1
      while pos_last and let_i <= n_word do
        pos_last = string.find(cand_to_match, letters[let_i], pos_last + 1)
        let_i = let_i + 1
      end
      -- Candidate is a match only if word's last letter is found
      if pos_last then
        match = H.improve_match(pos_last, cand_to_match, letters)
        match.candidate, match.index = cand, i
        table.insert(res, match)
      end
    end
  end

  return res
end

function H.improve_match(pos_last, candidate, letters)
  if #letters == 1 then
    return { pos_width = 0, pos_first = pos_last, pos_sum = pos_last }
  end

  local rev_line = candidate:reverse()
  local n = #candidate
  local rev_last = n - pos_last + 1

  -- Do backward search
  local pos, pos_sum = rev_last, pos_last
  for i = #letters - 1, 1, -1 do
    pos = rev_line:find(letters[i], pos + 1)
    pos_sum = pos_sum + (n - pos + 1)
  end
  local pos_first = n - pos + 1

  return {
    pos_width = pos_last - pos_first,
    pos_first = pos_first,
    pos_sum = pos_sum,
  }
end

function H.fuzzy_compare(a, b)
  -- '_time' is better than 't_ime'
  if a.pos_width < b.pos_width then
    return true
  end
  if a.pos_width == b.pos_width then
    -- 'time_aa' is better than 'aa_time'
    if a.pos_first < b.pos_first then
      return true
    end
    if a.pos_first == b.pos_first then
      -- 'tim_e' is better than 't_ime'
      if a.pos_sum < b.pos_sum then
        return true
      end
      if a.pos_sum == b.pos_sum then
        -- Make sorting stable by preserving index order
        return a.index < b.index
      end
    end
  end
  return false
end

function H.matches_to_tuple(matches)
  local candidates, indexes = {}, {}
  for _, m in pairs(matches) do
    table.insert(candidates, m.candidate)
    table.insert(indexes, m.index)
  end

  return candidates, indexes
end

-- time_lines = {'_time', 't_ime', 'time_aa', 'aa_time', 'tim_e', 'time_b', 'TIME'}
--
-- big_lines = {}
-- for k, val in pairs(vim) do table.insert(big_lines, k) end
-- for k, val in pairs(vim.api) do table.insert(big_lines, 'api.' .. k) end
-- for k, val in pairs(vim.lsp) do table.insert(big_lines, 'lsp.' .. k) end
-- for k, val in pairs(vim.loop) do table.insert(big_lines, 'loop.' .. k) end
-- table.sort(big_lines)

-- Return "first" elements of table as decided by `pairs`
--
-- NOTE: order of elements might be different.
--
-- @param t Table
-- @param n (default: 5) Maximum number of first elements
-- @return Table with at most `n` first elements of `t` (with same keys)
function M.head(t, n)
  n = n or 5
  local res, n_res = {}, 0
  for k, val in pairs(t) do
    if n_res >= n then
      return res
    end
    res[k] = val
    n_res = n_res + 1
  end
  return res
end

-- Return "last" elements of table as decided by `pairs`
--
-- This function makes two passes through elements of `t`:
-- - First to count number of elements.
-- - Second to construct result.
--
-- NOTE: order of elements might be different.
--
-- @param t Table
-- @param n (default: 5) Maximum number of last elements
-- @return Table with at most `n` last elements of `t` (with same keys)
function M.tail(t, n)
  n = n or 5

  -- Count number of elements on first pass
  local n_all = 0
  for _, _ in pairs(t) do
    n_all = n_all + 1
  end

  -- Construct result on second pass
  local res = {}
  local i, start_i = 0, n_all - n + 1
  for k, val in pairs(t) do
    i = i + 1
    if i >= start_i then
      res[k] = val
    end
  end
  return res
end

-- Export some functions
_G.put = M.put
_G.put_text = M.put_text

return M
