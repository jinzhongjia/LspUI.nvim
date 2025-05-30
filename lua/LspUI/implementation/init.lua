-- lua/LspUI/implementation/init.lua
local ClassLspFeature = require("LspUI.layer.lsp_feature")
local command = require("LspUI.command")
local config = require("LspUI.config")

-- 创建功能实例
local feature = ClassLspFeature:New("implementation", "implementation")

local M = {}

-- 添加标准的init函数
function M.init()
    -- 检查模块是否启用
    if not config.options.implementation.enable then
        return
    end

    -- 调用功能初始化
    feature:Init()

    -- 注册命令(如果配置允许)
    if config.options.implementation.command_enable then
        command.register_command("implementation", M.run, {})
    end
end

-- 运行函数
function M.run()
    -- 调用功能的Run方法
    feature:Run()
end

return M
