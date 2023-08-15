local lsp, api, fn = vim.lsp, vim.api, vim.fn
local definition_feature = lsp.protocol.Methods.textDocument_definition
local lib_debug = require("LspUI.lib.debug")
local lib_lsp = require("LspUI.lib.lsp")
local lib_notify = require("LspUI.lib.notify")
local lib_windows = require("LspUI.lib.windows")

local M = {}

-- get all valid clients for definition
--- @param buffer_id integer
--- @return lsp.Client[]|nil clients array or nil
M.get_clients = function(buffer_id)
    local clients =
        lsp.get_clients({ bufnr = buffer_id, method = definition_feature })
    return #clients == 0 and nil or clients
end

-- make request param
-- TODO: implement `WorkDoneProgressParams` and `PartialResultParams`
--
--- @param window_id integer
--- @return lsp.TextDocumentPositionParams
--- @see https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#definitionParams
M.make_params = function(window_id)
    return lsp.util.make_position_params(window_id)
end

--- @param uri lsp.URI
---@param range lsp.Range
local function handle(uri, range)
    local new_buffer = vim.uri_to_bufnr(uri)
    local new_name = vim.uri_to_fname(uri)
    if api.nvim_buf_is_loaded(new_buffer) then
        fn.bufload(new_buffer)
    end

    local new_window_wrap = lib_windows.new_window(new_buffer)
    lib_windows.set_width_window(
        new_window_wrap,
        math.floor(lib_windows.get_max_width())
    )
    lib_windows.set_height_window(
        new_window_wrap,
        math.floor(lib_windows.get_max_height() - 1)
    )
    lib_windows.set_enter_window(new_window_wrap, true)
    lib_windows.set_anchor_window(new_window_wrap, "NW")
    -- lib_windows.set_border_window(new_window_wrap, "rounded")
    lib_windows.set_relative_window(new_window_wrap, "editor")
    lib_windows.set_zindex_window(new_window_wrap, 10)
    -- lib_windows.set_col_window(new_window_wrap, 1)
    -- lib_windows.set_row_window(new_window_wrap, 1)
    local window_id = lib_windows.display_window(new_window_wrap)
    lib_windows.window_set_cursor(
        window_id,
        range.start.line + 1,
        range.start.character
    )

    local right_buffer = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(right_buffer, 0, -1, true, { "test" })
    local right_window_wrap = lib_windows.new_window(right_buffer)
    lib_windows.set_width_window(right_window_wrap, math.floor(20))
    lib_windows.set_height_window(
        right_window_wrap,
        math.floor(lib_windows.get_max_height() * 0.5)
    )
    lib_windows.set_enter_window(right_window_wrap, true)
    lib_windows.set_relative_window(right_window_wrap, "editor")
    lib_windows.set_col_window(
        right_window_wrap,
        lib_windows.get_max_width() - 22
    )
    lib_windows.set_style_window(right_window_wrap, "minimal")
    lib_windows.set_border_window(right_window_wrap, "rounded")
    lib_windows.set_zindex_window(right_window_wrap, 11)
    lib_windows.set_anchor_window(right_window_wrap, "NW")
    lib_windows.set_center_title_window(right_window_wrap, "definition")
    local window_id = lib_windows.display_window(right_window_wrap)
end

--- @param buffer_id integer
---@param clients lsp.Client[]
---@param params lsp.TextDocumentPositionParams
M.render = function(buffer_id, clients, params)
    lib_lsp.lsp_clients_request(
        buffer_id,
        clients,
        definition_feature,
        params,
        function(data)
            for _, val in pairs(data) do
                --- @type lsp.Location|lsp.Location[]|lsp.LocationLink[]|nil
                local definition_response = val.result
                local client = val.client
                if definition_response then
                    if definition_response.uri then
                        -- response is a position
                        local uri = definition_response.uri
                        local range = definition_response.range
                        handle(uri, range)
                        return
                    end
                    for _, response in ipairs(definition_response) do
                        local uri = response.uri or response.targetUri
                        local range = response.range or response.targetRange
                        handle(uri, range)
                        return
                    end
                end
            end
            lib_notify.Info("no valid definition!")
        end
    )
end

return M
