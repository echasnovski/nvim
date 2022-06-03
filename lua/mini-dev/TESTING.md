# How to test with 'mini.test'

## File organization

- Interactive.
- Headless.

## First test

## Builtin expectations

## Writing custom expectation

## Hooks

## Test parametrization

Single parametrization.
Nested parametrization.
Using array elements in nested parametrization.

## Collection

### Custom files and filter

## Execution

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
