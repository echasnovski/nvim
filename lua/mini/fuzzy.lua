-- MIT License Copyright (c) 2021 Evgeni Chasnovski
--
-- Lua module which implements functions fuzzy filtering and matching.
--
-- This module doesn't need to get activated. Call to `setup()` will create
-- global `MiniBase16` object. Use its functions as with normal Lua modules.
--
-- Default `config`: {} (currently nothing to configure)
--
-- `fuzzy_match()` reduces a list of `cadidates` to those matching the
-- `word`.  By default it also sorts the output from best to worst matching.
-- Its design is mainly focused on `fuzzy typing completion` use case.
--
-- *Algorithm*
-- Current approach is a slightly modified and simplified version of FZF's fast
-- (version 1) algorithm. It is mainly designed for speed sacrificing small
-- amount of match precision. Core ideas:
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
--       matched with candidate's third letter when in practice fifth letter
--       is more appropriate.
-- - Sorting is done based on comparing candidate's matching of word's
--   letters. It has the following logic (with examples for `word = 'time'`):
--     - Tighter match is more favourable (measured by 'index of last letter'
--       minus 'index of first letter'). So '_time' is a better match than
--       't_ime'. NOTE: due to the fact that currently only one "match
--       improvement" is done, this rule might not always hold. For example,
--       't__ime__time' is a worse match than `t_ime`, despite the fact that
--       it contains an exact word (which didn't end up being matched).
--     - In case of equally tight matches, the one starting earlier is
--       better. So 'time_a' is better than 'a_time'.
--     - In case of equally tight and early matches, the one having more
--       letters matched earlier is better. This is measured by the sum of
--       matched letter indexes. So 'tim_e' is better than 't_ime'.
--     - If previous steps can't decide a better candidate, the one with
--       earlier table index is better. This preserves input ordering of
--       candidates.
--
-- NOTE: currently doesn't work with multibyte symbols.

-- Module and its helper
local MiniFuzzy = {}
local H = {}

-- Module setup
function MiniFuzzy.setup(config)
  -- Export module
  _G.MiniFuzzy = MiniFuzzy

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)
end

-- @param candidates Lua array of strings inside which word will be searched
-- @param word String which will be searched
-- @param sort (default: `true`) Whether to sort output candidates from best
--   to worst match
-- @param case_sensitive (default: `false`) Whether search is case sensitive.
-- @return matched_candidates, matched_indexes Arrays of matched candidates
--   and their indexes in original input.
function MiniFuzzy.fuzzy_match(candidates, word, sort, case_sensitive)
  sort = sort or true
  case_sensitive = case_sensitive or false

  local matches = H.fuzzy_filter_impl(word, candidates, case_sensitive)
  if sort then
    table.sort(matches, H.fuzzy_compare)
  end

  return H.matches_to_tuple(matches)
end

---- Fuzzy matching for `MiniCompletion.lsp_completion.process_items`
function MiniFuzzy.fuzzy_process_lsp_items(items, base, sort, case_sensitive)
  -- Extract completion words from items
  local words = vim.tbl_map(function(x)
    if type(x.textEdit) == 'table' and x.textEdit.newText then
      return x.textEdit.newText
    end
    return x.insertText or x.label or ''
  end, items)

  -- Fuzzy match
  local _, match_inds = MiniFuzzy.fuzzy_match(words, base, sort, case_sensitive)
  return vim.tbl_map(function(i)
    return items[i]
  end, match_inds)
end

-- Helper functions
---- Settings
function H.setup_config(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.config, config or {})

  return config
end

function H.apply_config(config) end

---- Fuzzy matching
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

return MiniFuzzy
