-- lua/LspUI/interface.lua (新文件，提供简洁的公共接口)
local ClassController = require("LspUI.layer.controller")

local M = {}

-- 存储不同方法的控制器实例
local controllers = {}

---@param method_name string 方法名称
---@param bufnr integer 缓冲区号
---@param params table LSP请求参数
function M.go(method_name, bufnr, params)
    -- 创建新的控制器实例
    controllers[method_name] = ClassController:New()
    controllers[method_name]:Go(method_name, bufnr, params)
end

-- 定义、声明、引用等方法的快捷接口
function M.definition(bufnr, params)
    M.go("definition", bufnr, params)
end

function M.type_definition(bufnr, params)
    M.go("type_definition", bufnr, params)
end

function M.declaration(bufnr, params)
    M.go("declaration", bufnr, params)
end

function M.reference(bufnr, params)
    M.go("reference", bufnr, params)
end

function M.implementation(bufnr, params)
    M.go("implementation", bufnr, params)
end

-- 关闭所有控制器
function M.close_all()
    for _, controller in pairs(controllers) do
        controller:ActionQuit()
    end
    controllers = {}
end

return M
