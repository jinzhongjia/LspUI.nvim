local lib_notify = require("LspUI.lib.notify")

local M = {}

--- @type {[string]:fun(uri:lsp.URI,range:lsp.Range):{title:string,action:function}[]}
local list = {}

-- title and callback
--- @param name string
--- @param callback fun(uri:lsp.URI,range:lsp.Range):{title:string,action:function}[]
function M.register(name, callback)
    if not list[name] then
        list[name] = callback
    else
        lib_notify.Error(
            string.format(
                "the name %s of code action has been registered!",
                name
            )
        )
    end
end

--- @param name string
function M.unregister(name)
    if list[name] then
        list[name] = nil
    end
end

--- @param uri lsp.URI
--- @param range lsp.Range
--- @return {title:string,action:function}[]
function M.handle(uri, range)
    --- @type {title:string,action:function}[]
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
