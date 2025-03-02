local describe = require("plenary.busted").describe
local it = require("plenary.busted").it
local assert = require("luassert")

local diff_module = require("tabtab.diff")

describe("word_diff", function()
	it("should parse header correctly", function()
		local diff = [[
diff --git a/file.txt b/file.txt
index 1234567..abcdef0 100644
--- a/file.txt
+++ b/file.txt
@@ -1,3 +1,3 @@
 This is a test
 Second line
[-old content-]{+new content+}
]]

		local result = diff_module.word_diff(diff)

		-- Check header
		assert.are.same(5, #result.header)
		assert.are.same("diff --git a/file.txt b/file.txt", result.header[1])
		assert.are.same("index 1234567..abcdef0 100644", result.header[2])
		assert.are.same("--- a/file.txt", result.header[3])
		assert.are.same("+++ b/file.txt", result.header[4])

		-- Check hunks
		assert.is.truthy(result.hunk)
		assert.are.same(1, result.hunk.start_line)
		assert.are.same(3, result.hunk.count)
	end)

	it("should parse word diff markers correctly", function()
		local diff = [[
diff --git a/file.txt b/file.txt
index 1234567..abcdef0 100644
--- a/file.txt
+++ b/file.txt
@@ -1,3 +1,3 @@
 This is a test
 Second line
[-old content-]{+new content+}
]]

		local result = diff_module.word_diff(diff)

		-- Check the parsed changes
		local line = result.hunk.lines[3]
		assert.are.same(3, line.line_num)
		assert.are.same(3, line.absolute_line_num)

		-- Check the changes array
		assert.are.same(2, #line.changes)
		assert.are.same("deletion", line.changes[1].kind)
		assert.are.same("old content", line.changes[1].text)
		assert.are.same("addition", line.changes[2].kind)
		assert.are.same("new content", line.changes[2].text)
	end)

	it("should handle mixed context and changes in a line", function()
		local diff = [[
diff --git a/file.txt b/file.txt
index 1234567..abcdef0 100644
--- a/file.txt
+++ b/file.txt
@@ -1,1 +1,1 @@
This is [-old-]{+new+} text with more [-content-]{+changes+}
]]

		local result = diff_module.word_diff(diff)

		-- Check the parsed changes
		local line = result.hunk.lines[1]

		-- Check the changes array - should have 5 elements
		assert.are.same(6, #line.changes)
		assert.are.same("context", line.changes[1].kind)
		assert.are.same("This is ", line.changes[1].text)
		assert.are.same("deletion", line.changes[2].kind)
		assert.are.same("old", line.changes[2].text)
		assert.are.same("addition", line.changes[3].kind)
		assert.are.same("new", line.changes[3].text)
		assert.are.same("context", line.changes[4].kind)
		assert.are.same(" text with more ", line.changes[4].text)
		assert.are.same("deletion", line.changes[5].kind)
		assert.are.same("content", line.changes[5].text)
	end)

	it("should handle empty diffs", function()
		local diff = ""
		local result = diff_module.word_diff(diff)

		assert.are.same(0, #result.header)
		assert.is.falsy(result.hunk)
	end)

	it("should handle diffs with only headers", function()
		local diff = [[
diff --git a/file.txt b/file.txt
index 1234567..abcdef0 100644
--- a/file.txt
+++ b/file.txt
]]

		local result = diff_module.word_diff(diff)

		assert.are.same(4, #result.header)
		assert.is.falsy(result.hunk)
	end)
end)
