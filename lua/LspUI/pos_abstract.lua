local api, fn, lsp = vim.api, vim.fn, vim.lsp
local config = require("LspUI.config")
local lib_debug = require("LspUI.lib.debug")
local lib_notify = require("LspUI.lib.notify")
local lib_util = require("LspUI.lib.util")
local lib_windows = require("LspUI.lib.windows")

---
--- int this file, we will render two window
--- one window's content is the file name and code line, we call it secondary view
--- another is preview the file, we call it main view
---

local M = {}

-- create a namespace
local main_namespace = api.nvim_create_namespace("LspUI_main")

local seconday_namespace = api.nvim_create_namespace("LspUI_seconday")

local buffer_history = {}

-- create auto group

--- @alias lsp_range { start: lsp.Position, finish: lsp.Position }
--- @alias lsp_position  { buffer_id: integer, fold: boolean, range: lsp_range[]}
--- @alias Lsp_position_wrap  { [lsp.URI]: lsp_position}

--- @type { method: string, name: string, fold: boolean }
local method = nil

--- @type Lsp_position_wrap
local datas = {}

--- @type { uri: string, buffer_id: integer, range: lsp_range? }
local current_item = {}

-- main view
local main_view = {
    buffer = -1,
    window = -1,
    hide = false,
}

-- secondary view
local secondary_view = {
    buffer = -1,
    window = -1,
    hide = false,
}

-- these are methods which are exposed
M.method = {
    definition = {
        method = lsp.protocol.Methods.textDocument_definition,
        name = "definition",
        fold = false,
    },
    type_definition = {
        method = lsp.protocol.Methods.textDocument_typeDefinition,
        name = "type definition",
        fold = false,
    },
    declaration = {
        method = lsp.protocol.Methods.textDocument_declaration,
        name = "declaration",
        fold = false,
    },
    reference = {
        method = lsp.protocol.Methods.textDocument_references,
        name = "reference",
        fold = true,
    },
    implemention = {
        method = lsp.protocol.Methods.textDocument_implementation,
        name = "implemention",
        fold = true,
    },
}

-- get pos through lnum
--- @param lnum integer
--- @return string? uri
--- @return lsp_range? range
local get_lsp_position_by_lnum = function(lnum)
    for uri, data in pairs(M.datas()) do
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

-- highlight main view
--- @param data lsp_position
local main_set_hl = function(data)
    for _, val in pairs(data.range) do
        for row = val.start.line, val.finish.line, 1 do
            local start_col = 0
            local end_col = -1
            if row == val.start.line then
                start_col = val.start.character
            end

            if row == val.finish.line then
                end_col = val.finish.character
            end

            api.nvim_buf_add_highlight(
                M.main_view_buffer(),
                main_namespace,
                "Search",
                row,
                start_col,
                end_col
            )
        end
    end
end

-- highlight secondary view, only highlight file name
--- @param hl integer[]
local secondary_set_hl = function(hl)
    for _, lnum in pairs(hl) do
        api.nvim_buf_add_highlight(
            M.secondary_view_buffer(),
            seconday_namespace,
            "Directory",
            lnum - 1,
            3,
            -1
        )
    end
end

-- clear main highlight
local main_clear_hl = function()
    if api.nvim_buf_is_valid(M.main_view_buffer()) then
        vim.api.nvim_buf_clear_namespace(
            M.main_view_buffer(),
            main_namespace,
            0,
            -1
        )
    end
end

-- clear secondary highlight
local secondary_clear_hl = function()
    if api.nvim_buf_is_valid(M.secondary_view_buffer()) then
        vim.api.nvim_buf_clear_namespace(
            M.secondary_view_buffer(),
            seconday_namespace,
            0,
            -1
        )
    end
end

local main_view_clear_keybind = function()
    for _, lhs in pairs(config.options.pos_keybind.main) do
        pcall(vim.api.nvim_buf_del_keymap, M.main_view_buffer(), "n", lhs)
    end
