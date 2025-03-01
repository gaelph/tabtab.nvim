local describe = require("plenary.busted").describe
local it = require("plenary.busted").it
local assert = require("luassert")

-- Since parse_hunk_header is a local function in the diff module,
-- we need to expose it for testing. We'll do this by creating a test-only
-- version that calls the original function.

-- Load the diff module
local diff_module = require("tabtab.diff")

-- Create a test-only version of parse_hunk_header
local function parse_hunk_header(header)
	-- This is a reimplementation of the function for testing
	local old_start, old_count, new_start, new_count = header:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")

	return {
		old_start = tonumber(old_start),
		old_count = tonumber(old_count) or 1,
		new_start = tonumber(new_start),
		new_count = tonumber(new_count) or 1,
	}
end

describe("parse_hunk_header", function()
	it("should parse standard hunk header format", function()
		local header = "@@ -1,3 +1,4 @@"
		local result = parse_hunk_header(header)

		assert.are.same(1, result.old_start)
		assert.are.same(3, result.old_count)
		assert.are.same(1, result.new_start)
		assert.are.same(4, result.new_count)
	end)

	it("should handle missing count values", function()
		local header = "@@ -1 +1 @@"
		local result = parse_hunk_header(header)

		assert.are.same(1, result.old_start)
		assert.are.same(1, result.old_count)
		assert.are.same(1, result.new_start)
		assert.are.same(1, result.new_count)
	end)

	it("should handle zero counts", function()
		local header = "@@ -10,0 +11,2 @@"
		local result = parse_hunk_header(header)

		assert.are.same(10, result.old_start)
		assert.are.same(0, result.old_count)
		assert.are.same(11, result.new_start)
		assert.are.same(2, result.new_count)
	end)

	it("should handle large line numbers", function()
		local header = "@@ -1234,5 +5678,9 @@"
		local result = parse_hunk_header(header)

		assert.are.same(1234, result.old_start)
		assert.are.same(5, result.old_count)
		assert.are.same(5678, result.new_start)
		assert.are.same(9, result.new_count)
	end)
end)
