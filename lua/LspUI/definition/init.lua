local api, lsp = vim.api, vim.lsp
local definition_feature = lsp.protocol.Methods.textDocument_definition
local command = require("LspUI.command")
local config = require("LspUI.config")
local lib_notify = require("LspUI.lib.notify")
local pos_abstract = require("LspUI.pos_abstract")
local util = require("LspUI.definition.util")
local M = {}
-- whether this module is initialized
local is_initialized = false

M.init = function()
    if not config.options.definition.enable then
        return
    end

    if is_initialized then
        return
    end

    is_initialized = true

    -- TODO: de-comment this
    if config.options.definition.command_enable then
        command.register_command("definition", M.run, {})
    end
end

M.run = function()
    if not config.options.definition.enable then
        lib_notify.Info("definition is not enabled!")
        return
    end
    -- get current buffer
    local current_buffer = api.nvim_get_current_buf()

    local clients = util.get_clients(current_buffer)
    if clients == nil then
        return
    end

    -- get current window
    local current_window = api.nvim_get_current_win()

    local params = util.make_params(current_window)
    params.context = { includeDeclaration = true }
    pos_abstract.lsp_clients_request(
        current_buffer,
        clients,
        definition_feature,
        params,
        function(datas)
            if not datas then
                lib_notify.Info("no valid definition")
                return
            end

            pos_abstract.set_datas(datas)

            pos_abstract.secondary_view_render("definition")

            api.nvim_set_current_win(pos_abstract.secondary_view_window())
        end
    )
end

return M
