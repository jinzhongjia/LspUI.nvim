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

T["ClassView"] = new_set()

T["ClassView"]["New creates instance"] = function()
    local result = child.lua([[
        local ClassView = require("LspUI.layer.view")
        local view = ClassView:New(true)
        
        return {
            is_table = type(view) == "table",
            has_render = type(view.Render) == "function",
            has_destroy = type(view.Destroy) == "function",
        }
    ]])
    h.eq(true, result.is_table)
    h.eq(true, result.has_render)
    h.eq(true, result.has_destroy)
end

T["ClassView"]["chain methods return self"] = function()
    local result = child.lua([[
        local ClassView = require("LspUI.layer.view")
        local view = ClassView:New(true)
        
        local after_size = view:Size(10, 5)
        local after_pos = view:Pos(1, 1)
        local after_anchor = view:Anchor("NW")
        
        return {
            size_returns_self = after_size == view,
            pos_returns_self = after_pos == view,
            anchor_returns_self = after_anchor == view,
        }
    ]])
    h.eq(true, result.size_returns_self)
    h.eq(true, result.pos_returns_self)
    h.eq(true, result.anchor_returns_self)
end

T["ClassView"]["BufContent sets buffer content"] = function()
    local result = child.lua([[
        local ClassView = require("LspUI.layer.view")
        local view = ClassView:New(true)
        
        view:BufContent(0, -1, {"line1", "line2", "line3"})
        
        local buf_id = view:GetBufID()
        local lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
        
        return {
            line_count = #lines,
            first_line = lines[1],
            last_line = lines[3],
        }
    ]])
    h.eq(3, result.line_count)
    h.eq("line1", result.first_line)
    h.eq("line3", result.last_line)
end

T["ClassView"]["BufOption sets buffer option"] = function()
    local result = child.lua([[
        local ClassView = require("LspUI.layer.view")
        local view = ClassView:New(true)
        
        view:BufOption("buftype", "nofile")
        
        local buf_id = view:GetBufID()
        local buftype = vim.api.nvim_get_option_value("buftype", { buf = buf_id })
        
        return buftype
    ]])
    h.eq("nofile", result)
end

T["ClassView"]["Render creates window"] = function()
    local result = child.lua([[
        local ClassView = require("LspUI.layer.view")
        local view = ClassView:New(true)
            :Size(20, 5)
            :Pos(1, 1)
            :Anchor("NW")
            :Relative("cursor")
            :Style("minimal")
            :Border("rounded")
            :Render()
        
        local win_id = view:GetWinID()
        
        return {
            has_win_id = win_id ~= nil,
            win_is_valid = win_id and vim.api.nvim_win_is_valid(win_id),
        }
    ]])
    h.eq(true, result.has_win_id)
    h.eq(true, result.win_is_valid)
end

T["ClassView"]["Destroy closes window"] = function()
    local result = child.lua([[
        local ClassView = require("LspUI.layer.view")
        local view = ClassView:New(true)
            :Size(20, 5)
            :Pos(1, 1)
            :Anchor("NW")
            :Relative("cursor")
            :Style("minimal")
            :Render()
        
        local win_id = view:GetWinID()
        
        view:Destroy()
        
        return {
            win_valid_after = vim.api.nvim_win_is_valid(win_id),
        }
    ]])
    h.eq(false, result.win_valid_after)
end

T["ClassView"]["Valid returns correct state"] = function()
    local result = child.lua([[
        local ClassView = require("LspUI.layer.view")
        local view = ClassView:New(true)
            :Size(20, 5)
            :Pos(1, 1)
            :Anchor("NW")
            :Relative("cursor")
            :Style("minimal")
            :Render()
        
        local valid_before = view:Valid()
        
        view:Destroy()
        
        local valid_after = view:Valid()
        
        return {
            valid_before = valid_before,
            valid_after = valid_after,
        }
    ]])
    h.eq(true, result.valid_before)
    h.eq(false, result.valid_after)
end

T["ClassView"]["Title sets window title"] = function()
    local result = child.lua([[
        local ClassView = require("LspUI.layer.view")
        local view = ClassView:New(true)
            :Size(20, 5)
            :Pos(1, 1)
            :Anchor("NW")
            :Relative("cursor")
            :Style("minimal")
            :Border("rounded")
            :Title("Test Title", "center")
            :Render()
        
        local win_id = view:GetWinID()
        local config = vim.api.nvim_win_get_config(win_id)
        
        view:Destroy()
        
        return {
            has_title = config.title ~= nil,
        }
    ]])
    h.eq(true, result.has_title)
end

T["ClassView"]["KeyMap sets keybinding"] = function()
    local result = child.lua([[
        local ClassView = require("LspUI.layer.view")
        local view = ClassView:New(true)
            :Size(20, 5)
            :Pos(1, 1)
            :Anchor("NW")
            :Relative("cursor")
            :Style("minimal")
            :Render()
        
        local was_called = false
        view:KeyMap("n", "q", function()
            was_called = true
        end, "test keymap")
        
        local buf_id = view:GetBufID()
        local keymaps = vim.api.nvim_buf_get_keymap(buf_id, "n")
        
        local has_q_map = false
        for _, map in ipairs(keymaps) do
            if map.lhs == "q" then
                has_q_map = true
                break
            end
        end
        
        view:Destroy()
        
        return {
            has_keymap = has_q_map,
        }
    ]])
    h.eq(true, result.has_keymap)
end

T["ClassView"]["Focusable controls focus behavior"] = function()
    local result = child.lua([[
        local ClassView = require("LspUI.layer.view")
        
        local view1 = ClassView:New(true)
            :Size(20, 5)
            :Pos(1, 1)
            :Anchor("NW")
            :Relative("cursor")
            :Style("minimal")
            :Focusable(true)
            :Render()
        
        local win1 = view1:GetWinID()
        local config1 = vim.api.nvim_win_get_config(win1)
        
        view1:Destroy()
        
        local view2 = ClassView:New(true)
            :Size(20, 5)
            :Pos(1, 1)
            :Anchor("NW")
            :Relative("cursor")
            :Style("minimal")
            :Focusable(false)
            :Render()
        
        local win2 = view2:GetWinID()
        local config2 = vim.api.nvim_win_get_config(win2)
        
        view2:Destroy()
        
        return {
            focusable_true = config1.focusable,
            focusable_false = config2.focusable,
        }
    ]])
    h.eq(true, result.focusable_true)
    h.eq(false, result.focusable_false)
end

T["ClassView"]["Enter controls initial focus"] = function()
    local result = child.lua([[
        local ClassView = require("LspUI.layer.view")
        
        local original_win = vim.api.nvim_get_current_win()
        
        local view = ClassView:New(true)
            :Size(20, 5)
            :Pos(1, 1)
            :Anchor("NW")
            :Relative("cursor")
            :Style("minimal")
            :Focusable(true)
            :Enter(true)
            :Render()
        
        local current_win = vim.api.nvim_get_current_win()
        local view_win = view:GetWinID()
        
        view:Destroy()
        
        return {
            entered_view = current_win == view_win,
        }
    ]])
    h.eq(true, result.entered_view)
end

return T
