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

--- 检查客户端列表是否已就绪
--- @param clients vim.lsp.Client[]|vim.lsp.Client 客户端列表或单个客户端
--- @return boolean, string? 是否就绪，未就绪的原因
function ClassLsp:CheckClientsReady(clients)
    if not clients then
        return false, "No LSP client available"
    end

    -- 处理单个客户端的情况
    local client_list = type(clients) == "table" and clients or { clients }

    -- 检查是否有任何客户端
    if #client_list == 0 then
        return false, "No LSP client available"
    end

    -- 检查所有客户端的初始化状态
    local unready_clients = {}
    for _, client in ipairs(client_list) do
        -- 检查客户端是否已完成初始化
        -- server_capabilities 只有在 LSP 初始化完成后才会被设置
        if
            not client.server_capabilities
            or vim.tbl_isempty(client.server_capabilities)
        then
            table.insert(unready_clients, client.name or "unknown")
        end
    end

    if #unready_clients > 0 then
        local client_names = table.concat(unready_clients, ", ")
        return false,
            string.format(
                "LSP server(s) not ready yet: %s. Please wait a moment and try again.",
                client_names
            )
    end

    return true
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

    -- 获取支持该方法的客户端
    local clients = lsp.get_clients({
        bufnr = buffer_id,
        method = self._method.method,
    })

    -- 检查客户端是否就绪
    local ready, reason = self:CheckClientsReady(clients)
    if not ready then
        lib_notify.Warn(reason)
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

                -- 对结果进行排序
                if has_valid_result then
                    data = self:_sortLspResults(data)
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

                            -- 对调用层次结果进行排序
                            if not vim.tbl_isempty(data) then
                                data = self:_sortLspResults(data)

                                -- 对每个文件内的调用层次范围进行额外排序
                                for _, item in pairs(data) do
                                    self:_sortCallHierarchyRanges(item.range)
                                end
                            end

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

-- 修改处理调用层次结果的方法
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
                local new_range = {
                    start = range.start,
                    finish = range["end"],
                }

                -- 检查是否已存在相同的范围
                local is_duplicate = false
                for _, existing_range in ipairs(data[uri].range) do
                    if
                        self:_callHierarchyRangesEqual(
                            existing_range,
                            new_range
                        )
                    then
                        is_duplicate = true
                        break
                    end
                end

                -- 只有当不重复时才添加
                if not is_duplicate then
                    table.insert(data[uri].range, new_range)
                end
            end
        else
            -- 对于出站调用或没有 fromRanges 的入站调用，使用项目的选择范围或范围
            local range = item.selectionRange or item.range
            local new_range = {
                start = range.start,
                finish = range["end"],
            }

            -- 检查是否已存在相同的范围
            local is_duplicate = false
            for _, existing_range in ipairs(data[uri].range) do
                if
                    self:_callHierarchyRangesEqual(existing_range, new_range)
                then
                    is_duplicate = true
                    break
                end
            end

            -- 只有当不重复时才添加
            if not is_duplicate then
                table.insert(data[uri].range, new_range)
            end
        end
    end
end

-- 添加调用层次范围比较方法
---@private
---@param range1 table 第一个范围
---@param range2 table 第二个范围
---@return boolean 是否相等
function ClassLsp:_callHierarchyRangesEqual(range1, range2)
    return range1.start.line == range2.start.line
        and range1.start.character == range2.start.character
        and range1.finish.line == range2.finish.line
        and range1.finish.character == range2.finish.character
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
        local selection_range = lspRes.targetSelectionRange
            or lspRes.selectionRange
        local uri_buffer = vim.uri_to_bufnr(uri)

        if not data[uri] then
            data[uri] = {
                buffer_id = uri_buffer,
                fold = self._method.fold
                    and not tools.compare_uri(self._origin_uri, uri),
                range = {},
            }
        end

        -- 创建新的范围对象
        local new_range = {
            start = range.start,
            finish = range["end"],
            -- 新增：保存选择范围，用于精确跳转
            selection_start = selection_range and selection_range.start
                or range.start,
            selection_finish = selection_range and selection_range["end"]
                or range["end"],
        }

        -- 检查是否已存在相同的范围
        local is_duplicate = false
        for _, existing_range in ipairs(data[uri].range) do
            if self:_rangesEqual(existing_range, new_range) then
                is_duplicate = true
                break
            end
        end

        -- 只有当不重复时才添加（不在这里排序，统一在最后排序）
        if not is_duplicate then
            table.insert(data[uri].range, new_range)
        end
    end

    -- 处理单个结果或多个结果
    if result.uri then
        handle_result(result)
    elseif tools.islist(result) then
        for _, response in ipairs(result) do
            handle_result(response)
        end
    end
