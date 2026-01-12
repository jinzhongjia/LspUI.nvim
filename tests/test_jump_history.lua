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

T["jump_history module"] = new_set()

T["jump_history module"]["init does nothing when disabled"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ jump_history = { enable = false } })
        
        local jump_history = require("LspUI.jump_history")
        jump_history.init()
        
        local command = require("LspUI.command")
        command.init()
        
        local completions = vim.fn.getcompletion("LspUI history", "cmdline")
        
        return {
            has_history = vim.tbl_contains(completions, "history"),
        }
    ]])
    h.eq(false, result.has_history)
end

T["jump_history module"]["init registers command when enabled"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ jump_history = { enable = true, command_enable = true } })
        
        local command = require("LspUI.command")
        command.init()
        
        local jump_history = require("LspUI.jump_history")
        jump_history.init()
        
        local completions = vim.fn.getcompletion("LspUI hist", "cmdline")
        
        return {
            has_history = vim.tbl_contains(completions, "history"),
        }
    ]])
    h.eq(true, result.has_history)
end

T["jump_history module"]["run warns when disabled"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ jump_history = { enable = false } })
        
        local jump_history = require("LspUI.jump_history")
        
        local notifications = {}
        local original_notify = vim.notify
        vim.notify = function(msg, level)
            table.insert(notifications, { msg = msg, level = level })
        end
        
        jump_history.run()
        
        vim.notify = original_notify
        
        return {
            has_notification = #notifications > 0,
        }
    ]])
    h.eq(true, result.has_notification)
end

T["jump_history module"]["run function exists"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ jump_history = { enable = true } })
        
        local jump_history = require("LspUI.jump_history")
        jump_history.init()
        
        return type(jump_history.run)
    ]])
    h.eq("function", result)
end

T["jump_history config"] = new_set()

T["jump_history config"]["respects max_size setting"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ jump_history = { max_size = 100 } })
        
        return config.options.jump_history.max_size
    ]])
    h.eq(100, result)
end

T["jump_history config"]["respects win_max_height setting"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ jump_history = { win_max_height = 30 } })
        
        return config.options.jump_history.win_max_height
    ]])
    h.eq(30, result)
end

T["jump_history config"]["respects smart_jumplist settings"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({
            jump_history = {
                smart_jumplist = {
                    min_distance = 10,
                    cross_file_only = true,
                }
            }
        })
        
        return config.options.jump_history.smart_jumplist
    ]])
    h.eq(10, result.min_distance)
    h.eq(true, result.cross_file_only)
end

T["jump_history config"]["default values are correct"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        
        return {
            enable = config.options.jump_history.enable,
            max_size = config.options.jump_history.max_size,
            command_enable = config.options.jump_history.command_enable,
            win_max_height = config.options.jump_history.win_max_height,
            min_distance = config.options.jump_history.smart_jumplist.min_distance,
            cross_file_only = config.options.jump_history.smart_jumplist.cross_file_only,
        }
    ]])
    h.eq(true, result.enable)
    h.eq(50, result.max_size)
    h.eq(true, result.command_enable)
    h.eq(20, result.win_max_height)
    h.eq(5, result.min_distance)
    h.eq(false, result.cross_file_only)
end

return T
