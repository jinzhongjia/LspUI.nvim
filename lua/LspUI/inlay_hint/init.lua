local api, lsp, fn = vim.api, vim.lsp, vim.fn
local inlay_hint_feature = lsp.protocol.Methods.textDocument_inlayHint

local command = require("LspUI.command")
local config = require("LspUI.config")
local lib_util = require("LspUI.lib.util")

-- TODO: this is a patch
-- when 0.10 release, remove it
local inlay_hint = type(lsp.inlay_hint) == "table" and lsp.inlay_hint.enable
    or lsp.inlay_hint

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
    -- TODO: this logic can be changed to async
    if not config.options.inlay_hint.enable then
        return
    end

    if is_initialized then
        return
    end

    is_initialized = true

    is_open = true

    if config.options.inlay_hint.command_enable then
        command.register_command(command_key, M.run, {})
    end

    vim.schedule(function()
        -- init for existed buffers
        do
            local all_buffers = api.nvim_list_bufs()
            for _, buffer_id in pairs(all_buffers) do
                if
                    lib_util.buffer_is_listed(buffer_id)
                    and api.nvim_get_option_value("buftype", {
                            buf = buffer_id,
                        })
                        == "file"
                then
                    inlay_hint(true, {
                        bufnr = buffer_id,
                    })
                    table.insert(buffer_list, buffer_id)
                end
            end
        end

        local inlay_hint_group =
            api.nvim_create_augroup("Lspui_inlay_hint", { clear = true })

        autocmd_id = api.nvim_create_autocmd("LspAttach", {
            group = inlay_hint_group,
            callback = function(arg)
                --- @type integer
                local buffer_id = arg.buf
                ---@type string
                local filetype = api.nvim_get_option_value("filetype", {
                    buf = buffer_id,
                })

                if
                    not vim.tbl_isempty(
                        config.options.inlay_hint.filter.whitelist
                    )
                    and not vim.tbl_contains(
                        config.options.inlay_hint.filter.whitelist,
                        filetype
                    )
                then
                    -- when whitelist is not empty, and filetype not exists in whitelist
                    return
                end

                if
                    not vim.tbl_isempty(
                        config.options.inlay_hint.filter.blacklist
                    )
                    and vim.tbl_contains(
                        config.options.inlay_hint.filter.blacklist,
                        filetype
                    )
                then
                    -- when blacklist is not empty, and filetype exists in blacklist
                    return
                end

                local clients = lsp.get_clients({
                    bufnr = buffer_id,
                    method = inlay_hint_feature,
                })
                if not vim.tbl_isempty(clients) then
                    if is_open then
                        inlay_hint(true, {
                            bufnr = buffer_id,
                        })
                    end
                    table.insert(buffer_list, buffer_id)
                end
            end,
            desc = lib_util.command_desc("inlay hint"),
        })
    end)
end

-- run for inlay_hint
M.run = function()
    is_open = not is_open

    if is_open then
        -- open

        for _, buffer_id in pairs(buffer_list) do
            if api.nvim_buf_is_valid(buffer_id) then
                inlay_hint(true, {
                    bufnr = buffer_id,
                })
            end
        end
    else
        -- close

        for _, buffer_id in pairs(buffer_list) do
            if api.nvim_buf_is_valid(buffer_id) then
                inlay_hint(false, {
                    bufnr = buffer_id,
                })
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
            inlay_hint(false, {
                bufnr = buffer_id,
            })
        end
    end

    buffer_list = {}

    pcall(api.nvim_del_autocmd, autocmd_id)

    command.unregister_command(command_key)
end

return M
