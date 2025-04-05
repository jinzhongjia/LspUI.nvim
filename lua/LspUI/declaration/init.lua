local api = vim.api
local command = require("LspUI.command")
local config = require("LspUI.config")
local lib_notify = require("LspUI.lib.notify")
local pos_abstract = require("LspUI.pos_abstract")
local util = require("LspUI.declaration.util")

local M = {}

-- whether this module is initialized
local is_initialized = false

local command_key = "declaration"

M.init = function()
    if not config.options.declaration.enable then
        return
    end

    if is_initialized then
        return
    end

    is_initialized = true

    if config.options.declaration.command_enable then
        command.register_command(command_key, M.run, {})
    end
end

M.deinit = function()
    if not is_initialized then
        lib_notify.Info("declaration has been deinit")
        return
    end

    is_initialized = false

    command.unregister_command(command_key)
end

--- @param callback fun(Lsp_position_wrap?)?
M.run = function(callback)
    if not config.options.declaration.enable then
        lib_notify.Info("declaration is not enabled!")
        return
    end
    -- get current buffer
    local current_buffer = api.nvim_get_current_buf()

    local window = nil
    local params

    local clients = util.get_clients(current_buffer)

    if clients == nil then
        if callback then
            callback()
        else
            lib_notify.Warn("no client supports declaration!")
        end
        return
    end

    if pos_abstract.is_secondary_buffer(current_buffer) then
        if
            pos_abstract.get_current_method().name
            == pos_abstract.method.declaration.name
        then
            return
        end
        local current_item = pos_abstract.get_current_item()

        current_buffer = vim.uri_to_bufnr(current_item.uri)

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
        window = api.nvim_get_current_win()
        params = util.make_params(window, clients[1].offset_encoding)
    end

    pos_abstract.go(
        pos_abstract.method.declaration,
        current_buffer,
        window,
        params,
        callback
    )
end

return M
