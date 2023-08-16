local config = require("LspUI.config")
local lib_notify = require("LspUI.lib.notify")
local util = require("LspUI.lightbulb.util")

local M = {}

-- whether this module has initialized
local is_initialized = false

-- init for lightbulb
M.init = function()
    if not config.options.lightbulb.enable then
        return
    end

    if is_initialized then
        return
    end

    is_initialized = true

    -- register sign, should only be called once
    util.register_sign()

    util.autocmd()
end

-- run for lightbulb
M.run = function()
    lib_notify.Info("lightbulb has no run func")
end

return M
