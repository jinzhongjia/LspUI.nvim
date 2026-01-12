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

T["definition module"] = new_set()

T["definition module"]["init does nothing when disabled"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ definition = { enable = false } })
        
        local definition = require("LspUI.definition")
        definition.init()
        
        local command = require("LspUI.command")
        command.init()
        
        local completions = vim.fn.getcompletion("LspUI definition", "cmdline")
        
        return {
            has_definition = vim.tbl_contains(completions, "definition"),
        }
    ]])
    h.eq(false, result.has_definition)
end

T["definition module"]["init registers command when enabled"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ definition = { enable = true, command_enable = true } })
        
        local command = require("LspUI.command")
        command.init()
        
        local definition = require("LspUI.definition")
        definition.init()
        
        local completions = vim.fn.getcompletion("LspUI def", "cmdline")
        
        return {
            has_definition = vim.tbl_contains(completions, "definition"),
        }
    ]])
    h.eq(true, result.has_definition)
end

T["definition module"]["run exists as function"] = function()
    local result = child.lua([[
        local definition = require("LspUI.definition")
        return type(definition.run)
    ]])
    h.eq("function", result)
end

T["type_definition module"] = new_set()

T["type_definition module"]["init registers command when enabled"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ type_definition = { enable = true, command_enable = true } })
        
        local command = require("LspUI.command")
        command.init()
        
        local type_definition = require("LspUI.type_definition")
        type_definition.init()
        
        local completions = vim.fn.getcompletion("LspUI type", "cmdline")
        
        return {
            has_type_definition = vim.tbl_contains(completions, "type_definition"),
        }
    ]])
    h.eq(true, result.has_type_definition)
end

T["declaration module"] = new_set()

T["declaration module"]["init registers command when enabled"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ declaration = { enable = true, command_enable = true } })
        
        local command = require("LspUI.command")
        command.init()
        
        local declaration = require("LspUI.declaration")
        declaration.init()
        
        local completions = vim.fn.getcompletion("LspUI dec", "cmdline")
        
        return {
            has_declaration = vim.tbl_contains(completions, "declaration"),
        }
    ]])
    h.eq(true, result.has_declaration)
end

T["reference module"] = new_set()

T["reference module"]["init registers command when enabled"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ reference = { enable = true, command_enable = true } })
        
        local command = require("LspUI.command")
        command.init()
        
        local reference = require("LspUI.reference")
        reference.init()
        
        local completions = vim.fn.getcompletion("LspUI ref", "cmdline")
        
        return {
            has_reference = vim.tbl_contains(completions, "reference"),
        }
    ]])
    h.eq(true, result.has_reference)
end

T["implementation module"] = new_set()

T["implementation module"]["init registers command when enabled"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ implementation = { enable = true, command_enable = true } })
        
        local command = require("LspUI.command")
        command.init()
        
        local implementation = require("LspUI.implementation")
        implementation.init()
        
        local completions = vim.fn.getcompletion("LspUI impl", "cmdline")
        
        return {
            has_implementation = vim.tbl_contains(completions, "implementation"),
        }
    ]])
    h.eq(true, result.has_implementation)
end

T["navigation configs"] = new_set()

T["navigation configs"]["all navigation modules enabled by default"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        
        return {
            definition = config.options.definition.enable,
            type_definition = config.options.type_definition.enable,
            declaration = config.options.declaration.enable,
            reference = config.options.reference.enable,
            implementation = config.options.implementation.enable,
        }
    ]])
    h.eq(true, result.definition)
    h.eq(true, result.type_definition)
    h.eq(true, result.declaration)
    h.eq(true, result.reference)
    h.eq(true, result.implementation)
end

T["navigation configs"]["all navigation commands enabled by default"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        
        return {
            definition = config.options.definition.command_enable,
            type_definition = config.options.type_definition.command_enable,
            declaration = config.options.declaration.command_enable,
            reference = config.options.reference.command_enable,
            implementation = config.options.implementation.command_enable,
        }
    ]])
    h.eq(true, result.definition)
    h.eq(true, result.type_definition)
    h.eq(true, result.declaration)
    h.eq(true, result.reference)
    h.eq(true, result.implementation)
end

return T
