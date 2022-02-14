require('neogen').setup({
  languages = {
    lua = { template = { annotation_convention = 'emmylua' } },
    python = { template = { annotation_convention = 'numpydoc' } },
  },
})
