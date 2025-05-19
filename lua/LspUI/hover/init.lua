-- lua/LspUI/hover/init.lua
local api = vim.api
local command = require("LspUI.command")
local config = require("LspUI.config")
local lib_notify = require("LspUI.layer").notify
local ClassHover = require("LspUI.layer.hover")

local M = {}

-- 是否已初始化
local is_initialized = false
local command_key = "hover"

-- hover 实例
local hover_manager

-- 初始化
function M.init()
    if not config.options.hover.enable or is_initialized then
        return
    end

    is_initialized = true
    vim.treesitter.language.register("markdown", "LspUI_hover")

    -- 创建 hover 管理器
    hover_manager = ClassHover:New()

    -- 注册命令
    if config.options.hover.command_enable then
        command.register_command(command_key, M.run, {})
    end
end

-- 反初始化
function M.deinit()
    if not is_initialized then
        return
    end

    is_initialized = false
    command.unregister_command(command_key)
end

-- 运行 hover
function M.run()
    if not config.options.hover.enable then
        lib_notify.Info("hover is not enabled!")
        return
    end

    -- 如果 hover 已存在
    if hover_manager:IsValid() then
        hover_manager:EnterWithLock(function()
            hover_manager:Focus()
            -- 设置高亮
            if hover_manager._view then
                hover_manager._view:Winhl("Normal:Normal")
            end
        end)
        return
    end

    -- 获取当前缓冲区
    local current_buffer = api.nvim_get_current_buf()
    local clients = hover_manager:GetClients(current_buffer)
    if not clients or #clients < 1 then
        lib_notify.Warn("no client supports hover!")
        return
    end

    -- 获取 hover 信息
    hover_manager:GetHovers(clients, current_buffer, function(hover_tuples)
        if vim.tbl_isempty(hover_tuples) then
            lib_notify.Info("no hover!")
            return
        end

        -- 渲染第一个结果
        hover_manager:Render(hover_tuples[1], #hover_tuples, {
            transparency = config.options.hover.transparency,
        })

        -- 设置键绑定
        hover_manager:SetKeyBindings(config.options.hover.key_binding)

        -- 设置自动命令
        hover_manager:SetAutoCommands(current_buffer)
    end)
end

return M
