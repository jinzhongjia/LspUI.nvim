local api, fn = vim.api, vim.fn
local command = require("LspUI.command")
local config = require("LspUI.config")
local lib_notify = require("LspUI.lib.notify")
local util = require("LspUI.rename.util")

local M = {}

-- whether this module has initialized
local is_initialized = false

local command_key = "rename"

-- init for the rename
M.init = function()
    if not config.options.rename.enable then
        return
    end

    if is_initialized then
        return
    end

    is_initialized = true

    -- register command
    if config.options.rename.command_enable then
        command.register_command(command_key, M.run, {})
    end
end

M.deinit = function()
    if not is_initialized then
        lib_notify.Info("rename has been deinit")
        return
    end

    is_initialized = false

    command.unregister_command(command_key)
end

-- run of rename
M.run = function()
    if not config.options.rename.enable then
        lib_notify.Info("rename is not enabled!")
        return
    end

    local current_buffer = api.nvim_get_current_buf()
    local clients = util.get_clients(current_buffer)
    if clients == nil then
        -- if no valid client, step into here
        lib_notify.Warn("no client supports rename!")
        return
    end

    local current_win = api.nvim_get_current_win()

    local old_name = fn.expand("<cword>")

    util.done(clients, current_buffer, current_win, old_name)
end

return M
