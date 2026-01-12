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

T["diagnostic module"] = new_set()

T["diagnostic module"]["init does nothing when disabled"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ diagnostic = { enable = false } })
        
        local diagnostic = require("LspUI.diagnostic")
        diagnostic.init()
        
        local command = require("LspUI.command")
        command.init()
        
        local completions = vim.fn.getcompletion("LspUI diagnostic", "cmdline")
        
        return {
            has_diagnostic = vim.tbl_contains(completions, "diagnostic"),
        }
    ]])
    h.eq(false, result.has_diagnostic)
end

T["diagnostic module"]["init registers command when enabled"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ diagnostic = { enable = true, command_enable = true } })
        
        local command = require("LspUI.command")
        command.init()
        
        local diagnostic = require("LspUI.diagnostic")
        diagnostic.init()
        
        local completions = vim.fn.getcompletion("LspUI diag", "cmdline")
        
        return {
            has_diagnostic = vim.tbl_contains(completions, "diagnostic"),
        }
    ]])
    h.eq(true, result.has_diagnostic)
end

T["diagnostic module"]["run returns early when disabled"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ diagnostic = { enable = false } })
        
        local diagnostic = require("LspUI.diagnostic")
        
        local ok = pcall(diagnostic.run, "next")
        
        return {
            runs_without_error = ok,
        }
    ]])
    h.eq(true, result.runs_without_error)
end

T["diagnostic module"]["run accepts next and prev args"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ diagnostic = { enable = true } })
        
        local diagnostic = require("LspUI.diagnostic")
        diagnostic.init()
        
        local ok_next = pcall(diagnostic.run, "next")
        local ok_prev = pcall(diagnostic.run, "prev")
        
        return {
            next_ok = ok_next,
            prev_ok = ok_prev,
        }
    ]])
    h.eq(true, result.next_ok)
    h.eq(true, result.prev_ok)
end

T["diagnostic module"]["command has next/prev completion"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ diagnostic = { enable = true, command_enable = true } })
        
        local command = require("LspUI.command")
        command.init()
        
        local diagnostic = require("LspUI.diagnostic")
        diagnostic.init()
        
        local completions = vim.fn.getcompletion("LspUI diagnostic ", "cmdline")
        
        return {
            has_next = vim.tbl_contains(completions, "next"),
            has_prev = vim.tbl_contains(completions, "prev"),
        }
    ]])
    h.eq(true, result.has_next)
    h.eq(true, result.has_prev)
end

T["diagnostic module"]["double init is idempotent"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ diagnostic = { enable = true, command_enable = true } })
        
        local command = require("LspUI.command")
        command.init()
        
        local diagnostic = require("LspUI.diagnostic")
        diagnostic.init()
        diagnostic.init()
        
        local completions = vim.fn.getcompletion("LspUI ", "cmdline")
        local diagnostic_count = 0
        for _, c in ipairs(completions) do
            if c == "diagnostic" then
                diagnostic_count = diagnostic_count + 1
            end
        end
        
        return {
            count = diagnostic_count,
        }
    ]])
    h.eq(1, result.count)
end

T["diagnostic config"] = new_set()

T["diagnostic config"]["respects show_source setting"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ diagnostic = { show_source = false } })
        
        return config.options.diagnostic.show_source
    ]])
    h.eq(false, result)
end

T["diagnostic config"]["respects show_code setting"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ diagnostic = { show_code = false } })
        
        return config.options.diagnostic.show_code
    ]])
    h.eq(false, result)
end

T["diagnostic config"]["respects show_related_info setting"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ diagnostic = { show_related_info = false } })
        
        return config.options.diagnostic.show_related_info
    ]])
    h.eq(false, result)
end

T["diagnostic config"]["respects max_width setting"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ diagnostic = { max_width = 0.8 } })
        
        return config.options.diagnostic.max_width
    ]])
    h.eq(0.8, result)
end

T["diagnostic config"]["respects severity setting"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ diagnostic = { severity = vim.diagnostic.severity.ERROR } })
        
        return config.options.diagnostic.severity
    ]])
    h.eq(1, result)
end

T["diagnostic config"]["respects custom border"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ diagnostic = { border = "double" } })
        
        return config.options.diagnostic.border
    ]])
    h.eq("double", result)
end

return T
