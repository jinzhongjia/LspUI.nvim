-- lua/LspUI/interface.lua (新文件，提供简洁的公共接口)
local ClassController = require("LspUI.layer.controller")

local M = {}

-- 当前全局控制器实例引用（便于在本模块内缓存）
---@type ClassController?
local active_controller

---@return ClassController
local function ensure_controller()
    if not active_controller then
        active_controller = ClassController.GetInstance()
    end
    ---@cast active_controller ClassController
    return active_controller
end

---@param method_name string 方法名称（参考 ClassLsp.methods 的 key）
---@param bufnr integer 缓冲区号
---@param params lsp.TextDocumentPositionParams LSP请求参数
function M.go(method_name, bufnr, params)
    local controller = ensure_controller()
    controller:Go(method_name, bufnr, params)
end

---@param bufnr integer
---@param params lsp.TextDocumentPositionParams
function M.definition(bufnr, params)
    M.go("definition", bufnr, params)
end

---@param bufnr integer
---@param params lsp.TextDocumentPositionParams
function M.type_definition(bufnr, params)
    M.go("type_definition", bufnr, params)
end

---@param bufnr integer
---@param params lsp.TextDocumentPositionParams
function M.declaration(bufnr, params)
    M.go("declaration", bufnr, params)
end

---@param bufnr integer
---@param params lsp.TextDocumentPositionParams
function M.reference(bufnr, params)
    M.go("reference", bufnr, params)
end

---@param bufnr integer
---@param params lsp.TextDocumentPositionParams
function M.implementation(bufnr, params)
    M.go("implementation", bufnr, params)
end

--- 关闭所有视图并销毁控制器实例
function M.close_all()
    local controller = ClassController.GetInstance(false)
    if controller and controller:IsActive() then
        controller:ActionQuit()
    end
    ClassController.ResetInstance()
    active_controller = nil
end

return M
