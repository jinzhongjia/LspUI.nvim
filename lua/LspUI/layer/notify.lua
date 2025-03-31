local M = {}

local _notify_public_message = "[LspUI]: "

-- error notify
function M.Error(message)
    vim.api.nvim_echo({
        { _notify_public_message, "Comment" }, -- 前缀用 Comment 高亮
        { message, "ErrorMsg" }, -- 错误消息用 ErrorMsg 高亮
    }, true, { err = true })
end

-- Info notify
function M.Info(message)
    vim.api.nvim_echo({
        { _notify_public_message, "Comment" },
        { message }, 
    }, true, {})
end

-- Warn notify
function M.Warn(message)
    vim.api.nvim_echo({
        { _notify_public_message, "Comment" },
        { message, "WarningMsg" },
    }, true, {})
end

return M
