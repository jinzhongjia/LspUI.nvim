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

T["api module"] = new_set()

T["api module"]["exports all expected functions"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        local api = require("LspUI.api")
        return {
            has_code_action = type(api.code_action) == "function",
            has_rename = type(api.rename) == "function",
            has_diagnostic = type(api.diagnostic) == "function",
            has_hover = type(api.hover) == "function",
            has_definition = type(api.definition) == "function",
            has_type_definition = type(api.type_definition) == "function",
            has_declaration = type(api.declaration) == "function",
            has_reference = type(api.reference) == "function",
            has_implementation = type(api.implementation) == "function",
            has_inlay_hint = type(api.inlay_hint) == "function",
            has_call_hierarchy = type(api.call_hierarchy) == "function",
            has_signature = type(api.signature) == "function",
            has_jump_history = type(api.jump_history) == "function",
        }
    ]])
    h.eq(true, result.has_code_action)
    h.eq(true, result.has_rename)
    h.eq(true, result.has_diagnostic)
    h.eq(true, result.has_hover)
    h.eq(true, result.has_definition)
    h.eq(true, result.has_type_definition)
    h.eq(true, result.has_declaration)
    h.eq(true, result.has_reference)
    h.eq(true, result.has_implementation)
    h.eq(true, result.has_inlay_hint)
    h.eq(true, result.has_call_hierarchy)
    h.eq(true, result.has_signature)
    h.eq(true, result.has_jump_history)
end

T["api module"]["api functions are callable"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        local api = require("LspUI.api")
        local results = {}
        
        -- Test that functions don't error when called (they may warn about no LSP)
        -- We capture any notifications to verify they work
        local notifications = {}
        local original_notify = vim.notify
        vim.notify = function(msg, level)
            table.insert(notifications, { msg = msg, level = level })
        end
        
        -- Try calling some api functions - they should handle no-LSP gracefully
        pcall(api.hover)
        pcall(api.rename)
        pcall(api.code_action)
        
        vim.notify = original_notify
        
        return {
            notification_count = #notifications,
            has_notifications = #notifications > 0,
        }
    ]])
    h.eq(true, result.has_notifications)
end

T["api module"]["returns table from require"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        local api = require("LspUI.api")
        return type(api)
    ]])
    h.eq("table", result)
end

T["api module"]["api is accessible via main module"] = function()
    local result = child.lua([[
        local LspUI = require("LspUI")
        LspUI.setup()
        return {
            has_api = LspUI.api ~= nil,
            api_is_table = type(LspUI.api) == "table",
        }
    ]])
    h.eq(true, result.has_api)
    h.eq(true, result.api_is_table)
end

return T
