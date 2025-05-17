local api = vim.api

local M = {}

-- this is public notify message prefix
local _notify_public_message = "[LspUI]: "

-- Error notify
--- @param message string
M.Error = function(message)
    vim.notify(_notify_public_message .. message, vim.log.levels.ERROR)
end

-- Info notify
--- @param message string
M.Info = function(message)
    vim.notify(_notify_public_message .. message, vim.log.levels.INFO)
end

-- Warn notify
--- @param message string
M.Warn = function(message)
    vim.notify(_notify_public_message .. message, vim.log.levels.WARN)
end

return M
