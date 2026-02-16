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

T["controller"] = new_set()

T["controller"]["onCursorMoved short-circuits unchanged selection"] =
    function()
        local result = child.lua([[
            local ClassController = require("LspUI.layer.controller")

            local ctl = setmetatable({}, ClassController)
            local range = {
                start = { line = 1, character = 2 },
                finish = { line = 1, character = 4 },
            }

            ctl._current_item = {
                uri = "file:///tmp/a.lua",
                buffer_id = 1,
                range = vim.deepcopy(range),
                is_file_header = false,
            }

            local heavy_calls = 0
            local load_more_calls = 0

            ctl._getLspPositionByLnum = function()
                return "file:///tmp/a.lua", range
            end

            ctl._checkAndLoadMore = function()
                load_more_calls = load_more_calls + 1
            end

            ctl._mainView = {
                Valid = function() return true end,
                UnPinBuffer = function() heavy_calls = heavy_calls + 1 end,
                GetBufID = function() return 1 end,
                RestoreKeyMappings = function() heavy_calls = heavy_calls + 1 end,
                SwitchBuffer = function() heavy_calls = heavy_calls + 1 end,
                SaveKeyMappings = function() heavy_calls = heavy_calls + 1 end,
                PinBuffer = function() heavy_calls = heavy_calls + 1 end,
                GetWinID = function() heavy_calls = heavy_calls + 1; return nil end,
                SetHighlight = function() heavy_calls = heavy_calls + 1 end,
            }

            ctl._lsp = {
                GetData = function()
                    return { ["file:///tmp/a.lua"] = { buffer_id = 1 } }
                end,
            }

            ctl._virtual_scroll = { enabled = true }

            ctl:_onCursorMoved()

            return {
                heavy_calls = heavy_calls,
                load_more_calls = load_more_calls,
                uri_unchanged = ctl._current_item.uri == "file:///tmp/a.lua",
                range_unchanged = ctl._current_item.range.start.line == 1,
            }
        ]])

        h.eq(0, result.heavy_calls)
        h.eq(1, result.load_more_calls)
        h.eq(true, result.uri_unchanged)
        h.eq(true, result.range_unchanged)
    end

T["controller"]["onCursorMoved still updates when selection changes"] =
    function()
        local result = child.lua([[
            local ClassController = require("LspUI.layer.controller")

            local ctl = setmetatable({}, ClassController)
            local old_range = {
                start = { line = 1, character = 2 },
                finish = { line = 1, character = 4 },
            }
            local new_range = {
                start = { line = 2, character = 0 },
                finish = { line = 2, character = 3 },
            }

            ctl._current_item = {
                uri = "file:///tmp/a.lua",
                buffer_id = 1,
                range = old_range,
                is_file_header = false,
            }

            local heavy_calls = 0
            ctl._getLspPositionByLnum = function()
                return "file:///tmp/a.lua", new_range
            end
            ctl._setupMainViewKeyBindings = function()
                heavy_calls = heavy_calls + 1
            end

            ctl._mainView = {
                Valid = function() return true end,
                UnPinBuffer = function() heavy_calls = heavy_calls + 1 end,
                GetBufID = function() return 1 end,
                RestoreKeyMappings = function() heavy_calls = heavy_calls + 1 end,
                SwitchBuffer = function() heavy_calls = heavy_calls + 1 end,
                SaveKeyMappings = function() heavy_calls = heavy_calls + 1 end,
                PinBuffer = function() heavy_calls = heavy_calls + 1 end,
                GetWinID = function() return nil end,
                SetHighlight = function() heavy_calls = heavy_calls + 1 end,
            }

            ctl._lsp = {
                GetData = function()
                    return { ["file:///tmp/a.lua"] = { buffer_id = 1 } }
                end,
            }

            ctl._virtual_scroll = { enabled = false }

            ctl:_onCursorMoved()

            return {
                heavy_calls = heavy_calls,
                new_line = ctl._current_item.range.start.line,
            }
        ]])

        h.eq(true, result.heavy_calls > 0)
        h.eq(2, result.new_line)
    end

return T