end

-- 添加新的私有方法用于比较两个范围是否相等
---@private
---@param range1 table 第一个范围
---@param range2 table 第二个范围
---@return boolean 是否相等
function ClassLsp:_rangesEqual(range1, range2)
    -- 比较主要范围
    local main_equal = range1.start.line == range2.start.line
        and range1.start.character == range2.start.character
        and range1.finish.line == range2.finish.line
        and range1.finish.character == range2.finish.character

    -- 比较选择范围
    local selection_equal = range1.selection_start.line
            == range2.selection_start.line
        and range1.selection_start.character == range2.selection_start.character
        and range1.selection_finish.line == range2.selection_finish.line
        and range1.selection_finish.character
            == range2.selection_finish.character

    return main_equal and selection_equal
end

--- 对 LSP 结果进行排序
---@private
---@param data LspUIPositionWrap 要排序的数据
---@return LspUIPositionWrap 排序后的数据
function ClassLsp:_sortLspResults(data)
    -- 创建一个包含 URI 和数据的数组用于排序
    local sorted_entries = {}

    for uri, item in pairs(data) do
        table.insert(sorted_entries, {
            uri = uri,
            data = item,
            filename = vim.fn.fnamemodify(vim.uri_to_fname(uri), ":t"), -- 提取文件名用于排序
            filepath = vim.uri_to_fname(uri), -- 完整路径作为备用排序键
        })
    end

    -- 按文件名排序
    table.sort(sorted_entries, function(a, b)
        -- 首先按文件名排序
        if a.filename ~= b.filename then
            return a.filename < b.filename
        end
        -- 如果文件名相同，按完整路径排序
        return a.filepath < b.filepath
    end)

    -- 对每个文件内的范围进行排序
    for _, entry in ipairs(sorted_entries) do
        self:_sortRangesInFile(entry.data.range)
    end

    -- 重新构建有序的数据结构
    local sorted_data = {}
    for _, entry in ipairs(sorted_entries) do
        sorted_data[entry.uri] = entry.data
    end

    return sorted_data
end

--- 对单个文件内的范围进行排序
---@private
---@param ranges LspUIRange[] 要排序的范围数组
function ClassLsp:_sortRangesInFile(ranges)
    table.sort(ranges, function(a, b)
        -- 首先按行号排序
        if a.start.line ~= b.start.line then
            return a.start.line < b.start.line
        end

        -- 同一行内按字符位置排序
        if a.start.character ~= b.start.character then
            return a.start.character < b.start.character
        end

        -- 如果起始位置相同，按结束位置排序
        if a.finish.line ~= b.finish.line then
            return a.finish.line < b.finish.line
        end

        return a.finish.character < b.finish.character
    end)
end

--- 对调用层次结果进行排序（重载方法）
---@private
---@param ranges table[] 调用层次范围数组
function ClassLsp:_sortCallHierarchyRanges(ranges)
    table.sort(ranges, function(a, b)
        -- 首先按行号排序
        if a.start.line ~= b.start.line then
            return a.start.line < b.start.line
        end

        -- 同一行内按字符位置排序
        return a.start.character < b.start.character
    end)
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

    -- 检查客户端是否就绪
    local ready, reason = self:CheckClientsReady(clients)
    if not ready then
        lib_notify.Warn(reason)
        return false, reason
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
                    require("LspUI.layer.notify").Warn(
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
        require("LspUI.layer.notify").Warn(
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

    -- 检查客户端是否就绪
    local ready, reason = self:CheckClientsReady(clients)
    if not ready then
        callback(false, nil, reason)
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
                            callback(
                                false,
                                nil,
                                "This position cannot be renamed"
                            )
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
