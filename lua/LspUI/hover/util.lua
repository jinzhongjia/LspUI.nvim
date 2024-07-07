local lsp, api, fn = vim.lsp, vim.api, vim.fn
local hover_feature = lsp.protocol.Methods.textDocument_hover
local config = require("LspUI.config")
local lib_notify = require("LspUI.lib.notify")
local lib_util = require("LspUI.lib.util")
local lib_windows = require("LspUI.lib.windows")

--- @alias hover_tuple { client: vim.lsp.Client, buffer_id: integer, contents: string[], width: integer, height: integer }

local M = {}

local remove_lock = false

--- @type integer
local hover_tuple_index

-- get all valid clients for hover
--- @param buffer_id integer
--- @return vim.lsp.Client[]|nil clients array or nil
M.get_clients = function(buffer_id)
    local clients =
        lsp.get_clients({ bufnr = buffer_id, method = hover_feature })
    if vim.tbl_isempty(clients) then
        return nil
    end
    return clients
end

-- get hovers from lsp
--- @param clients vim.lsp.Client[]
--- @param buffer_id integer
--- @param callback function this callback has a param is hover_tuples[]
M.get_hovers = function(clients, buffer_id, callback)
    --- @type hover_tuple[]
    local hover_tuples = {}
    local params = lsp.util.make_position_params()
    local tmp_number = 0

    --- @type string[]
    local invalid_clients = {}

    for _, client in pairs(clients) do
        client.request(
            hover_feature,
            params,
            ---@param result lsp.Hover
            ---@param lsp_config any
            function(err, result, _, lsp_config)
                lsp_config = lsp_config or {}

                if err ~= nil then
                    if lsp_config.silent ~= true then
                        lib_notify.Warn(
                            string.format(
                                "server %s, err code is %d, err code is %s",
                                client.name,
                                err.code,
                                err.message
                            )
                        )
                    end
                else
                    if not (result and result.contents) then
                        if lsp_config.silent ~= true then
                            table.insert(invalid_clients, client.name)
                        end
                    else
                        local markdown_lines =
                            lsp.util.convert_input_to_markdown_lines(
                                result.contents
                            )
                        markdown_lines =
                            lib_util.trim_empty_lines(markdown_lines)

                        if vim.tbl_isempty(markdown_lines) then
                            if lsp_config.silent ~= true then
                                table.insert(invalid_clients, client.name)
                            end
                        else
                            local new_buffer = api.nvim_create_buf(false, true)

                            markdown_lines = lsp.util.stylize_markdown(
                                new_buffer,
                                markdown_lines,
                                {
                                    max_width = math.floor(
                                        lib_windows.get_max_width() * 0.6
                                    ),
                                    max_height = math.floor(
                                        lib_windows.get_max_height() * 0.8
                                    ),
                                }
                            )

                            local max_width = 0

                            for _, line in pairs(markdown_lines) do
                                max_width = math.max(
                                    fn.strdisplaywidth(line),
                                    max_width
                                )
                            end
                            -- note: don't change filetype, this will cause syntx failing
                            api.nvim_set_option_value("modifiable", false, {
                                buf = new_buffer,
                            })
                            api.nvim_set_option_value("bufhidden", "wipe", {
                                buf = new_buffer,
                            })

                            local width = math.min(
                                max_width,
                                math.floor(lib_windows.get_max_width() * 0.6)
                            )

                            local height =
                                lib_windows.compute_height_for_windows(
                                    markdown_lines,
                                    width
                                )

                            table.insert(
                                hover_tuples,
                                --- @type hover_tuple
                                {
                                    client = client,
                                    buffer_id = new_buffer,
                                    contents = markdown_lines,
                                    width = width,
                                    height = math.min(
                                        height,
                                        math.floor(
                                            lib_windows.get_max_height() * 0.8
                                        )
                                    ),
                                }
                            )
                        end
                    end
                end

                tmp_number = tmp_number + 1

                if tmp_number == #clients then
                    if not vim.tbl_isempty(invalid_clients) then
                        local names = ""
                        for index, client_name in pairs(invalid_clients) do
                            if index == 1 then
                                names = names .. client_name
                            else
                                names = names
                                    .. string.format(", %s", client_name)
                            end
                        end
                        lib_notify.Info(
                            string.format("No valid hover, %s", names)
                        )
                    end

                    callback(hover_tuples)
                end
            end,
            buffer_id
        )
    end
end

