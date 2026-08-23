local api, fn, uv = vim.api, vim.fn, vim.uv
local lib_path = require("LspUI.lib.path")
local lib_util = require("LspUI.lib.util")
local M = {}

local version = "v3"

--- 从磁盘按需读取指定行（0-indexed），读到最大行号即停。
--- 不经过 bufload：加载 buffer 会触发 BufReadPre/BufReadPost/FileType/Syntax
--- 整条自动命令链（LSP attach、gitsigns 等），对"只为取几行文本"来说纯属浪费。
--- @param file_path string
--- @param sorted_rows integer[] 升序 0-indexed 行号
--- @param lines table<integer, string> 输出表，按行号填充
--- @return boolean ok 文件是否成功读取
local function read_lines_from_disk(file_path, sorted_rows, lines)
    local file = io.open(file_path, "r")
    if not file then
        return false
    end

    local want = {}
    for _, row in ipairs(sorted_rows) do
        want[row] = true
    end
    local max_row = sorted_rows[#sorted_rows]

    local row = 0
    for line in file:lines() do
        if want[row] then
            -- CRLF 文件去掉行尾 \r，对齐 buffer 读取的行为
            lines[row] = (line:gsub("\r$", ""))
        end
        if row >= max_row then
            break
        end
        row = row + 1
    end
    file:close()
    return true
end

--- @param buffer_id integer
--- @param uri lsp.URI
--- @param rows integer[]
--- @return string[]
function M.GetUriLines(buffer_id, uri, rows)
    local lines = {}

    if type(rows) ~= "table" or #rows == 0 then
        return lines
    end

    -- 1. 过滤有效的数字行号并去重
    local unique_rows = {}
    local sorted_rows = {}
    for _, row in ipairs(rows) do
        local num = tonumber(row)
        if num and num >= 0 and not unique_rows[num] then
            unique_rows[num] = true
            table.insert(sorted_rows, num)
        end
    end

    if #sorted_rows == 0 then
        return lines
    end

    table.sort(sorted_rows)

    -- 2. buffer 未加载时直接读磁盘，避免 bufload 触发整条自动命令链
    local loaded = api.nvim_buf_is_valid(buffer_id)
        and api.nvim_buf_is_loaded(buffer_id)
    if not loaded then
        local ok, file_path = pcall(vim.uri_to_fname, uri)
        if ok and read_lines_from_disk(file_path, sorted_rows, lines) then
            return lines
        end
        -- 磁盘读取失败（非 file:// URI 等）：退回 bufload 路径
        if not api.nvim_buf_is_valid(buffer_id) then
            return lines
        end
        if not pcall(fn.bufload, buffer_id) then
            return lines
        end
    end

    -- 3. 将连续的行号合并为区间，避免一次性读取大跨度
    local segments = {}
    local seg_start = sorted_rows[1]
    local seg_end = seg_start

    for i = 2, #sorted_rows do
        local row = sorted_rows[i]
        if row == seg_end + 1 then
            seg_end = row
        else
            table.insert(segments, { seg_start, seg_end })
            seg_start = row
            seg_end = row
        end
    end
    table.insert(segments, { seg_start, seg_end })

    -- 4. 分段读取，避免跨越巨大范围
    for _, segment in ipairs(segments) do
        local start_row = segment[1]
        local end_row = segment[2]
        local ok, chunk = pcall(
            api.nvim_buf_get_lines,
            buffer_id,
            start_row,
            end_row + 1,
            false
        )

        if ok and type(chunk) == "table" then
            for idx, line in ipairs(chunk) do
                lines[start_row + idx - 1] = line or ""
            end
        else
            for row = start_row, end_row do
                lines[row] = ""
            end
        end
    end

    return lines
end

--- @param uri_1 lsp.URI
--- @param uri_2 lsp.URI
--- @return boolean
function M.compare_uri(uri_1, uri_2)
    local is_windows = fn.has("win32") == 1
    return lib_path.compare_uri(uri_1, uri_2, vim.uri_to_fname, is_windows)
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

--- @param contents string[]
--- @param width integer
--- @return integer
M.compute_height_for_windows = function(contents, width)
    return lib_util.compute_height_for_contents(
        contents,
        width,
        fn.strdisplaywidth
    )
end

--- @param t any
--- @return boolean
function M.islist(t)
    return lib_util.islist(t)
end

--- 保存当前位置到 jumplist 中
--- 可以在需要跳转前调用此函数，以便之后能够使用 CTRL-O 返回
--- @return nil
function M.save_position_to_jumplist()
    -- 使用 m' 命令将当前位置添加到 jumplist
    -- 这相当于在当前位置设置一个匿名标记
    pcall(api.nvim_command, "normal! m'")
end

--- 跳转后确保目标位置被记录到 jumplist
--- 使用 vim.schedule 延迟执行，避免干扰当前跳转
--- @return nil
function M.save_target_to_jumplist()
    vim.schedule(function()
        -- 确保目标位置也被记录
        pcall(api.nvim_command, "normal! m'")
    end)
end

--- 智能判断是否需要添加到 jumplist
--- @param target_buf integer 目标 buffer ID
--- @param target_line integer 目标行号（1-based）
--- @param config { min_distance: integer?, cross_file_only: boolean? }? 配置选项
--- @return boolean recorded 是否已添加到 jumplist
function M.smart_save_to_jumplist(target_buf, target_line, config)
    config = config or {}
    local min_distance = config.min_distance or 5
    local cross_file_only = config.cross_file_only or false

    local current_buf = api.nvim_get_current_buf()
    local current_pos = api.nvim_win_get_cursor(0)
    local current_line = current_pos[1]

    -- 1. 跨文件跳转：必须记录
    if current_buf ~= target_buf then
        pcall(api.nvim_command, "normal! m'")
        return true
    end

    -- 2. 如果配置为只记录跨文件跳转，则跳过同文件
    if cross_file_only then
        return false
    end

    -- 3. 同文件但距离较远（> min_distance 行）：记录
    if math.abs(current_line - target_line) > min_distance then
        pcall(api.nvim_command, "normal! m'")
        return true
    end

    -- 4. 同文件且距离很近：不记录（避免污染 jumplist）
    return false
end

-- generate command description
--- @param desc string
--- @return string
M.command_desc = function(desc)
    return "[LspUI]: " .. desc
end

--- 创建防抖函数，支持显式清理
--- @param func fun(...) 要防抖的函数
--- @param delay integer 延迟毫秒数
--- @return fun(...) debounced 防抖包装后的函数
--- @return fun() cleanup 显式清理 timer 的函数（模块卸载/buffer 删除时调用）
function M.debounce(func, delay)
    local timer = nil

    local debounced = function(...)
        local args = { ... }
        if timer then
            timer:stop()
            timer:close()
            timer = nil
        end

        timer = uv.new_timer()
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

    -- 提供清理函数，确保资源释放
    local cleanup = function()
        if timer then
            timer:stop()
            timer:close()
            timer = nil
        end
    end

    return debounced, cleanup
end

-- lib function: get version of LspUI
--- @return string
function M.version()
    return version
end

--- 把 callback 包装成只执行一次的函数（多次调用只生效首次）
--- @param callback fun(...)
--- @return fun(...) wrapper 调用任意次数仅首次会真正执行
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

--- 检测文件 filetype；先用 vim.filetype.match，失败时回退到扩展名映射
--- @param file_path string 文件名（相对/绝对路径均可）
--- @return string filetype 找不到时返回空串
-- detect_filetype 结果缓存：同一路径在一次渲染里会被反复查询，
-- vim.filetype.match 单次 ~0.03ms，路径到 filetype 的映射不会变化
local filetype_cache = {}

function M.detect_filetype(file_path)
    local cached = filetype_cache[file_path]
    if cached ~= nil then
        return cached
    end

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

    filetype_cache[file_path] = filetype
    return filetype
end

return M
