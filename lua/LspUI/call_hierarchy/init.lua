local ClassLsp = require("LspUI.layer.lsp")
local ClassLspFeature = require("LspUI.layer.lsp_feature")
local command = require("LspUI.command")
local config = require("LspUI.config")
local interface = require("LspUI.interface")
local notify = require("LspUI.layer.notify")

-- 创建通用功能实例
local M = ClassLspFeature:New("call_hierarchy", "prepareCallHierarchy")

-- 覆盖默认的初始化方法
M.init = function()
    if not config.options.call_hierarchy.enable or M.is_initialized then
        return
    end

    M.is_initialized = true

    if config.options.call_hierarchy.command_enable then
        command.register_command(
            "call_hierarchy",
            M.run,
            { "incoming", "outgoing" }
        )
    end
end

-- 覆盖默认的运行方法
M.run = function(method)
    if not config.options.call_hierarchy.enable then
        return
    end

    -- 获取当前缓冲区和客户端信息
    local current_buffer = vim.api.nvim_get_current_buf()
    local clients = M:GetClients(current_buffer)

    if not clients then
        notify.Warn("no client supports call_hierarchy!")
        return
    end

    local params =
        vim.lsp.util.make_position_params(0, clients[1].offset_encoding)

    local method_name = ""
    if method == "incoming" then
        method_name = ClassLsp.methods.incoming_calls.name
    elseif method == "outgoing" then
        method_name = ClassLsp.methods.outgoing_calls.name
    else
        notify.Warn("invalid method name!")
        return
    end

    -- 调用接口执行
    interface.go(method_name, current_buffer, params)
end

-- 初始化模块
M:Init()

return M
