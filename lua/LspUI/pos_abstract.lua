local api, fn = vim.api, vim.fn
local config = require("LspUI.config")
local lib_debug = require("LspUI.lib.debug")
local lib_notify = require("LspUI.lib.notify")
local lib_util = require("LspUI.lib.util")
local lib_windows = require("LspUI.lib.windows")

local M = {}

--- @alias lsp_range { start: lsp.Position, finish: lsp.Position }
--- @alias lsp_position  { buffer_id: integer, fold: boolean, range: lsp_range[]}
--- @alias Lsp_position_wrap  { [lsp.URI]: lsp_position}

--- @type Lsp_position_wrap
local datas = {}

--- @type integer
local type = 0

local main_view = {
    buffer = -1,
    window = -1,
}

local secondary_view = {
    buffer = -1,
    window = -1,
}

M.type = {
    definition = 1,
    type_definition = 2,
    declaration = 3,
    reference = 4,
    implemention = 5,
}

--- @return integer
M.main_view_buffer = function()
    return main_view.buffer
end

--- @return integer
M.main_view_window = function()
    return main_view.window
end

--- @return integer
M.secondary_view_buffer = function()
    return secondary_view.buffer
end

--- @return integer
M.secondary_view_window = function()
    return secondary_view.window
end

--- @param param Lsp_position_wrap
M.set_datas = function(param)
    datas = param
end

-- abstruct lsp request, this will request all clients which are passed
-- this function only can be called by `definition` or `declaration`
-- or `type definition` or `reference` or `implementation`
--- @param buffer_id integer
--- @param clients lsp.Client[]
--- @param method string
--- @param params table
--- @param callback fun(datas: Lsp_position_wrap|nil)
M.lsp_clients_request = function(buffer_id, clients, method, params, callback)
    local tmp_number = 0
    local client_number = #clients

    --- @type Lsp_position_wrap
    local data = {}
    for _, client in pairs(clients) do
        client.request(method, params, function(err, result, _, _)
            if not result then
                callback(nil)
                return
            end
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

local secondary_view_keybind = function()
    api.nvim_buf_set_keymap(
        secondary_view.buffer,
        "n",
        config.options.definition.key_binding.secondary.jump,
        "",
        {
            nowait = true,
            callback = function()
                -- get current cursor position
                local cursor_position =
                    api.nvim_win_get_cursor(secondary_view.window)
                -- get current lnum
                local lnum = cursor_position[1]
                -- get uri and range
                local uri, range = M.get_lsp_position_by_lnum(lnum)
                if not uri then
                    return
                end

                if range then
                    -- local uri_buffer = datas[uri].buffer_id
                    -- main_view.buffer = uri_buffer
                    --
                    -- M.main_view_render()
                    -- lib_windows.window_set_cursor(
                    --     main_view.window,
                    --     range.start.line + 1,
                    --     range.start.character
                    -- )
                    -- api.nvim_set_current_win(main_view.window)
                else
                    datas[uri].fold = not datas[uri].fold
                    M.secondary_view_render("definition")
                end
            end,
        }
    )
end

local secondary_view_autocmd = function()
    api.nvim_create_autocmd("WinClosed", {
        buffer = secondary_view.buffer,
        callback = function()
            lib_windows.close_window(main_view.window)
        end,
    })
    api.nvim_create_autocmd("CursorHold", {
        buffer = secondary_view.buffer,
        callback = function()
            local cursor_position =
                api.nvim_win_get_cursor(secondary_view.window)
            local lnum = cursor_position[1]
            local uri, range = M.get_lsp_position_by_lnum(lnum)
            if not uri then
                return
            end

            if range then
                local uri_buffer = datas[uri].buffer_id
                main_view.buffer = uri_buffer

                M.main_view_render()
                api.nvim_buf_call(main_view.buffer, function()
                    if
                        vim.api.nvim_buf_get_option(
                            main_view.buffer,
                            "filetype"
                        ) == ""
                    then
                        vim.cmd("do BufRead")
                    end
                end)
                lib_windows.window_set_cursor(
                    main_view.window,
                    range.start.line + 1,
                    range.start.character
                )
            end
        end,
    })
end

local main_view_keybind = function() end

local main_view_autocmd = function() end

--- @return integer width
--- @return integer height
local generate_secondary_view = function()
    if not api.nvim_buf_is_valid(secondary_view.buffer) then
        secondary_view.buffer = api.nvim_create_buf(false, true)
        secondary_view_autocmd()
        secondary_view_keybind()
    end

    local content = {}
    local max_width = 0
    local height = 0
    for uri, data in pairs(datas) do
        -- get full file name
        local file_full_name = vim.uri_to_fname(uri)
        -- get file name
        local file_fmt = string.format(
            " %s %s",
            data.fold and "" or "",
            fn.fnamemodify(file_full_name, ":t")
        )

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
            if not data.fold then
                table.insert(content, code_fmt)
            end
            height = height + 1

            local code_fmt_length = fn.strdisplaywidth(code_fmt)

            if code_fmt_length > max_width then
                max_width = code_fmt_length
            end
        end
    end

    api.nvim_buf_set_lines(secondary_view.buffer, 0, -1, true, content)

    -- For aesthetics, increase the width
    return max_width + 2 > 30 and 30 or max_width + 2, height + 1
end

-- render main view
M.main_view_render = function()
    if not api.nvim_buf_is_valid(main_view.buffer) then
        lib_notify.Error(
            "render main view fails, main view buffer is not valid"
        )
        return
    end
    if not api.nvim_buf_is_loaded(main_view.buffer) then
        fn.bufload(main_view.buffer)
    end

    if lib_windows.is_valid_window(main_view.window) then
        lib_debug.debug("not new")
        api.nvim_win_set_buf(main_view.window, main_view.buffer)
        return
    end
    local main_window_wrap = lib_windows.new_window(main_view.buffer)
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

    main_view.window = lib_windows.display_window(main_window_wrap)
end

--- @param name string
M.secondary_view_render = function(name)
    local width, height = generate_secondary_view()

    if lib_windows.is_valid_window(secondary_view.window) then
        api.nvim_win_set_buf(secondary_view.window, secondary_view.buffer)
        api.nvim_win_set_config(secondary_view.window, {
            width = width,
            height = height,
        })
        return
    end

    local second_window_wrap = lib_windows.new_window(secondary_view.buffer)

    -- set width
    lib_windows.set_width_window(second_window_wrap, width)
    -- set height
    lib_windows.set_height_window(second_window_wrap, height)
    -- whether enter window
    lib_windows.set_enter_window(second_window_wrap, false)
    -- fixed position
    lib_windows.set_relative_window(second_window_wrap, "editor")
    lib_windows.set_col_window(
        second_window_wrap,
        lib_windows.get_max_width() - width - 2
    )
    lib_windows.set_style_window(second_window_wrap, "minimal")
    lib_windows.set_border_window(second_window_wrap, "single")
    lib_windows.set_zindex_window(second_window_wrap, 11)
    lib_windows.set_anchor_window(second_window_wrap, "NW")
    lib_windows.set_center_title_window(second_window_wrap, name)

    secondary_view.window = lib_windows.display_window(second_window_wrap)
end

--- @param lnum integer
--- @return string? uri
--- @return lsp_range? range
M.get_lsp_position_by_lnum = function(lnum)
    for uri, data in pairs(datas) do
        lnum = lnum - 1
        if lnum == 0 then
            return uri, nil
        end
        if not data.fold then
            for _, val in pairs(data.range) do
                lnum = lnum - 1
                if lnum == 0 then
                    return uri, val
                end
            end
        end
    end
end

return M
