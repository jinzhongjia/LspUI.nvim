local command = require("LspUI.command")
local config = require("LspUI.config")
local notify = require("LspUI.layer.notify")
local util = require("LspUI.diagnostic.util")

local M = {}

-- whether this module has initialized
local is_initialized = false

local command_key = "diagnostic"

-- 检查模块是否启用
local function is_enabled()
    return config.options.diagnostic.enable
end

--- Run diagnostic command
--- @param arg "next"|"prev"|"show"|nil
M.run = function(arg)
    if not is_enabled() then
        return
    end

    -- Default to "show" if no argument provided
    if arg == nil or arg == "" then
        arg = "show"
    end

    -- Validate argument
    if type(arg) ~= "string" then
        notify.Warn(
            string.format("diagnostic: invalid argument type: %s", type(arg))
        )
        return
    end

    if arg == "next" then
        util.render("next")
    elseif arg == "prev" then
        util.render("prev")
    elseif arg == "show" then
        util.show()
    else
        notify.Warn(
            string.format("diagnostic: unknown action '%s'. Use: next, prev, or show", arg)
        )
    end
end

-- init for diagnostic
function M.init()
    if not is_enabled() or is_initialized then
        return
    end

    is_initialized = true

    if config.options.diagnostic.command_enable then
        command.register_command(command_key, M.run, { "next", "prev", "show" })
    end
end

return M
