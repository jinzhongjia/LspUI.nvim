local api, lsp, fn = vim.api, vim.lsp, vim.fn
local signature_feature = lsp.protocol.Methods.textDocument_signatureHelp

local config = require("LspUI.config")
local notify = require("LspUI.layer.notify")
local tools = require("LspUI.layer.tools")

local M = {}

-- 类型定义
--- @class signature_info
--- @field label string 签名标签
--- @field active_parameter integer? 活动参数的索引
--- @field parameters {label: string, doc: (string|lsp.MarkupContent)?}[]? 参数信息数组
--- @field doc string? 文档字符串

-- 使用集合管理支持签名功能的缓冲区
local buffer_set = {}
local signature_namespace = api.nvim_create_namespace("LspUI_signature")
local signature_group
local cached_signature_info = nil
local signature_handler

--- @param help lsp.SignatureHelp|nil
--- @param _ string|nil client name
--- @return signature_info? res len will not be zero
local function build_signature_info(help, _)
    if not help or not help.signatures or #help.signatures == 0 then
        return nil
    end

    local active_signature = (help.activeSignature or 0) + 1
    -- 确保签名索引有效
    if active_signature > #help.signatures then
        active_signature = 1
    end

    local current_signature = help.signatures[active_signature]
    local active_parameter = (help.activeParameter or 0) + 1

    -- 构建基本签名信息
    --- @type signature_info
    local res = {
        label = current_signature.label,
        -- 修复: 正确处理 lsp.MarkupContent 类型
        ---@diagnostic disable-next-line: assign-type-mismatch
        doc = type(current_signature.documentation) == "table"
                and current_signature.documentation.value
            or (current_signature.documentation or nil),
    }

    -- 如果没有参数，直接返回基本信息
    if
        not current_signature.parameters
        or #current_signature.parameters == 0
    then
        return res
    end

    -- 优先使用签名的活动参数
    if current_signature.activeParameter then
        active_parameter = current_signature.activeParameter + 1
    end

    -- 确保活动参数索引有效
    if
        active_parameter > #current_signature.parameters
        or active_parameter < 1
    then
        active_parameter = 1
    end

    -- 构建参数列表
    res.parameters = {}
    res.active_parameter = active_parameter

    for _, parameter in ipairs(current_signature.parameters) do
        local label
        if type(parameter.label) == "string" then
            label = parameter.label
        else
            label = string.sub(
                current_signature.label,
                parameter.label[1] + 1,
                parameter.label[2]
            )
        end

        table.insert(res.parameters, {
            label = label,
            doc = parameter.documentation,
        })
    end

    return res
end

-- get all valid clients for signature help
--- @param buffer_id integer
--- @return vim.lsp.Client[]|nil clients array or nil
function M.get_clients(buffer_id)
    local clients =
        lsp.get_clients({ bufnr = buffer_id, method = signature_feature })
    if vim.tbl_isempty(clients) then
        return nil
    end
    return clients
end

--- @param buffer_id number buffer's id
--- @param callback fun(result: lsp.SignatureHelp|nil, client_name:string|nil) callback function
local function request(buffer_id, callback)
    if not api.nvim_buf_is_valid(buffer_id) then
        return
    end

    local clients = M.get_clients(buffer_id)
    if not clients or #clients < 1 then
        return
    end

    -- 检查客户端是否就绪
    local ClassLsp = require("LspUI.layer.lsp")
    local lsp_instance = ClassLsp:New()
    local ready, reason = lsp_instance:CheckClientsReady(clients)
    if not ready then
        notify.Warn(reason or "LSP client not ready")
        return
    end

    local client = clients[1] -- 只使用第一个支持签名功能的客户端
    local params = lsp.util.make_position_params(0, client.offset_encoding)

    client:request(signature_feature, params, function(err, result, _, _)
        if err then
            notify.Error(
                string.format(
                    "sorry, lsp %s report signature error:%d, %s",
                    client.name,
                    err.code,
                    err.message
                )
            )
            return
        end
        callback(result, client.name)
    end, buffer_id)
end

