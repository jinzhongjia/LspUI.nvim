local api, fn = vim.api, vim.fn

--- @alias window_wrap { buffer: integer, enter: boolean, config: vim.api.keyset.float_config } wrap for windows

local M = {}

-- this func get max width of nvim
--- @return integer width
M.get_max_width = function()
    return api.nvim_get_option_value("columns", {})
end

-- this func get max height of nvim
--- @return integer height
M.get_max_height = function()
    return api.nvim_get_option_value("lines", {})
end

-- create a windows config,
-- here use similar c processing logic
--- @param buffer_id integer|nil buffer's id, if nil, it will be current buffer
--- @return window_wrap wrap a windows wrap config for other function to use
M.new_window = function(buffer_id)
    local window_wrap = {
        buffer = buffer_id or 0,
        enter = false,
        config = {},
    }
    return window_wrap
end

-- display window
-- this func is just call nvim_open_win
--- @return integer window_id
--- @param window_wrap window_wrap
M.display_window = function(window_wrap)
    local window_id = api.nvim_open_win(window_wrap.buffer, window_wrap.enter, window_wrap.config)
    return window_id
end

-- close window
-- this func will check if window's id is valid
-- notice: this func will force close window if its buffer change
--- @param window_id integer window's is
M.close_window = function(window_id)
    if M.is_valid_window(window_id) then
        api.nvim_win_close(window_id, true)
    end
end

-- check if window's id is valid
-- if valid, return true
--- @param window_id integer window's id
--- @return boolean
M.is_valid_window = function(window_id)
    return api.nvim_win_is_valid(window_id)
end

-- hide window
-- this func will check if window's id is valid
--- @param window_id integer window's id
M.hide_window = function(window_id)
    if M.is_valid_window(window_id) then
        api.nvim_win_hide(window_id)
    end
end

-- set window's if enter
--- @param window_wrap window_wrap
--- @param enter boolean if enter
--- @return window_wrap window_wrap a windows wrap config for other function to use
M.set_enter_window = function(window_wrap, enter)
    window_wrap.enter = enter
    return window_wrap
end

-- set window's relative attribute
--- @param window_wrap window_wrap
--- @param relative string ("editor" or "win" or "cursor" or "mouse")
--- @return window_wrap window_wrap a windows wrap config for other function to use
M.set_relative_window = function(window_wrap, relative)
    window_wrap.config.relative = relative
    if not window_wrap.config.row then
        window_wrap.config.row = 0
    end
    if not window_wrap.config.col then
        window_wrap.config.col = 0
    end
    return window_wrap
end

-- set window's relative to "window id"
--- @param window_wrap window_wrap
--- @param window_id integer relative to window's id
--- @return window_wrap window_wrap a windows wrap config for other function to use
M.set_relative_window_id_for_window = function(window_wrap, window_id)
    window_wrap.config.win = window_id
    return window_wrap
end

-- set window's anchor
--- @param window_wrap window_wrap
--- @param anchor string ("NW","NE","SW","SE")
--- @return window_wrap window_wrap a windows wrap config for other function to use
M.set_anchor_window = function(window_wrap, anchor)
    window_wrap.config.anchor = anchor
    return window_wrap
end

-- set window's width
--- @param window_wrap window_wrap
--- @param width integer
--- @return window_wrap window_wrap a windows wrap config for other function to use
M.set_width_window = function(window_wrap, width)
    window_wrap.config.width = width
    return window_wrap
end

-- set window's height
--- @param window_wrap window_wrap
--- @param height integer
--- @return window_wrap window_wrap a windows wrap config for other function to use
M.set_height_window = function(window_wrap, height)
    window_wrap.config.height = height
    return window_wrap
end

-- set window's bufpos
--- @param window_wrap window_wrap
--- @param row integer
--- @param col integer
--- @return window_wrap window_wrap a windows wrap config for other function to use
M.set_bufpos_window = function(window_wrap, row, col)
    window_wrap.config.bufpos = { row, col }
    return window_wrap
end

-- set window's row
--- @param window_wrap window_wrap
--- @param row integer
--- @return window_wrap window_wrap a windows wrap config for other function to use
M.set_row_window = function(window_wrap, row)
    window_wrap.config.row = row
    return window_wrap
end

