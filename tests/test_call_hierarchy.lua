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

T["call_hierarchy module"] = new_set()

T["call_hierarchy module"]["init does nothing when disabled"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ call_hierarchy = { enable = false } })
        
        local call_hierarchy = require("LspUI.call_hierarchy")
        call_hierarchy.init()
        
        local command = require("LspUI.command")
        command.init()
        
        local completions = vim.fn.getcompletion("LspUI call", "cmdline")
        
        return {
            has_call_hierarchy = vim.tbl_contains(completions, "call_hierarchy"),
        }
    ]])
    h.eq(false, result.has_call_hierarchy)
end

T["call_hierarchy module"]["init registers command when enabled"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ call_hierarchy = { enable = true, command_enable = true } })
        
        local command = require("LspUI.command")
        command.init()
        
        local call_hierarchy = require("LspUI.call_hierarchy")
        call_hierarchy.init()
        
        local completions = vim.fn.getcompletion("LspUI call", "cmdline")
        
        return {
            has_call_hierarchy = vim.tbl_contains(completions, "call_hierarchy"),
        }
    ]])
    h.eq(true, result.has_call_hierarchy)
end

T["call_hierarchy module"]["command registers with args"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ call_hierarchy = { enable = true, command_enable = true } })
        
        local command = require("LspUI.command")
        command.init()
        
        local call_hierarchy = require("LspUI.call_hierarchy")
        call_hierarchy.init()
        
        local completions = vim.fn.getcompletion("LspUI call", "cmdline")
        
        return {
            has_call_hierarchy = vim.tbl_contains(completions, "call_hierarchy"),
        }
    ]])
    h.eq(true, result.has_call_hierarchy)
end

T["call_hierarchy module"]["run returns early when disabled"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ call_hierarchy = { enable = false } })
        
        local call_hierarchy = require("LspUI.call_hierarchy")
        
        local ok = pcall(call_hierarchy.run, "incoming")
        
        return {
            runs_without_error = ok,
        }
    ]])
    h.eq(true, result.runs_without_error)
end

T["call_hierarchy module"]["run accepts incoming and outgoing"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ call_hierarchy = { enable = true } })
        
        local call_hierarchy = require("LspUI.call_hierarchy")
        call_hierarchy.init()
        
        local ok_incoming = pcall(call_hierarchy.run, "incoming")
        local ok_outgoing = pcall(call_hierarchy.run, "outgoing")
        
        return {
            incoming_ok = ok_incoming,
            outgoing_ok = ok_outgoing,
        }
    ]])
    h.eq(true, result.incoming_ok)
    h.eq(true, result.outgoing_ok)
end

T["call_hierarchy config"] = new_set()

T["call_hierarchy config"]["enabled by default"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        
        return {
            enable = config.options.call_hierarchy.enable,
            command_enable = config.options.call_hierarchy.command_enable,
        }
    ]])
    h.eq(true, result.enable)
    h.eq(true, result.command_enable)
end

return T
