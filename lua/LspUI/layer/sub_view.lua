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

--- 为子视图应用代码语法高亮（异步）
--- 优先使用源文件的 Treesitter 高亮，fallback 到关键字匹配
--- 只按需加载需要高亮的源文件，避免加载所有文件
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

    -- 智能高亮策略：
    -- 1. 已加载的源文件：立即应用 Treesitter 高亮（同步，快速）
    -- 2. 未加载的源文件：先应用关键字高亮，再异步加载并应用 Treesitter

    -- 第一遍：处理所有条目，区分已加载和未加载
    local lang_keyword_regions = {}  -- 未加载文件的关键字高亮
    local pending_entries = {}       -- 需要异步加载的条目

    for lang, entries in pairs(code_regions) do
        if lang and lang ~= "" then
            for _, entry in ipairs(entries) do
                if entry.line and entry.col_start and entry.col_end then
                    local used_treesitter = false

                    -- 如果源 buffer 存在且已加载，立即应用 Treesitter 高亮
                    if entry.source_buf and entry.source_line then
                        if api.nvim_buf_is_valid(entry.source_buf)
                            and api.nvim_buf_is_loaded(entry.source_buf) then
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
                        else
                            -- 源 buffer 未加载，记录下来稍后异步处理
                            if not pending_entries[lang] then
                                pending_entries[lang] = {}
                            end
                            table.insert(pending_entries[lang], entry)
                        end
                    end

                    -- 如果没有使用 Treesitter，收集到关键字高亮
                    if not used_treesitter then
                        if not lang_keyword_regions[lang] then
                            lang_keyword_regions[lang] = {}
                        end
                        table.insert(lang_keyword_regions[lang], {
                            { entry.line, entry.col_start },
                            { entry.line, entry.col_end },
                        })
                    end
                end
            end
        end
    end

    -- 立即应用关键字高亮（为未加载的源文件提供快速反馈）
    for lang, regions in pairs(lang_keyword_regions) do
        if #regions > 0 then
            keyword_highlight.apply(bufid, lang, regions)
        end
    end

    -- 异步加载未加载的源文件并应用 Treesitter 高亮
    if not vim.tbl_isempty(pending_entries) then
        vim.schedule(function()
            -- 再次检查 buffer 是否仍然有效
            if not api.nvim_buf_is_valid(bufid) then
                return
            end

            for lang, entries in pairs(pending_entries) do
                for _, entry in ipairs(entries) do
                    if api.nvim_buf_is_valid(entry.source_buf) then
                        -- 异步加载源文件
                        if not api.nvim_buf_is_loaded(entry.source_buf) then
                            pcall(vim.fn.bufload, entry.source_buf)
                        end

                        -- 如果加载成功，应用 Treesitter 高亮（覆盖关键字高亮）
                        if api.nvim_buf_is_loaded(entry.source_buf) then
                            local source_offset = entry.source_col_offset or 0
                            source_highlight.apply_highlights(
                                bufid,
                                entry.line,
                                entry.col_start,
                                entry.col_end,
                                entry.source_buf,
                                entry.source_line,
                                source_offset
                            )
                        end
                    end
                end
            end
        end)
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