-- set window's col
--- @param window_wrap window_wrap
--- @param col integer
--- @return window_wrap window_wrap a windows wrap config for other function to use
M.set_col_window = function(window_wrap, col)
    window_wrap.config.col = col
    return window_wrap
end

-- set window's focusable
--- @param window_wrap window_wrap
--- @param  focusable boolean
--- @return window_wrap window_wrap a windows wrap config for other function to use
M.set_focusable_window = function(window_wrap, focusable)
    window_wrap.config.focusable = focusable
    return window_wrap
end

-- set window's external
-- note: this func isn't used!!!
--- @param window_wrap window_wrap
--- @param external any
--- @return window_wrap window_wrap a windows wrap config for other function to use
M.set_external_window = function(window_wrap, external)
    window_wrap.config.external = external
    return window_wrap
end

-- set window's zindex
--- @param window_wrap window_wrap
--- @param zindex integer
--- @return window_wrap window_wrap a windows wrap config for other function to use
M.set_zindex_window = function(window_wrap, zindex)
    window_wrap.config.zindex = zindex
    return window_wrap
end

-- set window's style
-- note: now style only is minimal
-- about more info, need see documentation
--- @param window_wrap window_wrap
--- @param style string
--- @return window_wrap window_wrap a windows wrap config for other function to use
M.set_style_window = function(window_wrap, style)
    window_wrap.config.style = style or "minimal"
    return window_wrap
end

-- set window's border
-- border is string or a array
-- about more see documentation
--- @param window_wrap window_wrap
--- @param border string|table
--- @return window_wrap window_wrap a windows wrap config for other function to use
M.set_border_window = function(window_wrap, border)
    window_wrap.config.border = border
    return window_wrap
end

-- set window's title
-- note: title is string or list(text,highlight)
--- @param window_wrap window_wrap
--- @param title string|table
--- @return window_wrap window_wrap a windows wrap config for other function to use
M.set_title_window = function(window_wrap, title)
    window_wrap.config.title = title
    return window_wrap
end

-- set window's title position
-- default is left, value can be of ("left","center","tight")
--- @param window_wrap window_wrap
--- @param title_position string
--- @return window_wrap window_wrap a windows wrap config for other function to use
M.set_title_position_window = function(window_wrap, title_position)
    window_wrap.config.title_pos = title_position
    return window_wrap
end

-- set window's left title
--- @param window_wrap window_wrap
--- @param title string|table
--- @return window_wrap window_wrap a windows wrap config for other function to use
M.set_left_title_window = function(window_wrap, title)
    window_wrap.config.title_pos = "left"
    window_wrap.config.title = title
    return window_wrap
end

-- set window's center title
--- @param window_wrap window_wrap
--- @param title string|table
--- @return window_wrap window_wrap a windows wrap config for other function to use
M.set_center_title_window = function(window_wrap, title)
    window_wrap.config.title_pos = "center"
    window_wrap.config.title = title
    return window_wrap
end

-- set window's right title
--- @param window_wrap window_wrap
--- @param title string|table
--- @return window_wrap window_wrap a windows wrap config for other function to use
M.set_right_title_window = function(window_wrap, title)
    window_wrap.config.title_pos = "right"
    window_wrap.config.title = title
    return window_wrap
end

-- set window's noautocmd
-- if set true, this will shield buffer-related event
-- such as `BufEnter`, `BufeLeave`, `BufeWinEnter`
--- @param window_wrap window_wrap
--- @param noautocmd boolean
--- @return window_wrap window_wrap a windows wrap config for other function to use
M.set_noautocmd_window = function(window_wrap, noautocmd)
    window_wrap.config.noautocmd = noautocmd
    return window_wrap
end

--- compute height for window
--- @param contents string[]
--- @return integer
M.compute_height_for_windows = function(contents, width)
    local height = 0
    for _, line in pairs(contents) do
        --- @type integer
        local line_height = fn.strdisplaywidth(line)
        height = height + math.max(1, math.ceil(line_height / width))
    end

    return height
end

-- set window cursor
--- @param window_id integer
--- @param row integer 1 based
--- @param col integer 0 based
M.window_set_cursor = function(window_id, row, col)
    api.nvim_win_set_cursor(window_id, { row, col })
end

return M
