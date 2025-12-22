local api, lsp, fn = vim.api, vim.lsp, vim.fn
local signature_feature = lsp.protocol.Methods.textDocument_signatureHelp

local config = require("LspUI.config")
local sig_lib = require("LspUI.lib.signature")
local tools = require("LspUI.layer.tools")

local M = {}

local buffer_set = {}
local signature_namespace = api.nvim_create_namespace("LspUI_signature")
local signature_group
local cached_signature_info = {}
local signature_handler
local pending_cancel = nil

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

    -- 取消之前的请求
    if pending_cancel then
        pcall(pending_cancel)
        pending_cancel = nil
    end

    local clients = M.get_clients(buffer_id)
    if not clients or #clients < 1 then
        return
    end

    local client = clients[1] -- 只使用第一个支持签名功能的客户端
    local params = lsp.util.make_position_params(0, client.offset_encoding)

    local _, cancel = client:request(
        signature_feature,
        params,
        function(err, result, _, _)
            pending_cancel = nil
            -- 签名请求错误通常静默忽略，避免刷屏
            if err then
                return
            end
            callback(result, client.name)
        end,
        buffer_id
    )

    pending_cancel = cancel
end

-- 处理签名请求和展示
local function signature_handle()
    local current_buffer = api.nvim_get_current_buf()

    -- 当前缓冲区不支持签名功能时
    if not buffer_set[current_buffer] then
        cached_signature_info[current_buffer] = nil
        return
    end

    request(current_buffer, function(result, client_name)
        -- 更精确的插入模式检查：i, ic, ix, R, Rc, Rv, Rx
        local mode = api.nvim_get_mode().mode
        if not mode:match("^[iR]") then
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
--- @param _win integer window id (unused)
--- @param _client_name string|nil client name (unused)
function M.render(data, buffer_id, _win, _client_name)
    local info = sig_lib.build_signature_info(data)
    cached_signature_info[buffer_id] = info

    local active_label = sig_lib.get_active_parameter_label(info)
    if not active_label then
        return
    end

    local current_line = fn.line(".")
    local row = math.max(0, current_line - 2)
    local col = fn.virtcol(".") - 1

    local render_text = string.format(
        "%s %s",
        config.options.signature.icon,
        active_label
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
    cached_signature_info[buffer_id] = nil
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

-- 清理函数（用于模块卸载时释放资源）
local signature_handler_cleanup = nil

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
        signature_handler, signature_handler_cleanup =
            tools.debounce(signature_handle, time)
    end

    -- LSP 附加事件 - 添加缓冲区到支持集合
    -- 修复: 使用 args.buf 而不是 nvim_get_current_buf()
    create_autocmd("LspAttach", function(args)
        local buffer_id = args.buf
        local clients = M.get_clients(buffer_id)
        if clients then
            buffer_set[buffer_id] = true
        end
    end, "Lsp attach signature cmd")

    -- 光标移动和插入模式相关事件 - 触发签名处理
    create_autocmd(
        { "CursorMovedI", "InsertEnter" },
        signature_handler,
        "Signature update when CursorMovedI or InsertEnter"
    )

    -- LSP 分离事件 - 清理和移除缓冲区
    -- 修复: 使用 args.buf 而不是 nvim_get_current_buf()
    create_autocmd("LspDetach", function(args)
        local buffer_id = args.buf
        M.clean_render(buffer_id)
        buffer_set[buffer_id] = nil
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

    -- 清理防抖计时器资源
    if signature_handler_cleanup then
        signature_handler_cleanup()
        signature_handler_cleanup = nil
    end

    -- 取消挂起的请求
    if pending_cancel then
        pcall(pending_cancel)
        pending_cancel = nil
    end
end

-- 提供用于状态栏的签名信息
--- @return signature_info?
M.status_line = function()
    local buf = api.nvim_get_current_buf()
    return cached_signature_info[buf]
end

return M
