-- lua/LspUI/layer/controller.lua (修复版本)
local api = vim.api
local ClassLsp = require("LspUI.layer.lsp")
local ClassMainView = require("LspUI.layer.main_view")
local ClassSubView = require("LspUI.layer.sub_view")
local config = require("LspUI.config")
local lib_notify = require("LspUI.layer.notify")
local lib_util = require("LspUI.lib.util")
local tools = require("LspUI.layer.tools")

---@class ClassController
---@field _lsp ClassLsp
---@field _mainView ClassMainView
---@field _subView ClassSubView
---@field _current_item {uri: string, buffer_id: integer, range: LspUIRange?}
---@field _push_tagstack function|nil
local ClassController = {
    ---@diagnostic disable-next-line: assign-type-mismatch
    _lsp = nil,
    ---@diagnostic disable-next-line: assign-type-mismatch
    _mainView = nil,
    ---@diagnostic disable-next-line: assign-type-mismatch
    _subView = nil,
    _current_item = {},
    _push_tagstack = nil,
}

ClassController.__index = ClassController

---@return ClassController
function ClassController:New()
    local obj = {}
    setmetatable(obj, self)

    obj._lsp = ClassLsp:New()
    obj._mainView = ClassMainView:New(false)
    obj._subView = ClassSubView:New(true)

    api.nvim_create_augroup("LspUI_SubView", { clear = true })

    return obj
end

---@private
---@return integer width, integer height
function ClassController:_generateSubViewContent()
    local data = self._lsp:GetData()
    local bufId = self._subView:GetBufID()

    if not bufId or not api.nvim_buf_is_valid(bufId) then
        bufId = api.nvim_create_buf(false, true)
        self._subView:SwitchBuffer(bufId)
    end

    -- 允许修改缓冲区
    api.nvim_set_option_value("modifiable", true, { buf = bufId })

    -- 设置文件类型
    local method = self._lsp:GetMethod()
    api.nvim_set_option_value(
        "filetype",
        string.format("LspUI-%s", method.name),
        { buf = bufId }
    )

    -- 初始化变量
    local hl_num = 0
    local hl = {}
    local content = {}
    local max_width = 0
    local height = 0

    -- 生成内容
    for uri, item in pairs(data) do
        -- 文件名格式化
        local file_full_name = vim.uri_to_fname(uri)
        local file_fmt = string.format(
            " %s %s",
            item.fold and "" or "",
            vim.fn.fnamemodify(file_full_name, ":t")
        )

        table.insert(content, file_fmt)
        height = height + 1

        -- 记录高亮行
        hl_num = hl_num + 1
        table.insert(hl, hl_num)

        -- 更新最大宽度
        local file_fmt_len = vim.fn.strdisplaywidth(file_fmt)
        if file_fmt_len > max_width then
            max_width = file_fmt_len
        end

        -- 收集行号
        local uri_rows = {}
        for _, range in ipairs(item.range) do
            table.insert(uri_rows, range.start.line)
        end

        -- 获取代码行内容
        local lines = tools.GetUriLines(item.buffer_id, uri, uri_rows)
        for _, row in pairs(uri_rows) do
            local line_code = vim.fn.trim(lines[row])
            local code_fmt = string.format("   %s", line_code)

            -- 如果未折叠，添加到内容
            if not item.fold then
                table.insert(content, code_fmt)
                hl_num = hl_num + 1
            end

            height = height + 1

            -- 更新最大宽度
            local code_fmt_length = vim.fn.strdisplaywidth(code_fmt)
            if code_fmt_length > max_width then
                max_width = code_fmt_length
            end
        end
    end

    -- 设置内容和高亮
    api.nvim_buf_set_lines(bufId, 0, -1, true, content)

    local subViewNamespace = api.nvim_create_namespace("LspUISubView")
    api.nvim_buf_clear_namespace(bufId, subViewNamespace, 0, -1)

    for _, lnum in pairs(hl) do
        vim.api.nvim_buf_add_highlight(
            bufId,
            subViewNamespace,
            "Directory",
            lnum - 1,
            3,
            -1
        )
    end

    -- 禁止修改
    api.nvim_set_option_value("modifiable", false, { buf = bufId })

    -- 计算适当的宽度
    local res_width = max_width + 2 > 30 and 30 or max_width + 2
    local max_columns =
        math.floor(api.nvim_get_option_value("columns", {}) * 0.3)

    if max_columns > res_width then
        res_width = max_columns
    end

    return res_width, height + 1
end

