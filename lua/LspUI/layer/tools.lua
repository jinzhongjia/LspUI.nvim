local api, fn, uv = vim.api, vim.fn, vim.uv
local M = {}

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
        -- 转换为小写并将所有路径分隔符统一为 '\'
        path_1 = string.lower(path_1):gsub("/", "\\")
        path_2 = string.lower(path_2):gsub("/", "\\")
    end

    return path_1 == path_2
end

-- check buffer is listed ?
--- @param buffer_id integer
--- @return boolean
function M.buffer_is_listed(buffer_id)
    return fn.buflisted(buffer_id) == 1
end

return M
