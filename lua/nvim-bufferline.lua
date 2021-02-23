local ok, bufferline = pcall(require, 'bufferline')

if not ok then
  return
end

bufferline.setup{
  options = {
    numbers = "none",
    separator_style = "thin",
    diagnostics = false,
    -- TODO Figure out a better way to have minimum width tab
    max_name_length = 20,
    tab_size = 1,
    show_buffer_close_icons = false,
    enforce_regular_tabs = false,
    -- Sort by the buffer identifier
    sort_by = function(buffer_a, buffer_b) return buffer_a.id < buffer_b.id end
  }
}
