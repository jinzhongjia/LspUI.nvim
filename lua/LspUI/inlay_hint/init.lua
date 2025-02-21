local api, lsp = vim.api, vim.lsp
local inlay_hint_feature = lsp.protocol.Methods.textDocument_inlayHint

local command = require("LspUI.command")
local config = require("LspUI.config")
local lib_util = require("LspUI.lib.util")

local inlay_hint = lsp.inlay_hint.enable

local M = {}

--- @type integer[]
local buffer_list = {}
local autocmd_group = "Lspui_inlay_hint"

-- whether this module has initialized
local is_initialized = false

local command_key = "inlay_hint"

--- @type boolean
local is_open

-- init for inlay hint
function M.init()
    if not config.options.inlay_hint.enable then
        return
    end

    if is_initialized then
        return
    end

    is_initialized = true

    -- when init the inlay_hint, open is true
    is_open = true

    -- whether register the inlay_hint command
    if config.options.inlay_hint.command_enable then
        command.register_command(command_key, M.run, {})
    end

    local function _tmp()
        -- init for existed buffers (linked file)
        local all_buffers = api.nvim_list_bufs()
        for _, buffer_id in pairs(all_buffers) do
            -- stylua: ignore
            local buftype = api.nvim_get_option_value("buftype", { buf = buffer_id })

            if lib_util.buffer_is_listed(buffer_id) and buftype == "file" then
                inlay_hint(true, {
                    bufnr = buffer_id,
                })
                table.insert(buffer_list, buffer_id)
            end
        end

        local inlay_hint_group =
            api.nvim_create_augroup(autocmd_group, { clear = true })

        local function _cb(arg)
            --- @type integer
            local buffer_id = arg.buf
            ---@type string
            local filetype = api.nvim_get_option_value("filetype", {
                buf = buffer_id,
            })

            if
                not vim.tbl_isempty(config.options.inlay_hint.filter.whitelist)
                and not vim.tbl_contains(
                    config.options.inlay_hint.filter.whitelist,
                    filetype
                )
            then
                -- when whitelist is not empty, and filetype not exists in whitelist
                return
            end

            if
                not vim.tbl_isempty(config.options.inlay_hint.filter.blacklist)
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
                table.insert(buffer_list, buffer_id)
                if not is_open then
                    return
                end
                inlay_hint(true, {
                    bufnr = buffer_id,
                })
            end
        end

        api.nvim_create_autocmd("LspAttach", {
            group = inlay_hint_group,
            callback = _cb,
            desc = lib_util.command_desc("inlay hint"),
        })
    end

    vim.schedule(_tmp)
end

-- run for inlay_hint
function M.run()
    is_open = not is_open

    -- open
    if is_open then
        for _, buffer_id in pairs(buffer_list) do
            if api.nvim_buf_is_valid(buffer_id) then
                inlay_hint(true, {
                    bufnr = buffer_id,
                })
            end
        end
        return
    end

    -- close
    for _, buffer_id in pairs(buffer_list) do
        if api.nvim_buf_is_valid(buffer_id) then
            inlay_hint(false, {
                bufnr = buffer_id,
            })
        end
    end
end

-- deinit for inlay_hint
function M.deinit()
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

    api.nvim_del_augroup_by_name(autocmd_group)

    command.unregister_command(command_key)
end

return M
