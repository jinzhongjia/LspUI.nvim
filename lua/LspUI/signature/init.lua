local api = vim.api
local config = require("LspUI.config")
local lib_notify = require("LspUI.lib.notify")
local util = require("LspUI.signature.util")

local M = {}

local is_initialized = false

function M.init()
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
        hl_val.bg = config.options.signature.color.bg -- 修复：正确设置背景色而不是覆盖前景色
    end
    api.nvim_set_hl(0, "LspUI_Signature", hl_val)

    -- init autocmd
    util.autocmd()
end

function M.run()
    lib_notify.Info("signature has no run func")
end

M.status_line = util.status_line

return M
