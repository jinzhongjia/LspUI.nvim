local command = require("LspUI.command")
local config = require("LspUI.config")
local util = require("LspUI.diagnostic.util")
local M = {}

-- whether this module has initialized
local is_initialized = false

local command_key = "diagnostic"

-- 检查模块是否启用
local function is_enabled()
    return config.options.diagnostic.enable
end

--- @param arg "next"|"prev"
M.run = function(arg)
    if not is_enabled() then
        return
    end

    util.render(arg)
end

-- init for diagnostic
M.init = function()
    if not is_enabled() or is_initialized then
        return
    end

    is_initialized = true

    if config.options.diagnostic.command_enable then
        command.register_command(command_key, M.run, { "next", "prev" })
    end
end

return M
