-- lua/LspUI/rename/util.lua
local api, fn = vim.api, vim.fn
local ClassLsp = require("LspUI.layer.lsp")
local ClassView = require("LspUI.layer.view")
local config = require("LspUI.config")
local notify = require("LspUI.layer.notify")
local tools = require("LspUI.layer.tools")

local M = {}

-- 计算显示长度，确定输入框宽度
---@param str string 要计算长度的字符串
---@return integer 计算后的显示宽度
local function calculate_length(str)
    local len = fn.strdisplaywidth(str) + 2
    return len > 10 and len or 10
end

-- 设置重命名视图的键绑定和自动命令
---@param view ClassView 重命名浮动窗口
---@param old_name string 原始名称
---@param clients vim.lsp.Client[] LSP客户端数组
---@param buffer_id integer 包含重命名目标的缓冲区ID
---@param position_param table LSP位置参数
local function setup_view_bindings(
    view,
    old_name,
    clients,
    buffer_id,
    position_param
)
    -- 获取LSP处理器实例
    local lsp_handler = ClassLsp:New()

    -- 记录进入时的模式
    local entry_mode = api.nvim_get_mode().mode

    -- 创建自动命令组
    local autocmd_group_id =
        api.nvim_create_augroup("LspUI-rename_autocmd_group", {
            clear = true,
        })

    -- 执行重命名的键绑定（支持多种模式）
    for _, mode in pairs({ "i", "n", "v" }) do
        view:KeyMap(mode, config.options.rename.key_binding.exec, function()
            local new_name = vim.trim(api.nvim_get_current_line())

            -- 仅当名称有变化时执行重命名
            if old_name ~= new_name then
                position_param.newName = new_name

                -- 使用防抖处理器确保不重复执行
                vim.schedule(function()
                    -- 尝试执行重命名
                    local success = lsp_handler:ExecuteRename(
                        clients,
                        buffer_id,
                        position_param
                    )

                    if not success then
                        notify.Error("Rename operation failed")
                    else
                        notify.Info(
                            string.format(
                                "Renamed '%s' to '%s'",
                                old_name,
                                new_name
                            )
                        )
                    end

                    -- 恢复到进入时的模式
                    if
                        entry_mode == "n"
                        or entry_mode == "v"
                        or entry_mode == "V"
                        or entry_mode == ""
                    then
                        vim.cmd("stopinsert")
                    end
                    -- 如果是插入模式，不需要特殊处理，默认就是插入模式
                end)
            end

            view:Destroy()
        end, "Execute Rename")
    end

    -- 退出重命名的键绑定
    view:KeyMap("n", config.options.rename.key_binding.quit, function()
        view:Destroy()
    end, "Cancel Rename")

    -- 文本变化时自动调整窗口大小（使用防抖处理）
    local resize_debounce = tools.debounce(function()
        if not view:Valid() then
            return
        end

        local now_name = api.nvim_get_current_line()
        local len = calculate_length(now_name)

        local win_id = view:GetWinID()
        if win_id and api.nvim_win_is_valid(win_id) then
            api.nvim_win_set_config(win_id, { width = len })
        end
    end, 100) -- 100ms防抖延迟

    -- 文本变化事件
    view:BufAutoCmd(
        { "TextChanged", "TextChangedI" },
        autocmd_group_id,
        resize_debounce,
        "Auto-adjust the width of the rename input box"
    )

    -- 窗口失焦时自动关闭
    view:BufAutoCmd("WinLeave", autocmd_group_id, function()
        view:Destroy()
    end, "Close rename window when losing focus")

    -- 确保窗口关闭时清理自动命令组
    local original_close_event = view._closeEvent
    view:CloseEvent(function()
        if original_close_event then
            original_close_event()
        end

        -- 清理自动命令组
        pcall(api.nvim_del_augroup_by_id, autocmd_group_id)
    end)
end

-- 渲染重命名视图
---@param clients vim.lsp.Client[] LSP客户端数组
---@param buffer_id integer 缓冲区ID
---@param old_name string 原始名称
---@param position_param table LSP位置参数
local function render_rename_view(clients, buffer_id, old_name, position_param)
    local width = calculate_length(old_name)

    local view = ClassView:New(true)
        :BufContent(0, -1, { old_name })
        :BufCall(function()
            -- 确保重命名内容不会被历史撤销操作影响
            local old_undolevels = vim.bo.undolevels
            vim.bo.undolevels = -1
            vim.cmd("normal! a \b") -- 无意义的改变和删除
            vim.bo.undolevels = old_undolevels
        end)
        :BufOption("filetype", "LspUI-rename")
        :BufOption("modifiable", true)
        :BufOption("bufhidden", "wipe")
        :Size(width, 1)
        :Enter(true)
        :Anchor("NW")
        :Border("rounded")
        :Focusable(true)
        :Relative("cursor")
        :Pos(1, 1)
        :Style("minimal")
        :Title("rename", "right")
        :Render()
        :Winhl("Normal:Normal")
        :Winbl(config.options.rename.transparency)

    -- 自动选择文本（如果启用）
    if config.options.rename.auto_select then
        view:Call(function()
            vim.cmd([[normal! V]])
            api.nvim_feedkeys(
                api.nvim_replace_termcodes("<C-g>", true, true, true),
                "n",
                false
            )
        end)
    end

    -- 设置键绑定和自动命令
    setup_view_bindings(view, old_name, clients, buffer_id, position_param)
end

-- 执行重命名操作
---@param clients vim.lsp.Client[] LSP客户端数组
---@param buffer_id integer 缓冲区ID
---@param window_id integer 窗口ID
---@param old_name string 原始名称
function M.done(clients, buffer_id, window_id, old_name)
    -- 在操作前确认缓冲区有效性
    if not api.nvim_buf_is_valid(buffer_id) then
        notify.Error("Invalid buffer ID")
        return
    end

    -- 获取LSP处理器实例
    local lsp_handler = ClassLsp:New()

    -- 创建位置参数
    local offset_encoding = clients[1] and clients[1].offset_encoding
        or "utf-16"
    local position_param =
        vim.lsp.util.make_position_params(window_id, offset_encoding)

    -- 检查位置是否可重命名
    lsp_handler:CheckRenamePosition(
        buffer_id,
        position_param,
        function(can_rename, valid_clients, error_msg)
            if not can_rename then
                notify.Info(error_msg or "Cannot rename at this position")
                return
            end

            if not valid_clients or #valid_clients == 0 then
                notify.Info("No valid rename clients found")
                return
            end

            -- 渲染重命名视图
            render_rename_view(
                valid_clients,
                buffer_id,
                old_name,
                position_param
            )
        end
    )
end

return M
