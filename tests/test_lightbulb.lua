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

T["lightbulb module"] = new_set()

T["lightbulb module"]["init does nothing when disabled"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ lightbulb = { enable = false } })
        
        local lightbulb = require("LspUI.lightbulb")
        lightbulb.init()
        
        local signs = vim.fn.sign_getdefined("LspUI_lightbulb")
        
        return {
            sign_count = #signs,
        }
    ]])
    h.eq(0, result.sign_count)
end

T["lightbulb module"]["run shows info message"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ lightbulb = { enable = true } })
        
        local lightbulb = require("LspUI.lightbulb")
        
        local notifications = {}
        local original_notify = vim.notify
        vim.notify = function(msg, level)
            table.insert(notifications, { msg = msg, level = level })
        end
        
        lightbulb.run()
        
        vim.notify = original_notify
        
        return {
            has_notification = #notifications > 0,
            is_info = notifications[1] and notifications[1].level == vim.log.levels.INFO,
        }
    ]])
    h.eq(true, result.has_notification)
    h.eq(true, result.is_info)
end

T["lightbulb module"]["double init is idempotent"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ lightbulb = { enable = true } })
        
        local lightbulb = require("LspUI.lightbulb")
        lightbulb.init()
        
        vim.wait(50)
        
        lightbulb.init()
        
        return true
    ]])
    h.eq(true, result)
end

T["lightbulb util"] = new_set()

T["lightbulb util"]["get_clients returns nil when no clients"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        
        local util = require("LspUI.lightbulb.util")
        local clients = util.get_clients(vim.api.nvim_get_current_buf())
        
        return clients == nil
    ]])
    h.eq(true, result)
end

T["lightbulb util"]["render handles invalid buffer"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        
        local util = require("LspUI.lightbulb.util")
        local sign_id = util.render(999999, 1)
        
        return sign_id == nil
    ]])
    h.eq(true, result)
end

T["lightbulb util"]["clear_render handles buffer parameter"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        
        local util = require("LspUI.lightbulb.util")
        local buf = vim.api.nvim_get_current_buf()
        
        local ok = pcall(util.clear_render, buf)
        
        return ok
    ]])
    h.eq(true, result)
end

T["lightbulb util"]["clear_render without buffer clears all"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        
        local util = require("LspUI.lightbulb.util")
        
        local ok = pcall(util.clear_render)
        
        return ok
    ]])
    h.eq(true, result)
end

T["lightbulb util"]["register_sign and unregister_sign work"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        
        local util = require("LspUI.lightbulb.util")
        local global = require("LspUI.global")
        
        util.register_sign()
        local after_register = vim.fn.sign_getdefined(global.lightbulb.sign_name)
        
        util.unregister_sign()
        local after_unregister = vim.fn.sign_getdefined(global.lightbulb.sign_name)
        
        return {
            registered_count = #after_register,
            unregistered_count = #after_unregister,
        }
    ]])
    h.eq(1, result.registered_count)
    h.eq(0, result.unregistered_count)
end

T["lightbulb config"] = new_set()

T["lightbulb config"]["respects custom icon"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ lightbulb = { icon = "!" } })
        
        return config.options.lightbulb.icon
    ]])
    h.eq("!", result)
end

T["lightbulb config"]["respects debounce setting"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ lightbulb = { debounce = 500 } })
        
        return config.options.lightbulb.debounce
    ]])
    h.eq(500, result)
end

T["lightbulb config"]["respects is_cached setting"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ lightbulb = { is_cached = false } })
        
        return config.options.lightbulb.is_cached
    ]])
    h.eq(false, result)
end

return T
