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
    debounce = 250,
}

--- @type LspUI_code_action_config
local default_code_action_config = {
    enable = true,
    command_enable = true,
    gitsigns = true,
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

--- @type LspUI_inlay_hint_config
local default_inlay_hint_config = {
    enable = true,
}

--- @type LspUI_definition_config
local default_definition_config = {
    enable = true,
    command_enable = true,
}

--- @type LspUI_type_definition_config
local default_type_definition_config = {
    enable = true,
    command_enable = true,
}

--- @type LspUI_declaration_config
local default_declaration_config = {
    enable = true,
    command_enable = true,
}

--- @type LspUI_implementation_config
local default_implementation_config = {
    enable = true,
    command_enable = true,
}

--- @type LspUI_reference_config
local default_reference_config = {
    enable = true,
    command_enable = true,
}

--- @type LspUI_pos_keybind_config
local default_pos_keybind_config = {
    main = {
        back = "<leader>l",
        hide_secondary = "<leader>h",
    },
    secondary = {
        jump = "o",
        quit = "q",
        hide_main = "<leader>h",
        enter = "<leader>l",
    },
}

-- default config
--- @type LspUI_config
local default_config = {
    rename = default_rename_config,
    lightbulb = default_lightbulb_config,
    code_action = default_code_action_config,
    diagnostic = default_diagnostic_config,
    hover = default_hover_config,
    inlay_hint = default_inlay_hint_config,
    definition = default_definition_config,
    type_definition = default_type_definition_config,
    declaration = default_declaration_config,
    implementation = default_implementation_config,
    reference = default_reference_config,
    pos_keybind = default_pos_keybind_config,
}

-- Prevent plugins from being initialized multiple times
local is_already_init = false

local M = {}

M.options = {}

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
    M.options.rename = vim.tbl_deep_extend(
        "force",
        M.options.rename or default_rename_config,
        rename_config
    )
end

-- separate function for `lightbulb` module
-- now this function can't use
--- @param lightbulb_config LspUI_lightbulb_config
M.lightbulb_setup = function(lightbulb_config)
    M.options.lightbulb = vim.tbl_deep_extend(
        "force",
        M.options.lightbulb or default_lightbulb_config,
        lightbulb_config
    )

    local lightbulb = require("LspUI.lightbulb")

    if M.options.lightbulb.enable then
        lightbulb.init()
    else
        lightbulb.deinit()
    end
end

-- separate function for `code_action` module
--- @param code_action_config LspUI_code_action_config
M.code_action_setup = function(code_action_config)
    M.options.code_action = vim.tbl_deep_extend(
        "force",
        M.options.code_action or default_code_action_config,
        code_action_config
    )
end

-- separate function for `diagnostic` module
--- @param diagnostic_config LspUI_diagnostic_config
M.diagnostic_setup = function(diagnostic_config)
    M.options.diagnostic = vim.tbl_deep_extend(
        "force",
        M.options.diagnostic or default_diagnostic_config,
        diagnostic_config
    )
end

-- separate function for `hover` module
--- @param hover_config LspUI_hover_config
M.hover_setup = function(hover_config)
    M.options.hover = vim.tbl_deep_extend(
        "force",
        M.options.hover or default_hover_config,
        hover_config
    )
end

-- separate function for `definition` module
--- @param definition_config LspUI_definition_config
M.definition_setup = function(definition_config)
    M.options.definition = vim.tbl_deep_extend(
        "force",
        M.options.definition or default_definition_config,
        definition_config
    )
end

-- separate function for `type_definition` module
--- @param type_definition_config LspUI_type_definition_config
M.type_definition_setup = function(type_definition_config)
    M.options.type_definition = vim.tbl_deep_extend(
        "force",
        M.options.type_definition or default_type_definition_config,
        type_definition_config
    )
end

-- separate function for `declaration` module
--- @param declaration_config LspUI_declaration_config
M.declaration_setup = function(declaration_config)
    M.options.declaration = vim.tbl_deep_extend(
        "force",
        M.options.declaration or default_declaration_config,
        declaration_config
    )
end

-- separate function for `reference` module
--- @param reference_config LspUI_reference_config
M.reference_setup = function(reference_config)
    M.options.reference = vim.tbl_deep_extend(
        "force",
        M.options.reference or default_reference_config,
        reference_config
    )
end

-- separate function for `implementation` module
--- @param implementation_config LspUI_implementation_config
M.implementation_setup = function(implementation_config)
    M.options.implementation = vim.tbl_deep_extend(
        "force",
        M.options.implementation or default_implementation_config,
        implementation_config
    )
end

-- separate function for `pos_keybind` module
--- @param pos_keybind_config LspUI_pos_keybind_config
M.pos_keybind_setup = function(pos_keybind_config)
    M.options.pos_keybind = vim.tbl_deep_extend(
        "force",
        M.options.pos_keybind or default_pos_keybind_config,
        pos_keybind_config
    )
end

-- separate function for `inlay_hint` module
--- @param inlay_hint_config LspUI_inlay_hint_config
M.inlay_hint_setup = function(inlay_hint_config)
    M.options.inlay_hint = vim.tbl_deep_extend(
        "force",
        M.options.inlay_hint or default_inlay_hint_config,
        inlay_hint_config
    )

    local inlay_hint = require("LspUI.inlay_hint")

    if inlay_hint_config.enable then
        inlay_hint.init()
    else
        inlay_hint.deinit()
    end
end

return M