-- 处理签名请求和展示
local function signature_handle()
    local current_buffer = api.nvim_get_current_buf()

    -- 当前缓冲区不支持签名功能时
    if not buffer_set[current_buffer] then
        cached_signature_info = nil
        return
    end

    request(current_buffer, function(result, client_name)
        -- 检查是否仍在插入模式
        local mode = api.nvim_get_mode().mode
        if not (mode:find("i") or mode:find("ic")) then
            return
        end

        -- 检查当前缓冲区是否仍然是请求时的缓冲区
        local callback_buffer = api.nvim_get_current_buf()
        if callback_buffer ~= current_buffer then
            return
        end

        -- 清除旧的渲染并设置新的
        M.clean_render(current_buffer)
        local current_window = api.nvim_get_current_win()
        M.render(result, current_buffer, current_window, client_name)
    end)
end

--- @param data lsp.SignatureHelp|nil
--- @param buffer_id integer
--- @param _ integer window id
--- @param client_name string|nil
function M.render(data, buffer_id, _, client_name)
    local info = build_signature_info(data, client_name)
    cached_signature_info = info

    -- 无签名信息或无活动参数时不渲染
    if not info or not info.parameters or not info.active_parameter then
        return
    end

    local row = fn.line(".") == 1 and 1 or fn.line(".") - 2
    local col = fn.virtcol(".") - 1
    local active_param = info.parameters[info.active_parameter]

    -- 确保活动参数存在
    if not active_param then
        return
    end

    -- 设置虚拟文本
    local render_text = string.format(
        "%s %s",
        config.options.signature.icon,
        active_param.label
    )

    api.nvim_buf_set_extmark(buffer_id, signature_namespace, row, 0, {
        virt_text = { { render_text, "LspUI_Signature" } },
        virt_text_win_col = col,
        hl_mode = "blend",
    })
end

-- clean signature virtual text
--- @param buffer_id integer
function M.clean_render(buffer_id)
    if api.nvim_buf_is_valid(buffer_id) then
        api.nvim_buf_clear_namespace(buffer_id, signature_namespace, 0, -1)
    end
end

-- 创建自动命令帮助函数
--- @param events string|string[] 事件名称
--- @param callback function 回调函数
--- @param desc string 描述
local function create_autocmd(events, callback, desc)
    api.nvim_create_autocmd(events, {
        group = signature_group,
        callback = callback,
        desc = tools.command_desc(desc),
    })
end

-- 设置自动命令
function M.autocmd()
    signature_group =
        api.nvim_create_augroup("Lspui_signature", { clear = true })

    -- 应用去抖动（如果配置了）
    signature_handler = signature_handle
    if config.options.signature.debounce then
        local time = 300
        -- 修复: 确保 debounce 是数字
        if type(config.options.signature.debounce) == "number" then
            ---@diagnostic disable-next-line: param-type-mismatch
            time = math.floor(config.options.signature.debounce)
        end
        -- 如果是 true，使用默认值
        signature_handler = tools.debounce(signature_handle, time)
    end

    -- LSP 附加事件 - 添加缓冲区到支持集合
    create_autocmd("LspAttach", function()
        local current_buffer = api.nvim_get_current_buf()
        local clients = M.get_clients(current_buffer)
        if clients then
            buffer_set[current_buffer] = true
        end
    end, "Lsp attach signature cmd")

    -- 光标移动和插入模式相关事件 - 触发签名处理
    create_autocmd(
        { "CursorMovedI", "InsertEnter" },
        signature_handler,
        "Signature update when CursorMovedI or InsertEnter"
    )

    -- LSP 分离事件 - 清理和移除缓冲区
    create_autocmd("LspDetach", function()
        local current_buffer = api.nvim_get_current_buf()
        M.clean_render(current_buffer)
        buffer_set[current_buffer] = nil
    end, "Clean signature when LSP detached")

    -- 缓冲区删除事件 - 防止内存泄漏
    create_autocmd("BufDelete", function(args)
        local bufnr = args.buf
        M.clean_render(bufnr)
        buffer_set[bufnr] = nil
    end, "Clean signature data when buffer is deleted")

    -- 离开插入模式或窗口时 - 清理虚拟文本
    create_autocmd({ "InsertLeave", "WinLeave" }, function()
        local current_buffer = api.nvim_get_current_buf()
        M.clean_render(current_buffer)
    end, "Clean signature virtual text when InsertLeave or WinLeave")
end

-- 移除自动命令
function M.deautocmd()
    if signature_group then
        api.nvim_del_augroup_by_id(signature_group)
    end
end

-- 提供用于状态栏的签名信息
--- @return signature_info?
M.status_line = function()
    return cached_signature_info
end

return M
