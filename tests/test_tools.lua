local h = require("tests.helpers")
local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()

local T = new_set({
    hooks = {
        pre_case = function()
            h.child_start(child)
        end,
        post_once = child.stop,
    },
})

T["version"] = new_set()

T["version"]["returns version string"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        return tools.version()
    ]])
    h.expect_type("string", result)
    h.expect_match("v", result)
end

T["islist"] = new_set()

T["islist"]["returns true for array-like tables"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        return tools.islist({1, 2, 3})
    ]])
    h.eq(true, result)
end

T["islist"]["returns true for string array"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        return tools.islist({"a", "b", "c"})
    ]])
    h.eq(true, result)
end

T["islist"]["returns false for dict-like tables"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        return tools.islist({a = 1, b = 2})
    ]])
    h.eq(false, result)
end

T["islist"]["returns false for mixed tables"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        return tools.islist({1, 2, a = 3})
    ]])
    h.eq(false, result)
end

T["islist"]["returns true for empty table"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        return tools.islist({})
    ]])
    h.eq(true, result)
end

T["islist"]["returns false for non-table"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        return {
            string = tools.islist("hello"),
            number = tools.islist(123),
            boolean = tools.islist(true),
            null = tools.islist(nil),
        }
    ]])
    h.eq(false, result.string)
    h.eq(false, result.number)
    h.eq(false, result.boolean)
    h.eq(false, result.null)
end

T["command_desc"] = new_set()

T["command_desc"]["prefixes description with LspUI"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        return tools.command_desc("hover")
    ]])
    h.eq("[LspUI]: hover", result)
end

T["command_desc"]["handles empty string"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        return tools.command_desc("")
    ]])
    h.eq("[LspUI]: ", result)
end

T["get_max_width"] = new_set()

T["get_max_width"]["returns positive number"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        return tools.get_max_width()
    ]])
    h.expect_type("number", result)
    h.eq(true, result > 0)
end

T["get_max_height"] = new_set()

T["get_max_height"]["returns positive number"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        return tools.get_max_height()
    ]])
    h.expect_type("number", result)
    h.eq(true, result > 0)
end

T["compute_height_for_windows"] = new_set()

T["compute_height_for_windows"]["returns line count for short lines"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        return tools.compute_height_for_windows({"line1", "line2", "line3"}, 80)
    ]])
    h.eq(3, result)
end

T["compute_height_for_windows"]["accounts for line wrapping"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        local long_line = string.rep("a", 100)
        return tools.compute_height_for_windows({long_line}, 50)
    ]])
    h.eq(2, result)
end

T["compute_height_for_windows"]["handles empty content"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        return tools.compute_height_for_windows({}, 80)
    ]])
    h.eq(0, result)
end

T["compute_height_for_windows"]["returns line count for invalid width"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        return tools.compute_height_for_windows({"a", "b"}, 0)
    ]])
    h.eq(2, result)
end

T["compare_uri"] = new_set()

T["compare_uri"]["returns true for identical URIs"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        return tools.compare_uri("file:///test/path.lua", "file:///test/path.lua")
    ]])
    h.eq(true, result)
end

T["compare_uri"]["returns false for different URIs"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        return tools.compare_uri("file:///test/path1.lua", "file:///test/path2.lua")
    ]])
    h.eq(false, result)
end

T["buffer_is_listed"] = new_set()

T["buffer_is_listed"]["returns true for listed buffer"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        local buf = vim.api.nvim_get_current_buf()
        return tools.buffer_is_listed(buf)
    ]])
    h.eq(true, result)
end

T["buffer_is_listed"]["returns false for unlisted buffer"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        local buf = vim.api.nvim_create_buf(false, true)
        return tools.buffer_is_listed(buf)
    ]])
    h.eq(false, result)
end

T["debounce"] = new_set()

T["debounce"]["returns function and cleanup"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        local debounced, cleanup = tools.debounce(function() end, 100)
        return {
            debounced_is_function = type(debounced) == "function",
            cleanup_is_function = type(cleanup) == "function",
        }
    ]])
    h.eq(true, result.debounced_is_function)
    h.eq(true, result.cleanup_is_function)
