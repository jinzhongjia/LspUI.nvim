local api, fn = vim.api, vim.fn
local command = require("LspUI.command")
local config = require("LspUI.config")
local lib_notify = require("LspUI.lib.notify")
local util = require("LspUI.signature.util")

local M = {}

local is_initialized = false

M.init = function()
    if not config.options.signature.enable then
        return
    end

    if is_initialized then
        return
    end

    is_initialized = true

    -- init autocmd
    util.autocmd()
end

M.deinit = function()
    if not is_initialized then
        lib_notify.Info("signature has been deinit")
    end

    is_initialized = false

    -- remove autocmd
    util.deautocmd()
end

M.run = function()
    lib_notify.Info("signature has no run func")
end

M.status_line = util.status_line

return M
