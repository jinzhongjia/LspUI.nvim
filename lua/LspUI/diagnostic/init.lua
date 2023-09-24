local command = require("LspUI.command")
local config = require("LspUI.config")
local lib_notify = require("LspUI.lib.notify")
local util = require("LspUI.diagnostic.util")
local M = {}

-- whether this module has initialized
local is_initialized = false

local command_key = "diagnostic"

-- init for diagnostic
M.init = function()
    if not config.options.diagnostic.enable then
        return
    end
    if is_initialized then
        return
    end

    is_initialized = true

    if config.options.diagnostic.command_enable then
        command.register_command(command_key, M.run, { "next", "prev" })
    end
end

M.deinit = function()
    if not is_initialized then
        lib_notify.Info("diagnostic has been deinit")
        return
    end

    is_initialized = false

    command.unregister_command(command_key)
end

--- @param arg "next"|"prev"
M.run = function(arg)
    if not config.options.diagnostic.enable then
        return
    end

    util.render(arg)
end

return M
