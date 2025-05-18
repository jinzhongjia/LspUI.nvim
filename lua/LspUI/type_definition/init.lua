local api = vim.api
local command = require("LspUI.command")
local config = require("LspUI.config")
local interface = require("LspUI.interface")
local layer = require("LspUI.layer")
local util = require("LspUI.type_definition.util")

local lib_notify = layer.notify
local LspLayer = layer.lsp

local M = {}

-- Whether this module is initialized
local is_initialized = false
local command_key = "type_definition"

-- Initialize the module
M.init = function()
    if not config.options.type_definition.enable or is_initialized then
        return
    end

    is_initialized = true

    if config.options.type_definition.command_enable then
        command.register_command(command_key, M.run, {})
    end
end

--- @param callback fun(LspUIPositionWrap?)?
M.run = function(callback)
    if not config.options.type_definition.enable then
        lib_notify.Info("Type Definition feature is not enabled!")
        return
    end

    -- Get current buffer and client information
    local current_buffer = api.nvim_get_current_buf()
    local clients = util.get_clients(current_buffer)

    if not clients or #clients < 1 then
        if callback then
            callback()
        else
            lib_notify.Warn("No client supports type definition!")
        end
        return
    end

    -- Get request parameters
    local params
    -- Get position information from current window
    params =
        util.make_params(api.nvim_get_current_win(), clients[1].offset_encoding)

    -- Call interface to execute type definition lookup
    interface.go(
        layer.ClassLsp.methods.type_definition.name,
        current_buffer,
        params
    )
end

return M
