local api = vim.api
local ClassView = require("LspUI.layer.view")

--- @class ClassSubView: ClassView
local ClassSubView = {}

setmetatable(ClassSubView, ClassView)
ClassSubView.__index = ClassSubView

--- @param create_buf boolean
--- @return ClassSubView
function ClassSubView:New(create_buf)
    --- @type ClassView
    local view = ClassView:New(create_buf)
    --- @type ClassSubView
    --- @diagnostic disable-next-line: assign-type-mismatch
    local obj = setmetatable(view, self)
    obj._config.style = "minimal"
    return obj
end

-- pin the buffer
function ClassSubView:PinBuffer()
    if not self:Valid() then
        return
    end
    api.nvim_set_option_value("winfibuf", true, { win = self._windowId })
end

-- unpin the buffer
function ClassSubView:UnPinBuffer()
    if not self:Valid() then
        return
    end
    api.nvim_set_option_value("winfibuf", false, { win = self._windowId })
end

return ClassSubView