end

T["exec_once"] = new_set()

T["exec_once"]["executes callback only once"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        local count = 0
        local fn = tools.exec_once(function() count = count + 1 end)
        fn()
        fn()
        fn()
        return count
    ]])
    h.eq(1, result)
end

T["detect_filetype"] = new_set()

T["detect_filetype"]["detects lua files"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        return tools.detect_filetype("test.lua")
    ]])
    h.eq("lua", result)
end

T["detect_filetype"]["detects typescript files"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        return tools.detect_filetype("test.ts")
    ]])
    h.eq("typescript", result)
end

T["detect_filetype"]["detects tsx files"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        return tools.detect_filetype("Component.tsx")
    ]])
    h.eq("typescriptreact", result)
end

T["detect_filetype"]["detects javascript files"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        return tools.detect_filetype("app.js")
    ]])
    h.eq("javascript", result)
end

T["detect_filetype"]["detects python files"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        return tools.detect_filetype("script.py")
    ]])
    h.eq("python", result)
end

T["smart_save_to_jumplist"] = new_set()

T["smart_save_to_jumplist"]["returns true for cross-file jump"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        local current_buf = vim.api.nvim_get_current_buf()
        local other_buf = vim.api.nvim_create_buf(true, false)
        return tools.smart_save_to_jumplist(other_buf, 10, {})
    ]])
    h.eq(true, result)
end

T["smart_save_to_jumplist"]["returns false for nearby same-file jump"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        vim.api.nvim_buf_set_lines(0, 0, -1, false, {"line1", "line2", "line3", "line4", "line5"})
        vim.api.nvim_win_set_cursor(0, {1, 0})
        local current_buf = vim.api.nvim_get_current_buf()
        return tools.smart_save_to_jumplist(current_buf, 3, { min_distance = 5 })
    ]])
    h.eq(false, result)
end

T["smart_save_to_jumplist"]["returns true for distant same-file jump"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        local lines = {}
        for i = 1, 20 do lines[i] = "line" .. i end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.api.nvim_win_set_cursor(0, {1, 0})
        local current_buf = vim.api.nvim_get_current_buf()
        return tools.smart_save_to_jumplist(current_buf, 15, { min_distance = 5 })
    ]])
    h.eq(true, result)
end

T["smart_save_to_jumplist"]["respects cross_file_only option"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        local lines = {}
        for i = 1, 20 do lines[i] = "line" .. i end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.api.nvim_win_set_cursor(0, {1, 0})
        local current_buf = vim.api.nvim_get_current_buf()
        return tools.smart_save_to_jumplist(current_buf, 15, { cross_file_only = true })
    ]])
    h.eq(false, result)
end

T["GetUriLines"] = new_set()

T["GetUriLines"]["returns empty for invalid buffer"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        return #tools.GetUriLines(99999, "file:///nonexistent", {0, 1, 2})
    ]])
    h.eq(0, result)
end

T["GetUriLines"]["returns lines for valid buffer"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        local buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {"line1", "line2", "line3"})
        local uri = vim.uri_from_bufnr(buf)
        local lines = tools.GetUriLines(buf, uri, {0, 1, 2})
        return {
            line0 = lines[0],
            line1 = lines[1],
            line2 = lines[2],
        }
    ]])
    h.eq("line1", result.line0)
    h.eq("line2", result.line1)
    h.eq("line3", result.line2)
end

T["GetUriLines"]["reads unloaded buffer from disk without autocmds"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        local path = vim.fn.tempname() .. ".lua"
        local file = io.open(path, "w")
        for i = 1, 50 do
            file:write(("local line_%d = %d\n"):format(i, i))
        end
        file:close()

        local fired = 0
        vim.api.nvim_create_autocmd(
            { "BufReadPre", "BufReadPost", "FileType", "Syntax" },
            { callback = function() fired = fired + 1 end }
        )

        local buf = vim.fn.bufadd(path)
        local uri = vim.uri_from_fname(path)
        local lines = tools.GetUriLines(buf, uri, { 0, 9, 49 })

        local out = {
            line0 = lines[0],
            line9 = lines[9],
            line49 = lines[49],
            loaded = vim.api.nvim_buf_is_loaded(buf),
            fired = fired,
        }
        vim.fn.delete(path)
        return out
    ]])
    h.eq("local line_1 = 1", result.line0)
    h.eq("local line_10 = 10", result.line9)
    h.eq("local line_50 = 50", result.line49)
    -- 关键断言：buffer 未被加载、未触发任何 BufRead/FileType 链
    h.eq(false, result.loaded)
    h.eq(0, result.fired)
