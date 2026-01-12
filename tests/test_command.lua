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

T["command module"] = new_set()

T["command module"]["init creates LspUI command"] = function()
    local result = child.lua([[
        local command = require("LspUI.command")
        command.init()
        
        -- Check if LspUI command exists
        local commands = vim.api.nvim_get_commands({})
        return commands["LspUI"] ~= nil
    ]])
    h.eq(true, result)
end

T["command module"]["register_command adds command to store"] = function()
    local result = child.lua([[
        local command = require("LspUI.command")
        command.init()
        
        local was_called = false
        command.register_command("test_cmd", function()
            was_called = true
        end, {})
        
        -- Execute the command
        vim.cmd("LspUI test_cmd")
        
        return was_called
    ]])
    h.eq(true, result)
end

T["command module"]["register_command with args"] = function()
    local result = child.lua([[
        local command = require("LspUI.command")
        command.init()
        
        local received_args = {}
        command.register_command("test_args", function(...)
            received_args = {...}
        end, { "arg1", "arg2" })
        
        -- Execute with arguments
        vim.cmd("LspUI test_args arg1")
        
        return {
            arg_count = #received_args,
            first_arg = received_args[1],
        }
    ]])
    h.eq(1, result.arg_count)
    h.eq("arg1", result.first_arg)
end

T["command module"]["unregister_command removes command"] = function()
    local result = child.lua([[
        local command = require("LspUI.command")
        command.init()
        
        local call_count = 0
        command.register_command("to_remove", function()
            call_count = call_count + 1
        end, {})
        
        -- Execute once
        vim.cmd("LspUI to_remove")
        local first_count = call_count
        
        -- Unregister
        command.unregister_command("to_remove")
        
        -- Try to execute again (should warn about unknown command)
        local notifications = {}
        local original_notify = vim.notify
        vim.notify = function(msg, level)
            table.insert(notifications, msg)
        end
        
        vim.cmd("LspUI to_remove")
        
        vim.notify = original_notify
        
        return {
            first_count = first_count,
            final_count = call_count,
            has_warning = #notifications > 0,
        }
    ]])
    h.eq(1, result.first_count)
    h.eq(1, result.final_count)
    h.eq(true, result.has_warning)
end

T["command module"]["unknown command shows warning"] = function()
    local result = child.lua([[
        local command = require("LspUI.command")
        command.init()
        
        local notifications = {}
        local original_notify = vim.notify
        vim.notify = function(msg, level)
            table.insert(notifications, { msg = msg, level = level })
        end
        
        vim.cmd("LspUI nonexistent_command")
        
        vim.notify = original_notify
        
        return {
            has_notification = #notifications > 0,
            contains_unknown = notifications[1] and notifications[1].msg:find("Unknown") ~= nil,
        }
    ]])
    h.eq(true, result.has_notification)
    h.eq(true, result.contains_unknown)
end

T["command module"]["no args shows version info"] = function()
    local result = child.lua([[
        local command = require("LspUI.command")
        command.init()
        
        local notifications = {}
        local original_notify = vim.notify
        vim.notify = function(msg, level)
            table.insert(notifications, { msg = msg, level = level })
        end
        
        vim.cmd("LspUI")
        
        vim.notify = original_notify
        
        return {
            has_notification = #notifications > 0,
            contains_version = notifications[1] and notifications[1].msg:find("version") ~= nil,
        }
    ]])
    h.eq(true, result.has_notification)
    h.eq(true, result.contains_version)
end

T["command module"]["command completion works"] = function()
    local result = child.lua([[
        local command = require("LspUI.command")
        command.init()
        
        -- Register some test commands
        command.register_command("hover", function() end, {})
        command.register_command("help", function() end, {})
        command.register_command("rename", function() end, {})
        
        -- Get completions for "h"
        local completions = vim.fn.getcompletion("LspUI h", "cmdline")
        
        return {
            count = #completions,
            has_hover = vim.tbl_contains(completions, "hover"),
            has_help = vim.tbl_contains(completions, "help"),
        }
    ]])
    h.eq(true, result.count >= 2)
    h.eq(true, result.has_hover)
    h.eq(true, result.has_help)
end

T["command module"]["subcommand args completion"] = function()
    local result = child.lua([[
        local command = require("LspUI.command")
        command.init()
        
        -- Register command with static args
        command.register_command("diagnostic", function() end, { "next", "prev" })
        
        -- Get completions for subcommand args
        local completions = vim.fn.getcompletion("LspUI diagnostic ", "cmdline")
        
        return {
            count = #completions,
            has_next = vim.tbl_contains(completions, "next"),
            has_prev = vim.tbl_contains(completions, "prev"),
        }
    ]])
    h.eq(2, result.count)
    h.eq(true, result.has_next)
    h.eq(true, result.has_prev)
end

T["command module"]["dynamic args completion"] = function()
    local result = child.lua([[
        local command = require("LspUI.command")
        command.init()
        
        -- Register command with dynamic args function
        command.register_command("dynamic", function() end, function(arg_lead)
            if arg_lead:find("^t") then
                return { "test1", "test2" }
            end
            return { "alpha", "beta" }
        end)
        
        -- Get completions without prefix
        local completions1 = vim.fn.getcompletion("LspUI dynamic ", "cmdline")
        
        -- Get completions with prefix
        local completions2 = vim.fn.getcompletion("LspUI dynamic t", "cmdline")
        
        return {
            default_count = #completions1,
            prefix_count = #completions2,
            has_alpha = vim.tbl_contains(completions1, "alpha"),
            has_test1 = vim.tbl_contains(completions2, "test1"),
        }
    ]])
    h.eq(2, result.default_count)
    h.eq(2, result.prefix_count)
    h.eq(true, result.has_alpha)
    h.eq(true, result.has_test1)
end

T["command module"]["command error handling"] = function()
    local result = child.lua([[
        local command = require("LspUI.command")
        command.init()
        
        -- Register command that throws error
        command.register_command("error_cmd", function()
            error("intentional error")
        end, {})
        
        local notifications = {}
        local original_notify = vim.notify
        vim.notify = function(msg, level)
            table.insert(notifications, { msg = msg, level = level })
        end
        
        -- Execute - should be caught and show error notification
        vim.cmd("LspUI error_cmd")
        
        vim.notify = original_notify
        
        return {
            has_notification = #notifications > 0,
            is_error = notifications[1] and notifications[1].level == vim.log.levels.ERROR,
            contains_failed = notifications[1] and notifications[1].msg:find("failed") ~= nil,
        }
    ]])
    h.eq(true, result.has_notification)
    h.eq(true, result.is_error)
    h.eq(true, result.contains_failed)
end

return T
