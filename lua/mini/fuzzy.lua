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

function MiniFuzzy.get_telescope_sorter(opts)
  opts = vim.tbl_deep_extend('force', { case_sensitive = false }, opts or {})

  return require('telescope.sorters').Sorter:new({
    start = function(self, prompt)
      -- Cache prompt's letters
      local letters = {}
      if not opts.case_sensitive then
        prompt = prompt:lower()
      end
      for i = 1, #prompt do
        -- Use `vim.pesc()` to treat special characters ('.', etc.) literally
        letters[i] = vim.pesc(prompt:sub(i, i))
      end
      self.letters = letters
    end,

    -- @param self
    -- @param prompt (which is the text on the line)
    -- @param line (entry.ordinal)
    -- @param entry (the whole entry)
    scoring_function = function(self, _, line, _)
      local match = H.match(self.letters, line, opts.case_sensitive)
      return H.match_to_score(match)
    end,

    -- Currently there doesn't seem to be a proper way to cache matched
    -- positions from inside of `scoring_function` (see `highlighter` code of
    -- `get_fzy_sorter`'s output). Besides, it seems that `display` and `line`
    -- arguments might be different. So, extra calls to `match` are made.
    highlighter = function(self, _, display)
      if #self.letters == 0 or #display == 0 then
        return {}
      end
      local match = H.match(self.letters, display, opts.case_sensitive)
      return match.positions
    end,
  })
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
  -- Precompute a table of word's letters
  local n_word = #word
  if not case_sensitive then
    word = word:lower()
  end
  local letters = {}
  for i = 1, n_word do
    -- Use `vim.pesc()` to treat special characters ('.', etc.) literally
    letters[i] = vim.pesc(word:sub(i, i))
  end

  local res = {}
  for i, cand in ipairs(candidates) do
    local match = H.match(letters, cand, case_sensitive)
    if match then
      match.candidate, match.index = cand, i
      match.score = H.match_to_score(match)
      table.insert(res, match)
    end
  end

  return res
end

-- @param letters List of letters from "typed" word
-- @param candidate String of interest
-- @param case_sensitive Whether match is case sensitive
--
-- @return Table with match information if there is a match, `nil` otherwise.
function H.match(letters, candidate, case_sensitive)
  local n_candidate, n_letters = #candidate, #letters
  if n_candidate <= n_letters then
    return nil
  end

  local cand = case_sensitive and candidate or candidate:lower()

  -- Make forward search for match presence
  local pos_last, let_i = 0, 1
  while pos_last and let_i <= n_letters do
    pos_last = string.find(cand, letters[let_i], pos_last + 1)
    let_i = let_i + 1
  end

  -- Candidate is matched only if word's last letter is found
  if not pos_last then
    return nil
  end

  -- Compute matching positions by going backwards from last letter match
  if n_letters == 1 then
    return { positions = { pos_last }, pos_width = 1, pos_first = pos_last, pos_mean = pos_last }
  end

  local rev_cand, rev_last = cand:reverse(), n_candidate - pos_last + 1

  local positions, pos_sum = { pos_last }, pos_last
  local rev_pos = rev_last
  for i = #letters - 1, 1, -1 do
    rev_pos = rev_cand:find(letters[i], rev_pos + 1)
    local pos = n_candidate - rev_pos + 1
    table.insert(positions, pos)
    pos_sum = pos_sum + pos
  end
  local pos_first = n_candidate - rev_pos + 1

  return {
    positions = H.tbl_reverse(positions),
    pos_width = pos_last - pos_first + 1,
    pos_first = pos_first,
    pos_mean = pos_sum / n_letters,
  }
end

-- Convert match information into score. Smaller values indicate better match
-- (i.e. like distance). Reasoning behind the score is for it to produce the
-- same ordering as with sequential comparison of match's width, first position
-- and mean position. So it shouldn't be perceived as linear distance
-- (difference between scores don't really matter, only their comparison with
-- each other).
--
-- Reasoning behind comparison logic (based on 'time' input):
-- - '_time' is better than 't_ime' (width is smaller).
-- - 'time_aa' is better than 'aa_time' (width is same, first position is
--   smaller).
-- - 'tim_e' is better than 't_ime' (width and first position are same, mean
--   position is smaller).
function H.match_to_score(match)
  if not match then return -1 end
  return 1000 * math.min(match.pos_width, 1000)
    + 1 * math.min(match.pos_first, 1000)
    + 0.001 * math.min(match.pos_mean, 1000)
end

function H.fuzzy_compare(a, b)
  if a.score < b.score then
    return true
  end

  if a.score == b.score then
    -- Make sorting stable by preserving index order
    return a.index < b.index
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

function H.tbl_reverse(t)
  if #t == 0 then
    return {}
  end
  local res = {}
  for i = #t, 1, -1 do
    table.insert(res, t[i])
  end
  return res
end

return MiniFuzzy
