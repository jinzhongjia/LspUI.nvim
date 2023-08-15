local api = vim.api
local command = require("LspUI.command")
local config = require("LspUI.config")
local lib_notify = require("LspUI.lib.notify")
local util = require("LspUI.definition.util")
local M = {}
-- whether this module is initialized
local is_initialized = false

M.init = function()
    if not config.options.definition.enable then
        return
    end
    lib_notify.Error(
        "definition has not been completed yet, please do not enable it"
    )

    if is_initialized then
        return
    end

    is_initialized = true

    -- TODO: de-comment this
    -- if config.options.definition.command_enable then
    --     command.register_command("definition", M.run, {})
    -- end
end

M.run = function()
    if not config.options.definition.enable then
        lib_notify.Info("definition is not enabled!")
        return
    end
    lib_notify.Error(
        "definition has not been completed yet, please do not enable it"
    )
    -- TODO:de-comment this
    -- -- get current buffer
    -- local current_buffer = api.nvim_get_current_buf()
    --
    -- local clients = util.get_clients(current_buffer)
    -- if clients == nil then
    --     return
    -- end
    --
    -- -- get current window
    -- local current_window = api.nvim_get_current_win()
    --
    -- local params = util.make_params(current_window)
    --
    -- util.render(current_buffer, clients, params)
end

return M
