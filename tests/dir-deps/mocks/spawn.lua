_G.process_log = {}

local n_pid, n_stream = 0, 0
local new_process = function(pid)
  return {
    pid = pid,
    close = function(_) table.insert(_G.process_log, 'Process ' .. pid .. ' was closed.') end,
    is_closing = function(_) return false end,
  }
end

-- Define object containing the queue from which created streams will read
-- their data.
-- NOTE: Actual tests **heavily** rely on assumption that `vim.loop.new_pipe()`
-- is called in `stdout` / `stderr` pairs for each `spawn` (IN THAT ORDER).
_G.feed_queue = {}
local stream_id = 0
vim.loop.new_pipe = function()
  stream_id = stream_id + 1
  local cur_stream_id = stream_id
  local cur_feed = _G.feed_queue[stream_id] or {}
  if type(cur_feed) == 'string' then cur_feed = { cur_feed } end

  return {
    read_start = function(_, callback)
      for _, x in ipairs(cur_feed) do
        if type(x) == 'table' then callback(x.err, nil) end
        if type(x) == 'string' then callback(nil, x) end
      end
      callback(nil, nil)
    end,
    close = function() table.insert(_G.process_log, string.format('Stream %s was closed.', cur_stream_id)) end,
  }
end

_G.spawn_log = {}
vim.loop.spawn = function(path, options, on_exit)
  local options_without_callables = vim.deepcopy(options)
  options_without_callables.stdio = nil
  table.insert(_G.spawn_log, { executable = path, options = options_without_callables })

  vim.schedule(function() on_exit(0) end)

  n_pid = n_pid + 1
  local pid = 'Pid_' .. n_pid
  return new_process(pid), pid
end

vim.loop.process_kill = function(process) table.insert(_G.process_log, 'Process ' .. process.pid .. ' was killed.') end

_G.n_cpu_info = 4
vim.loop.cpu_info = function()
  local res = {}
  for i = 1, _G.n_cpu_info do
    res[i] = { model = 'A Very High End CPU' }
  end
  return res
end
