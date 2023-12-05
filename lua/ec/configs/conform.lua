require('conform').setup({
  -- Map of filetype to formatters
  formatters_by_ft = {
    javascript = { 'prettier' },
    json = { 'prettier' },
    lua = { 'stylua' },
    python = { 'black' },
    r = { 'my_styler' },
  },

  formatters = {
    my_styler = {
      command = 'R',
      -- A list of strings, or a function that returns a list of strings
      -- Return a single string instead of a list to run the command in a shell
      args = { '-s', '-e', 'styler::style_file(commandArgs(TRUE)[1])', '--args', '$FILENAME' },
      stdin = false,
    },
  },
})
