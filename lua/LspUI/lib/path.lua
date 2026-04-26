local M = {}

--- @param path string
--- @param is_windows boolean?
--- @return string
function M.normalize_path(path, is_windows)
    local result = path:gsub("\\", "/")
    if is_windows then
        result = result:lower()
    end
    if result:sub(-1) ~= "/" then
        result = result .. "/"
    end
    return result
end

--- @param path string
--- @return string
function M.normalize_display_path(path)
    return path:gsub("\\", "/")
end

--- @param uri_1 string
--- @param uri_2 string
--- @param path_converter fun(uri: string): string
--- @param is_windows boolean?
--- @return boolean
function M.compare_uri(uri_1, uri_2, path_converter, is_windows)
    if uri_1 == uri_2 then
        return true
    end

    local path_1 = path_converter(uri_1)
    local path_2 = path_converter(uri_2)

    if is_windows then
        path_1 = path_1:lower():gsub("\\", "/")
        path_2 = path_2:lower():gsub("\\", "/")
    end

    return path_1 == path_2
end

--- @param full_path string
--- @param cwd string
--- @param is_windows boolean?
--- @return string?
function M.get_relative_path(full_path, cwd, is_windows)
    local norm_full = M.normalize_path(full_path, is_windows)
    local norm_cwd = M.normalize_path(cwd, is_windows)

    if norm_full:sub(1, #norm_cwd) == norm_cwd then
        local rel = full_path:sub(#cwd + 1)
        if rel:sub(1, 1) == "/" or rel:sub(1, 1) == "\\" then
            rel = rel:sub(2)
        end
        return M.normalize_display_path(rel)
    end

    return nil
end

--- 与 `get_relative_path` 等价，但接受预归一化的 cwd，避免对每个文件重复归一化
--- 调用方必须保证 `cwd_norm == M.normalize_path(cwd_raw, is_windows)`，
--- 否则 `#cwd_raw` 与 `#cwd_norm` 长度差不再固定为 0/1，下面的 sub 切片会切到中间字符。
--- @param full_path string
--- @param cwd_raw string 用来切片的原始 cwd（保留分隔符差异）
--- @param cwd_norm string 已归一化的 cwd（含末尾 "/"）
--- @param is_windows boolean?
--- @return string?
function M.get_relative_path_with_norm_cwd(
    full_path,
    cwd_raw,
    cwd_norm,
    is_windows
)
    local norm_full = M.normalize_path(full_path, is_windows)
    if norm_full:sub(1, #cwd_norm) == cwd_norm then
        local rel = full_path:sub(#cwd_raw + 1)
        if rel:sub(1, 1) == "/" or rel:sub(1, 1) == "\\" then
            rel = rel:sub(2)
        end
        return M.normalize_display_path(rel)
    end
    return nil
end

--- @param rel_path string
--- @return string
function M.format_relative_display(rel_path)
    local dir = rel_path:match("(.+)/[^/]+$") or "."
    dir = M.normalize_display_path(dir)
    if dir == "." then
        return " (./)"
    end
    return " (./" .. dir .. ")"
end

--- @param full_path string
--- @return string
function M.format_absolute_display(full_path)
    local dir = full_path:match("(.+)/[^/]+$")
        or full_path:match("(.+)\\[^\\]+$")
        or full_path
    dir = M.normalize_display_path(dir)
    return " (" .. dir .. ")"
end

return M
