local api = vim.api
local command = require("LspUI.command")
local config = require("LspUI.config")
local lib_notify = require("LspUI.layer").notify
local util = require("LspUI.hover.util")
local M = {}

-- whether this module has initialized
local is_initialized = false
local command_key = "hover"

-- window's id
--- @type ClassView
local view

-- init for hover
function M.init()
    if not config.options.hover.enable or is_initialized then
        return
    end

    is_initialized = true
    vim.treesitter.language.register("markdown", "LspUI_hover")
    
    -- register command
    if config.options.hover.command_enable then
        command.register_command(command_key, M.run, {})
    end
end

function M.deinit()
    if not is_initialized then
        return
    end

    is_initialized = false
    command.unregister_command(command_key)
end

-- run of hover
function M.run()
    if not config.options.hover.enable then
        lib_notify.Info("hover is not enabled!")
        return
    end

    -- when hover has existed
    if view and view:Valid() then
        util.enter_wrap(function()
            view:Focus()
            view:Winhl("Normal:Normal")
        end)
        return
    end
    
    -- get current buffer
    local current_buffer = api.nvim_get_current_buf()
    local clients = util.get_clients(current_buffer)
    if not clients or #clients < 1 then
        lib_notify.Warn("no client supports hover!")
        return
    end
    
    util.get_hovers(clients, current_buffer, function(hover_tuples)
        if vim.tbl_isempty(hover_tuples) then
            lib_notify.Info("no hover!")
            return
        end
        view = util.render(hover_tuples[1], #hover_tuples)
        util.keybind(view)
        util.autocmd(current_buffer, view)
    end)
end

return M
