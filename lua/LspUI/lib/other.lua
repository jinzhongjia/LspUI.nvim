local api, fn = vim.api, vim.fn
local lib_notify = require("LspUI.lib.notify")
local lib_util = require("LspUI.lib.util")
local lib_windows = require("LspUI.lib.windows")

local M = {}

--- @alias position  { buffer_id: integer, fold: boolean, range: { start: lsp.Position, finish: lsp.Position }[]}
--- @alias position_wrap  { [lsp.URI]: position}

--- @alias view_size { width: integer, height: integer }

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
                        fold = false,
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
                            fold = false,
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

-- @param view_size view_size

--- @param buffer_id integer
--- @return integer
M.main_view_render = function(buffer_id)
    local main_window_wrap = lib_windows.new_window(buffer_id)
    lib_windows.set_width_window(main_window_wrap, lib_windows.get_max_width())
    lib_windows.set_height_window(
        main_window_wrap,
        lib_windows.get_max_height() - 3
    )
    lib_windows.set_enter_window(main_window_wrap, false)
    lib_windows.set_anchor_window(main_window_wrap, "NW")
    -- set none border, TODO: add more border here
    lib_windows.set_border_window(main_window_wrap, "none")
    lib_windows.set_relative_window(main_window_wrap, "editor")
    lib_windows.set_zindex_window(main_window_wrap, 10)
    lib_windows.set_col_window(main_window_wrap, 0)
    lib_windows.set_row_window(main_window_wrap, 1)

    local window_id = lib_windows.display_window(main_window_wrap)
    return window_id
end

--- @param view_size view_size
--- @param buffer_id integer
--- @param name string
--- @return integer
M.secondary_view_render = function(view_size, buffer_id, name)
    local second_window_wrap = lib_windows.new_window(buffer_id)

    -- set width
    lib_windows.set_width_window(second_window_wrap, view_size.width)
    -- set height
    lib_windows.set_height_window(
        second_window_wrap,
        view_size.height or math.floor(lib_windows.get_max_height() * 0.5)
    )
    -- whether enter window
    lib_windows.set_enter_window(second_window_wrap, false)
    -- fixed position
    lib_windows.set_relative_window(second_window_wrap, "editor")
    lib_windows.set_col_window(
        second_window_wrap,
        lib_windows.get_max_width() - view_size.width - 2
    )
    lib_windows.set_style_window(second_window_wrap, "minimal")
    lib_windows.set_border_window(second_window_wrap, "single")
    lib_windows.set_zindex_window(second_window_wrap, 11)
    lib_windows.set_anchor_window(second_window_wrap, "NW")
    lib_windows.set_center_title_window(second_window_wrap, name)

    local window_id = lib_windows.display_window(second_window_wrap)

    return window_id
end

--- @param buffer_id integer
--- @param datas position_wrap
--- @return integer
--- @return integer
M.generate_secondary_view = function(buffer_id, datas)
    local content = {}
    local max_width = 0
    local height = 0
    for uri, data in pairs(datas) do
        -- get full file name
        local file_full_name = vim.uri_to_fname(uri)
        -- get file name
        local file_fmt =
            string.format("  %s", fn.fnamemodify(file_full_name, ":t"))

        table.insert(content, file_fmt)
        height = height + 1

        -- get file_fmt length
        local file_fmt_len = fn.strdisplaywidth(file_fmt)

        -- detect max width
        if file_fmt_len > max_width then
            max_width = file_fmt_len
        end

        local uri_rows = {}
        do
            -- local tmp_store = {}
            for _, range in ipairs(data.range) do
                local row = range.start.line
                -- if not tmp_store[row] then
                table.insert(uri_rows, row)
                -- tmp_store[row] = true
                -- end
            end
        end

        local lines = lib_util.get_uri_lines(data.buffer_id, uri, uri_rows)
        for _, row in pairs(uri_rows) do
            local line_code = fn.trim(lines[row])
            local code_fmt = string.format("   %s", line_code)

            table.insert(content, code_fmt)
            height = height + 1

            local code_fmt_length = fn.strdisplaywidth(code_fmt)

            if code_fmt_length > max_width then
                max_width = code_fmt_length
            end
        end
    end

    api.nvim_buf_set_lines(buffer_id, 0, -1, true, content)

    -- For aesthetics, increase the width
    return max_width + 2, height + 1
end

return M