end

-- keybind for main view
local main_view_keybind = function()
    -- back keybind
    api.nvim_buf_set_keymap(
        M.main_view_buffer(),
        "n",
        config.options.pos_keybind.main.back,
        "",
        {
            callback = function()
                if not M.secondary_view_hide() then
                    api.nvim_set_current_win(M.secondary_view_window())
                    main_view_clear_keybind()
                end
            end,
        }
    )
    -- hide secondary view
    api.nvim_buf_set_keymap(
        M.main_view_buffer(),
        "n",
        config.options.pos_keybind.main.hide_secondary,
        "",
        {
            callback = function()
                M.secondary_view_hide(not M.secondary_view_hide())
                if M.secondary_view_hide() then
                    lib_windows.close_window(M.secondary_view_window())
                else
                    M.secondary_view_render()
                end
            end,
        }
    )
end

local secondary_cmd = {}

local main_view_autocmd = function()
    local main_group =
        api.nvim_create_augroup("Lspui_main_view", { clear = true })

    api.nvim_create_autocmd("WinClosed", {
        group = main_group,
        pattern = {
            tostring(M.main_view_window()),
        },
        once = true,
        callback = function()
            if not M.main_view_hide() then
                main_clear_hl()
                lib_windows.close_window(M.secondary_view_window())
                pcall(api.nvim_del_autocmd, secondary_cmd.CursorMoved)
            end
        end,
    })
end

-- keybind for secondary view
local secondary_view_keybind = function()
    -- keybind for jump
    api.nvim_buf_set_keymap(
        M.secondary_view_buffer(),
        "n",
        config.options.pos_keybind.secondary.jump,
        "",
        {
            nowait = true,
            noremap = true,
            callback = function()
                M.action.jump()
            end,
        }
    )

    api.nvim_buf_set_keymap(
        M.secondary_view_buffer(),
        "n",
        config.options.pos_keybind.secondary.enter,
        "",
        {
            nowait = true,
            noremap = true,
            callback = function()
                M.action.enter_main()
            end,
        }
    )

    -- quit for secondary
    api.nvim_buf_set_keymap(
        M.secondary_view_buffer(),
        "n",
        config.options.pos_keybind.secondary.quit,
        "",
        {
            nowait = true,
            noremap = true,
            callback = function()
                M.action.secondary_quit()
            end,
        }
    )

    -- hide main for keybind
    api.nvim_buf_set_keymap(
        M.secondary_view_buffer(),
        "n",
        config.options.pos_keybind.secondary.hide_main,
        "",
        {
            nowait = true,
            noremap = true,
            callback = function()
                M.action.hide_main()
            end,
        }
    )
end

-- auto cmd for secondary view
local secondary_view_autocmd = function()
    local secondary_group =
        api.nvim_create_augroup("Lspui_secondary_view", { clear = true })

    secondary_cmd.close = api.nvim_create_autocmd("WinClosed", {
        group = secondary_group,
        pattern = {
            tostring(M.secondary_view_window()),
        },
        once = true,
        callback = function()
            pcall(api.nvim_del_autocmd, secondary_cmd.CursorMoved)
            if not M.secondary_view_hide() then
                main_clear_hl()
                lib_windows.close_window(M.main_view_window())
            end
        end,
        desc = lib_util.command_desc(" secondary view winclose"),
    })
    secondary_cmd.CursorMoved = api.nvim_create_autocmd("CursorMoved", {
        group = secondary_group,
        -- pattern = {
        --     tostring(M.secondary_view_window()),
        -- },
        -- note: we can't use buffer and pattern together
        -- CursorMoved can't effect on pattern
        buffer = M.secondary_view_buffer(),
        callback = function()
            -- get current cursor position
            local cursor_position =
                api.nvim_win_get_cursor(M.secondary_view_window())

            local lnum = cursor_position[1]

            local uri, range = get_lsp_position_by_lnum(lnum)
            if not uri then
                return
            end

            -- set current cursorhold
            current_item = {
                uri = uri,
                buffer_id = M.datas()[uri].buffer_id,
                range = range,
            }

            if range then
                local uri_buffer = M.datas()[uri].buffer_id

                -- change main view buffer
                M.main_view_buffer(uri_buffer)

                if not M.main_view_hide() then
                    -- render main vie
                    M.main_view_render()

                    -- set cursor
                    lib_windows.window_set_cursor(
                        M.main_view_window(),
                        range.start.line + 1,
                        range.start.character
                    )

                    -- move center
                    api.nvim_win_call(M.main_view_window(), function()
                        vim.cmd("norm! zv")
                        vim.cmd("norm! zz")
                    end)
                end
            end
        end,
    })
