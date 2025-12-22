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

T["setup"] = new_set()

T["setup"]["accepts empty config"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({})
        return config.options ~= nil
    ]])
    h.eq(true, result)
end

T["setup"]["uses default values when no config provided"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        return {
            rename_enable = config.options.rename.enable,
            lightbulb_enable = config.options.lightbulb.enable,
            code_action_enable = config.options.code_action.enable,
            hover_enable = config.options.hover.enable,
        }
    ]])
    h.eq(true, result.rename_enable)
    h.eq(true, result.lightbulb_enable)
    h.eq(true, result.code_action_enable)
    h.eq(true, result.hover_enable)
end

T["setup"]["merges user config with defaults"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup({
            rename = { enable = false },
            hover = { border = "single" },
        })
        return {
            rename_enable = config.options.rename.enable,
            rename_auto_select = config.options.rename.auto_select,
            hover_border = config.options.hover.border,
            hover_enable = config.options.hover.enable,
        }
    ]])
    h.eq(false, result.rename_enable)
    h.eq(true, result.rename_auto_select)
    h.eq("single", result.hover_border)
    h.eq(true, result.hover_enable)
end

T["rename config"] = new_set()

T["rename config"]["has correct default values"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        return {
            enable = config.options.rename.enable,
            command_enable = config.options.rename.command_enable,
            auto_select = config.options.rename.auto_select,
            fixed_width = config.options.rename.fixed_width,
            width = config.options.rename.width,
            border = config.options.rename.border,
        }
    ]])
    h.eq(true, result.enable)
    h.eq(true, result.command_enable)
    h.eq(true, result.auto_select)
    h.eq(false, result.fixed_width)
    h.eq(30, result.width)
    h.eq("rounded", result.border)
end

T["rename config"]["key_binding has correct defaults"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        return config.options.rename.key_binding
    ]])
    h.eq("<CR>", result.exec)
    h.eq("<ESC>", result.quit)
end

T["lightbulb config"] = new_set()

T["lightbulb config"]["has correct default values"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        return {
            enable = config.options.lightbulb.enable,
            is_cached = config.options.lightbulb.is_cached,
            icon = config.options.lightbulb.icon,
            debounce = config.options.lightbulb.debounce,
        }
    ]])
    h.eq(true, result.enable)
    h.eq(true, result.is_cached)
    h.eq(250, result.debounce)
end

T["code_action config"] = new_set()

T["code_action config"]["has correct default values"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        return {
            enable = config.options.code_action.enable,
            command_enable = config.options.code_action.command_enable,
            gitsigns = config.options.code_action.gitsigns,
            border = config.options.code_action.border,
        }
    ]])
    h.eq(true, result.enable)
    h.eq(true, result.command_enable)
    h.eq(true, result.gitsigns)
    h.eq("rounded", result.border)
end

T["code_action config"]["key_binding has correct defaults"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        return config.options.code_action.key_binding
    ]])
    h.eq("<cr>", result.exec)
    h.eq("k", result.prev)
    h.eq("j", result.next)
    h.eq("q", result.quit)
end

T["diagnostic config"] = new_set()

T["diagnostic config"]["has correct default values"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        return {
            enable = config.options.diagnostic.enable,
            command_enable = config.options.diagnostic.command_enable,
            border = config.options.diagnostic.border,
            show_source = config.options.diagnostic.show_source,
            show_code = config.options.diagnostic.show_code,
            show_related_info = config.options.diagnostic.show_related_info,
            max_width = config.options.diagnostic.max_width,
        }
    ]])
    h.eq(true, result.enable)
    h.eq(true, result.command_enable)
    h.eq("rounded", result.border)
    h.eq(true, result.show_source)
    h.eq(true, result.show_code)
    h.eq(true, result.show_related_info)
    h.eq(0.6, result.max_width)
end

T["hover config"] = new_set()

T["hover config"]["has correct default values"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        return {
            enable = config.options.hover.enable,
            command_enable = config.options.hover.command_enable,
            border = config.options.hover.border,
        }
    ]])
    h.eq(true, result.enable)
    h.eq(true, result.command_enable)
    h.eq("rounded", result.border)
end

T["hover config"]["key_binding has correct defaults"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        return config.options.hover.key_binding
    ]])
    h.eq("p", result.prev)
    h.eq("n", result.next)
    h.eq("q", result.quit)
end

T["inlay_hint config"] = new_set()

T["inlay_hint config"]["has correct default values"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        return {
            enable = config.options.inlay_hint.enable,
            command_enable = config.options.inlay_hint.command_enable,
            filter_whitelist = config.options.inlay_hint.filter.whitelist,
            filter_blacklist = config.options.inlay_hint.filter.blacklist,
        }
    ]])
    h.eq(true, result.enable)
    h.eq(true, result.command_enable)
    h.eq({}, result.filter_whitelist)
    h.eq({}, result.filter_blacklist)
end

T["jump_history config"] = new_set()

T["jump_history config"]["has correct default values"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        return {
            enable = config.options.jump_history.enable,
            max_size = config.options.jump_history.max_size,
            command_enable = config.options.jump_history.command_enable,
            win_max_height = config.options.jump_history.win_max_height,
        }
    ]])
    h.eq(true, result.enable)
    h.eq(50, result.max_size)
    h.eq(true, result.command_enable)
    h.eq(20, result.win_max_height)
end

T["jump_history config"]["smart_jumplist has correct defaults"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        return config.options.jump_history.smart_jumplist
    ]])
    h.eq(5, result.min_distance)
    h.eq(false, result.cross_file_only)
end

T["signature config"] = new_set()

T["signature config"]["is disabled by default"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        return {
            enable = config.options.signature.enable,
            debounce = config.options.signature.debounce,
        }
    ]])
    h.eq(false, result.enable)
    h.eq(300, result.debounce)
end

T["navigation configs"] = new_set()

T["navigation configs"]["definition has correct defaults"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        return config.options.definition
    ]])
    h.eq(true, result.enable)
    h.eq(true, result.command_enable)
end

T["navigation configs"]["type_definition has correct defaults"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        return config.options.type_definition
    ]])
    h.eq(true, result.enable)
    h.eq(true, result.command_enable)
end

T["navigation configs"]["declaration has correct defaults"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        return config.options.declaration
    ]])
    h.eq(true, result.enable)
    h.eq(true, result.command_enable)
end

T["navigation configs"]["implementation has correct defaults"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        return config.options.implementation
    ]])
    h.eq(true, result.enable)
    h.eq(true, result.command_enable)
end

T["navigation configs"]["reference has correct defaults"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        return config.options.reference
    ]])
    h.eq(true, result.enable)
    h.eq(true, result.command_enable)
end

T["pos_keybind config"] = new_set()

T["pos_keybind config"]["main keybindings have correct defaults"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        return config.options.pos_keybind.main
    ]])
    h.eq("<leader>l", result.back)
    h.eq("<leader>h", result.hide_secondary)
end

T["pos_keybind config"]["secondary keybindings have correct defaults"] = function()
    local result = child.lua([[
        local config = require("LspUI.config")
        config.setup()
        return config.options.pos_keybind.secondary
    ]])
    h.eq("o", result.jump)
    h.eq("sh", result.jump_split)
    h.eq("sv", result.jump_vsplit)
    h.eq("t", result.jump_tab)
    h.eq("<Cr>", result.toggle_fold)
    h.eq("J", result.next_entry)
    h.eq("K", result.prev_entry)
    h.eq("q", result.quit)
end

return T
