-- lua/LspUI/layer/hover.lua
local api, lsp, fn = vim.api, vim.lsp, vim.fn
local hover_feature = lsp.protocol.Methods.textDocument_hover
local ClassView = require("LspUI.layer.view")
local config = require("LspUI.config")
local notify = require("LspUI.layer.notify")
local tools = require("LspUI.layer.tools")

--- @class ClassHover
--- @field private _view ClassView|nil 当前的 hover 视图
--- @field private _markview any|false markview 插件引用
--- @field private _hover_tuples hover_tuple[] hover 结果数组
--- @field private _current_index integer 当前显示的 hover 索引
--- @field private _enter_lock boolean 进入锁，防止自动关闭
local ClassHover = {
    _view = nil,
    _markview = nil,
    _hover_tuples = {},
    _current_index = 1,
    _enter_lock = false,
}

ClassHover.__index = ClassHover

--- 创建新的 ClassHover 实例
--- @return ClassHover
function ClassHover:New()
    local obj = {}
    setmetatable(obj, self)

    -- 尝试加载 markview 插件
    local status, markview = pcall(require, "markview")
    if status then
        obj._markview = markview
    else
        obj._markview = false
    end

    return obj
end

--- 获取支持 hover 的客户端
--- @param buffer_id integer
--- @return vim.lsp.Client[]|nil
function ClassHover:GetClients(buffer_id)
    local clients = lsp.get_clients({
        bufnr = buffer_id,
        method = hover_feature,
    })

    if vim.tbl_isempty(clients) then
        return nil
    end

    return clients
end

--- @class LspUI_hover_ctx
--- @field clients vim.lsp.Client[]
--- @field requested_client_count integer
--- @field invalid_clients string[]
--- @field callback fun(hover_tuples: hover_tuple[])

--- @alias hover_tuple { client: vim.lsp.Client, buffer_id: integer, width: integer, height: integer }

--- @param client vim.lsp.Client
--- @param hover_ctx LspUI_hover_ctx
--- @return fun(err: lsp.ResponseError, result: lsp.Hover, ctx: any, config: table)
function ClassHover:CreateHoverCallback(client, hover_ctx)
    local self_ref = self

    return function(err, result, _, lsp_config)
        lsp_config = lsp_config or {}

        -- 检查错误
        local is_err = err ~= nil and lsp_config.silent ~= true
        if is_err then
            local _err_msg = string.format(
                "server %s, err code is %d, err code is %s",
                client.name,
                err.code,
                err.message
            )
            notify.Warn(_err_msg)
        end

        if err == nil then
            if not (result and result.contents) then
                if lsp_config.silent ~= true then
                    table.insert(hover_ctx.invalid_clients, client.name)
                end
            else
                -- 处理有效结果
                local markdown_lines =
                    lsp.util.convert_input_to_markdown_lines(result.contents)

                -- 创建缓冲区
                local new_buffer = api.nvim_create_buf(false, true)
                api.nvim_buf_set_lines(new_buffer, 0, -1, true, markdown_lines)
                api.nvim_set_option_value(
                    "bufhidden",
                    "wipe",
                    { buf = new_buffer }
                )
                api.nvim_set_option_value(
                    "modifiable",
                    false,
                    { buf = new_buffer }
                )

                -- 计算尺寸
                local width = 0
                for _, str in pairs(markdown_lines) do
                    local _tmp_width = fn.strdisplaywidth(str)
                    width = math.max(width, _tmp_width)
                end

                -- 限制宽度
                width = math.min(width, math.floor(tools.get_max_width() * 0.6))
                local height = #markdown_lines

                -- 添加到结果数组
                table.insert(self_ref._hover_tuples, {
                    client = client,
                    buffer_id = new_buffer,
                    width = width,
                    height = math.min(
                        height,
                        math.floor(tools.get_max_height() * 0.8)
                    ),
                })
            end
        end

        -- 更新请求计数
        hover_ctx.requested_client_count = hover_ctx.requested_client_count + 1

        -- 如果所有请求完成，调用回调
        if hover_ctx.requested_client_count == #hover_ctx.clients then
            if not vim.tbl_isempty(hover_ctx.invalid_clients) then
                local names = table.concat(hover_ctx.invalid_clients, ", ")
                notify.Info(string.format("No valid hover: %s", names))
            end

            hover_ctx.callback(self_ref._hover_tuples)
        end
    end
end

--- 请求 hover 信息
--- @param clients vim.lsp.Client[]
--- @param buffer_id integer
--- @param callback fun(hover_tuples: hover_tuple[])
function ClassHover:GetHovers(clients, buffer_id, callback)
    -- 清空上次结果
    self._hover_tuples = {}

    -- 创建参数
    local params = lsp.util.make_position_params(0, clients[1].offset_encoding)

    -- 创建上下文对象
    local hover_ctx = {
        clients = clients,
        requested_client_count = 0,
        invalid_clients = {},
        callback = callback,
    }

    -- 发送请求到每个客户端
    for _, client in pairs(clients) do
        client:request(
            hover_feature,
            params,
            self:CreateHoverCallback(client, hover_ctx),
            buffer_id
        )
    end
