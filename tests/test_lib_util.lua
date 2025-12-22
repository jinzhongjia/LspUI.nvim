local h = require("tests.helpers")
local new_set = MiniTest.new_set

local lib_util = require("LspUI.lib.util")

local T = new_set()

T["islist"] = new_set()

T["islist"]["returns false for non-table values"] = function()
    h.eq(false, lib_util.islist(nil))
    h.eq(false, lib_util.islist(123))
    h.eq(false, lib_util.islist("string"))
    h.eq(false, lib_util.islist(true))
    h.eq(false, lib_util.islist(function() end))
end

T["islist"]["returns false for empty table"] = function()
    h.eq(false, lib_util.islist({}))
end

T["islist"]["returns true for array-like tables"] = function()
    h.eq(true, lib_util.islist({ 1 }))
    h.eq(true, lib_util.islist({ 1, 2, 3 }))
    h.eq(true, lib_util.islist({ "a", "b", "c" }))
    h.eq(true, lib_util.islist({ 1, "mixed", true }))
end

T["islist"]["returns false for dict-like tables"] = function()
    h.eq(false, lib_util.islist({ a = 1 }))
    h.eq(false, lib_util.islist({ key = "value" }))
end

T["islist"]["returns false for sparse arrays"] = function()
    h.eq(false, lib_util.islist({ [1] = "a", [3] = "c" }))
end

T["islist"]["returns false for mixed tables"] = function()
    h.eq(false, lib_util.islist({ 1, 2, key = "value" }))
end

T["compute_height_for_contents"] = new_set()

local function mock_width_calculator(str)
    return #str
end

T["compute_height_for_contents"]["returns content count for invalid width"] = function()
    local contents = { "line1", "line2", "line3" }
    h.eq(3, lib_util.compute_height_for_contents(contents, 0, mock_width_calculator))
    h.eq(3, lib_util.compute_height_for_contents(contents, -1, mock_width_calculator))
    h.eq(3, lib_util.compute_height_for_contents(contents, nil, mock_width_calculator))
end

T["compute_height_for_contents"]["returns correct height for single-line content"] = function()
    local contents = { "hello" }
    h.eq(1, lib_util.compute_height_for_contents(contents, 10, mock_width_calculator))
    h.eq(1, lib_util.compute_height_for_contents(contents, 5, mock_width_calculator))
end

T["compute_height_for_contents"]["calculates wrapped lines correctly"] = function()
    local contents = { "1234567890" }
    h.eq(1, lib_util.compute_height_for_contents(contents, 10, mock_width_calculator))
    h.eq(2, lib_util.compute_height_for_contents(contents, 5, mock_width_calculator))
    h.eq(4, lib_util.compute_height_for_contents(contents, 3, mock_width_calculator))
end

T["compute_height_for_contents"]["handles multiple lines"] = function()
    local contents = { "12345", "1234567890" }
    h.eq(2, lib_util.compute_height_for_contents(contents, 10, mock_width_calculator))
    h.eq(3, lib_util.compute_height_for_contents(contents, 5, mock_width_calculator))
end

T["compute_height_for_contents"]["handles empty content"] = function()
    h.eq(0, lib_util.compute_height_for_contents({}, 10, mock_width_calculator))
end

T["compute_height_for_contents"]["handles empty lines"] = function()
    local contents = { "", "abc", "" }
    h.eq(3, lib_util.compute_height_for_contents(contents, 10, mock_width_calculator))
end

return T
