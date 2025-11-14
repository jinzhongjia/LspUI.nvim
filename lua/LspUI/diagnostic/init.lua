local command = require("LspUI.command")
local config = require("LspUI.config")
local notify = require("LspUI.layer.notify")
local util = require("LspUI.diagnostic.util")
local M = {}

-- whether this module has initialized
local is_initialized = false

local command_key = "diagnostic"

-- 检查模块是否启用
local function is_enabled()
    return config.options.diagnostic.enable
end

--- @param arg "next"|"prev"|nil
M.run = function(arg)
    if not is_enabled() then
        return
    end

    -- 确保 `arg` 是字符串类型，并且是 "next" 或 "prev"
    if type(arg) ~= "string" or (arg ~= "next" and arg ~= "prev") then
        notify.Warn(
            string.format("diagnostic, unknown action: %s", vim.inspect(arg))
        )
        -- 提供默认值，避免错误
        arg = "next"
    end

    util.render(arg)
end
-- init for diagnostic
function M.init()
    if not is_enabled() or is_initialized then
        return
    end

    is_initialized = true

    if config.options.diagnostic.command_enable then
        command.register_command(command_key, M.run, { "next", "prev" })
    end
end

return M
