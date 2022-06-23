# How to test with 'mini.test'

Writing tests for Neovim Lua plugin is hard. Writing good tests for Neovim Lua plugin is even harder. The 'mini.test' module is designed to make it reasonably easier while still allowing lots of flexibility. It deliberately favors a more verbose and program-like style of writing tests, opposite to "human readable, DSL like" approach of [nvim-lua/plenary.nvim](https://github.com/nvim-lua/plenary.nvim) ("busted-style testing" from [Olivine-Labs/busted](https://github.com/Olivine-Labs/busted)). Although the latter is also possible.

This file is intended as a hands-on introduction to 'mini.test' with examples. For more details, see 'mini.test' section of [help file](doc/mini.txt) and tests of this plugin's modules.

General approach of writing test files:
- Organize tests in separate Lua files.
- Each file should be associated with a test set table (output of `MiniTest.new_set()`). Recommended approach is to create it manually in each test file and then return it.
- Each test action should be defined in separate function assign to an entry of test set.
- It is strongly encouraged to use custom Neovim processes to do actual testing inside test action. See [Using child process](#using-child-process).

**NOTES**:
- All commands are assumed to be executed with current working directory being a root of your Neovim plugin project. That is both for shell and Neovim commands.
- All paths are assumed to be relative to current working directory.

## Example plugin

In this file we will be testing 'hello_lines' plugin (once some basic concepts are introduced). It will have functionality to add prefix 'Hello ' to lines. It will have single file 'lua/hello_lines/init.lua' with the following content:

<details><summary>'hello_lines/init.lua'</summary>

```lua
local M = {}

--- Prepend 'Hello ' to every element
---@param lines table Array. Default: { 'world' }.
---@return table Array of strings.
M.compute = function(lines)
  return vim.tbl_map(function(x) return 'Hello ' .. tostring(x) end, lines or { 'world' })
end

--- Set lines with 'Hello ' prefix
---@param buf_id number Buffer handle where lines should be set. Default: 0.
---@param lines table Array. Default: { 'world' }.
M.set_lines = function(buf_id, lines)
  vim.api.nvim_buf_set_lines(buf_id or 0, 0, -1, true, M.compute(lines))
end

return M
```

</details>

## File organization

It might be a bit overwhelming. It actually is for most of the people. However, it should be done once and then you rarely need to touch it.

Overview of full file structure used in for testing 'hello_lines' plugin:

```
.
├── deps
│   └── mini.nvim # Mandatory
├── lua
│   └── hello_lines
│       └── init.lua # Mandatory
├── Makefile # Recommended
├── scripts
│   ├── minimal_init.lua # Mandatory
│   └── minitest.lua # Recommended
└── tests
    └── test_hello_lines.lua # Mandatory
```

To write tests, you'll need these files:

Mandatory:
- **Your Lua plugin in 'lua' directory**. Here we will be testing 'hello_lines' plugin.
- **Test files**. By default they should be Lua files located in 'tests/' directory and named with 'test_' prefix. For example, we will write everything in 'test_hello_lines.lua'. It is usually a good idea to follow this template (will be assumed for the rest of this file):

<details><summary>Template for test files</summary>

```lua
local new_set = MiniTest.new_set
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = new_set()

-- Actual tests definitions will go here

return T
```

</details><br>

- **'mini.nvim' dependency**. It is needed to use its 'mini.test' module. Proposed way to store it is in 'deps/mini.nvim' directory. Create it with `git`:

```bash
mkdir -p deps
git clone --depth 1 https://github.com/echasnovski/mini.nvim deps/mini.nvim
```

- **Manual Neovim startup file** (a.k.a 'init.lua') with proposed path 'scripts/minimal_init.lua'. It will be used to ensure that Neovim processes can recognize your tested plugin and 'mini.nvim' dependency. Proposed minimal content:

<details><summary>'scripts/minimal_init.lua'</summary>

```lua
-- Add current directory to 'runtimepath' to be able to use 'lua' files
vim.cmd([[let &rtp.=','.getcwd()]])

-- Set up 'mini.test' only when calling headless Neovim (like with `make test`)
if #vim.api.nvim_list_uis() == 0 then
  -- Add 'mini.nvim' to 'runtimepath' to be able to use 'mini.test'
  -- Assumed that 'mini.nvim' is stored in 'deps/mini.nvim'
  vim.cmd('set rtp+=deps/mini.nvim')

  -- Set up 'mini.test'
  require('mini.test').setup()
end
```

</details><br>

Recommended:
- **Makefile**. In order to simplify running tests from shell and inside Continuous Integration services (like Github Actions), it is recommended to define Makefile. It will define steps for running tests. Proposed template:

<details><summary>Template for Makefile</summary>

```
# Run all test files
test: deps/mini.nvim
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()"

# Run test from file at `$FILE` environment variable
test_file: deps/mini.nvim
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run_file('$(FILE)')"

# Download 'mini.nvim' to use its 'mini.test' testing module
deps/mini.nvim:
	@mkdir -p deps
	git clone --depth 1 https://github.com/echasnovski/mini.nvim $@
```

</details><br>

- **'mini.test' script** at 'scripts/minitest.lua'. Use it to customize what is tested (which files, etc.) and how. Usually not needed, but otherwise should have some variant of a call to `MiniTest.run()`.

## Running tests

The 'mini.test' module out of the box supports two major ways of running tests:
- **Interactive**. All test files will be run directly inside current Neovim session. This proved to be very useful for debugging while writing tests. To run tests, simply execute `:lua MiniTest.run()` or `:lua MiniTest.run_file()` (assuming, you already have 'mini.test' set up with `require('mini.test').setup()`). With default configuration this will result into floating window with information about results of test execution. Press `q` to close it. **Note**: Be careful though, as it might affect your current setup. To avoid this, [use child processes](#using-child-process) inside tests.
- **Headless** (from shell). Start headless Neovim process with proper startup file and execute `lua MiniTest.run()`. Assuming full file organization from previous section, this can be achieved with `make test`. This will show information about results of test execution directly in shell.


## Basics

These sections will show some basic capabilities of 'mini.test' and how to use them. In all examples code blocks represent some whole test file (like 'tests/test_basics.lua').

### First test

A test is defined as function assigned to a field of test set. If it throws error, test has failed. Here is an example:

```lua
local T = MiniTest.new_set()

T['works'] = function()
  local x = 1 + 1
  if x ~= 2 then
    error('`x` is not equal to 2')
  end
end

return T
```

Writing `if .. error() .. end` is too tiresome. That is why 'mini.test' comes with very minimal but usually quite enough set of *expectations*: `MiniTest.expect`. They display the intended expectation between objects and will throw error with informative message if it doesn't hold. Here is a rewritten previous example:

```lua
local T = MiniTest.new_set()

T['works'] = function()
  local x = 1 + 1
  MiniTest.expect(x, 2)
end

return T
```

Test sets can be nested. This will be useful in combination with [hooks](#hooks) and [parametrization](#test-parametrization):

```lua
local T = MiniTest.new_set()

T['big scope'] = new_set()

T['big scope']['works'] = function()
  local x = 1 + 1
  MiniTest.expect.equality(x, 2)
end

T['big scope']['also works'] = function()
  local x = 2 + 2
  MiniTest.expect.equality(x, 4)
end

T['out of scope'] = function()
  local x = 3 + 3
  MiniTest.expect.equality(x, 6)
end

return T
```

**NOTE**: 'mini.test' supports emulation of busted-style testing by default. So previous example can be written like this:

```lua
describe('big scope', function()
  it('works', function()
    local x = 1 + 1
    MiniTest.expect.equality(x, 2)
  end)

  it('also works', function()
    local x = 2 + 2
    MiniTest.expect.equality(x, 4)
  end)
end)

it('out of scope', function()
  local x = 3 + 3
  MiniTest.expect.equality(x, 6)
end)
```

Although this is possible, the rest of this file will use a recommended test set approach.

### Builtin expectations

There are four builtin expectations:

```lua
local T = MiniTest.new_set()
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local x = 1 + 1

-- This is so frequently used that having short alias proved useful
T['expect.equality'] = function()
  eq(x, 2)
end

T['expect.no_equality'] = function()
  expect.no_equality(x, 1)
end

T['expect.error'] = function()
  -- This expectation will pass because function will throw an error
  expect.error(function()
    if x == 2 then error('Deliberate error') end
  end)
end

T['expect.no_error'] = function()
  -- This expectation will pass because function will *not* throw an error
  expect.no_error(function()
    if x ~= 2 then error('This should not be thrown') end
  end)
end

return T
```

### Writing custom expectation

Although you can use `if ... error() ... end` approach, there is `MiniTest.new_expectation()` to simplify this process for some repetitive expectation. Here is an example used in this plugin:

```lua
local T = MiniTest.new_set()

local expect_match = MiniTest.new_expectation(
  -- Expectation subject
  'string matching',
  -- Predicate
  function(str, pattern) return str:find(pattern) ~= nil end,
  -- Fail context
  function(str, pattern)
    return string.format('Pattern: %s\nObserved string: %s', vim.inspect(pattern), str)
  end
)

T['string matching'] = function()
  local x = 'abcd'
  -- This will pass
  expect_match(x, '^a')

  -- This will fail
  expect_match(x, 'x')
end

return T
```

Executing this content from file 'tests/test_basics.lua' will fail with the following message:

```
FAIL in "tests/test_hello_lines.lua | string matching":
  Failed expectation for string matching.
  Pattern: "x"
  Observed string: abcd
  Traceback:
    tests/test_basics.lua:20
```

### Hooks

Hooks are functions that will be called without arguments at predefined stages of test execution. They are defined for a test set. There are four types of hooks:
- **pre_once** - executed before first (filtered) node.
- **pre_case** - executed before each case (even nested).
- **post_case** - executed after each case (even nested).
- **post_once** - executed after last (filtered) node.

Example:

```lua
local new_set = MiniTest.new_set
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = new_set()

local n = 0
local increase_n = function() n = n + 1 end

T['hooks'] = new_set({
	hooks = { pre_once = increase_n, pre_case = increase_n, post_case = increase_n, post_once = increase_n },
})

T['hooks']['work'] = function()
  -- `n` will be increased twice: in `pre_once` and `pre_case`
  eq(n, 2)
end

T['hooks']['work again'] = function()
  -- `n` will be increased twice: in `post_case` from previous case and
  -- `pre_case` before this one
  eq(n, 4)
end

T['after hooks set'] = function()
  -- `n` will be again increased twice: in `post_case` from previous case and
  -- `post_once` after last case in T['hooks'] test set
  eq(n, 6)
end

return T
```

### Test parametrization

One of the distinctive features of 'mini.test' is ability to leverage test parametrization. As hooks, it is a feature of test set.

Example of simple parametrization:

```lua
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local T = new_set()

-- Each parameter should be an array to allow parametrizing multiple arguments
T['parametrize'] = new_set({ parametrize = { { 1 }, { 2 } } })

-- This will result into two cases. First will fail.
T['parametrize']['works'] = function(x)
  eq(x, 2)
end

-- Parametrization can be nested. Cases are "multiplied" with every combination
-- of parameters.
T['parametrize']['nested'] = new_set({ parametrize = { { '1' }, { '2' } } })

-- This will result into four cases. Two of them will fail.
T['parametrize']['nested']['works'] = function(x, y)
  eq(tostring(x), y)
end

-- Parametrizing multiple arguments
T['parametrize multiple arguments'] = new_set({ parametrize = { { 1, 1 }, { 2, 2 } } })

-- This will result into two cases. Both will pass.
T['parametrize multiple arguments']['works'] = function(x, y)
  eq(x, y)
end

return T
```

### Runtime access to current cases

There is `MiniTest.current` table containing information about "current" test cases. It has `all_cases` and `case` fields with all currently executed tests and *the* current case.

Test case is a single unit of sequential test execution. It contains all information needed to execute test case along with data about its execution. Example:

```lua
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local T = new_set()

T['MiniTest.current.all_cases'] = function()
  -- A useful hack: show runtime data with expecting it to be something else
  eq(MiniTest.current.all_cases, 0)
end

T['MiniTest.current.case'] = function()
  eq(MiniTest.current.case, 0)
end

return T
```

This will result into following lengthy fails:

<details><summary>Fail information</summary>

```
FAIL in "tests/test_basics.lua | MiniTest.current.all_cases":
  Failed expectation for equality.
  Left: { {
      args = {},
      data = {},
      desc = { "tests/test_basics.lua", "MiniTest.current.all_cases" },
      exec = {
        fails = {},
        notes = {},
        state = "Executing test"
      },
      hooks = {
        post = {},
        pre = {}
      },
      test = <function 1>
    }, {
      args = {},
      data = {},
      desc = { "tests/test_basics.lua", "MiniTest.current.case" },
      hooks = {
        post = {},
        pre = {}
      },
      test = <function 2>
    } }
  Right: 0
  Traceback:
    tests/test_basics.lua:8

FAIL in "tests/test_basics.lua | MiniTest.current.case":
  Failed expectation for equality.
  Left: {
    args = {},
    data = {},
    desc = { "tests/test_basics.lua", "MiniTest.current.case" },
    exec = {
      fails = {},
      notes = {},
      state = "Executing test"
    },
    hooks = {
      post = {},
      pre = {}
    },
    test = <function 1>
  }
  Right: 0
  Traceback:
    tests/test_basics.lua:12
```

</details>

### Case helpers

There are some functions intended to help writing more robust cases: `skip()`, `finally()`, and `add_note()`. The `MiniTest.current` table with all 

Example:

```lua
local T = MiniTest.new_set()

-- `MiniTest.skip()` allows skipping rest of test execution while giving an
-- informative note. This test will pass with notes.
T['skip()'] = function()
  if 1 + 1 == 2 then
    MiniTest.skip('Apparently, 1 + 1 is 2')
  end
  error('1 + 1 is not 2')
end

-- `MiniTest.add_note()` allows adding notes. Final state will have
-- "with notes" suffix.
T['add_note()'] = function()
  MiniTest.add_note('This test is not important.')
  error('Custom error.')
end

-- `MiniTest.finally()` allows registering some function to be executed after
-- this case is finished executing (with or without an error).
T['finally()'] = function()
  -- Add note only if test fails
  MiniTest.finally(function()
    if #MiniTest.current.case.exec.fails > 0 then
      MiniTest.add_note('This test is flaky.')
    end
  end)
  error('Expected error from time to time')
end

return T
```

This will result into following messages:

```
NOTE in "tests/test_basics.lua | skip()": Apparently, 1 + 1 is 2

FAIL in "tests/test_basics.lua | add_note()": tests/test_basics.lua:16: Custom error.
NOTE in "tests/test_basics.lua | add_note()": This test is not important.

FAIL in "tests/test_basics.lua | finally()": tests/test_basics.lua:28: Expected error from time to time
NOTE in "tests/test_basics.lua | finally()": This test is flaky.
```

## Customizing test run

### Collection

### Custom files and filter

### Execution

## Using child process

Limitations:
- Due to current RPC protocol implementation can not use functions in both input and output.
- Hanging due to hit-enter-prompt or Operator-pending mode.

### Start/stop in hooks

For `child.reset` and `child.stop`.

### Use helpers

### Test screenshot

## Test 'mini.nvim'

- `mini_load`, etc.
- Use `helpers.new_child_neovim` (with `setup()` method instead of `restart`) and `helpers.expect`, which are monkey-patched versions of ones from `MiniTest`.