---@private
function ClassController:_setupSubViewKeyBindings()
    local buf = self._subView:GetBufID()
    if not buf then
        return
    end

    local keyBindings = {
        [config.options.pos_keybind.secondary.jump] = function()
            self:ActionJump()
        end,
        [config.options.pos_keybind.secondary.jump_tab] = function()
            self:ActionJump("tabe")
        end,
        [config.options.pos_keybind.secondary.jump_split] = function()
            self:ActionJump("split")
        end,
        [config.options.pos_keybind.secondary.jump_vsplit] = function()
            self:ActionJump("vsplit")
        end,
        [config.options.pos_keybind.secondary.toggle_fold] = function()
            self:ActionToggleFold()
        end,
        [config.options.pos_keybind.secondary.next_entry] = function()
            self:ActionNextEntry()
        end,
        [config.options.pos_keybind.secondary.prev_entry] = function()
            self:ActionPrevEntry()
        end,
        [config.options.pos_keybind.secondary.quit] = function()
            self:ActionQuit()
        end,
        [config.options.pos_keybind.secondary.hide_main] = function()
            self:ActionToggleMainView()
        end,
        [config.options.pos_keybind.secondary.fold_all] = function()
            self:ActionFoldAll(true)
        end,
        [config.options.pos_keybind.secondary.expand_all] = function()
            self:ActionFoldAll(false)
        end,
        [config.options.pos_keybind.secondary.enter] = function()
            self:ActionEnterMainView()
        end,
    }

    for key, callback in pairs(keyBindings) do
        api.nvim_buf_set_keymap(buf, "n", key, "", {
            nowait = true,
            noremap = true,
            callback = callback,
        })
    end

    -- 设置光标移动事件
    self._subView:BufAutoCmd("CursorMoved", "LspUI_SubView", function()
        self:_onCursorMoved()
    end, "跟踪光标移动")
end

---@private
function ClassController:_setupMainViewKeyBindings()
    local buf = self._mainView:GetBufID()
    if not buf then
        return
    end

    local keyBindings = {
        [config.options.pos_keybind.main.back] = function()
            self:ActionBackToSubView()
        end,
        [config.options.pos_keybind.main.hide_secondary] = function()
            self:ActionToggleSubView()
        end,
    }

    for key, callback in pairs(keyBindings) do
        api.nvim_buf_set_keymap(buf, "n", key, "", {
            nowait = true,
            noremap = true,
            callback = callback,
        })
    end
end

---@private
function ClassController:_onCursorMoved()
    local lnum = vim.fn.line(".")
    local uri, range = self:_getLspPositionByLnum(lnum)

    if not uri then
        return
    end

    -- 设置当前项目
    self._current_item = {
        uri = uri,
        buffer_id = self._lsp:GetData()[uri].buffer_id,
        range = range,
    }

    if range and self._mainView:Valid() then
        -- 切换主视图缓冲区
        local bufId = self._lsp:GetData()[uri].buffer_id
        self._mainView:SwitchBuffer(bufId)

        -- 设置光标位置
        local win = self._mainView:GetWinID()
        if win then
            api.nvim_win_set_cursor(
                win,
                { range.start.line + 1, range.start.character }
            )

            -- 居中显示
            api.nvim_win_call(win, function()
                vim.cmd("norm! zv")
                vim.cmd("norm! zz")
            end)
        end
    end
end

---@private
---@param lnum integer
---@return string? uri, LspUIRange? range
function ClassController:_getLspPositionByLnum(lnum)
    local data = self._lsp:GetData()
    for uri, item in pairs(data) do
        lnum = lnum - 1
        if lnum == 0 then
            return uri, nil
        end
        if not item.fold then
            for _, val in pairs(item.range) do
                lnum = lnum - 1
                if lnum == 0 then
                    return uri, val
                end
            end
        end
    end
    return nil, nil
end

---@private
---@param uri string
---@return integer lnum 光标应放置的行号
function ClassController:_getCursorPosForUri(uri)
    local lnum = 0
    for currentUri, data in pairs(self._lsp:GetData()) do
        lnum = lnum + 1
        if currentUri == uri then
            return lnum
        end
        if not data.fold then
            for _, _ in pairs(data.range) do
                lnum = lnum + 1
            end
        end
    end

    -- 默认返回值
    local method = self._lsp:GetMethod()
    if method and method.fold then
        return 1
    end
    return 2
end

