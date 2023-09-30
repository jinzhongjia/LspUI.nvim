local api = vim.api
local command = require("LspUI.command")
local config = require("LspUI.config")
local lib_notify = require("LspUI.lib.notify")
local util = require("LspUI.call_hierarchy.util")

local M = {}

-- whether this module is initialized
local is_initialized = false

local command_key = "call_hierarchy"

-- init for call_hierarchy
M.init = function()
    if not config.options.call_hierarchy.enable then
        return
    end

    if is_initialized then
        return
    end

    is_initialized = true

    if config.options.call_hierarchy.command_enable then
        command.register_command(command_key, M.run, { "incoming", "outgoing" })
    end
end

-- deinit for call_hierarchy
M.deinit = function()
    if not is_initialized then
        lib_notify.Info("call_hierarchy has been deinit")
        return
    end

    is_initialized = false

    command.unregister_command(command_key)
end

--- @param arg "incoming"|"outgoing"
M.run = function(arg)
    if not config.options.call_hierarchy.enable then
        return
    end

    -- TODO:the run logic
end

return M
