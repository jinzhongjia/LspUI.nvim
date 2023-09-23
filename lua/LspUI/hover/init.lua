local api = vim.api
local command = require("LspUI.command")
local config = require("LspUI.config")
local lib_notify = require("LspUI.lib.notify")
local util = require("LspUI.hover.util")
local M = {}

-- whether this module has initialized
local is_initialized = false

local command_key = "hover"

-- window's id
--- @type integer
local window_id = -1

-- init for hover
M.init = function()
    if not config.options.hover.enable then
        return
    end

    if is_initialized then
        return
    end

    is_initialized = true

    -- register command
    if config.options.hover.command_enable then
        command.register_command(command_key, M.run, {})
    end
end

M.deinit = function()
    if not is_initialized then
        lib_notify.Info("hover has been deinit")
        return
    end

    is_initialized = false

    command.unregister_command(command_key)
end

-- run of hover
M.run = function()
    if not config.options.hover.enable then
        lib_notify.Info("hover is not enabled!")
        return
    end
    if api.nvim_win_is_valid(window_id) then
        util.enter_wrap(function()
            api.nvim_set_current_win(window_id)
        end)
        return
    end
    -- get current buffer
    local current_buffer = api.nvim_get_current_buf()
    local clients = util.get_clients(current_buffer)
    if clients == nil then
        lib_notify.Warn("no client supports hover!")
        return
    end
    util.get_hovers(
        clients,
        current_buffer,
        --- @param hover_tuples hover_tuple[]
        function(hover_tuples)
            -- We should detect hover_tuples is empty ?
            if vim.tbl_isempty(hover_tuples) then
                return
            end
            local buffer_id
            window_id, buffer_id =
                util.base_render(hover_tuples[1], #hover_tuples)
            util.keybind(hover_tuples, window_id, buffer_id)
            vim.schedule(function()
                util.autocmd(current_buffer, window_id)
            end)
        end
    )
end

return M
