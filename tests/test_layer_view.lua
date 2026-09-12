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

T["ClassMainView"] = new_set()

T["ClassMainView"]["screen coverage"] = new_set({
    parametrize = {
        { 0, 3, false, 0, 19 },
        { 1, 2, false, 0, 18 },
        { 2, 0, false, 0, 18 },
        { 0, 1, false, 1, 20 },
        { 0, 1, true, 0, 19 },
        { 0, 3, false, 2, 19 },
    },
})

T["ClassMainView"]["screen coverage"]["covers the last editor row"] = function(
    cmdheight,
    laststatus,
    split,
    showtabline,
    bottom
)
    child.lua(
        [[
        local cmdheight, laststatus, split, showtabline = ...
        vim.o.lines, vim.o.columns = 20, 60
        vim.o.cmdheight, vim.o.laststatus = cmdheight, laststatus
        vim.o.showtabline = showtabline
        vim.o.statusline = 'STATUS'
        vim.api.nvim_buf_set_lines(0, 0, -1, false,
            vim.fn['repeat']({string.rep('B', 60)}, 1000))
        if split then vim.cmd('vsplit') end
        local view = require('LspUI.layer.main_view'):New(true):Border('none')
        vim.api.nvim_buf_set_lines(view:GetBufID(), 0, -1, false,
            vim.fn['repeat']({string.rep('P', 60)}, 1000))
        view:Render():Option('wrap', false)
    ]],
        { cmdheight, laststatus, split, showtabline }
    )

    local screen = child.get_screenshot().text
    h.eq(string.rep("P", 60), table.concat(screen[bottom]))
    if laststatus >= 2 or (laststatus == 1 and split) then
        h.eq("STATUS", table.concat(screen[bottom + 1]):sub(1, 6))
    end
end

T["ClassMainView"]["border stays above statusline after resizing"] = function()
    child.lua([[
        vim.o.lines, vim.o.columns = 20, 60
        vim.o.cmdheight, vim.o.laststatus = 0, 3
        vim.o.statusline = 'STATUS'
        preview = require('LspUI.layer.main_view'):New(true):Border('rounded')
        preview:Render()
    ]])
    local screen = child.get_screenshot().text
    h.eq("╰", screen[19][1])
    h.eq("╯", screen[19][60])
    h.eq("STATUS", table.concat(screen[20]):sub(1, 6))

    child.lua([[
        vim.o.lines, vim.o.columns = 16, 50
        preview:Resize()
    ]])
    screen = child.get_screenshot().text
    h.eq("╰", screen[15][1])
    h.eq("╯", screen[15][50])
    h.eq("STATUS", table.concat(screen[16]):sub(1, 6))
end

return T
