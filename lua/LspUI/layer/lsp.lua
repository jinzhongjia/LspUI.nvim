-- lua/LspUI/layer/lsp.lua (重构版本)
local api, lsp = vim.api, vim.lsp
local diagnostic_severity = vim.diagnostic.severity -- 缓存常用引用

local lib_notify = require("LspUI.layer.notify")
local tools = require("LspUI.layer.tools")

---@class ClassLsp
---@field _client vim.lsp.Client|nil
---@field _datas LspUIPositionWrap 存储LSP结果数据
---@field _method table 当前使用的LSP方法
---@field _origin_uri string 请求发起的URI
local ClassLsp = {
    _client = nil,
    _datas = {},
    ---@diagnostic disable-next-line: assign-type-mismatch
    _method = nil,
    ---@diagnostic disable-next-line: assign-type-mismatch
    _origin_uri = nil,
}

ClassLsp.__index = ClassLsp

ClassLsp.methods = {
    definition = {
        method = lsp.protocol.Methods.textDocument_definition,
        name = "definition",
        fold = false,
    },
    type_definition = {
        method = lsp.protocol.Methods.textDocument_typeDefinition,
        name = "type_definition",
        fold = false,
    },
    declaration = {
        method = lsp.protocol.Methods.textDocument_declaration,
        name = "declaration",
        fold = false,
    },
    reference = {
        method = lsp.protocol.Methods.textDocument_references,
        name = "reference",
        fold = true,
    },
    implementation = {
        method = lsp.protocol.Methods.textDocument_implementation,
        name = "implementation",
        fold = true,
    },
    -- 添加新的调用层次方法
    incoming_calls = {
        method = lsp.protocol.Methods.callHierarchy_incomingCalls,
        name = "incoming_calls",
        fold = true,
        prepare = lsp.protocol.Methods.textDocument_prepareCallHierarchy,
    },
    outgoing_calls = {
        method = lsp.protocol.Methods.callHierarchy_outgoingCalls,
        name = "outgoing_calls",
        fold = true,
        prepare = lsp.protocol.Methods.textDocument_prepareCallHierarchy,
    },
}

---@return ClassLsp
function ClassLsp:New()
    local obj = {}
    setmetatable(obj, self)
    return obj
end

---@param method_name string "definition"|"type_definition"|"declaration"|"reference"|"implementation"
---@return boolean 设置是否成功
function ClassLsp:SetMethod(method_name)
    if self.methods[method_name] then
        self._method = self.methods[method_name]
        return true
    else
        lib_notify.Error("Unsupported LSP method: " .. method_name)
        return false
    end
end

---@return table 当前使用的方法信息
function ClassLsp:GetMethod()
    return self._method
end

---@return LspUIPositionWrap LSP结果数据
function ClassLsp:GetData()
    return self._datas
end

---@param buffer_id integer 缓冲区ID
---@param params table LSP请求参数
---@param callback function 回调函数
function ClassLsp:Request(buffer_id, params, callback)
    if not self._method then
        lib_notify.Error("Please set LSP method first")
        return
    end

    self._origin_uri = vim.uri_from_bufnr(buffer_id)
    self._datas = {}

    -- 检查是否是调用层次相关请求
    if self._method.prepare then
        -- 调用层次需要先准备调用层次项，然后再请求调用层次关系
        self:_requestCallHierarchy(buffer_id, params, callback)
    else
        -- 常规LSP请求
        lsp.buf_request_all(
            buffer_id,
            self._method.method,
            params,
            function(results, _, _)
                if not api.nvim_buf_is_valid(buffer_id) then
                    return
                end

                local data = {}
                local has_valid_result = false

                -- 处理LSP响应数据
                for _, result in pairs(results) do
                    if
                        result
                        and result.result
                        and not vim.tbl_isempty(result.result)
                    then
                        self:_processLspResult(result.result, data)
                        has_valid_result = true
                    end
                end

                self._datas = data

                -- 调用回调函数
                if callback then
                    callback(data)
                end
            end
        )
    end
end

