-- Helper to print Lua objects
function _G.dump(x)
  print(vim.inspect(x))
end

-- Execute `f` once and time how long it took
-- @param f Function which execution to benchmark
-- @param ... Arguments when calling `f`
-- @return duration, output Duration (in seconds; up to microseconds) and
--   output of function execution
function bench_time(f, ...)
  local start_sec, start_usec = vim.loop.gettimeofday()
  local output = f(...)
  local end_sec, end_usec = vim.loop.gettimeofday()
  local duration = (end_sec - start_sec) + 0.000001 * (end_usec - start_usec)

  return duration, output
end
