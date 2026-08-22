local lib_notify = require("LspUI.layer.notify")

local default_transparency = 0

--- @type LspUI_rename_config
local default_rename_config = {
    enable = true,
    command_enable = true,
    auto_select = true,
    fixed_width = false,
    width = 30,
    key_binding = {
        exec = "<CR>",
        quit = "<ESC>",
    },
    transparency = default_transparency,
    border = "rounded",
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
    border = "rounded",
}

--- @type LspUI_diagnostic_config
local default_diagnostic_config = {
    enable = true,
    command_enable = true,
    transparency = default_transparency,
    border = "rounded",
    severity = nil, -- nil means all severities
    show_source = true,
    show_code = true,
    show_related_info = true,
    max_width = 0.6, -- 60% of screen width
}

--- @type LspUI_hover_config
local default_hover_config = {
    enable = true,
    command_enable = true,
    key_binding = {
        prev = "p",
        next = "n",
        quit = "q",
        open_url = "gx",
    },
    transparency = default_transparency,
    border = "rounded",
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

--- @type LspUI_jump_history_config
local default_jump_history_config = {
    enable = true, -- 是否启用跳转历史功能
    max_size = 50, -- 最大历史记录数量
    command_enable = true, -- 是否启用 :LspUI history 命令
    win_max_height = 20, -- 跳转历史窗口的最大高度（行数）
    smart_jumplist = {
        min_distance = 5, -- 同文件跳转的最小行距（小于此距离不记录）
        cross_file_only = false, -- 是否只记录跨文件跳转
    },
}

--- @type LspUI_virtual_scroll_config
local default_virtual_scroll_config = {
    threshold = 500, -- 超过此数量的项目启用虚拟滚动
    chunk_size = 200, -- 每次渲染的文件数
    load_more_threshold = 50, -- 距离底部多少行时触发加载
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
        toggle_fold = "<Cr>",
        next_entry = "J",
        prev_entry = "K",
        quit = "q",
        hide_main = "<leader>h",
        fold_all = "w",
        expand_all = "e",
        enter = "<leader>l",
    },
    transparency = default_transparency,
    main_border = "none",
    secondary_border = "single",
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
    main_border = "none",
    secondary_border = "single",
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
    jump_history = default_jump_history_config,
    virtual_scroll = default_virtual_scroll_config,
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

return M
