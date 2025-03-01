# TabTab Diff Tests

This directory contains tests for the TabTab Diff module using the Plenary.nvim test harness.

## Running Tests

To run all tests:

```bash
./run_tests.sh
```

Or manually:

```bash
nvim --headless -c "PlenaryBustedDirectory lua/tabtab/diff/tests/ {minimal_init = 'lua/tabtab/diff/tests/minimal_init.lua'}"
```

To run a specific test file:

```bash
nvim --headless -c "PlenaryBustedFile lua/tabtab/diff/tests/word_diff_spec.lua {minimal_init = 'lua/tabtab/diff/tests/minimal_init.lua'}"
```

## Test Files

- `word_diff_spec.lua`: Tests for the `word_diff` function that parses git word-diff format
- `parse_hunk_header_spec.lua`: Tests for the hunk header parsing functionality
- `integration_spec.lua`: Integration tests that verify the entire diff processing pipeline

## Minimal Init

The `minimal_init.lua` file provides a minimal Neovim configuration for running the tests.

## Requirements

- Neovim
- Plenary.nvim (for the test harness)

## Test Structure

Each test file follows the BDD-style testing pattern provided by Plenary:

```lua
describe("component", function()
  it("should do something specific", function()
    -- Test code
    assert.are.same(expected, actual)
  end)
end)
```
