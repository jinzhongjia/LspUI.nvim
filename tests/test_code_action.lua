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

T["code_action module"] = new_set()

T["code_action module"]["init does nothing when disabled"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ code_action = { enable = false } })
        
        local code_action = require("LspUI.code_action")
        code_action.init()
        
        local command = require("LspUI.command")
        command.init()
        
        local notifications = {}
        local original_notify = vim.notify
        vim.notify = function(msg, level)
            table.insert(notifications, msg)
        end
        
        vim.cmd("LspUI code_action")
        
        vim.notify = original_notify
        
        return {
            has_unknown_warning = #notifications > 0 and notifications[1]:find("Unknown") ~= nil,
        }
    ]])
    h.eq(true, result.has_unknown_warning)
end

T["code_action module"]["init registers command when enabled"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ code_action = { enable = true, command_enable = true } })
        
        local command = require("LspUI.command")
        command.init()
        
        local code_action = require("LspUI.code_action")
        code_action.init()
        
        local completions = vim.fn.getcompletion("LspUI code", "cmdline")
        
        return {
            has_code_action = vim.tbl_contains(completions, "code_action"),
        }
    ]])
    h.eq(true, result.has_code_action)
end

T["code_action module"]["run warns when no client available"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ code_action = { enable = true } })
        
        local code_action = require("LspUI.code_action")
        code_action.init()
        
        local notifications = {}
        local original_notify = vim.notify
        vim.notify = function(msg, level)
            table.insert(notifications, { msg = msg, level = level })
        end
        
        code_action.run()
        
        vim.notify = original_notify
        
        return {
            has_notification = #notifications > 0,
            is_warning = notifications[1] and notifications[1].level == vim.log.levels.WARN,
            mentions_client = notifications[1] and notifications[1].msg:find("client") ~= nil,
        }
    ]])
    h.eq(true, result.has_notification)
    h.eq(true, result.is_warning)
    h.eq(true, result.mentions_client)
end

T["code_action module"]["run warns when disabled"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ code_action = { enable = false } })
        
        local code_action = require("LspUI.code_action")
        
        local notifications = {}
        local original_notify = vim.notify
        vim.notify = function(msg, level)
            table.insert(notifications, { msg = msg, level = level })
        end
        
        code_action.run()
        
        vim.notify = original_notify
        
        return {
            has_notification = #notifications > 0,
            mentions_not_enabled = notifications[1] and notifications[1].msg:find("not enabled") ~= nil,
        }
    ]])
    h.eq(true, result.has_notification)
    h.eq(true, result.mentions_not_enabled)
end

T["code_action module"]["deinit unregisters command"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ code_action = { enable = true, command_enable = true } })
        
        local command = require("LspUI.command")
        command.init()
        
        local code_action = require("LspUI.code_action")
        code_action.init()
        
        local before = vim.fn.getcompletion("LspUI code", "cmdline")
        local had_command = vim.tbl_contains(before, "code_action")
        
        code_action.deinit()
        
        local after = vim.fn.getcompletion("LspUI code", "cmdline")
        local has_command = vim.tbl_contains(after, "code_action")
        
        return {
            had_command = had_command,
            has_command_after = has_command,
        }
    ]])
    h.eq(true, result.had_command)
    h.eq(false, result.has_command_after)
end

T["code_action module"]["double init is idempotent"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ code_action = { enable = true, command_enable = true } })
        
        local command = require("LspUI.command")
        command.init()
        
        local code_action = require("LspUI.code_action")
        code_action.init()
        code_action.init()
        
        local completions = vim.fn.getcompletion("LspUI ", "cmdline")
        local code_action_count = 0
        for _, c in ipairs(completions) do
            if c == "code_action" then
                code_action_count = code_action_count + 1
            end
        end
        
        return {
            count = code_action_count,
        }
    ]])
    h.eq(1, result.count)
end

T["code_action util"] = new_set()

T["code_action util"]["render shows info when no actions"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        
        local util = require("LspUI.code_action.util")
        
        local notifications = {}
        local original_notify = vim.notify
        vim.notify = function(msg, level)
            table.insert(notifications, { msg = msg, level = level })
        end
        
        util.render({})
        
        vim.notify = original_notify
        
        return {
            has_notification = #notifications > 0,
            mentions_no_action = notifications[1] and notifications[1].msg:find("no code action") ~= nil,
        }
    ]])
    h.eq(true, result.has_notification)
    h.eq(true, result.mentions_no_action)
end

return T
