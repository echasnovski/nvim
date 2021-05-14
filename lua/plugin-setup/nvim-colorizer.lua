local ok, colorizer = pcall(require, 'colorizer')

if not ok then return end

colorizer.setup({
  '*';
  css = { rgb_fn = true; }; -- Enable parsing rgb(...) functions in css
  }, {
    names = false; -- Don't color plain names
    RRGGBBAA = true; -- Color 'RRGGBBAA' codes
  })
