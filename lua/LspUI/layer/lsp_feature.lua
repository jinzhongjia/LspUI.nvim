local command = require("LspUI.command")
local config = require("LspUI.config")
local layer_notify = require("LspUI.layer.notify")
local api = vim.api

--- @class ClassLspFeature
--- @field name string 功能名称
--- @field lsp_method string LSP 方法名
--- @field is_initialized boolean 是否已初始化
local ClassLspFeature = {}
ClassLspFeature.__index = ClassLspFeature

--- 创建新的功能特性实例
--- @param name string 功能名称
--- @param lsp_method string|nil LSP 方法名
--- @return ClassLspFeature
function ClassLspFeature:New(name, lsp_method)
    local obj = {}
    setmetatable(obj, self)

    obj.name = name
    obj.lsp_method = lsp_method or name
    obj.is_initialized = false

    return obj
end

--- 初始化功能模块
--- @return ClassLspFeature
function ClassLspFeature:Init()
    -- 添加防御性检查，确保 config.options 和 config.options[self.name] 存在
    local options = config.options or {}
    local feature_options = options[self.name] or {}

    -- 检查功能是否已启用
    if not (feature_options.enable == true) or self.is_initialized then
        return self
    end

    self.is_initialized = true

    -- 注册命令（如果配置允许）
    if feature_options.command_enable == true then
        command.register_command(self.name, function(callback)
            self:Run(callback)
        end, {})
    end

    return self
end

--- 获取特定缓冲区的 LSP 客户端
--- @param buffer_id integer 缓冲区 ID
--- @param method string|nil LSP 方法名
--- @return vim.lsp.Client[]|nil 客户端列表或 nil
function ClassLspFeature:GetClients(buffer_id, method)
    local lsp_method = method or self.lsp_method

    -- 获取支持此方法的客户端
    local clients = vim.lsp.get_clients({
        bufnr = buffer_id,
        method = vim.lsp.protocol.Methods["textDocument_" .. lsp_method],
    })

    if vim.tbl_isempty(clients) then
        return nil
    end

    return clients
end

--- 创建请求参数
--- @param window_id integer 窗口 ID
--- @param offset_encoding string 偏移编码
--- @return table 请求参数
function ClassLspFeature:MakeParams(window_id, offset_encoding)
    local params = vim.lsp.util.make_position_params(window_id, offset_encoding)

    -- 对特殊方法的参数进行扩展
    if self.name == "reference" then
        params.context = { includeDeclaration = true }
    end

    return params
end

--- 执行功能
--- @param callback fun(LspUIPositionWrap?)|nil 回调函数
function ClassLspFeature:Run(callback)
    -- 添加防御性检查
    local options = config.options or {}
    local feature_options = options[self.name] or {}

    -- 检查功能是否启用
    if not (feature_options.enable == true) then
        layer_notify.Info(
            string.format(
                "%s feature is not enabled!",
                self.name:sub(1, 1):upper() .. self.name:sub(2)
            )
        )
        return
    end

    -- 获取当前缓冲区和客户端
    local current_buffer = api.nvim_get_current_buf()
    local clients = self:GetClients(current_buffer)

    -- 检查是否有可用客户端
    if not clients or #clients < 1 then
        if callback then
            callback()
        else
            layer_notify.Warn(
                string.format("No client supports %s!", self.name)
            )
        end
        return
    end

    -- 创建请求参数
    local params =
        self:MakeParams(api.nvim_get_current_win(), clients[1].offset_encoding)

    -- 使用延迟加载避免循环引用
    vim.defer_fn(function()
        -- 延迟加载 interface 模块
        local interface = require("LspUI.interface")
        -- 使用安全的方式获取方法名
        local ClassLsp = require("LspUI.layer.lsp")
        if ClassLsp and ClassLsp.methods and ClassLsp.methods[self.name] then
            local method_name = ClassLsp.methods[self.name].name
            -- 调用接口
            interface.go(method_name, current_buffer, params)
        else
            layer_notify.Error("无法找到LSP方法: " .. self.name)
        end
    end, 0)
end

return ClassLspFeature
