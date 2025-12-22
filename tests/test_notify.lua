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

T["Error"] = new_set()

T["Error"]["calls vim.notify with error level"] = function()
    local result = child.lua([[
        local notifications = {}
        local original_notify = vim.notify
        vim.notify = function(msg, level)
            table.insert(notifications, { msg = msg, level = level })
        end
        
        local notify = require("LspUI.layer.notify")
        notify.Error("test error message")
        
        vim.notify = original_notify
        return {
            msg = notifications[1].msg,
            level = notifications[1].level,
            expected_level = vim.log.levels.ERROR
        }
    ]])
    h.expect_match("[LspUI]:", result.msg)
    h.expect_match("test error message", result.msg)
    h.eq(result.expected_level, result.level)
end

T["Info"] = new_set()

T["Info"]["calls vim.notify with info level"] = function()
    local result = child.lua([[
        local notifications = {}
        local original_notify = vim.notify
        vim.notify = function(msg, level)
            table.insert(notifications, { msg = msg, level = level })
        end
        
        local notify = require("LspUI.layer.notify")
        notify.Info("test info message")
        
        vim.notify = original_notify
        return {
            msg = notifications[1].msg,
            level = notifications[1].level,
            expected_level = vim.log.levels.INFO
        }
    ]])
    h.expect_match("[LspUI]:", result.msg)
    h.expect_match("test info message", result.msg)
    h.eq(result.expected_level, result.level)
end

T["Warn"] = new_set()

T["Warn"]["calls vim.notify with warn level"] = function()
    local result = child.lua([[
        local notifications = {}
        local original_notify = vim.notify
        vim.notify = function(msg, level)
            table.insert(notifications, { msg = msg, level = level })
        end
        
        local notify = require("LspUI.layer.notify")
        notify.Warn("test warning message")
        
        vim.notify = original_notify
        return {
            msg = notifications[1].msg,
            level = notifications[1].level,
            expected_level = vim.log.levels.WARN
        }
    ]])
    h.expect_match("[LspUI]:", result.msg)
    h.expect_match("test warning message", result.msg)
    h.eq(result.expected_level, result.level)
end

return T
