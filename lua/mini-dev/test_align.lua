-- Works with `opts.splitter` edge cases: `''`, `'.'`.
-- Last row column doesn't affect column width in case of left justification.

-- - Visual selection is "registered" after performing alignment (`gv` selects
--   previous selection).
-- - Doesn't add trailing whitespace.
-- - Respects different `direction` and `indent` values in `splits.trim()` and
--   `gen_step.trim()`.
-- - Doesn't merge empty strings.

-- - Doesn't remove marks in both Normal and Visual mode.

-- Tests for block mode:
-- - Selection goes past the line (only right column, both columns).
-- - Selection goes over empty line (at start/middle/end of selection).
-- - Works with multibyte characters.
