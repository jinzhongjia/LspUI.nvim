local config = require("LspUI.config")
local lib_notify = require("LspUI.layer.notify")
local util = require("LspUI.lightbulb.util")

local M = {}

--- note: lightbulb depends on code_action

-- whether this module has initialized
local is_initialized = false

-- init for lightbulb
function M.init()
    if (not config.options.lightbulb.enable) or is_initialized then
        return
    end

    is_initialized = true

    vim.schedule(function()
        -- register sign, should only be called once
        util.register_sign()

        util.autocmd()
    end)
end

-- run for lightbulb
function M.run()
    lib_notify.Info("lightbulb has no run func")
end

-- deinit for lightbulb
function M.deinit()
    if not is_initialized then
        return
    end

    util.unregister_sign()
    util.un_autocmd()

    is_initialized = false
end

return M
