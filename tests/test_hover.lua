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

T["hover module"] = new_set()

T["hover module"]["init does nothing when disabled"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ hover = { enable = false } })
        
        local hover = require("LspUI.hover")
        hover.init()
        
        local command = require("LspUI.command")
        command.init()
        
        local completions = vim.fn.getcompletion("LspUI hover", "cmdline")
        
        return {
            has_hover = vim.tbl_contains(completions, "hover"),
        }
    ]])
    h.eq(false, result.has_hover)
end

T["hover module"]["init registers command when enabled"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ hover = { enable = true, command_enable = true } })
        
        local command = require("LspUI.command")
        command.init()
        
        local hover = require("LspUI.hover")
        hover.init()
        
        local completions = vim.fn.getcompletion("LspUI ho", "cmdline")
        
        return {
            has_hover = vim.tbl_contains(completions, "hover"),
        }
    ]])
    h.eq(true, result.has_hover)
end

T["hover module"]["run warns when disabled"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ hover = { enable = false } })
        
        local hover = require("LspUI.hover")
        
        local notifications = {}
        local original_notify = vim.notify
        vim.notify = function(msg, level)
            table.insert(notifications, { msg = msg, level = level })
        end
        
        hover.run()
        
        vim.notify = original_notify
        
        return {
            has_notification = #notifications > 0,
            mentions_not_enabled = notifications[1] and notifications[1].msg:find("not enabled") ~= nil,
        }
    ]])
    h.eq(true, result.has_notification)
    h.eq(true, result.mentions_not_enabled)
end

T["hover module"]["run warns when no client available"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ hover = { enable = true } })
        
        local hover = require("LspUI.hover")
        hover.init()
        
        local notifications = {}
        local original_notify = vim.notify
        vim.notify = function(msg, level)
            table.insert(notifications, { msg = msg, level = level })
        end
        
        hover.run()
        
        vim.notify = original_notify
        
        return {
            has_notification = #notifications > 0,
            mentions_client = notifications[1] and (
                notifications[1].msg:find("client") ~= nil or
                notifications[1].msg:find("hover") ~= nil
            ),
        }
    ]])
    h.eq(true, result.has_notification)
    h.eq(true, result.mentions_client)
end

T["hover module"]["deinit unregisters command"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ hover = { enable = true, command_enable = true } })
        
        local command = require("LspUI.command")
        command.init()
        
        local hover = require("LspUI.hover")
        hover.init()
        
        local before = vim.fn.getcompletion("LspUI ho", "cmdline")
        local had_command = vim.tbl_contains(before, "hover")
        
        hover.deinit()
        
        local after = vim.fn.getcompletion("LspUI ho", "cmdline")
        local has_command = vim.tbl_contains(after, "hover")
        
        return {
            had_command = had_command,
            has_command_after = has_command,
        }
    ]])
    h.eq(true, result.had_command)
    h.eq(false, result.has_command_after)
end

T["hover module"]["double init is idempotent"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ hover = { enable = true, command_enable = true } })
        
        local command = require("LspUI.command")
        command.init()
        
        local hover = require("LspUI.hover")
        hover.init()
        hover.init()
        
        local completions = vim.fn.getcompletion("LspUI ", "cmdline")
        local hover_count = 0
        for _, c in ipairs(completions) do
            if c == "hover" then
                hover_count = hover_count + 1
            end
        end
        
        return {
            count = hover_count,
        }
    ]])
    h.eq(1, result.count)
end

T["hover config"] = new_set()

T["hover config"]["respects custom key_binding"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({
            hover = {
                key_binding = {
                    prev = "P",
                    next = "N",
                    quit = "Q",
                }
            }
        })
        
        return config.options.hover.key_binding
    ]])
    h.eq("P", result.prev)
    h.eq("N", result.next)
    h.eq("Q", result.quit)
end

T["hover config"]["respects custom border"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ hover = { border = "single" } })
        
        return config.options.hover.border
    ]])
    h.eq("single", result)
end

T["hover config"]["respects transparency setting"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ hover = { transparency = 20 } })
        
        return config.options.hover.transparency
    ]])
    h.eq(20, result)
end

return T
