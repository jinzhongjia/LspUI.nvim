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

T["inlay_hint module"] = new_set()

T["inlay_hint module"]["init does nothing when disabled"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ inlay_hint = { enable = false } })
        
        local inlay_hint = require("LspUI.inlay_hint")
        inlay_hint.init()
        
        local command = require("LspUI.command")
        command.init()
        
        local completions = vim.fn.getcompletion("LspUI inlay", "cmdline")
        
        return {
            has_inlay_hint = vim.tbl_contains(completions, "inlay_hint"),
        }
    ]])
    h.eq(false, result.has_inlay_hint)
end

T["inlay_hint module"]["init registers command when enabled"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ inlay_hint = { enable = true, command_enable = true } })
        
        local command = require("LspUI.command")
        command.init()
        
        local inlay_hint = require("LspUI.inlay_hint")
        inlay_hint.init()
        
        local completions = vim.fn.getcompletion("LspUI inlay", "cmdline")
        
        return {
            has_inlay_hint = vim.tbl_contains(completions, "inlay_hint"),
        }
    ]])
    h.eq(true, result.has_inlay_hint)
end

T["inlay_hint module"]["run toggles state"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ inlay_hint = { enable = true } })
        
        local inlay_hint = require("LspUI.inlay_hint")
        inlay_hint.init()
        
        local ok1 = pcall(inlay_hint.run)
        local ok2 = pcall(inlay_hint.run)
        
        return {
            first_toggle_ok = ok1,
            second_toggle_ok = ok2,
        }
    ]])
    h.eq(true, result.first_toggle_ok)
    h.eq(true, result.second_toggle_ok)
end

T["inlay_hint module"]["deinit unregisters command"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ inlay_hint = { enable = true, command_enable = true } })
        
        local command = require("LspUI.command")
        command.init()
        
        local inlay_hint = require("LspUI.inlay_hint")
        inlay_hint.init()
        
        local before = vim.fn.getcompletion("LspUI inlay", "cmdline")
        local had_command = vim.tbl_contains(before, "inlay_hint")
        
        inlay_hint.deinit()
        
        local after = vim.fn.getcompletion("LspUI inlay", "cmdline")
        local has_command = vim.tbl_contains(after, "inlay_hint")
        
        return {
            had_command = had_command,
            has_command_after = has_command,
        }
    ]])
    h.eq(true, result.had_command)
    h.eq(false, result.has_command_after)
end

T["inlay_hint module"]["double init is idempotent"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({ inlay_hint = { enable = true, command_enable = true } })
        
        local command = require("LspUI.command")
        command.init()
        
        local inlay_hint = require("LspUI.inlay_hint")
        inlay_hint.init()
        inlay_hint.init()
        
        local completions = vim.fn.getcompletion("LspUI ", "cmdline")
        local inlay_hint_count = 0
        for _, c in ipairs(completions) do
            if c == "inlay_hint" then
                inlay_hint_count = inlay_hint_count + 1
            end
        end
        
        return {
            count = inlay_hint_count,
        }
    ]])
    h.eq(1, result.count)
end

T["inlay_hint config"] = new_set()

T["inlay_hint config"]["respects whitelist filter"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({
            inlay_hint = {
                filter = {
                    whitelist = { "lua", "rust" },
                }
            }
        })
        
        return config.options.inlay_hint.filter.whitelist
    ]])
    h.eq(2, #result)
    h.eq(true, vim.tbl_contains(result, "lua"))
    h.eq(true, vim.tbl_contains(result, "rust"))
end

T["inlay_hint config"]["respects blacklist filter"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({
            inlay_hint = {
                filter = {
                    blacklist = { "python" },
                }
            }
        })
        
        return config.options.inlay_hint.filter.blacklist
    ]])
    h.eq(1, #result)
    h.eq("python", result[1])
end

T["inlay_hint config"]["empty filters by default"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        
        return {
            whitelist = config.options.inlay_hint.filter.whitelist,
            blacklist = config.options.inlay_hint.filter.blacklist,
        }
    ]])
    h.eq(0, #result.whitelist)
    h.eq(0, #result.blacklist)
end

return T
