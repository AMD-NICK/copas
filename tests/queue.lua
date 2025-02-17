-- make sure we are pointing to the local copas first
package.path = string.format("../src/?.lua;%s", package.path)
local now = require("socket").gettime


local copas = require "copas"
local Queue = copas.queue



local test_complete = false
copas.loop(function()

  -- basic push/pop
  local q = Queue:new()
  q:push "hello"
  assert(q:pop() == "hello", "expected the input to be returned")

  -- yielding on pop when queue is empty
  local s = now()
  copas.addthread(function()
    copas.pause(0.5)
    q:push("delayed")
  end)
  assert(q:pop() == "delayed", "expected a delayed result")
  assert(now() - s >= 0.5, "result was not delayed!")

  -- pop times out
  local ok, err = q:pop(0.5)
  assert(err == "timeout", "expected a timeout")
  assert(ok == nil)

  -- get_size returns queue size
  assert(q:get_size() == 0)
  q:push(1)
  assert(q:get_size() == 1)
  q:push(2)
  assert(q:get_size() == 2)
  q:push(3)
  assert(q:get_size() == 3)

  -- queue behaves as fifo
  assert(q:pop() == 1)
  assert(q:pop() == 2)
  assert(q:pop() == 3)

  -- handles nil values
  q:push(1)
  q:push(nil)
  q:push(3)

  assert(q:pop() == 1)
  local val, err = q:pop()
  assert(val == nil)
  assert(err == nil)
  assert(q:pop() == 3)

  -- stopping
  q:push(1)
  q:push(2)
  q:push(3)
  assert(q:stop())
  local count = 0
  local coro = q:add_worker(function(item)
    count = count + 1
  end)
  copas.pause(0.1)
  assert(count == 3, "expected all 3 items handled")
  assert(coroutine.status(coro) == "dead", "expected thread to be gone")
  -- coro should be GC'able
  local weak = setmetatable({}, {__mode="v"})
  weak[{}] = coro
  coro = nil  -- luacheck: ignore
  collectgarbage()
  collectgarbage()
  assert(not next(weak))
  -- worker exited, so queue is destroyed now?
  ok, err = q:push()
  assert(err == "destroyed", "expected queue to be destroyed")
  assert(ok == nil)
  ok, err = q:pop()
  assert(err == "destroyed", "expected queue to be destroyed")
  assert(ok == nil)


  test_complete = true
end)

-- copas loop exited when here

assert(test_complete, "test did not complete!")
print("test 1 success!")



-- a worker handling nil values
local count = 0
copas.loop(function()
  local q = Queue:new()
  q:push(1)
  q:push(nil)
  q:push(3)
  q:add_worker(function() count = count + 1 end)
  copas.pause(0.5) -- to activate the worker, which will now be blocked on the q semaphore
  assert(q:finish(5))
end)
assert(count == 3, "expected count to be 3, got "..tostring(count))
print("test 2 success!")


-- finish blocks for a timeout
local passed = false
copas.loop(function()
  local q = Queue:new()
  q:push(1) -- no workers, so this one will not be handled

  local s = now()
  local ok, err = q:finish(1)
  local duration = now() - s

  assert(not ok, "expected a falsy value, got: "..tostring(ok))
  assert(err == "timeout", "expected error 'timeout', got: "..tostring(err))
  assert(duration > 1 and duration < 1.2, string.format("expected timeout of 1 second, but took: %f",duration))
  passed = true
end)
assert(passed, "test failed!")
print("test 3 success!")


-- destroying a queue while workers are idle
copas.loop(function()
  local q = Queue:new()
  q:add_worker(function() end)
  copas.pause(0.5) -- to activate the worker, which will now be blocked on the q semaphore
  q:stop()  -- this should exit the idle workers and exit the copas loop
end)

print("test 4 success!")
