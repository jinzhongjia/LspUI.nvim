local api, lsp = vim.api, vim.lsp
local inlay_hint_feature = lsp.protocol.Methods.textDocument_inlayHint

local command = require("LspUI.command")
local config = require("LspUI.config")
local tools = require("LspUI.layer.tools")

local inlay_hint = lsp.inlay_hint.enable
local inlay_hint_is_enabled = lsp.inlay_hint.is_enabled

local M = {}

local autocmd_group = "Lspui_inlay_hint"
local command_key = "inlay_hint"

-- 模块状态
local is_initialized = false
local is_open = false -- 确保变量有初始值

-- 检查文件类型是否应该应用内联提示
local function should_set_inlay_hint(filetype)
    local options = config.options.inlay_hint.filter or {}

    -- 确保 options 存在必要的字段
    local whitelist = options.whitelist or {}
    local blacklist = options.blacklist or {}

    -- 白名单检查
    if
        not vim.tbl_isempty(whitelist)
        and not vim.tbl_contains(whitelist, filetype)
    then
        return false
    end

    -- 黑名单检查
    if
        not vim.tbl_isempty(blacklist)
        and vim.tbl_contains(blacklist, filetype)
    then
        return false
    end

    return true
end

-- 为单个缓冲区设置内联提示
local function set_inlay_hint(buffer_id)
    if not buffer_id or not api.nvim_buf_is_valid(buffer_id) then
        return
    end

    local filetype = api.nvim_get_option_value("filetype", { buf = buffer_id })

    if not should_set_inlay_hint(filetype) then
        return
    end

    local clients = lsp.get_clients({
        bufnr = buffer_id,
        method = inlay_hint_feature,
    })

    if not vim.tbl_isempty(clients) then
        local current_state = inlay_hint_is_enabled({ bufnr = buffer_id })
        if is_open ~= current_state then
            inlay_hint(is_open, { bufnr = buffer_id })
        end
    end
end

-- 应用于所有缓冲区
local function apply_to_all_buffers()
    local all_buffers = api.nvim_list_bufs()
    for _, buffer_id in ipairs(all_buffers) do
        set_inlay_hint(buffer_id)
    end
end

-- 初始化模块
function M.init()
    if not config.options.inlay_hint.enable or is_initialized then
        return
    end

    is_initialized = true
    is_open = true

    -- 注册命令
    if config.options.inlay_hint.command_enable then
        command.register_command(command_key, M.run, {})
    end

    -- 处理现有缓冲区
    apply_to_all_buffers()

    -- 设置自动命令
    local inlay_hint_group =
        api.nvim_create_augroup(autocmd_group, { clear = true })
    api.nvim_create_autocmd("LspAttach", {
        group = inlay_hint_group,
        callback = function(arg)
            -- 确保有效的 buffer 编号
            if arg and arg.buf then
                set_inlay_hint(arg.buf)
            end
            -- 移除了 arg.bufnr 检查，因为它未定义
        end,
        desc = tools.command_desc("inlay hint"),
    })
end

-- 切换内联提示状态
function M.run()
    is_open = not is_open
    apply_to_all_buffers()
end

-- 清理模块
function M.deinit()
    if not is_initialized then
        return
    end

    is_initialized = false
    is_open = false

    -- 确保关闭所有内联提示
    apply_to_all_buffers()
    api.nvim_del_augroup_by_name(autocmd_group)
    command.unregister_command(command_key)
end

return M
