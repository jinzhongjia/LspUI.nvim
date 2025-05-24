local api, fn, uv = vim.api, vim.fn, vim.uv
local M = {}

local version = "v3"

--- @param buffer_id integer
--- @param uri lsp.URI
--- @param rows integer[]
--- @return string[]
function M.GetUriLines(buffer_id, uri, rows)
    local lines = {}
    if api.nvim_buf_is_loaded(buffer_id) then
        for _, row in ipairs(rows) do
            if not lines[row] then
                lines[row] = (api.nvim_buf_get_lines(
                    buffer_id,
                    row,
                    row + 1,
                    false
                ) or { "" })[1]
            end
        end
        return lines
    end

    if string.sub(uri, 1, 4) ~= "file" then
        fn.bufload(buffer_id)
        for _, row in ipairs(rows) do
            if not lines[row] then
                lines[row] = (api.nvim_buf_get_lines(
                    buffer_id,
                    row,
                    row + 1,
                    false
                ) or { "" })[1]
            end
        end
        return lines
    end

    -- get file name through buffer
    local file_full_name = api.nvim_buf_get_name(buffer_id)

    -- open file handle
    local fd = uv.fs_open(file_full_name, "r", 438)
    if not fd then
        return lines
    end

    -- get file status
    local stat = uv.fs_fstat(fd)
    if not stat then
        return lines
    end

    -- read all file content
    local data = uv.fs_read(fd, stat.size, 0)
    uv.fs_close(fd)
    if not data then
        return lines
    end

    local need = 0 -- keep track of how many unique rows we need
    for _, row in pairs(rows) do
        if not lines[row] then
            need = need + 1
        end
        lines[row] = true
    end

    local found = 0
    local lnum = 0

    ---@diagnostic disable-next-line: param-type-mismatch
    for line in string.gmatch(data, "([^\n]*)\n?") do
        if lines[lnum] == true then
            lines[lnum] = line
            found = found + 1
            if found == need then
                break
            end
        end
        lnum = lnum + 1
    end

    for i, line in pairs(lines) do
        if line == true then
            lines[i] = ""
        end
    end

    return lines
end

--- 比较两个 URI 是否指向同一文件
--- @param uri_1 lsp.URI 第一个 URI
--- @param uri_2 lsp.URI 第二个 URI
--- @return boolean 是否相同
function M.compare_uri(uri_1, uri_2)
    -- 快速路径：URI 字符串相同时直接返回 true
    if uri_1 == uri_2 then
        return true
    end

    -- 转换为本地路径
    local path_1 = vim.uri_to_fname(uri_1)
    local path_2 = vim.uri_to_fname(uri_2)

    -- Windows 系统上执行不区分大小写的比较并规范化路径分隔符
    if vim.fn.has("win32") == 1 then
        -- 转换为小写并将所有路径分隔符统一为 '/'
        path_1 = path_1:lower():gsub("\\", "/")
        path_2 = path_2:lower():gsub("\\", "/")
    end

    return path_1 == path_2
end

-- check buffer is listed ?
--- @param buffer_id integer
--- @return boolean
function M.buffer_is_listed(buffer_id)
    return fn.buflisted(buffer_id) == 1
end

-- this func get max width of nvim
--- @return integer width
M.get_max_width = function()
    return api.nvim_get_option_value("columns", {})
end

-- this func get max height of nvim
--- @return integer height
M.get_max_height = function()
    -- 减去命令行高度、状态栏和标签页行的高度
    return api.nvim_get_option_value("lines", {})
        - api.nvim_get_option_value("cmdheight", {})
        - (api.nvim_get_option_value("laststatus", {}) > 0 and 1 or 0)
        - (api.nvim_get_option_value("showtabline", {}) > 0 and 1 or 0)
end

--- 计算窗口内容的显示高度
--- @param contents string[] 要显示的内容
--- @param width integer 窗口宽度
--- @return integer 内容在给定宽度下需要的高度
M.compute_height_for_windows = function(contents, width)
    if not width or width <= 0 then
        return #contents -- 如果宽度无效，至少返回行数
    end

    local height = 0
    for _, line in ipairs(contents) do
        local line_width = fn.strdisplaywidth(line)
        height = height + math.max(1, math.ceil(line_width / width))
    end

    return height
end

-- 添加一个辅助函数到 tools 模块，用于检查是否为列表类型
-- 在 lua\LspUI\layer\tools.lua 中添加：
function M.islist(t)
    if type(t) ~= "table" then
        return false
    end
    -- 检查是否为序列
    local count = 0
    for _ in pairs(t) do
        count = count + 1
        if t[count] == nil then
            return false
        end
    end
    return count > 0
end

--- 保存当前位置到 jumplist 中
--- 可以在需要跳转前调用此函数，以便之后能够使用 CTRL-O 返回
--- @return nil
function M.save_position_to_jumplist()
    -- 使用 m' 命令将当前位置添加到 jumplist
    -- 这相当于在当前位置设置一个匿名标记
    api.nvim_command("normal! m'")
end

-- generate command description
--- @param desc string
--- @return string
M.command_desc = function(desc)
    return "[LspUI]: " .. desc
end

function M.debounce(func, delay)
    local timer = nil
    return function(...)
        local args = { ... }
        if timer then
            timer:stop()
            timer:close() -- 确保计时器资源被释放
        end

        timer = vim.loop.new_timer()
        if timer == nil then
            return
        end
        timer:start(
            delay,
            0,
            vim.schedule_wrap(function()
                func(unpack(args))
                if timer then
                    timer:close()
                    timer = nil
                end
            end)
        )
    end
end

-- lib function: get version of LspUI
--- @return string
function M.version()
    return version
end

-- execute once
--- @param callback function
function M.exec_once(callback)
    local is_exec = false
    return function(...)
        if is_exec then
            return
        end
        callback(...)
        is_exec = true
    end
end

function M.detect_filetype(file_path)
    local filetype = vim.filetype.match({ filename = file_path }) or ""

    if not filetype or filetype == "" then
        local ext = vim.fn.fnamemodify(file_path, ":e")
        local ext_map = {
            ts = "typescript",
            tsx = "typescriptreact",
            js = "javascript",
            jsx = "javascriptreact",
            py = "python",
            rb = "ruby",
            -- 更全面的映射表
        }
        filetype = ext_map[ext] or ""
    end

    return filetype
end

return M
