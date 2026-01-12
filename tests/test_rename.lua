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

T["rename module"] = new_set()

T["rename module"]["init does nothing when disabled"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ rename = { enable = false } })
        
        local rename = require("LspUI.rename")
        rename.init()
        
        local command = require("LspUI.command")
        command.init()
        
        local completions = vim.fn.getcompletion("LspUI rename", "cmdline")
        
        return {
            has_rename = vim.tbl_contains(completions, "rename"),
        }
    ]])
    h.eq(false, result.has_rename)
end

T["rename module"]["init registers command when enabled"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ rename = { enable = true, command_enable = true } })
        
        local command = require("LspUI.command")
        command.init()
        
        local rename = require("LspUI.rename")
        rename.init()
        
        local completions = vim.fn.getcompletion("LspUI re", "cmdline")
        
        return {
            has_rename = vim.tbl_contains(completions, "rename"),
        }
    ]])
    h.eq(true, result.has_rename)
end

T["rename module"]["run warns when disabled"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ rename = { enable = false } })
        
        local rename = require("LspUI.rename")
        
        local notifications = {}
        local original_notify = vim.notify
        vim.notify = function(msg, level)
            table.insert(notifications, { msg = msg, level = level })
        end
        
        rename.run()
        
        vim.notify = original_notify
        
        return {
            has_notification = #notifications > 0,
            mentions_not_enabled = notifications[1] and notifications[1].msg:find("not enabled") ~= nil,
        }
    ]])
    h.eq(true, result.has_notification)
    h.eq(true, result.mentions_not_enabled)
end

T["rename module"]["run warns when no client available"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ rename = { enable = true } })
        
        local rename = require("LspUI.rename")
        rename.init()
        
        local notifications = {}
        local original_notify = vim.notify
        vim.notify = function(msg, level)
            table.insert(notifications, { msg = msg, level = level })
        end
        
        rename.run()
        
        vim.notify = original_notify
        
        return {
            has_notification = #notifications > 0,
            mentions_client = notifications[1] and (
                notifications[1].msg:find("client") ~= nil or
                notifications[1].msg:find("No clients") ~= nil
            ),
        }
    ]])
    h.eq(true, result.has_notification)
    h.eq(true, result.mentions_client)
end

T["rename module"]["double init is idempotent"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ rename = { enable = true, command_enable = true } })
        
        local command = require("LspUI.command")
        command.init()
        
        local rename = require("LspUI.rename")
        rename.init()
        rename.init()
        
        local completions = vim.fn.getcompletion("LspUI ", "cmdline")
        local rename_count = 0
        for _, c in ipairs(completions) do
            if c == "rename" then
                rename_count = rename_count + 1
            end
        end
        
        return {
            count = rename_count,
        }
    ]])
    h.eq(1, result.count)
end

T["rename util"] = new_set()

T["rename util"]["done validates buffer"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        
        local util = require("LspUI.rename.util")
        
        local notifications = {}
        local original_notify = vim.notify
        vim.notify = function(msg, level)
            table.insert(notifications, { msg = msg, level = level })
        end
        
        util.done({}, 999999, 0, "test")
        
        vim.notify = original_notify
        
        return {
            has_notification = #notifications > 0,
            is_error = notifications[1] and notifications[1].level == vim.log.levels.ERROR,
        }
    ]])
    h.eq(true, result.has_notification)
    h.eq(true, result.is_error)
end

T["rename config"] = new_set()

T["rename config"]["respects auto_select setting"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ rename = { auto_select = false } })
        
        return config.options.rename.auto_select
    ]])
    h.eq(false, result)
end

T["rename config"]["respects fixed_width setting"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ rename = { fixed_width = true, width = 50 } })
        
        return {
            fixed_width = config.options.rename.fixed_width,
            width = config.options.rename.width,
        }
    ]])
    h.eq(true, result.fixed_width)
    h.eq(50, result.width)
end

T["rename config"]["respects custom key_binding"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({
            rename = {
                key_binding = {
                    exec = "<C-s>",
                    quit = "<C-c>",
                }
            }
        })
        
        return config.options.rename.key_binding
    ]])
    h.eq("<C-s>", result.exec)
    h.eq("<C-c>", result.quit)
end

return T
