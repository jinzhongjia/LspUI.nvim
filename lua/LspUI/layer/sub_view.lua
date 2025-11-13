-- this file is just for secondary view
local api, fn = vim.api, vim.fn
local ClassView = require("LspUI.layer.view")
local keyword_highlight = require("LspUI.layer.keyword_highlight")
local source_highlight = require("LspUI.layer.source_highlight")

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
    if not self:BufValid() then
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
    if not self:BufValid() then
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
--- 优先使用源文件的 Treesitter 高亮，fallback 到关键字匹配
--- @param code_regions table<string, {line:integer, col_start:integer, col_end:integer, source_buf:integer?, source_line:integer?, source_col_offset:integer?}[]>
--- @return ClassSubView
function ClassSubView:ApplySyntaxHighlight(code_regions)
    if not self:BufValid() then
        return self
    end

    local bufid = self:GetBufID()

    -- 检查是否有数据
    if not code_regions or vim.tbl_isempty(code_regions) then
        return self
    end

    -- 为每种语言应用高亮
    for lang, entries in pairs(code_regions) do
        if lang and lang ~= "" then
            local keyword_regions = {}
            local has_treesitter = false

            -- 处理每个条目
            for _, entry in ipairs(entries) do
                if entry.line and entry.col_start and entry.col_end then
                    -- 尝试使用源文件的 Treesitter 高亮
                    local used_treesitter = false
                    if entry.source_buf and entry.source_line then
                        -- 使用 controller 提供的源文件列偏移（trim掉的前导空格）
                        local source_offset = entry.source_col_offset or 0
                        used_treesitter = source_highlight.apply_highlights(
                            bufid,
                            entry.line,
                            entry.col_start,
                            entry.col_end,
                            entry.source_buf,
                            entry.source_line,
                            source_offset
                        )
                    end

                    -- 如果 Treesitter 不可用，收集起来用关键字高亮
                    if not used_treesitter then
                        table.insert(keyword_regions, {
                            { entry.line, entry.col_start },
                            { entry.line, entry.col_end },
                        })
                    else
                        has_treesitter = true
                    end
                end
            end

            -- 对于没有 Treesitter 高亮的行，使用关键字高亮作为 fallback
            if #keyword_regions > 0 then
                keyword_highlight.apply(bufid, lang, keyword_regions)
            end
        end
    end

    return self
end

-- 清除子视图的语法高亮
--- @param languages? table<string, boolean> 要清除的语言列表，如果为nil则不清除
--- @return ClassSubView
function ClassSubView:ClearSyntaxHighlight(languages)
    if not self:BufValid() then
        return self
    end

    local bufid = self:GetBufID()

    -- 清除源文件 Treesitter 高亮的命名空间
    local source_ns = api.nvim_create_namespace("LspUI_source_highlight")
    api.nvim_buf_clear_namespace(bufid, source_ns, 0, -1)

    -- 如果提供了语言列表，逐个清除关键字高亮
    if languages then
        for lang, _ in pairs(languages) do
            keyword_highlight.clear(bufid, lang)
        end
    end

    return self
end

return ClassSubView