end

--- @param buffer_id integer?
--- @return integer
M.main_view_buffer = function(buffer_id)
    if buffer_id then
        if not M.main_view_hide() then
            -- remove old buffer's highlight
            main_clear_hl()
        end

        -- set new main view buffer
        main_view.buffer = buffer_id

        -- TODO: maybe these can be optional run with main_view_hide
        -- load main view buffer
        if not api.nvim_buf_is_loaded(M.main_view_buffer()) then
            fn.bufload(M.main_view_buffer())
        end

        -- TODO: why we must do `BufRead`
        api.nvim_buf_call(M.main_view_buffer(), function()
            if
                vim.api.nvim_buf_get_option(M.main_view_buffer(), "filetype")
                == ""
            then
                vim.cmd("do BufRead")
            end
        end)

        if not M.main_view_hide() then
            -- highlight new main_view_buffer
            main_set_hl(M.datas()[current_item.uri])
        end
    end
    return main_view.buffer
end

--- @param window_id integer?
--- @return integer
M.main_view_window = function(window_id)
    if window_id then
        main_view.window = window_id
    end
    return main_view.window
end

--- @param hide boolean?
--- @return boolean
M.main_view_hide = function(hide)
    if hide ~= nil then
        main_view.hide = hide
        if hide then
            main_clear_hl()
        else
            main_set_hl(M.datas()[current_item.uri])
        end
    end
    return main_view.hide
end

--- @param buffer_id integer?
--- @return integer
M.secondary_view_buffer = function(buffer_id)
    if buffer_id and buffer_id ~= M.secondary_view_buffer() then
        secondary_view.buffer = buffer_id
        secondary_view_keybind()
    end
    return secondary_view.buffer
end

--- @param window_id integer?
--- @return integer
M.secondary_view_window = function(window_id)
    if window_id then
        secondary_view.window = window_id
    end
    return secondary_view.window
end

--- @param hide boolean?
--- @return boolean
M.secondary_view_hide = function(hide)
    if hide ~= nil then
        secondary_view.hide = hide
    end
    return secondary_view.hide
end

--- @param param Lsp_position_wrap?
--- @return Lsp_position_wrap
M.datas = function(param)
    if param then
        datas = param
    end
    return datas
end

