-- lua/LspUI/rename/init.lua
local api, fn = vim.api, vim.fn
local ClassLsp = require("LspUI.layer.lsp") -- 添加引入 ClassLsp
local command = require("LspUI.command")
local config = require("LspUI.config")
local lib_notify = require("LspUI.layer.notify")
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

-- run of rename
M.run = function()
    if not config.options.rename.enable then
       lib_notify.Info("Rename function is not enabled!") 
        return
    end

    local current_buffer = api.nvim_get_current_buf()

    -- 使用 ClassLsp 获取客户端
    local lsp_handler = ClassLsp:New()
    local clients = lsp_handler:GetRenameClients(current_buffer)

    if not clients or #clients < 1 then
       lib_notify.Warn("No clients supporting rename operation!") 
        return
    end

    local current_win = api.nvim_get_current_win()
    local old_name = fn.expand("<cword>")

    util.done(clients, current_buffer, current_win, old_name)
end

return M
