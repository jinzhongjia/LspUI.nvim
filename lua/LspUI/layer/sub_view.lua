-- this file is just for secondary view
local api, fn = vim.api, vim.fn
local ClassView = require("LspUI.layer.view")
local syntax_highlight = require("LspUI.layer.syntax_highlight")

--- @class ClassSubView: ClassView
--- @field _data LspUIPositionWrap
--- @field _method_name string
local ClassSubView = {}

local subViewNamespace = api.nvim_create_namespace("LspUISubView")

setmetatable(ClassSubView, ClassView)
ClassSubView.__index = ClassSubView

--- @class LspUIRange
--- @field lnum integer
--- @field col integer
--- @field end_col integer
--- @field start lsp.Position
--- @field finish lsp.Position

--- @class LspUIPosition
--- @field buffer_id integer
--- @field fold boolean
--- @field range LspUIRange[]

--- @alias LspUIPositionWrap  { [lsp.URI]: LspUIPosition}

--- @param createBuf boolean
--- @return ClassSubView
function ClassSubView:New(createBuf)
    --- @type ClassView
    local view = ClassView:New(createBuf)
    --- @type ClassSubView
    --- @diagnostic disable-next-line: assign-type-mismatch
    local obj = setmetatable(view, self)
    obj._config = {}
    obj._config.style = "minimal"
    return obj
end

-- pin the buffer
--- @return ClassSubView
function ClassSubView:PinBuffer()
    if not self:Valid() then
        return self
    end
    api.nvim_set_option_value("winfixbuf", true, { win = self._windowId })
    return self
end

-- unpin the buffer
--- @return ClassSubView
function ClassSubView:UnPinBuffer()
    if not self:Valid() then
        return self
    end
    api.nvim_set_option_value("winfixbuf", false, { win = self._windowId })
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

--- 为子视图应用代码语法高亮
--- @param code_regions table<string, {line:integer, col_start:integer, col_end:integer}[]>
--- @return ClassSubView
function ClassSubView:ApplySyntaxHighlight(code_regions)
    if not self:BufVaild() then
        return self
    end

    -- 检查是否有数据
    if not code_regions or vim.tbl_isempty(code_regions) then
        return self
    end

    -- 格式化数据为treesitter需要的格式
    local regions = {}

    for lang, entries in pairs(code_regions) do
        if lang and lang ~= "" then
            regions[lang] = {}

            for i, entry in ipairs(entries) do
                -- 验证条目数据
                if entry.line and entry.col_start and entry.col_end then
                    -- 使用Treesitter兼容的格式
                    table.insert(regions[lang], {
                        { entry.line, entry.col_start }, -- [start_row, start_col]
                        { entry.line, entry.col_end }, -- [end_row, end_col]
                    })
                end
            end
        end
    end

    -- 应用语法高亮
    if not vim.tbl_isempty(regions) then
        require("LspUI.layer.syntax_highlight").attach(self:GetBufID(), regions)
    end

    return self
end

-- 添加方法用于移除语法高亮
--- 清除子视图的语法高亮
--- @return ClassSubView
function ClassSubView:ClearSyntaxHighlight()
    if not self:BufVaild() then
        return self
    end

    syntax_highlight.detach(self:GetBufID())
    return self
end

return ClassSubView
