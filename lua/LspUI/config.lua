local lib_notify = require("LspUI.lib.notify")

local default_transparency = 0

--- @type LspUI_rename_config
local default_rename_config = {
    enable = true,
    command_enable = true,
    auto_select = true,
    key_binding = {
        exec = "<CR>",
        quit = "<ESC>",
    },
    transparency = default_transparency,
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
    transparency = default_transparency,
}

--- @type LspUI_diagnostic_config
local default_diagnostic_config = {
    enable = true,
    command_enable = true,
    transparency = default_transparency,
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
    transparency = default_transparency,
}

--- @type LspUI_inlay_hint_config
local default_inlay_hint_config = {
    enable = true,
    command_enable = true,
    filter = {
        whitelist = {},
        blacklist = {},
    },
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
        jump_split = "sh",
        jump_vsplit = "sv",
        jump_tab = "t",
        quit = "q",
        hide_main = "<leader>h",
        fold_all = "w",
        expand_all = "e",
        enter = "<leader>l",
    },
    transparency = default_transparency,
}

-- Now, this is not available
-- TODO: replace pos_keybind_config with pos_config
--
--- @type LspUI_pos_config
local default_pos_config = {
    main_keybind = {
        back = "<leader>l",
        hide_secondary = "<leader>h",
    },
    secondary_keybind = {
        jump = "o",
        jump_split = "sh",
        jump_vsplit = "sv",
        jump_tab = "t",
        quit = "q",
        hide_main = "<leader>h",
        fold_all = "w",
        expand_all = "e",
        enter = "<leader>l",
    },
    transparency = default_transparency,
}

-- TODO: now, this is not avaiable
--
--- @type LspUI_call_hierarchy_config
local default_call_hierarchy_config = {
    enable = true,
    command_enable = true,
}

--- @type LspUI_signature
local default_signature_config = {
    enable = false,
    icon = "✨",
    color = {
        fg = "#FF8C00",
        bg = nil,
    },
    debounce = 300,
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
    call_hierarchy = default_call_hierarchy_config,
    signature = default_signature_config,
}

-- Prevent plugins from being initialized multiple times
local is_already_init = false

local M = {}

--- @type LspUI_config
M.options = {}

-- LspUI plugin init function
-- you need to pass a table
--- @param config LspUI_config?
M.setup = function(config)
    -- check plugin whether has initialized
    if is_already_init then
        vim.schedule(function()
            lib_notify.Warn("you have already initialized the plugin config!")
        end)
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

    local rename = require("LspUI.rename")

    if rename_config.enable then
        rename.init()
    else
        rename.deinit()
    end
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

    local code_action = require("LspUI.code_action")
    if code_action_config.enable then
        code_action.init()
    else
        code_action.deinit()
    end
end

-- separate function for `diagnostic` module
--- @param diagnostic_config LspUI_diagnostic_config
M.diagnostic_setup = function(diagnostic_config)
    M.options.diagnostic = vim.tbl_deep_extend(
        "force",
        M.options.diagnostic or default_diagnostic_config,
        diagnostic_config
    )

    local diagnostic = require("LspUI.diagnostic")

    if diagnostic_config.enable then
        diagnostic.init()
    else
        diagnostic.deinit()
    end
end

-- separate function for `hover` module
--- @param hover_config LspUI_hover_config
M.hover_setup = function(hover_config)
    M.options.hover = vim.tbl_deep_extend(
        "force",
        M.options.hover or default_hover_config,
        hover_config
    )

    local hover = require("LspUI.hover")

    if hover_config.enable then
        hover.init()
    else
        hover.deinit()
    end
end

-- separate function for `definition` module
--- @param definition_config LspUI_definition_config
M.definition_setup = function(definition_config)
    M.options.definition = vim.tbl_deep_extend(
        "force",
        M.options.definition or default_definition_config,
        definition_config
    )

    local definition = require("LspUI.definition")

    if definition_config.enable then
        definition.init()
    else
        definition.deinit()
    end
end

-- separate function for `type_definition` module
--- @param type_definition_config LspUI_type_definition_config
M.type_definition_setup = function(type_definition_config)
    M.options.type_definition = vim.tbl_deep_extend(
        "force",
        M.options.type_definition or default_type_definition_config,
        type_definition_config
    )

    local type_definition = require("LspUI.type_definition")

    if type_definition_config.enable then
        type_definition.init()
    else
        type_definition.deinit()
    end
end

-- separate function for `declaration` module
--- @param declaration_config LspUI_declaration_config
M.declaration_setup = function(declaration_config)
    M.options.declaration = vim.tbl_deep_extend(
        "force",
        M.options.declaration or default_declaration_config,
        declaration_config
    )

    local declaration = require("LspUI.declaration")

    if declaration.enable then
        declaration.init()
    else
        declaration.deinit()
    end
end

-- separate function for `reference` module
--- @param reference_config LspUI_reference_config
M.reference_setup = function(reference_config)
    M.options.reference = vim.tbl_deep_extend(
        "force",
        M.options.reference or default_reference_config,
        reference_config
    )

    local reference = require("LspUI.reference")

    if reference_config.enable then
        reference.init()
    else
        reference.deinit()
    end
end

-- separate function for `implementation` module
--- @param implementation_config LspUI_implementation_config
M.implementation_setup = function(implementation_config)
    M.options.implementation = vim.tbl_deep_extend(
        "force",
        M.options.implementation or default_implementation_config,
        implementation_config
    )

    local implementation = require("LspUI.implementation")

    if implementation_config.enable then
        implementation.init()
    else
        implementation.deinit()
    end
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

-- separate function for `signature` module
--- @param signature_config LspUI_signature
M.signature_setup = function(signature_config)
    M.options.signature = vim.tbl_deep_extend(
        "force",
        M.options.signature or default_signature_config,
        signature_config
    )

    local signature = require("LspUI.signature")

    if signature_config.enable then
        signature.init()
    else
        signature.deinit()
    end
end

-- TODO:add separate setup function for call_hierarchy

return M
