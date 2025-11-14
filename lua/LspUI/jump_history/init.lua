-- lua/LspUI/jump_history/init.lua
local command = require("LspUI.command")
local config = require("LspUI.config")
local controller_module = require("LspUI.layer.controller")
local notify = require("LspUI.layer.notify")

local M = {}

-- 添加标准的init函数
function M.init()
    -- 检查模块是否启用
    if
        not config.options.jump_history
        or not config.options.jump_history.enable
    then
        return
    end

    -- 注册命令(如果配置允许)
    if config.options.jump_history.command_enable then
        command.register_command("history", M.run, {})
    end
end

-- 运行函数 - 显示跳转历史
function M.run()
    -- 获取全局控制器实例
    local controller = controller_module:GetInstance()

    if not controller then
        notify.Warn("LspUI controller is not initialized")
        return
    end

    if not controller.ActionShowHistory then
        notify.Warn("Jump history feature is not available")
        return
    end

    controller:ActionShowHistory()
end

return M
