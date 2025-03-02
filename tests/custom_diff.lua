local describe = require("plenary.busted").describe
local it = require("plenary.busted").it
local assert = require("luassert")

-- Since parse_hunk_header is a local function in the diff module,
-- we need to expose it for testing. We'll do this by creating a test-only
-- version that calls the original function.

-- Load the diff module
local diff_module = require("tabtab.diff.custom")

describe("compute_diff", function()
	it("should compute diff between two strings", function()
		local old_content = [[this is a line for context
this line will be replaced
this is another line for context
this line should be deleted

this is a line for context
it is important to have some context]]

		local new_content = [[this is a line for context
this line has been replaced
this is another line for context

this is a line for context
it is important to have some context
to see if those lines are added
after the replacement
and the changes
and the deletions
and the additions
]]

		local diff = diff_module.compute_diff(old_content, new_content)
		vim.print(diff)

		assert.are.same(8, #diff)
		local change = diff[1]
		assert.are.same(1, change.line)
		assert.are.same("context", change.kind)
		assert.are.same("this is a line for context", change.content)

		change = diff[2]
		assert.are.same(2, change.line)
		assert.are.same("change", change.kind)
		assert.are.same("this line has been replaced", change.content)
		assert.are.same(7, #change.changes)

		local word_change = change.changes[1]
		assert.are.same("context", word_change.kind)
		assert.are.same("this line ", word_change.content)
		word_change = change.changes[2]
		assert.are.same("deletion", word_change.kind)
		assert.are.same("will", word_change.content)
		word_change = change.changes[3]
		assert.are.same("addition", word_change.kind)
		assert.are.same("has", word_change.content)
		word_change = change.changes[4]
		assert.are.same("context", word_change.kind)
		assert.are.same(" ", word_change.content)
		word_change = change.changes[5]
		assert.are.same("deletion", word_change.kind)
		assert.are.same("be", word_change.content)
		word_change = change.changes[6]
		assert.are.same("addition", word_change.kind)
		assert.are.same("been", word_change.content)
		word_change = change.changes[7]
		assert.are.same("context", word_change.kind)
		assert.are.same(" replaced", word_change.content)

		change = diff[3]
		assert.are.same(3, change.line)
		assert.are.same("context", change.kind)
		assert.are.same("this is another line for context", change.content)

		change = diff[4]
		assert.are.same(4, change.line)
		assert.are.same("deletion", change.kind)
		assert.are.same("this line should be deleted", change.content)

		change = diff[5]
		assert.are.same(4, change.line)
		assert.are.same("context", change.kind)
		assert.are.same("", change.content)

		change = diff[6]
		assert.are.same(5, change.line)
		assert.are.same("context", change.kind)
		assert.are.same("this is a line for context", change.content)

		change = diff[7]
		assert.are.same(6, change.line)
		assert.are.same("context", change.kind)
		assert.are.same("it is important to have some context", change.content)

		change = diff[8]
		assert.are.same(7, change.line)
		assert.are.same("addition", change.kind)
		assert.are.same(
			"to see if those lines are added\nafter the replacement\nand the changes\nand the deletions\nand the additions\n",
			change.content
		)
	end)
end)
