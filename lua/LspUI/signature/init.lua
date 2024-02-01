local api, fn = vim.api, vim.fn
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

    local hl_val = {
        fg = config.options.signature.color.fg,
        italic = true,
        -- standout = true,
        undercurl = true,
    }

    if config.options.signature.color.bg then
        hl_val.fg = config.options.signature.color.bg
    end
    api.nvim_set_hl(0, "LspUI_Signature", hl_val)

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
