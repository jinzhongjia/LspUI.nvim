-- this file is just for secondary view
local api = vim.api
local ClassView = require("LspUI.layer.view")

--- @class ClassSubView: ClassView
--- @field _data LspUIPositionWrap
--- @field _method_name string
local ClassSubView = {}

local subViewNamespace = api.nvim_create_namespace("LspUISubView")

setmetatable(ClassSubView, ClassView)
ClassSubView.__index = ClassSubView

--- @alias LspUIRange { start: lsp.Position, finish: lsp.Position }
--- @alias LspUIPosition  { buffer_id: integer, fold: boolean, range: LspUIRange[]}
--- @alias LspUIPositionWrap  { [lsp.URI]: LspUIPosition}

--- @param createBuf boolean
--- @return ClassSubView
function ClassSubView:New(createBuf)
    --- @type ClassView
    local view = ClassView:New(createBuf)
    --- @type ClassSubView
    --- @diagnostic disable-next-line: assign-type-mismatch
    local obj = setmetatable(view, self)
    obj._config.style = "minimal"
    return obj
end

-- pin the buffer
--- @return ClassSubView
function ClassSubView:PinBuffer()
    if not self:Valid() then
        return self
    end
    api.nvim_set_option_value("winfibuf", true, { win = self._windowId })
    return self
end

-- unpin the buffer
--- @return ClassSubView
function ClassSubView:UnPinBuffer()
    if not self:Valid() then
        return self
    end
    api.nvim_set_option_value("winfibuf", false, { win = self._windowId })
    return self
end

--- @param nameSpace integer
--- @return ClassSubView
function ClassSubView:ClearHl(nameSpace)
    if not self:BufVaild() then
        return self
    end
    api.nvim_buf_clear_namespace(self._attachBuffer, nameSpace, 0, -1)
    return self
end

--- @param nameSpace integer
--- @param hlGroup string
--- @param lnum integer
--- @param col integer
--- @param endCol integer
function ClassSubView:AddHl(nameSpace, hlGroup, lnum, col, endCol)
    if not self:BufVaild() then
        return self
    end
    vim.hl.range(
        self._attachBuffer,
        nameSpace,
        hlGroup,
        { lnum, col },
        { lnum, endCol }
    )
    return self
end

-- 渲染 buffer 内容
function ClassSubView:BufRender()
    if self:BufVaild() then
        -- 如果 buffer 有效

        return
    end
    self:BufOption("modifiable", true)
    self:BufOption("filetype", string.format("LspUI-%s",self._method_name))
end

return ClassSubView
