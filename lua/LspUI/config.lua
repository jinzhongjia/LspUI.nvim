local global = require("LspUI.global")
local lib_notify = require("LspUI.lib.notify")

--- @type LspUI_rename_config
local default_rename_config = {
    enable = true,
    command_enable = true,
    auto_select = true,
    key_binding = {
        exec = "<CR>",
        quit = "<ESC>",
    },
}

--- @type LspUI_lightbulb_config
local default_lightbulb_config = {
    enable = true,
    -- whether cache code action, if do, code action will use lightbulb's cache
    is_cached = true,
    icon = "💡",
}

--- @type LspUI_code_action_config
local default_code_action_config = {
    enable = true,
    command_enable = true,
    key_binding = {
        exec = "<cr>",
        prev = "k",
        next = "j",
        quit = "q",
    },
}

--- @type LspUI_diagnostic_config
local default_diagnostic_config = {
    enable = true,
    command_enable = true,
}

--- @type LspUI_hover_config
local default_hover_config = {
    enable = true,
    command_enable = true,
    key_binding = {
        prev = "p",
        next = "n",
        quit = "q",
    },
}

--- @type LspUI_definition_config
local default_definition_config = {
    enable = true,
    command_enable = true,
}

-- default config
--- @type LspUI_config
local default_config = {
    rename = default_rename_config,
    lightbulb = default_lightbulb_config,
    code_action = default_code_action_config,
    diagnostic = default_diagnostic_config,
    hover = default_hover_config,
    definition = default_definition_config,
}

-- Prevent plugins from being initialized multiple times
local is_already_init = false

local M = {}

-- LspUI plugin init function
-- you need to pass a table
--- @param config LspUI_config?
M.setup = function(config)
    -- check plugin whether has initialized
    if is_already_init then
        -- TODO:whether retain this
        lib_notify.Warn("you have already initialized the plugin config!")
        return
    end

    config = config or {}
    M.options = vim.tbl_deep_extend("force", default_config, config)
    is_already_init = true
end

-- separate function for `rename` module
--- @param rename_config LspUI_rename_config
M.rename_setup = function(rename_config)
    M.options.rename = vim.tbl_deep_extend("force", default_rename_config, rename_config)
end

-- separate function for `lightbulb` module
-- now this function can't use
--- @param lightbulb_config LspUI_lightbulb_config
M.lightbulb_setup = function(lightbulb_config)
    M.options.lightbulb = vim.tbl_deep_extend("force", default_lightbulb_config, lightbulb_config)
    vim.fn.sign_define(global.lightbulb.sign_name, { text = M.options.lightbulb.icon })
end

-- separate function for `code_action` module
--- @param code_action_config LspUI_code_action_config
M.code_action_setup = function(code_action_config)
    M.options.code_action = vim.tbl_deep_extend("force", default_code_action_config, code_action_config)
end

-- separate function for `diagnostic` module
--- @param diagnostic_config LspUI_diagnostic_config
M.diagnostic_setup = function(diagnostic_config)
    M.options.diagnostic = vim.tbl_deep_extend("force", default_diagnostic_config, diagnostic_config)
end

-- separate function for `hover` module
--- @param hover_config LspUI_hover_config
M.hover_setup = function(hover_config)
    M.options.hover = vim.tbl_deep_extend("force", default_hover_config, hover_config)
end

return M