-- 添加调用层次请求处理方法
---@private
---@param buffer_id integer 缓冲区ID
---@param params table LSP请求参数
---@param callback function 回调函数
function ClassLsp:_requestCallHierarchy(buffer_id, params, callback)
    -- 第一步：准备调用层次项
    lsp.buf_request_all(
        buffer_id,
        self._method.prepare,
        params,
        function(prepare_results, _, _)
            if not api.nvim_buf_is_valid(buffer_id) then
                return
            end

            local items = {}
            for _, result in pairs(prepare_results) do
                if result and result.result and #result.result > 0 then
                    vim.list_extend(items, result.result)
                end
            end

            if #items == 0 then
                lib_notify.Info("No available call hierarchy items found")
                if callback then
                    callback({})
                end
                return
            end

            local data = {}
            local pending_requests = #items
            local all_complete = false

            -- 第二步：请求每个调用层次项的调用关系
            for _, hierarchy_item in ipairs(items) do
                lsp.buf_request_all(
                    buffer_id,
                    self._method.method,
                    { item = hierarchy_item },
                    function(call_results, _, _)
                        if
                            all_complete or not api.nvim_buf_is_valid(buffer_id)
                        then
                            return
                        end

                        for _, call_result in pairs(call_results) do
                            if
                                call_result
                                and call_result.result
                                and #call_result.result > 0
                            then
                                self:_processCallHierarchyResult(
                                    call_result.result,
                                    data,
                                    self._method.name == "incoming_calls"
                                )
                            end
                        end

                        pending_requests = pending_requests - 1
                        if pending_requests == 0 then
                            all_complete = true
                            self._datas = data
                            if callback then
                                callback(data)
                            end
                        end
                    end
                )
            end
        end
    )
end

-- 添加处理调用层次结果的方法
---@private
---@param results table 调用层次结果
---@param data LspUIPositionWrap 处理结果存放表
---@param is_incoming boolean 是否是入站调用
function ClassLsp:_processCallHierarchyResult(results, data, is_incoming)
    for _, call in ipairs(results) do
        local item = is_incoming and call.from or call.to
        local uri = item.uri

        -- 初始化该 URI 的数据结构
        if not data[uri] then
            data[uri] = {
                buffer_id = vim.uri_to_bufnr(uri),
                fold = self._method.fold
                    and not tools.compare_uri(self._origin_uri, uri),
                range = {},
            }
        end

        -- 处理调用位置
        if is_incoming and call.fromRanges and #call.fromRanges > 0 then
            -- 对于入站调用，使用 fromRanges 中的所有位置
            for _, range in ipairs(call.fromRanges) do
                table.insert(data[uri].range, {
                    start = range.start,
                    finish = range["end"],
                })
            end
        else
            -- 对于出站调用或没有 fromRanges 的入站调用，使用项目的选择范围或范围
            local range = item.selectionRange or item.range
            table.insert(data[uri].range, {
                start = range.start,
                finish = range["end"],
            })
        end
    end
end

---@private
---@param result table|nil LSP响应结果
---@param data LspUIPositionWrap 处理结果存放表
function ClassLsp:_processLspResult(result, data)
    -- 防御性编程：检查结果是否为nil
    if not result then
        return
    end

    local handle_result = function(lspRes)
        local uri = lspRes.uri or lspRes.targetUri
        local range = lspRes.range or lspRes.targetRange
        local uri_buffer = vim.uri_to_bufnr(uri)

        if not data[uri] then
            data[uri] = {
                buffer_id = uri_buffer,
                fold = self._method.fold
                    and not tools.compare_uri(self._origin_uri, uri),
                range = {},
            }
        end

        table.insert(data[uri].range, {
            start = range.start,
            finish = range["end"],
        })
    end

    -- 处理单个结果或多个结果
    if result.uri then
        handle_result(result)
    elseif tools.islist(result) then -- 使用辅助函数检查是否为列表
        for _, response in ipairs(result) do
            handle_result(response)
        end
    end
end

--- 将 Vim 诊断格式转换为 LSP 诊断格式
--- @param diagnostics vim.Diagnostic[] Vim 格式的诊断数组
--- @return lsp.Diagnostic[] LSP 格式的诊断数组
function ClassLsp:diagnostic_vim_to_lsp(diagnostics)
    if not diagnostics or #diagnostics == 0 then
        return {} -- 添加空检查提高健壮性
    end

    local result = {}
    for i, diagnostic in ipairs(diagnostics) do -- 使用 ipairs 替代 tbl_map 可能更高效
        local severity = diagnostic.severity
        if type(severity) == "string" then
            severity = diagnostic_severity[severity]
        end

        local user_data_lsp = (
            diagnostic.user_data and diagnostic.user_data.lsp
        ) or {}

        result[i] = vim.tbl_extend("keep", {
            range = {
                start = {
                    line = diagnostic.lnum,
                    character = diagnostic.col,
                },
                ["end"] = {
                    line = diagnostic.end_lnum,
                    character = diagnostic.end_col,
                },
            },
            severity = severity,
            message = diagnostic.message,
            source = diagnostic.source,
            code = diagnostic.code,
        }, user_data_lsp)
    end

    return result
