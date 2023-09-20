local api = vim.api
local command = require("LspUI.command")
local config = require("LspUI.config")
local lib_notify = require("LspUI.lib.notify")
local pos_abstract = require("LspUI.pos_abstract")
local util = require("LspUI.reference.util")
local M = {}
-- whether this module is initialized
local is_initialized = false

M.init = function()
    if not config.options.reference.enable then
        return
    end

    if is_initialized then
        return
    end

    is_initialized = true

    if config.options.reference.command_enable then
        command.register_command("reference", M.run, {})
    end
end

M.run = function()
    if not config.options.reference.enable then
        lib_notify.Info("reference is not enabled!")
        return
    end
    -- get current buffer
    local current_buffer = api.nvim_get_current_buf()

    local clients = util.get_clients(current_buffer)
    if clients == nil then
        lib_notify.Warn("no client supports reference!")
        return
    end

    -- get current window
    local current_window = api.nvim_get_current_win()

    local params = util.make_params(current_window)

    pos_abstract.go(
        pos_abstract.method.reference,
        current_buffer,
        current_window,
        clients,
        params
    )
end

return M
