-- this file is just for secondary view
local api, fn = vim.api, vim.fn
local ClassView = require("LspUI.layer.view")
local tools = require("LspUI.layer.tools")

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

--- 将 SubView 与 MainView 绑定，设置正确的z-index层级关系
--- @param mainView ClassMainView MainView实例
--- @return ClassSubView
function ClassSubView:BindWithMainView(mainView)
    -- 调用基础绑定方法
    self:BindView(mainView)

    -- 设置正确的z-index，确保SubView在MainView之上
    if self:Valid() and mainView:Valid() then
        local mainWinId = mainView:GetWinID()
        local subWinId = self:GetWinID()
        if mainWinId and subWinId then
            api.nvim_win_set_config(mainWinId, { zindex = 50 })
            api.nvim_win_set_config(subWinId, { zindex = 100 })
        end
    end

    return self
end

-- 渲染 buffer 内容
-- function ClassSubView:BufRender()
--     if self:BufVaild() then
--         -- 如果 buffer 有效
--         -- 清理掉之前的高亮
--         self:ClearHl(subViewNamespace)
--     else
--         -- 新创建一个 buffer
--         self._attachBuffer = api.nvim_create_buf(false, true)
--     end
--     -- 允许修改 buffer
--     self:BufOption("modifiable", true)
--     self:BufOption("filetype", string.format("LspUI-%s", self._method_name))
--
--     -- hl_num for highlight lnum recording
--     local hl_num = 0
--     -- this array stores the highlighted line number
--     local hl = {}
--
--     -- the buffer's new content
--     local content = {}
--
--     -- calculate the max width that we need
--     local max_width = 0
--     -- calculate the height for render
--     local height = 0
--
--     for uri, data in pairs(self._data) do
--         -- get full file name
--         local file_full_name = vim.uri_to_fname(uri)
--         -- get file name
--         local file_fmt = string.format(
--             " %s %s",
--             data.fold and "" or "",
--             fn.fnamemodify(file_full_name, ":t")
--         )
--
--         table.insert(content, file_fmt)
--
--         height = height + 1
--
--         hl_num = hl_num + 1
--         table.insert(hl, hl_num)
--
--         -- get file_fmt length
--         local file_fmt_len = fn.strdisplaywidth(file_fmt)
--
--         -- detect max width
--         if file_fmt_len > max_width then
--             max_width = file_fmt_len
--         end
--
--         local uri_rows = {}
--         do
--             for _, range in ipairs(data.range) do
--                 local row = range.start.line
--                 table.insert(uri_rows, row)
--             end
--         end
--
--         local lines = tools.GetUriLines(data.buffer_id, uri, uri_rows)
--         for _, row in pairs(uri_rows) do
--             local line_code = fn.trim(lines[row])
--             local code_fmt = string.format("   %s", line_code)
--             if not data.fold then
--                 table.insert(content, code_fmt)
--                 hl_num = hl_num + 1
--             end
--             height = height + 1
--
--             local code_fmt_length = fn.strdisplaywidth(code_fmt)
--
--             if code_fmt_length > max_width then
--                 max_width = code_fmt_length
--             end
--         end
--     end
--
--     self:BufContent(0, -1, content)
--
--     for _, lnum in pairs(hl) do
--         self:AddHl(subViewNamespace, "Directory", lnum - 1, 3, -1)
--     end
--
--     -- disable change for this buffer
--     self:BufOption("modifiable", false)
--
--     local res_width = max_width + 2 > 30 and 30 or max_width + 2
--
--     local max_columns =
--         math.floor(api.nvim_get_option_value("columns", {}) * 0.3)
--
--     if max_columns > res_width then
--         res_width = max_columns
--     end
--
--     self:Size(res_width, height + 1)
-- end

return ClassSubView
