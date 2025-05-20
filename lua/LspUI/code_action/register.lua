local lib_notify = require("LspUI.layer.notify")

local M = {}

--- @type {[string]:fun(uri:lsp.URI,range:lsp.Range):{title:string,action:function}[]}
local list = {}

--- @param name string
--- @param callback fun(uri:lsp.URI,range:lsp.Range):{title:string,action:function}[]
function M.register(name, callback)
    if list[name] then
        -- stylua: ignore
        lib_notify.Error(string.format("the name %s of code action has been registered!", name))
        return
    end
    list[name] = callback
end

--- @param name string
function M.unregister(name)
    list[name] = nil
end

--- @param uri lsp.URI
--- @param range lsp.Range
--- @return {title:string,action:function}[]
function M.handle(uri, range)
    local result = {}
    for _, callback in pairs(list) do
        if callback then
            local res = callback(uri, range)
            for _, val in pairs(res) do
                table.insert(result, val)
            end
        end
    end
    return result
end

return M