end

--- 渲染 hover 窗口
--- @param hover_tuple hover_tuple
--- @param hover_tuple_number integer
--- @param options table|nil 配置选项
--- @return ClassView 视图实例
function ClassHover:Render(hover_tuple, hover_tuple_number, options)
    options = options or {}

    -- 设置标题
    local title = hover_tuple_number > 1
            and string.format("hover[1/%d]", hover_tuple_number)
        or "hover"

    self._current_index = 1

    -- 创建视图
    local view = ClassView:New(false)
        :SwitchBuffer(hover_tuple.buffer_id)
        :Title(title, "right")
        :Size(hover_tuple.width, hover_tuple.height)
        :Relative("cursor")
        :Border(config.options.hover.border)
        :Style("minimal")
        :Focusable(true)
        :Enter(false)
        :Anchor("NW")
        :Pos(1, 1)
        :Render()
        :Winhl("Normal:Normal")
        :Option("wrap", true)
        :Option("conceallevel", 3)
        :Option("concealcursor", "nvic")
        :Winbl(options.transparency or 0)
        :BufOption("filetype", "LspUI_hover")

    -- 应用 markview
    if self._markview then
        self._markview.render(hover_tuple.buffer_id)
    end

    self._view = view
    return view
end

--- 切换到下一个或上一个 hover
--- @param forward boolean 是否向前
function ClassHover:NextRender(forward)
    if not self._view or #self._hover_tuples <= 1 then
        return
    end

    -- 计算新索引
    if forward then
        self._current_index = self._current_index == #self._hover_tuples and 1
            or self._current_index + 1
    else
        self._current_index = self._current_index == 1 and #self._hover_tuples
            or self._current_index - 1
    end

    -- 获取当前 hover 数据
    local hover_tuple = self._hover_tuples[self._current_index]

    -- 更新视图
    self._view:SwitchBuffer(hover_tuple.buffer_id)
    self._view:BufOption("filetype", "LspUI_hover")

    -- 应用 markview
    if self._markview then
        self._markview.render(hover_tuple.buffer_id)
    end

    -- 更新标题和尺寸
    local title =
        string.format("hover[%d/%d]", self._current_index, #self._hover_tuples)
    self._view:Updates(function()
        self._view:Size(hover_tuple.width, hover_tuple.height)
        self._view:Title(title, "right")
    end)
end

--- 设置 hover 窗口的键绑定
--- @param key_bindings table 键绑定配置
function ClassHover:SetKeyBindings(key_bindings)
    if not self._view then
        return
    end

    local self_ref = self

    -- 定义键绑定
    local mapping_list = {
        {
            key = key_bindings.next,
            cb = function()
                self_ref:NextRender(true)
                self_ref:SetKeyBindings(key_bindings)
            end,
            desc = "next hover",
        },
        {
            key = key_bindings.prev,
            cb = function()
                self_ref:NextRender(false)
                self_ref:SetKeyBindings(key_bindings)
            end,
            desc = "prev hover",
        },
        {
            key = key_bindings.quit,
            cb = function()
                self_ref:Close()
            end,
            desc = "hover, close window",
        },
    }

    -- 应用键绑定
    for _, mapping in pairs(mapping_list) do
        self._view:KeyMap("n", mapping.key, mapping.cb, mapping.desc)
    end
end

--- 设置自动命令
--- @param buffer_id integer 当前缓冲区ID
function ClassHover:SetAutoCommands(buffer_id)
    if not self._view then
        return
    end

    local self_ref = self

    -- 设置自动命令
    api.nvim_create_autocmd(
        { "CursorMoved", "InsertEnter", "BufDelete", "BufLeave" },
        {
            buffer = buffer_id,
            callback = function(_)
                if self_ref._enter_lock then
                    return
                end
                self_ref:Close()
                return true
            end,
            desc = tools.command_desc("auto close hover when cursor moves"),
        }
    )
end

--- 进入 hover 窗口
--- @param callback function 回调函数
function ClassHover:EnterWithLock(callback)
    self._enter_lock = true
    callback()
    self._enter_lock = false
end

--- 检查 hover 窗口是否有效
--- @return boolean
function ClassHover:IsValid()
    return self._view ~= nil and self._view:Valid()
end

--- 聚焦 hover 窗口
function ClassHover:Focus()
    if self:IsValid() then
        self._view:Focus()
    end
end

--- 关闭 hover 窗口
function ClassHover:Close()
    if self:IsValid() then
        self._view:Destroy()
        self._view = nil
    end
end

return ClassHover
