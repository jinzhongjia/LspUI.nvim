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
function M.init()
    if not config.options.hover.enable then
        return
    end

    if is_initialized then
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
        lib_notify.Info("hover has been deinit")
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
    if api.nvim_win_is_valid(window_id) then
        util.enter_wrap(function()
            api.nvim_set_current_win(window_id)
            api.nvim_set_option_value("winhighlight", "Normal:Normal", {
                win = window_id,
            })
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
    -- make hover params
    -- TODO: inplement workDoneProgreeParam
    -- https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#hoverParams
    --- @type lsp.TextDocumentPositionParams
    local position_param = vim.lsp.util.make_position_params()
    util.get_hovers(
        position_param,
        clients,
        current_buffer,
        --- @param hover_tuples hover_tuple[]
        function(hover_tuples)
            -- We should detect hover_tuples is empty ?
            if vim.tbl_isempty(hover_tuples) then
                return
            end
            local new_current_buffer = api.nvim_get_current_buf()
            if current_buffer ~= new_current_buffer then
                -- Since the request is asynchronous, the server response might be slow.
                -- Need to check if the current buffer when the response returns is the same as the buffer when the request was made. If they're different, don't render the result.
                return
            end
            --- @type lsp.TextDocumentPositionParams
            local new_position_param = vim.lsp.util.make_position_params()
            local old_position = position_param.position
            local new_position = new_position_param.position
            if
                old_position.character ~= new_position.character
                or old_position.line ~= new_position.line
            then
                return
            end
            local buffer_id
            window_id, buffer_id = util.render(hover_tuples[1], #hover_tuples)
            util.keybind(window_id, buffer_id)
            util.autocmd(current_buffer, window_id)
        end
    )
end

return M