-- render hover
--- @param hover_tuple hover_tuple
--- @param hover_tuple_number integer
--- @return integer window_id window's id
--- @return integer buffer_id buffer's id
M.base_render = function(hover_tuple, hover_tuple_number)
    local new_window_wrap = lib_windows.new_window(hover_tuple.buffer_id)

    lib_windows.set_width_window(new_window_wrap, hover_tuple.width)
    lib_windows.set_height_window(new_window_wrap, hover_tuple.height)
    lib_windows.set_enter_window(new_window_wrap, false)
    lib_windows.set_anchor_window(new_window_wrap, "NW")
    lib_windows.set_border_window(new_window_wrap, "rounded")
    lib_windows.set_focusable_window(new_window_wrap, true)
    lib_windows.set_relative_window(new_window_wrap, "cursor")
    lib_windows.set_col_window(new_window_wrap, 1)
    lib_windows.set_row_window(new_window_wrap, 1)
    lib_windows.set_style_window(new_window_wrap, "minimal")
    lib_windows.set_right_title_window(
        new_window_wrap,
        hover_tuple_number > 1
                and string.format("hover[1/%d]", hover_tuple_number)
            or "hover"
    )

    local window_id = lib_windows.display_window(new_window_wrap)
    hover_tuple_index = 1

    api.nvim_set_option_value("winhighlight", "Normal:Normal", {
        win = window_id,
    })
    api.nvim_set_option_value("wrap", true, {
        win = window_id,
    })
    -- this is very very important, because it will hide highlight group
    api.nvim_set_option_value("conceallevel", 2, {
        win = window_id,
    })
    api.nvim_set_option_value("concealcursor", "n", {
        win = window_id,
    })
    api.nvim_set_option_value("winblend", config.options.hover.transparency, {
        win = window_id,
    })

    return window_id, hover_tuple.buffer_id
end

--- @param hover_tuples hover_tuple[]
--- @param window_id integer float window's id
--- @param forward boolean true is next, false is prev
--- @return integer
local next_render = function(hover_tuples, window_id, forward)
    if forward then
        -- next
        if hover_tuple_index == #hover_tuples then
            hover_tuple_index = 1
        else
            hover_tuple_index = hover_tuple_index + 1
        end
    else
        -- prev
        if hover_tuple_index == 1 then
            hover_tuple_index = #hover_tuples
        else
            hover_tuple_index = hover_tuple_index - 1
        end
    end

    --- @type hover_tuple
    local hover_tuple = hover_tuples[hover_tuple_index]
    api.nvim_win_set_buf(window_id, hover_tuple.buffer_id)
    api.nvim_win_set_config(window_id, {
        width = hover_tuple.width,
        height = hover_tuple.height,
        title = #hover_tuples > 1
                and string.format("hover[1/%d]", #hover_tuples)
            or "hover",
        title_pos = "right",
    })

    return hover_tuple.buffer_id
end

--- audo for hover
--- this must be called in vim.schedule
--- @param current_buffer integer current buffer id, not float window's buffer id'
--- @param window_id integer  float window's id
M.autocmd = function(current_buffer, window_id)
    -- autocmd
    api.nvim_create_autocmd(
        { "CursorMoved", "InsertEnter", "BufDelete", "BufLeave" },
        {
            buffer = current_buffer,
            callback = function(arg)
                if remove_lock then
                    return
                end
                lib_windows.close_window(window_id)
                api.nvim_del_autocmd(arg.id)
            end,
            desc = lib_util.command_desc("auto close hover when cursor moves"),
        }
    )
end

--- @param hover_tuples hover_tuple[]
--- @param window_id integer window's id
--- @param buffer_id integer buffer's id
M.keybind = function(hover_tuples, window_id, buffer_id)
    -- next
    api.nvim_buf_set_keymap(
        buffer_id,
        "n",
        config.options.hover.key_binding.next,
        "",
        {
            nowait = true,
            noremap = true,
            callback = function()
                if #hover_tuples == 1 then
                    return
                end
                local next_buffer = next_render(hover_tuples, window_id, true)
                M.keybind(hover_tuples, window_id, next_buffer)
            end,
            desc = lib_util.command_desc("next hover"),
        }
    )
    -- prev
    api.nvim_buf_set_keymap(
        buffer_id,
        "n",
        config.options.hover.key_binding.prev,
        "",
        {
            nowait = true,
            noremap = true,
            callback = function()
                if #hover_tuples == 1 then
                    return
                end
                local next_buffer = next_render(hover_tuples, window_id, false)
                M.keybind(hover_tuples, window_id, next_buffer)
            end,
            desc = lib_util.command_desc("prev hover"),
        }
    )
    -- quit
    api.nvim_buf_set_keymap(
        buffer_id,
        "n",
        config.options.hover.key_binding.quit,
        "",
        {
            nowait = true,
            noremap = true,
            callback = function()
                lib_windows.close_window(window_id)
            end,
            desc = lib_util.command_desc("hover, close window"),
        }
    )
end

--- @param callback function
M.enter_wrap = function(callback)
    remove_lock = true
    callback()
    remove_lock = false
end

return M