-- 公开API开始
---@param method_name string
---@param buffer_id integer
---@param params table
function ClassController:Go(method_name, buffer_id, params)
    -- 设置方法
    if not self._lsp:SetMethod(method_name) then
        return
    end

    -- 保存标签栈
    self._push_tagstack = lib_util.create_push_tagstack(0)

    -- 发起LSP请求
    self._lsp:Request(buffer_id, params, function(data)
        if not data or vim.tbl_isempty(data) then
            lib_notify.Info(string.format("找不到%s", method_name))
            return
        end

        -- 初始化视图
        self:RenderViews()

        -- 绑定键映射
        self:_setupSubViewKeyBindings()

        -- 设置光标位置
        local win = self._subView:GetWinID()
        if win then
            api.nvim_set_current_win(win)
            local lnum = self:_findPositionFromParams(params)
            api.nvim_win_set_cursor(win, { lnum, 0 })
        end
    end)
end

function ClassController:RenderViews()
    -- 创建副视图
    local width, height = self:_generateSubViewContent()

    self._subView:Updates(function()
        self._subView
            :Border("single")
            :Style("minimal")
            :Relative("editor")
            :Size(width, height)
            :Pos(0, api.nvim_get_option_value("columns", {}) - width - 2)
            :Winbl(config.options.pos_keybind.transparency)
            :Title(self._lsp:GetMethod().name, "center")
    end)

    self._subView:Render()

    -- 获取第一个URI对应的缓冲区作为MainView的初始缓冲区
    local firstBuffer = nil
    for _, item in pairs(self._lsp:GetData()) do
        firstBuffer = item.buffer_id
        break
    end

    -- 创建主视图，确保设置了初始缓冲区
    if firstBuffer then
        self._mainView:SwitchBuffer(firstBuffer)

        self._mainView:Updates(function()
            self
                ._mainView
                :Border("none")
                -- :Style("minimal")
                :Relative("editor")
                :Size(
                    api.nvim_get_option_value("columns", {}) - 2,
                    api.nvim_get_option_value("lines", {}) - 2
                )
                :Pos(0, 0)
                :Winbl(config.options.pos_keybind.transparency)
        end)

        self._mainView:Render()

        -- 建立双向绑定
        self._mainView:BindView(self._subView)
        self._subView:SetZIndex(100)

        -- 初始化主视图键绑定
        self:_setupMainViewKeyBindings()
    else
        -- 如果找不到初始缓冲区，记录警告
        lib_notify.Warn("找不到可用的缓冲区来初始化主视图")
    end
end

---@param cmd string|nil 可选的跳转命令
function ClassController:ActionJump(cmd)
    if not self._current_item.uri then
        return
    end

    -- 保存当前项目
    local item = self._current_item

    -- 执行标签栈
    if self._push_tagstack then
        self._push_tagstack()
    end

    -- 关闭视图
    self._subView:Destory() -- 会同时销毁绑定的mainView

    -- 执行跳转
    if item.range then
        -- 打开新窗口或标签页
        if cmd then
            if cmd == "tabe" then
                vim.cmd("tab split")
            else
                vim.cmd(cmd)
            end
        end

        -- 打开文件
        if lib_util.buffer_is_listed(item.buffer_id) then
            vim.cmd(string.format("buffer %s", item.buffer_id))
        else
            vim.cmd(
                string.format(
                    "edit %s",
                    vim.fn.fnameescape(vim.uri_to_fname(item.uri))
                )
            )
        end

        -- 设置光标位置
        api.nvim_win_set_cursor(0, {
            item.range.start.line + 1,
            item.range.start.character,
        })
        vim.cmd("norm! zz")
    else
        -- 切换折叠状态
        self:ActionToggleFold()
    end
end

function ClassController:ActionToggleFold()
    if not self._current_item.uri then
        return
    end

    -- 切换折叠状态
    local data = self._lsp:GetData()
    local uri = self._current_item.uri

    if data[uri] then
        data[uri].fold = not data[uri].fold

        -- 重新渲染视图
        local width, height = self:_generateSubViewContent()
        self._subView:Size(width, height)
    end
end

function ClassController:ActionNextEntry()
    if not self._current_item.uri then
        return
    end

    local current_uri = self._current_item.uri
    local data = self._lsp:GetData()
    local found = false
    local line = 1

    -- 查找下一个项目
    for uri, item in pairs(data) do
        if found then
            api.nvim_win_set_cursor(self._subView:GetWinID(), { line, 0 })
            return
        end

        line = line + 1
        if not item.fold then
            line = line + #item.range
        end

        if uri == current_uri then
            found = true
        end
    end
end

function ClassController:ActionPrevEntry()
    if not self._current_item.uri then
        return
    end

    local current_uri = self._current_item.uri
    local data = self._lsp:GetData()
    local line = 1
    local prev_line = 1

    -- 查找上一个项目
    for uri, item in pairs(data) do
        if uri == current_uri then
            if prev_line < line then
                api.nvim_win_set_cursor(
                    self._subView:GetWinID(),
                    { prev_line, 0 }
                )
            end
            return
        end

        prev_line = line
        line = line + 1
        if not item.fold then
            line = line + #item.range
        end
    end
