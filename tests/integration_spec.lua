local describe = require("plenary.busted").describe
local it = require("plenary.busted").it
local assert = require("luassert")

local diff_module = require("tabtab.diff")

describe("diff module integration", function()
	it("should process a complete word diff correctly", function()
		local diff = [[
diff --git a/file.txt b/file.txt
index 1234567..abcdef0 100644
--- a/file.txt
+++ b/file.txt
@@ -1,5 +1,5 @@
This is the first line
This is the [-second-]{+modified+} line
This is the third line
[-This line was completely removed-]{+This line was completely changed+}
This is the last line
]]

		local result = diff_module.word_diff(diff)

		-- Check basic structure
		assert.are.same(5, #result.header)
		assert.is.truthy(result.hunk)
		assert.are.same(6, #result.hunk.lines)

		-- Check specific line with word diff
		local line2 = result.hunk.lines[2]
		assert.are.same(2, line2.line_num)

		-- Check the changes in line 2
		assert.are.same(4, #line2.changes)
		assert.are.same("context", line2.changes[1].type)
		assert.are.same("This is the ", line2.changes[1].text)
		assert.are.same("deletion", line2.changes[2].type)
		assert.are.same("second", line2.changes[2].text)
		assert.are.same("addition", line2.changes[3].type)
		assert.are.same("modified", line2.changes[3].text)

		-- Check that we can process the result further
		-- For example, reconstruct the original and modified lines
		local original_line2 = ""
		local modified_line2 = ""

		for _, change in ipairs(line2.changes) do
			if change.type == "context" or change.type == "deletion" then
				original_line2 = original_line2 .. change.text
			end

			if change.type == "context" or change.type == "addition" then
				modified_line2 = modified_line2 .. change.text
			end
		end

		assert.are.same("This is the second line", original_line2)
		assert.are.same("This is the modified line", modified_line2)
	end)
end)
