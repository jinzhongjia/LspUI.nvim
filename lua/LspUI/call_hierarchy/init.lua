local api, lsp = vim.api, vim.lsp
local command = require("LspUI.command")
local config = require("LspUI.config")
local interface = require("LspUI.interface")
local layer = require("LspUI.layer")
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

--- @param method "incoming"|"outgoing"
M.run = function(method)
    if not config.options.call_hierarchy.enable then
        return
    end

    -- get current buffer id
    local current_buffer = api.nvim_get_current_buf()

    -- get current buffer's clients
    local clients = util.get_clients(current_buffer)

    if not clients then
        lib_notify.Warn("no client supports call_hierarchy!")
        return
    end

    local params = lsp.util.make_position_params(0, clients[1].offset_encoding)

    local method_name = ""
    if method == "incoming" then
        method_name = layer.ClassLsp.methods.incoming_calls.name
    elseif method == "outgoing" then
        method_name = layer.ClassLsp.methods.outgoing_calls.name
    else
        lib_notify.Warn("invalid method name!")
        return
    end

    -- Call interface to execute declaration lookup
    interface.go(method_name, current_buffer, params)
end

return M
