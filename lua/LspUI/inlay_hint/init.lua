local api, lsp = vim.api, vim.lsp
local inlay_hint_feature = lsp.protocol.Methods.textDocument_inlayHint

local command = require("LspUI.command")
local config = require("LspUI.config")
local lib_util = require("LspUI.lib.util")

local inlay_hint = lsp.inlay_hint.enable
local inlay_hint_is_enabled = lsp.inlay_hint.is_enabled

local M = {}

local autocmd_group = "Lspui_inlay_hint"

-- whether this module has initialized
local is_initialized = false

local command_key = "inlay_hint"

--- @type boolean
local is_open

--- @param buffer_id integer
local function set_inlay_hint(buffer_id)
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
        if is_open == inlay_hint_is_enabled({ bufnr = buffer_id }) then
            return
        end
        inlay_hint(is_open, {
            bufnr = buffer_id,
        })
    end
end

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

    -- init for existed listed buffers
    local all_buffers = api.nvim_list_bufs()
    for _, buffer_id in pairs(all_buffers) do
        set_inlay_hint(buffer_id)
    end

    local inlay_hint_group =
        api.nvim_create_augroup(autocmd_group, { clear = true })

    api.nvim_create_autocmd("LspAttach", {
        group = inlay_hint_group,
        callback = function(arg)
            set_inlay_hint(arg.bufnr)
        end,
        desc = lib_util.command_desc("inlay hint"),
    })
end

-- run for inlay_hint
function M.run()
    is_open = not is_open

    local all_buffers = api.nvim_list_bufs()
    for _, buffer_id in pairs(all_buffers) do
        set_inlay_hint(buffer_id)
    end
end

-- deinit for inlay_hint
function M.deinit()
    if not is_initialized then
        return
    end

    is_initialized = false

    is_open = false

    local all_buffers = api.nvim_list_bufs()
    for _, buffer_id in pairs(all_buffers) do
        set_inlay_hint(buffer_id)
    end

    api.nvim_del_augroup_by_name(autocmd_group)

    command.unregister_command(command_key)
end

return M
