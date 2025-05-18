local api = vim.api
local command = require("LspUI.command")
local config = require("LspUI.config")
local interface = require("LspUI.interface")
local layer = require("LspUI.layer")
local util = require("LspUI.implementation.util")

local lib_notify = layer.notify
local LspLayer = layer.lsp

local M = {}

-- Whether this module is initialized
local is_initialized = false
local command_key = "implementation"

-- Initialize the module
M.init = function()
    if not config.options.implementation.enable or is_initialized then
        return
    end

    is_initialized = true

    if config.options.implementation.command_enable then
        command.register_command(command_key, M.run, {})
    end
end

-- De-initialize the module
M.deinit = function()
    if not is_initialized then
        lib_notify.Info("Implementation module has been deinitialized")
        return
    end

    is_initialized = false
    command.unregister_command(command_key)
end

--- @param callback fun(LspUIPositionWrap?)?
M.run = function(callback)
    if not config.options.implementation.enable then
        lib_notify.Info("Implementation feature is not enabled!")
        return
    end

    -- Get current buffer and client information
    local current_buffer = api.nvim_get_current_buf()
    local clients = util.get_clients(current_buffer)

    if not clients or #clients < 1 then
        if callback then
            callback()
        else
            lib_notify.Warn("No client supports implementation!")
        end
        return
    end

    -- Get request parameters
    local params
    -- Get position information from current window
    params =
        util.make_params(api.nvim_get_current_win(), clients[1].offset_encoding)

    -- Call interface to execute implementation lookup
    interface.go("implementation", current_buffer, params)
end

return M
