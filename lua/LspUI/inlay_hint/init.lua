local api, lsp = vim.api, vim.lsp
local inlay_hint_feature = lsp.protocol.Methods.textDocument_inlayHint

local command = require("LspUI.command")
local config = require("LspUI.config")
local lib_util = require("LspUI.lib.util")

local M = {}

local buffer_list = {}
local autocmd_id = -1

-- whether this module has initialized
local is_initialized = false

local command_key = "inlay_hint"

--- @type boolean
local is_open

-- init for inlay hint
M.init = function()
    if not config.options.inlay_hint.enable then
        return
    end

    if is_initialized then
        return
    end

    is_initialized = true

    is_open = true

    -- init for existed buffers
    do
        local all_buffers = api.nvim_list_bufs()
        for _, buffer_id in pairs(all_buffers) do
            if lib_util.buffer_is_listed(buffer_id) then
                lsp.inlay_hint(buffer_id, true)
                table.insert(buffer_list, buffer_id)
            end
        end
    end

    command.register_command(command_key, M.run, {})

    local inlay_hint_group =
        api.nvim_create_augroup("Lspui_inlay_hint", { clear = true })

    autocmd_id = api.nvim_create_autocmd("LspAttach", {
        group = inlay_hint_group,
        callback = function(arg)
            --- @type integer
            local buffer_id = arg.buf

            local clients = lsp.get_clients({
                bufnr = buffer_id,
                method = inlay_hint_feature,
            })
            if not vim.tbl_isempty(clients) then
                if is_open then
                    lsp.inlay_hint(buffer_id, true)
                end
                table.insert(buffer_list, buffer_id)
            end
        end,
        desc = lib_util.command_desc("inlay hint"),
    })
end

-- run for inlay_hint
M.run = function()
    is_open = not is_open

    if is_open then
        -- open

        for _, buffer_id in pairs(buffer_list) do
            if api.nvim_buf_is_valid(buffer_id) then
                lsp.inlay_hint(buffer_id, true)
            end
        end
    else
        -- close

        for _, buffer_id in pairs(buffer_list) do
            if api.nvim_buf_is_valid(buffer_id) then
                lsp.inlay_hint(buffer_id, false)
            end
        end
    end
end

-- deinit for inlay_hint
M.deinit = function()
    if not is_initialized then
        return
    end

    is_initialized = false

    for _, buffer_id in pairs(buffer_list) do
        if api.nvim_buf_is_valid(buffer_id) then
            lsp.inlay_hint(buffer_id, false)
        end
    end

    buffer_list = {}

    pcall(api.nvim_del_autocmd, autocmd_id)

    command.unregister_command(command_key)
end

return M
