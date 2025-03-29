local api, lsp = vim.api, vim.lsp
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
    if true then
        return
    end
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
    if true then
        return
    end
    if not is_initialized then
        lib_notify.Info("call_hierarchy has been deinit")
        return
    end

    is_initialized = false

    command.unregister_command(command_key)
end

--- @param _ "incoming"|"outgoing"
M.run = function(_)
    if true then
        return
    end
    if not config.options.call_hierarchy.enable then
        return
    end

    -- TODO:the run logic

    -- get current buffer id
    local current_buffer = api.nvim_get_current_buf()

    -- get current buffer's clients
    local clients = util.get_clients(current_buffer)

    if not clients then
        lib_notify.Warn("no client supports call_hierarchy!")
        return
    end
    local params = lsp.util.make_position_params(0, clients[1].offset_encoding)

    for _, client in pairs(clients) do
        client:request(
            lsp.protocol.Methods.textDocument_prepareCallHierarchy,
            params,
            function(_, _, _, _) end,
            current_buffer
        )
    end
end

return M