-- abstruct lsp request, this will request all clients which are passed
-- this function only can be called by `definition` or `declaration`
-- or `type definition` or `reference` or `implementation`
--- @param buffer_id integer which buffer do method
--- @param clients lsp.Client[]
--- @param params table
--- @param callback fun(datas: Lsp_position_wrap|nil)
M.lsp_clients_request = function(buffer_id, clients, params, callback)
    -- tmp_number is only for counts
    local tmp_number = 0
    local client_number = #clients

    local origin_uri = vim.uri_from_bufnr(buffer_id)

    --- @type Lsp_position_wrap
    local data = {}
    for _, client in pairs(clients) do
        client.request(method.method, params, function(err, result, _, _)
            if not result then
                callback(nil)
                return
            end
            if err ~= nil then
                lib_notify.Warn(
                    string.format("when %s, err: %s", method.name, err)
                )
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
                        fold = method.fold
                                and (origin_uri ~= uri and true or false)
                            or false,
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
                            fold = method.fold
                                    and (origin_uri ~= uri and true or false)
                                or false,
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

--- @return integer width
--- @return integer height
local generate_secondary_view = function()
    if not api.nvim_buf_is_valid(M.secondary_view_buffer()) then
        -- in this scope, we will create a new buffer
        M.secondary_view_buffer(api.nvim_create_buf(false, true))
    else
        -- is this scope, we will reuse old buffer, so we need clear old highlight
        secondary_clear_hl()
    end

    -- enable change for this buffer
    api.nvim_buf_set_option(M.secondary_view_buffer(), "modifiable", true)

    -- hl_num for highlight lnum recording
    local hl_num = 0
    -- this array stores the highlighted line number
    local hl = {}

    -- the buffer's new content
    local content = {}

    -- calculate the max width that we need
    local max_width = 0
    -- calculate the height for render
    local height = 0

    for uri, data in pairs(M.datas()) do
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

        hl_num = hl_num + 1
        table.insert(hl, hl_num)

        -- get file_fmt length
        local file_fmt_len = fn.strdisplaywidth(file_fmt)

        -- detect max width
        if file_fmt_len > max_width then
            max_width = file_fmt_len
        end

        local uri_rows = {}
        do
            for _, range in ipairs(data.range) do
                local row = range.start.line
                table.insert(uri_rows, row)
            end
        end

        local lines = lib_util.get_uri_lines(data.buffer_id, uri, uri_rows)
        for _, row in pairs(uri_rows) do
            local line_code = fn.trim(lines[row])
            local code_fmt = string.format("   %s", line_code)
            if not data.fold then
                table.insert(content, code_fmt)
                hl_num = hl_num + 1
            end
            height = height + 1

            local code_fmt_length = fn.strdisplaywidth(code_fmt)

            if code_fmt_length > max_width then
                max_width = code_fmt_length
            end
        end
    end

    api.nvim_buf_set_lines(M.secondary_view_buffer(), 0, -1, true, content)

    -- now we have calculated the highlight line numbers
    secondary_set_hl(hl)

    -- disable change for this buffer
    api.nvim_buf_set_option(M.secondary_view_buffer(), "modifiable", false)

    -- For aesthetics, increase the width
    return max_width + 2 > 30 and 30 or max_width + 2, height + 1
end

-- render main view
M.main_view_render = function()
    -- detect the buffer is valid
    if not api.nvim_buf_is_valid(M.main_view_buffer()) then
        lib_notify.Error(
            "render main view fails, main view buffer is not valid"
        )
        return
    end

    if lib_windows.is_valid_window(M.main_view_window()) then
        -- if now windows is valid, just set buffer
        api.nvim_win_set_buf(M.main_view_window(), M.main_view_buffer())
    else
        -- window is not valid, create a new window
        local main_window_wrap = lib_windows.new_window(M.main_view_buffer())

        -- set width and height
        lib_windows.set_width_window(
            main_window_wrap,
            lib_windows.get_max_width()
        )
        lib_windows.set_height_window(
            main_window_wrap,
            lib_windows.get_max_height() - 3
        )

        -- set whether enter the main_view_window
        lib_windows.set_enter_window(main_window_wrap, false)

        lib_windows.set_anchor_window(main_window_wrap, "NW")

        -- set none border, TODO: add more border here
        lib_windows.set_border_window(main_window_wrap, "none")

        lib_windows.set_relative_window(main_window_wrap, "editor")

        lib_windows.set_zindex_window(main_window_wrap, 10)

        lib_windows.set_row_window(main_window_wrap, 1)
        lib_windows.set_col_window(main_window_wrap, 0)

        -- set new main view window
        M.main_view_window(lib_windows.display_window(main_window_wrap))

        -- prevent extra shadows
        api.nvim_win_set_option(
            M.main_view_window(),
            "winhighlight",
            "Normal:Normal"
        )
    end
    main_view_autocmd()
end

-- render secondary view
M.secondary_view_render = function()
    -- generate buffer, get width and height
    local width, height = generate_secondary_view()

    if lib_windows.is_valid_window(M.secondary_view_window()) then
        api.nvim_win_set_buf(
            M.secondary_view_window(),
            M.secondary_view_buffer()
        )
        api.nvim_win_set_config(M.secondary_view_window(), {
            width = width,
            height = height,
        })
    else
        local second_window_wrap =
            lib_windows.new_window(M.secondary_view_buffer())

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
        lib_windows.set_center_title_window(second_window_wrap, method.name)

        M.secondary_view_window(lib_windows.display_window(second_window_wrap))

        -- prevent extra shadows
        api.nvim_win_set_option(
            M.secondary_view_window(),
            "winhighlight",
            "Normal:Normal"
        )
    end
    secondary_view_autocmd()
end

--- @param cmd string?
local action_jump = function(cmd)
    if current_item.range then
        lib_windows.close_window(M.secondary_view_window())

        if cmd then
            vim.cmd(cmd)
        end

        if fn.buflisted(current_item.buffer_id) == 1 then
            vim.cmd(string.format("buffer %s", current_item.buffer_id))
        else
            vim.cmd(
                string.format(
                    "edit %s",
                    fn.fnameescape(vim.uri_to_fname(current_item.uri))
                )
            )
        end
        api.nvim_win_set_cursor(0, {
            current_item.range.start.line + 1,
            current_item.range.start.character,
        })
        vim.cmd("norm! zz")
    else
        datas[current_item.uri].fold = not M.datas()[current_item.uri].fold
        M.secondary_view_render()
    end
end

local action_enter_main = function()
    if not M.main_view_hide() then
        api.nvim_set_current_win(M.main_view_window())
        main_view_keybind()
    end
end

local action_secondary_quit = function()
    lib_windows.close_window(M.secondary_view_window())
end

local action_hide_main = function()
    M.main_view_hide(not M.main_view_hide())
    if M.main_view_hide() then
        lib_windows.close_window(M.main_view_window())
    else
        M.main_view_render()
    end
end

-- local action_

-- define actions
M.action = {
    jump = function()
        action_jump()
    end,
    jump_vsplit = function()
        action_jump("vsplit")
    end,
    jump_split = function()
        action_jump("split")
    end,
    jump_tab = function()
        action_jump("tabe")
    end,
    enter_main = function()
        action_enter_main()
    end,
    secondary_quit = function()
        action_secondary_quit()
    end,
    hide_main = function()
        action_hide_main()
    end,
}

--- @param params lsp.TextDocumentPositionParams
local find_position_from_params = function(params)
    local lnum = 0
    local param_uri = params.textDocument.uri

    for uri, data in pairs(M.datas()) do
        lnum = lnum + 1
        if not data.fold then
            for _, val in pairs(data.range) do
                lnum = lnum + 1
                if
                    uri == param_uri
                    and val.start.line == params.position.line
                then
                    return lnum
                end
            end
        end
    end

    return 2
end

--- @param buffer_id integer which buffer do method
--- @param clients lsp.Client[]
--- @param params table
--- @param new_method { method: string, name: string, fold: boolean }
M.go = function(new_method, buffer_id, clients, params)
    -- set method
    method = new_method

    M.lsp_clients_request(buffer_id, clients, params, function(data)
        if not data then
            lib_notify.Info("no valid definition")
            return
        end
        M.datas(data)

        M.secondary_view_render()

        -- set current window
        api.nvim_set_current_win(M.secondary_view_window())
        -- set the cursor position
        api.nvim_win_set_cursor(
            M.secondary_view_window(),
            { find_position_from_params(params), 0 }
        )
    end)
end

return M