end

function ClassController:ActionQuit()
    -- 使用 Destory 会同时销毁两个视图，因为它们是绑定的
    self._subView:Destory()
end

function ClassController:ActionToggleMainView()
    if not self._mainView:Valid() then
        -- 如果数据存在则重新渲染
        local firstBuffer = nil
        for _, item in pairs(self._lsp:GetData()) do
            firstBuffer = item.buffer_id
            break
        end

        if firstBuffer then
            self._mainView:SwitchBuffer(firstBuffer)

            -- 更新配置
            self._mainView:Updates(function()
                self
                    ._mainView
                    :Border("none")
                    -- :Style("minimal")
                    :Relative("editor")
                    :Size(
                        api.nvim_get_option_value("columns", {}) - 2,
                        api.nvim_get_option_value("lines", {}) - 2
                    )
                    :Pos(0, 0)
                    :Winbl(config.options.pos_keybind.transparency)
            end)

            self._mainView:Render()
            self:_setupMainViewKeyBindings()

            -- 确保 z-index 正确
            if self._subView:Valid() then
                self._subView:SetZIndex(100)
            end
        end
    else
        -- 保存当前配置后隐藏
        self._mainView:SaveCurrentConfig():HideView()
    end
end

function ClassController:ActionToggleSubView()
    if not self._subView:Valid() then
        -- 先完全重新生成内容
        local width, height = self:_generateSubViewContent()

        -- 更新配置
        self._subView:Updates(function()
            self._subView
                :Border("single")
                :Style("minimal")
                :Relative("editor")
                :Size(width, height)
                :Pos(0, api.nvim_get_option_value("columns", {}) - width - 2)
                :Winbl(config.options.pos_keybind.transparency)
                :Title(self._lsp:GetMethod().name, "center")
        end)

        -- 渲染视图
        self._subView:Render()

        self._subView:SetZIndex(100)

        -- 恢复键映射
        self:_setupSubViewKeyBindings()

        -- 恢复光标位置
        if self._current_item and self._current_item.uri then
            local lnum = self:_getCursorPosForUri(self._current_item.uri)
            local win = self._subView:GetWinID()
            if win then
                api.nvim_win_set_cursor(win, { lnum, 0 })
            end
        end
    else
        -- 保存当前配置后隐藏
        self._subView:SaveCurrentConfig():HideView()
    end
end

---@param fold boolean 是否全部折叠
function ClassController:ActionFoldAll(fold)
    local current_uri = self._current_item.uri
    local data = self._lsp:GetData()
    local changed = false

    -- 修改所有项目的折叠状态
    for uri, item in pairs(data) do
        if item.fold ~= fold then
            item.fold = fold
            changed = true
        end
    end

    if changed then
        -- 重新渲染
        local width, height = self:_generateSubViewContent()
        self._subView:Size(width, height)

        -- 恢复光标位置
        local lnum = self:_getCursorPosForUri(current_uri)
        api.nvim_win_set_cursor(self._subView:GetWinID(), { lnum, 0 })
    end
end

function ClassController:ActionEnterMainView()
    if self._mainView:Valid() then
        self._mainView:Focus()
    end
end

function ClassController:ActionBackToSubView()
    if self._subView:Valid() then
        self._subView:Focus()
    end
end

---@private
---@param params table
---@return integer
function ClassController:_findPositionFromParams(params)
    local lnum = 0
    local param_uri = params.textDocument.uri

    local file_lnum = nil
    local code_lnum = nil
    local tmp = nil

    for uri, data in pairs(self._lsp:GetData()) do
        lnum = lnum + 1
        if not data.fold then
            for _, val in pairs(data.range) do
                lnum = lnum + 1
                if lib_util.compare_uri(uri, param_uri) then
                    if not file_lnum then
                        file_lnum = lnum
                    end
                    if val.start.line == params.position.line then
                        if tmp then
                            if
                                math.abs(
                                    val.start.character
                                        - params.position.character
                                ) < tmp
                            then
                                tmp = math.abs(
                                    val.start.character
                                        - params.position.character
                                )
                                code_lnum = lnum
                            end
                        else
                            tmp = math.abs(
                                val.start.character - params.position.character
                            )
                            code_lnum = lnum
                        end
                    end
                end
            end
        end
    end

    if code_lnum then
        return code_lnum
    end
    if file_lnum then
        return file_lnum
    end

    local method = self._lsp:GetMethod()
    if method and method.fold then
        return 1
    end
    return 2
end

return ClassController
