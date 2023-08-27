local api, lsp = vim.api, vim.lsp
local inlay_hint_feature = lsp.protocol.Methods.textDocument_inlayHint

local config = require("LspUI.config")
local lib_notify = require("LspUI.lib.notify")
local lib_util = require("LspUI.lib.util")

local M = {}

local buffer_list = {}
local autocmd_id = -1

-- whether this module has initialized
local is_initialized = false

-- init for inlay hint
M.init = function()
    if not config.options.inlay_hint.enable then
        return
    end

    if is_initialized then
        return
    end

    is_initialized = true

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
                lsp.inlay_hint(buffer_id, true)
                table.insert(buffer_list, buffer_id)
            end
        end,
        desc = lib_util.command_desc("inlay hint"),
    })
end

-- run for inlay_hint
M.run = function()
    lib_notify.Info("inlay hint has no run func")
end

-- deinit for inlay_hint
M.deinit = function()
    if not is_initialized then
        return
    end

    for _, buffer_id in pairs(buffer_list) do
        if api.nvim_buf_is_valid(buffer_id) then
            lsp.inlay_hint(buffer_id, false)
        end
    end

    pcall(api.nvim_del_autocmd, autocmd_id)

    is_initialized = false
end

return M
