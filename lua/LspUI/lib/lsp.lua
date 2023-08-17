local lsp, api = vim.lsp, vim.api

local lib_notify = require("LspUI.lib.notify")

local M = {}

--- @alias position  { buffer_id: integer, range: { start: lsp.Position, finish: lsp.Position }[]}
--- @alias position_wrap  { [lsp.URI]: position}

-- check whether there is an active lsp client
-- note: this function now should not be called!!
--- @param is_notify boolean whether notify, default not
--- @return boolean
M.is_lsp_active = function(is_notify)
    is_notify = is_notify or false
    local current_buf = api.nvim_get_current_buf()

    local clients = lsp.get_clients({
        bufnr = current_buf,
    })

    if vim.tbl_isempty(clients) then
        if is_notify then
            local message = string.format(
                "not found lsp client on this buffer, id is %d",
                current_buf
            )
            lib_notify.Warn(message)
        end
        return false
    end
    return true
end

-- format and complete diagnostic default option,
-- this func is referred from
-- https://github.com/neovim/neovim/blob/master/runtime/lua/vim/lsp/diagnostic.lua#L138-L160
--- @param diagnostics lsp.Diagnostic[]
--- @return lsp.Diagnostic[]
M.diagnostic_vim_to_lsp = function(diagnostics)
    ---@diagnostic disable-next-line:no-unknown
    return vim.tbl_map(function(diagnostic)
        ---@cast diagnostic Diagnostic
        return vim.tbl_extend("keep", {
            -- "keep" the below fields over any duplicate fields
            -- in diagnostic.user_data.lsp
            range = {
                start = {
                    line = diagnostic.lnum,
                    character = diagnostic.col,
                },
                ["end"] = {
                    line = diagnostic.end_lnum,
                    character = diagnostic.end_col,
                },
            },
            severity = type(diagnostic.severity) == "string"
                    and vim.diagnostic.severity[diagnostic.severity]
                or diagnostic.severity,
            message = diagnostic.message,
            source = diagnostic.source,
            code = diagnostic.code,
        }, diagnostic.user_data and (diagnostic.user_data.lsp or {}) or {})
    end, diagnostics)
end

-- abstruct lsp request, this will request all clients which are passed
-- this function only can be called by `definition` or `declaration`
-- or `type definition` or `reference` or `implementation`
--- @param buffer_id integer
--- @param clients lsp.Client[]
--- @param method string
--- @param params table
--- @param callback fun(datas: position_wrap)
M.lsp_clients_request = function(buffer_id, clients, method, params, callback)
    local tmp_number = 0
    local client_number = #clients

    --- @type position_wrap
    local data = {}
    for _, client in pairs(clients) do
        client.request(method, params, function(err, result, _, _)
            if err ~= nil then
                lib_notify.Warn(string.format("when %s, err: %s", method, err))
            end
            tmp_number = tmp_number + 1

            if result.uri then
                -- response is a position
                local uri = result.uri
                local range = result.range
                local uri_buffer = vim.uri_to_bufnr(uri)
                if data[uri] == nil then
                    data[uri] = {
                        buffer_id = uri_buffer,
                        range = {},
                    }
                end

                table.insert(data[uri].range, {
                    start = range.start,
                    finish = range["end"],
                })
            else
                for _, response in ipairs(result) do
                    local uri = response.uri or response.targetUri
                    local range = response.range or response.targetRange
                    local uri_buffer = vim.uri_to_bufnr(uri)
                    if data[uri] == nil then
                        data[uri] = {
                            buffer_id = uri_buffer,
                            range = {},
                        }
                    end
                    table.insert(data[uri].range, {
                        start = range.start,
                        finish = range["end"],
                    })
                end
            end

            if tmp_number == client_number then
                callback(data)
            end
        end, buffer_id)
    end
end

return M
