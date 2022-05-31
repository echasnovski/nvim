return {
  h = function(...)
    local t = { 1, 2, 3 }
    local dots = { ... }
    return vim.tbl_filter(function(x)
      local ok, err = pcall(MiniTest.expect.equality, unpack(dots))
      error(err)
    end, t)
  end,
}