end

ClassLsp.code_action_feature = lsp.protocol.Methods.textDocument_codeAction
ClassLsp.exec_command_feature = lsp.protocol.Methods.workspace_executeCommand
ClassLsp.code_action_resolve_feature = lsp.protocol.Methods.codeAction_resolve
ClassLsp.rename_feature = lsp.protocol.Methods.textDocument_rename
-- stylua: ignore
ClassLsp.prepare_rename_feature = lsp.protocol.Methods.textDocument_prepareRename

-- 获取支持代码操作的客户端
function ClassLsp:GetCodeActionClients(buffer_id)
    local clients = lsp.get_clients({
        bufnr = buffer_id,
        method = self.code_action_feature,
    })

    if vim.tbl_isempty(clients) then
        return nil
    end
    return clients
end

-- 构建代码操作参数
function ClassLsp:MakeCodeActionParams(buffer_id, client, is_visual_mode)
    local mode = api.nvim_get_mode().mode
    local params
    local is_visual = is_visual_mode or (mode == "v" or mode == "V")
    local offset_encoding = client and client.offset_encoding or "utf-16"

    if is_visual then
        -- 视觉模式参数逻辑
        local start = vim.fn.getpos("v")
        local end_ = vim.fn.getpos(".")
        local start_row = start[2]
        local start_col = start[3]
        local end_row = end_[2]
        local end_col = end_[3]

        -- 规范化范围
        if start_row == end_row and end_col < start_col then
            end_col, start_col = start_col, end_col
        elseif end_row < start_row then
            start_row, end_row = end_row, start_row
            start_col, end_col = end_col, start_col
        end

        if mode == "V" then
            start_col = 1
            local lines =
                api.nvim_buf_get_lines(buffer_id, end_row - 1, end_row, true)
            end_col = #lines[1]
        end

        params = lsp.util.make_given_range_params(
            { start_row, start_col - 1 },
            { end_row, end_col - 1 },
            buffer_id,
            offset_encoding
        )
    else
        -- 普通模式参数
        params = lsp.util.make_range_params(0, offset_encoding)
    end

    -- 添加上下文
    local context = {
        triggerKind = vim.lsp.protocol.CodeActionTriggerKind.Invoked,
        diagnostics = self:diagnostic_vim_to_lsp(
            vim.diagnostic.get(buffer_id, {
                lnum = vim.fn.line(".") - 1,
            })
        ),
    }
    params.context = context

    return params, is_visual
end

-- 获取Git签名操作
function ClassLsp:GetGitsignsActions(
    action_tuples,
    buffer_id,
    is_visual,
    uri,
    range
)
    local config = require("LspUI.config")
    if not config.options.code_action.gitsigns then
        return action_tuples
    end

    local status, gitsigns = pcall(require, "gitsigns")
    if not status then
        return action_tuples
    end

    local gitsigns_actions = gitsigns.get_actions()
    for name, gitsigns_action in pairs(gitsigns_actions or {}) do
        local title = string.format(
            "%s%s",
            string.sub(name, 1, 1),
            string.sub(string.gsub(name, "_", " "), 2)
        )

        local func = gitsigns_action
        if is_visual then
            func = function()
                gitsigns_action({ range.start.line, range["end"].line })
            end
        end

        local do_func = function()
            local bufnr = vim.uri_to_bufnr(uri)
            api.nvim_buf_call(bufnr, func)
        end

        table.insert(action_tuples, {
            action = { title = title },
            buffer_id = buffer_id,
            callback = do_func,
        })
    end

    return action_tuples
end

