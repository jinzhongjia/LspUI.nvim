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
        lib_notify.Error("不支持的LSP方法: " .. method_name)
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
        lib_notify.Error("请先设置LSP方法")
        return
    end

    self._origin_uri = vim.uri_from_bufnr(buffer_id)
    self._datas = {}

    -- 发送LSP请求
    lsp.buf_request_all(
        buffer_id,
        self._method.method,
        params,
        function(results, _, _)
            if not api.nvim_buf_is_valid(buffer_id) then
                return
            end

            local data = {}

            -- 处理LSP响应数据
            for _, result in pairs(results) do
                if result and not vim.tbl_isempty(result) then
                    self:_processLspResult(result.result, data)
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

---@private
---@param result table LSP响应结果
---@param data LspUIPositionWrap 处理结果存放表
function ClassLsp:_processLspResult(result, data)
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
    else
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

return ClassLsp