end

T["GetUriLines"]["loaded buffer returns unsaved modifications"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        local path = vim.fn.tempname() .. ".lua"
        local file = io.open(path, "w")
        file:write("on disk\n")
        file:close()

        local buf = vim.fn.bufadd(path)
        vim.fn.bufload(buf)
        vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "modified in memory" })

        local lines = tools.GetUriLines(buf, vim.uri_from_fname(path), { 0 })
        vim.fn.delete(path)
        return lines[0]
    ]])
    h.eq("modified in memory", result)
end

T["GetUriLines"]["normalizes CRLF line endings"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        local path = vim.fn.tempname() .. ".lua"
        local file = io.open(path, "wb")
        file:write("local a = 1\r\nlocal b = 2\r\n")
        file:close()

        local buf = vim.fn.bufadd(path)
        local lines = tools.GetUriLines(buf, vim.uri_from_fname(path), { 1 })
        local out = {
            line = lines[1],
            has_cr = lines[1] and lines[1]:find("\r") ~= nil,
        }
        vim.fn.delete(path)
        return out
    ]])
    h.eq("local b = 2", result.line)
    h.eq(false, result.has_cr)
end

T["GetUriLines"]["invalid buffer falls back to disk read"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        local path = vim.fn.tempname() .. ".lua"
        local file = io.open(path, "w")
        file:write("first\nsecond\n")
        file:close()

        local lines = tools.GetUriLines(99999, vim.uri_from_fname(path), { 1 })
        vim.fn.delete(path)
        return lines[1]
    ]])
    h.eq("second", result)
end

T["GetUriLines"]["missing file returns empty result"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        local path = vim.fn.tempname() .. "_missing.lua"
        local lines =
            tools.GetUriLines(99999, vim.uri_from_fname(path), { 0, 1 })
        return { count = vim.tbl_count(lines) }
    ]])
    h.eq(0, result.count)
end

T["GetUriLines"]["dedupes and filters invalid rows"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        local path = vim.fn.tempname() .. ".lua"
        local file = io.open(path, "w")
        file:write("a\nb\nc\n")
        file:close()

        local buf = vim.fn.bufadd(path)
        local lines = tools.GetUriLines(
            buf,
            vim.uri_from_fname(path),
            { 1, 1, -5, "bad", 100 }
        )
        local out = {
            line1 = lines[1],
            count = vim.tbl_count(lines),
        }
        vim.fn.delete(path)
        return out
    ]])
    h.eq("b", result.line1)
    -- 行 100 超出文件末尾、-5/"bad" 非法，只应得到行 1
    h.eq(1, result.count)
end

T["detect_filetype"]["caches results consistently"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        local first = tools.detect_filetype("/tmp/cache_probe.lua")
        local second = tools.detect_filetype("/tmp/cache_probe.lua")
        local unknown_first = tools.detect_filetype("/tmp/x.someunknownext")
        local unknown_second = tools.detect_filetype("/tmp/x.someunknownext")
        return {
            first = first,
            second = second,
            unknown_first = unknown_first,
            unknown_second = unknown_second,
        }
    ]])
    h.eq("lua", result.first)
    h.eq(result.first, result.second)
    -- 空结果也要被缓存且保持一致
    h.eq(result.unknown_first, result.unknown_second)
end

T["GetUriLines"]["handles empty rows array"] = function()
    local result = child.lua([[
        local tools = require("LspUI.layer.tools")
        local buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {"line1", "line2"})
        local uri = vim.uri_from_bufnr(buf)
        return #tools.GetUriLines(buf, uri, {})
    ]])
    h.eq(0, result)
end

return T