-- 请求代码操作
function ClassLsp:RequestCodeActions(buffer_id, params, callback, options)
    options = options or {}
    local register = require("LspUI.code_action.register")
    local clients = self:GetCodeActionClients(buffer_id)

    if not clients then
        return false, "no client supports code_action"
    end

    local action_tuples = {}
    local pending_requests = #clients
    local is_visual = options.is_visual or false

    -- 首先添加注册的操作
    if not options.skip_registered then
        local register_actions =
            register.handle(params.textDocument.uri, params.range)
        for _, val in pairs(register_actions) do
            table.insert(action_tuples, {
                action = { title = val.title },
                buffer_id = buffer_id,
                callback = val.action,
            })
        end
    end

    -- 检查是否需要添加git操作
    if not options.skip_gitsigns then
        action_tuples = self:GetGitsignsActions(
            action_tuples,
            buffer_id,
            is_visual,
            params.textDocument.uri,
            params.range
        )
    end

    -- 如果只需要注册的操作和git操作，可以直接返回
    if options.skip_lsp and #action_tuples > 0 then
        if callback then
            callback(action_tuples)
        end
        return true
    end

    -- 请求LSP服务器的代码操作
    for _, client in pairs(clients) do
        client:request(
            self.code_action_feature,
            params,
            function(err, result, _, _)
                if err then
                    require("LspUI.lib.notify").Warn(
                        string.format("code action error: %s", err.message)
                    )
                else
                    -- 处理结果
                    for _, action in pairs(result or {}) do
                        if action.title and action.title ~= "" then
                            table.insert(action_tuples, {
                                action = action,
                                client = client,
                                buffer_id = buffer_id,
                            })
                        end
                    end
                end

                pending_requests = pending_requests - 1
                if pending_requests == 0 and callback then
                    callback(action_tuples)
                end
            end,
            buffer_id
        )
    end

    return true
end

-- 执行代码操作
function ClassLsp:ExecCodeAction(action_tuple)
    local callback = action_tuple.callback
    if callback then
        callback()
        return true
    end

    local action = action_tuple.action
    local client = action_tuple.client
    if not client then
        return false, "no client available"
    end

    -- 应用操作逻辑
    if action.edit then
        lsp.util.apply_workspace_edit(action.edit, client.offset_encoding)
    end

    if action.command then
        local command = type(action.command) == "table" and action.command
            or action
        self:ExecCommand(client, command, action_tuple.buffer_id)
    end

    return true
end

-- 执行命令
function ClassLsp:ExecCommand(client, command, buffer_id, handler)
    local cmdname = command.command
    local func = client.commands[cmdname] or lsp.commands[cmdname]

    if func then
        func(command, { bufnr = buffer_id, client_id = client.id })
        return
    end

    -- 检查服务器是否支持该命令
    local command_provider = client.server_capabilities.executeCommandProvider
    local commands = type(command_provider) == "table"
            and command_provider.commands
        or {}

    if not vim.list_contains(commands, cmdname) then
        require("LspUI.lib.notify").Warn(
            string.format(
                "Language server `%s` does not support command `%s`",
                client.name,
                cmdname
            )
        )
        return
    end

    local params = {
        command = command.command,
        arguments = command.arguments,
    }

    client:request(self.exec_command_feature, params, handler, buffer_id)
end

-- 获取支持重命名的客户端
function ClassLsp:GetRenameClients(buffer_id)
    local clients = lsp.get_clients({
        bufnr = buffer_id,
        method = self.rename_feature,
    })

    if vim.tbl_isempty(clients) then
        return nil
    end
    return clients
end

-- 检查位置是否可以重命名
function ClassLsp:CheckRenamePosition(buffer_id, params, callback)
    local clients = self:GetRenameClients(buffer_id)
    if not clients then
       callback(false, nil, "No available renaming client") 
        return
    end

    local valid_clients = {}
    local remaining = #clients

    for _, client in ipairs(clients) do
        if client:supports_method(self.prepare_rename_feature) then
            client:request(
                self.prepare_rename_feature,
                params,
                function(err, result, _, _)
                    remaining = remaining - 1

                    if not err and result then
                        table.insert(valid_clients, client)
                    end

                    if remaining == 0 then
                        if #valid_clients > 0 then
                            callback(true, valid_clients)
                        else
                           callback(false, nil, "This position cannot be renamed") 
                        end
                    end
                end,
                buffer_id
            )
        else
            -- 客户端不支持预检查，假定位置有效
            remaining = remaining - 1
            table.insert(valid_clients, client)

            if remaining == 0 then
                callback(true, valid_clients)
            end
        end
    end
end

-- 执行重命名操作
function ClassLsp:ExecuteRename(clients, buffer_id, params)
    local count = #clients
    local completed = 0

    for _, client in ipairs(clients) do
        local handler = client.handlers[self.rename_feature]
            or lsp.handlers[self.rename_feature]

        client:request(self.rename_feature, params, function(...)
            handler(...)
            completed = completed + 1
        end, buffer_id)
    end

    return true
end

return ClassLsp
