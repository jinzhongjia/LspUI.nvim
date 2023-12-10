local api = vim.api
local command = require("LspUI.command")
local config = require("LspUI.config")
local lib_notify = require("LspUI.lib.notify")
local pos_abstract = require("LspUI.pos_abstract")
local util = require("LspUI.type_definition.util")

local M = {}

-- whether this module is initialized
local is_initialized = false

local command_key = "type_definition"

M.init = function()
    if not config.options.type_definition.enable then
        return
    end

    if is_initialized then
        return
    end

    is_initialized = true

    if config.options.type_definition.command_enable then
        command.register_command(command_key, M.run, {})
    end
end

M.deinit = function()
    if not is_initialized then
        lib_notify.Info("type_definition has been deinit")
        return
    end

    is_initialized = false

    command.unregister_command(command_key)
end

M.run = function()
    if not config.options.type_definition.enable then
        lib_notify.Info("type_definition is not enabled!")
        return
    end
    -- get current buffer
    local current_buffer = api.nvim_get_current_buf()

    local clients

    local window = nil
    local params

    if pos_abstract.is_secondary_buffer(current_buffer) then
        if
            pos_abstract.get_current_method().name
            == pos_abstract.method.type_definition.name
        then
            return
        end
        local current_item = pos_abstract.get_current_item()

        current_buffer = vim.uri_to_bufnr(current_item.uri)

        clients = util.get_clients(current_buffer)

        if clients == nil then
            lib_notify.Warn("no client supports type_definition!")
            return
        end

        if current_item.range then
            --- @type lsp.TextDocumentPositionParams
            params = {
                textDocument = {
                    uri = current_item.uri,
                },
                position = {
                    line = current_item.range.start.line,
                    character = current_item.range.start.character,
                },
            }
        else
            return
        end
    else
        clients = util.get_clients(current_buffer)

        if clients == nil then
            lib_notify.Warn("no client supports type_definition!")
            return
        end

        window = api.nvim_get_current_win()
        params = util.make_params(window)
    end

    pos_abstract.go(
        pos_abstract.method.type_definition,
        current_buffer,
        window,
        clients,
        params
    )
end

return M
