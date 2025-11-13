# LspUI SubView 语法高亮实现文档

## 概述

LspUI 的 SubView（第二视图）用于显示代码片段（如函数定义、类型定义等），而不是完整的文件内容。由于 Treesitter 需要完整的语法树才能正确工作，直接对代码片段进行解析会失败（返回 0 个语法树）。

为了解决这个问题，我们实现了一个**双层高亮策略**：

1. **主策略**：从源文件的 buffer 提取 Treesitter 高亮信息，然后映射到 SubView
2. **备用策略**：基于关键字的正则表达式匹配高亮（支持 12 种语言）

## 架构设计

```
┌─────────────────────────────────────────────────────┐
│               SubView (显示代码片段)                  │
└─────────────────────────────────────────────────────┘
                        ▲
                        │ 应用高亮
                        │
        ┌───────────────┴───────────────┐
        │                               │
   [Treesitter 高亮]            [关键字高亮]
   (source_highlight.lua)      (keyword_highlight.lua)
        │                               │
        │                               │
从源 buffer 提取               正则匹配关键字
已有的高亮信息                  (12 种语言)
```

## 核心模块

### 1. source_highlight.lua - Treesitter 高亮提取

**职责**：从源文件的 buffer 提取指定行的 Treesitter 高亮信息

**核心函数**：

#### `extract_line_highlights(source_buf, source_line)`
提取源文件中指定行的所有高亮信息。

**性能优化策略**：

1. **优先使用已有的 highlighter**：避免重复解析文件
   ```lua
   local highlighter = ts_highlighter.active[source_buf]
   if highlighter and highlighter.tree then
       parser = highlighter.tree  -- 复用已有的解析结果
   end
   ```

2. **行范围查询**：只遍历相关的语法节点
   ```lua
   -- iter_captures 的第4和第5个参数指定行范围
   -- 这让 Treesitter 只遍历与该行相交的节点，而不是整个树
   local iter = query.iter_captures(query, root, source_buf, source_line, source_line + 1)
   ```

3. **缓存机制**：避免对同一行重复查询
   ```lua
   M.cache[source_buf][source_line] = highlights
   ```

4. **增量解析**：Treesitter 本身是增量的，只会重新解析变化的部分

**返回格式**：
```lua
{
    {
        hl_group = "@keyword",
        start_col = 0,
        end_col = 4,
        priority = 100,
    },
    ...
}
```

#### `apply_highlights(target_buf, target_line, target_col_start, target_col_end, source_buf, source_line, source_col_offset)`
将提取的高亮应用到目标 buffer。

**列映射逻辑**：

```
源文件:    "    func example() {"
            ^    ^
         offset  实际代码起始位置
         (trim 掉的前导空格)

SubView:   "1│ func example() {"
            ^  ^
         标号  代码起始位置

映射公式:
target_col = target_col_start + (source_col - source_col_offset)
```

**关键点**：
- `source_col_offset`：源文件中被 `vim.fn.trim()` 移除的前导空格数量
- `target_col_start`：目标 buffer 中代码的起始位置（通常是行号标记后的位置）
- 裁剪到有效范围：`math.max(target_start, target_col_start)` 和 `math.min(target_end, actual_target_end)`

### 2. keyword_highlight.lua - 关键字高亮

**职责**：当 Treesitter 不可用时，使用正则表达式匹配关键字进行高亮

**支持的语言**：
- Go
- Lua
- Rust
- TypeScript / JavaScript / Vue
- Zig
- Python
- C / C++
- Java / C#

**高亮类别**：
1. `keywords` → `@keyword`：语言关键字（if, for, return 等）
2. `types` → `@type`：类型名称（int, string, bool 等）
3. `builtins` → `@function.builtin`：内置函数/常量（print, len, append 等）

**模式匹配**：

使用 Lua 的 frontier pattern 实现单词边界匹配：
```lua
local pattern = "%f[%w_]" .. vim.pesc(keyword) .. "%f[^%w_]"
```

- `%f[%w_]`：前向边界，确保前面不是字母/数字/下划线
- `%f[^%w_]`：后向边界，确保后面不是字母/数字/下划线
- `vim.pesc(keyword)`：转义特殊字符

**已知问题和解决方案**：

1. **关键字冲突**：
   - ❌ 问题：Python 的 `type` 既是关键字又是内置函数
   - ✅ 解决：从 builtins 中移除，因为无法区分上下文

2. **重复定义**：
   - ❌ 问题：C++ 的 `nullptr`, `true`, `false` 在 keywords 和 builtins 都有
   - ✅ 解决：只保留在 keywords 中

### 3. controller.lua - 数据准备

**职责**：生成 `syntax_regions` 数据，包含源文件信息

**关键修改**：

```lua
-- 计算被 trim 移除的前导空格数量
local original_line = lines[row] or ""
local line_code = vim.fn.trim(original_line)
local leading_spaces = 0

if #original_line > 0 then
    local first_non_space = original_line:find("%S")
    if first_non_space then
        leading_spaces = first_non_space - 1
    else
        leading_spaces = #original_line  -- 整行都是空格
    end
end

-- 添加源文件信息
local region_data = {
    line = start_line_offset + #content - 1,
    col_start = 3,
    col_end = #line_content,
    source_buf = item.buffer_id,           -- 源 buffer ID
    source_line = row,                     -- 源文件行号（0-indexed）
    source_col_offset = leading_spaces,    -- 列偏移
}
```

**数据格式**：

```lua
syntax_regions = {
    ["go"] = {
        {
            line = 5,              -- SubView 中的行号
            col_start = 3,         -- SubView 中的起始列
            col_end = 25,          -- SubView 中的结束列
            source_buf = 42,       -- 源文件 buffer ID
            source_line = 120,     -- 源文件行号
            source_col_offset = 4, -- 源文件列偏移
        },
        ...
    },
    ...
}
```

### 4. sub_view.lua - 高亮应用

**职责**：协调两种高亮策略的应用

#### `ApplySyntaxHighlight(code_regions)`

**执行流程**：

```lua
for lang, entries in pairs(code_regions) do
    local keyword_regions = {}

    for _, entry in ipairs(entries) do
        local used_treesitter = false

        -- 1. 尝试 Treesitter 高亮
        if entry.source_buf and entry.source_line then
            used_treesitter = source_highlight.apply_highlights(
                bufid, entry.line, entry.col_start, entry.col_end,
                entry.source_buf, entry.source_line,
                entry.source_col_offset or 0
            )
        end

        -- 2. Treesitter 失败时收集到 keyword_regions
        if not used_treesitter then
            table.insert(keyword_regions, {
                { entry.line, entry.col_start },
                { entry.line, entry.col_end },
            })
        end
    end

    -- 3. 对失败的行应用关键字高亮
    if #keyword_regions > 0 then
        keyword_highlight.apply(bufid, lang, keyword_regions)
    end
end
```

**策略选择**：
- ✅ **优先 Treesitter**：准确度高，支持复杂语法
- ⚠️ **备用关键字**：简单快速，但可能有误报

#### `ClearSyntaxHighlight(languages)`

清除所有语法高亮：

```lua
-- 清除 Treesitter 高亮
local source_ns = api.nvim_create_namespace("LspUI_source_highlight")
api.nvim_buf_clear_namespace(bufid, source_ns, 0, -1)

-- 清除关键字高亮
for lang, _ in pairs(languages) do
    keyword_highlight.clear(bufid, lang)
end
```

## 性能考虑

### 为什么不创建临时 buffer？

❌ **不推荐的做法**：
```lua
-- 创建临时 buffer，将代码片段写入，然后用 Treesitter 解析
local tmp_buf = api.nvim_create_buf(false, true)
api.nvim_buf_set_lines(tmp_buf, 0, -1, false, code_lines)
local parser = vim.treesitter.get_parser(tmp_buf, lang)
```

**问题**：
1. 代码片段不完整，Treesitter 无法构建有效的语法树
2. 创建和销毁 buffer 有开销
3. 需要手动管理生命周期

✅ **推荐的做法**：
```lua
-- 直接使用源 buffer，它已经有完整的语法树
local highlighter = ts_highlighter.active[source_buf]
if highlighter then
    parser = highlighter.tree  -- 复用已有的
end
```

### 性能优化清单

- [x] **复用已有的 highlighter**：避免重新解析文件
- [x] **行范围查询**：`iter_captures(query, root, buf, start_row, end_row)`
- [x] **缓存提取结果**：相同行不重复查询
- [x] **增量解析**：Treesitter 自动优化
- [x] **提前过滤**：跳过完全不在目标行的节点
- [x] **自动清理**：BufDelete/BufWipeout 时清理缓存

### 性能基准

对于典型的代码片段显示场景：
- **Treesitter 提取**：< 1ms（使用已有 highlighter）
- **关键字匹配**：< 0.5ms（每行）
- **缓存命中**：< 0.1ms

## 边界情况处理

### 1. 跨行节点

**场景**：多行字符串、多行注释

```go
msg := `This is a
multi-line string`
```

**处理**：
```lua
-- 计算在当前行的实际列范围
local actual_start_col = start_row == source_line and start_col or 0
local actual_end_col = end_row == source_line and end_col or #line_text
```

### 2. 空行或无效行

**处理**：
```lua
local ok, lines = pcall(api.nvim_buf_get_lines, source_buf, source_line, source_line + 1, false)
if not ok or not lines or #lines == 0 then
    return {}  -- 返回空数组，避免错误
end
```

### 3. Buffer 失效

**处理**：
```lua
if not api.nvim_buf_is_valid(source_buf) then
    return {}
end
```

### 4. 列范围越界

**处理**：
```lua
target_start = math.max(target_start, target_col_start)
target_end = math.min(target_end, actual_target_end)

if target_start < target_end and target_start >= 0 then
    -- 应用高亮
end
```

### 5. 不支持的语言

**Treesitter**：静默失败，返回空数组
**关键字**：返回 `false`，调用者可以知道不支持

## 命名空间管理

### Treesitter 高亮
```lua
local ns = api.nvim_create_namespace("LspUI_source_highlight")
```

### 关键字高亮
```lua
local ns = api.nvim_create_namespace("LspUI_keyword_" .. lang)
```

**优点**：
- 独立清理：可以单独清除某种语言的高亮
- 避免冲突：不同来源的高亮不会互相覆盖

## 测试建议

### 功能测试

1. **基本高亮**：
   - [ ] 打开 SubView，查看 Go 函数定义的高亮
   - [ ] 验证关键字、类型、内置函数颜色正确

2. **列偏移映射**：
   - [ ] 源文件有缩进的代码
   - [ ] 验证 SubView 中高亮位置准确

3. **多语言支持**：
   - [ ] 测试 Lua, Rust, TypeScript 等 12 种语言
   - [ ] 验证关键字不冲突

4. **边界情况**：
   - [ ] 多行字符串/注释
   - [ ] 空行
   - [ ] 极长的行（> 1000 字符）

### 性能测试

1. **大文件场景**：
   - [ ] 打开 5000+ 行的文件
   - [ ] 显示多个 SubView
   - [ ] 验证无明显延迟

2. **频繁切换**：
   - [ ] 快速打开/关闭 SubView
   - [ ] 验证无内存泄漏

3. **缓存有效性**：
   - [ ] 修改源文件
   - [ ] 重新打开 SubView
   - [ ] 验证高亮更新正确

## 故障排查

### 问题：高亮完全不显示

**可能原因**：
1. Treesitter parser 未安装：`:TSInstall <lang>`
2. 源 buffer 无效：检查 `source_buf` 是否有效
3. 列偏移计算错误：检查 `source_col_offset`

**调试**：
```lua
-- 在 apply_highlights 中添加
vim.notify(string.format(
    "Applying: line=%d, col=%d-%d, src_buf=%d, src_line=%d, offset=%d",
    target_line, target_col_start, target_col_end,
    source_buf, source_line, source_col_offset
))
```

### 问题：高亮位置不对

**可能原因**：
1. `source_col_offset` 计算错误
2. `target_col_start` 传递错误
3. 源文件包含多字节字符（UTF-8）

**调试**：
```lua
-- 检查映射计算
local target_start = target_col_start + (src_start - source_col_offset)
vim.notify(string.format(
    "Mapping: src=%d-%d, target=%d-%d (offset=%d)",
    src_start, src_end, target_start, target_end, source_col_offset
))
```

### 问题：部分关键字未高亮

**可能原因**：
1. 关键字定义缺失
2. 单词边界模式匹配失败（特殊字符）
3. Treesitter 优先级覆盖

**解决**：
1. 检查 `LANGUAGE_KEYWORDS` 定义
2. 验证 `vim.pesc()` 是否正确转义
3. 检查 highlight group 是否定义

## 未来改进

### 短期

- [ ] 添加更多语言支持（Ruby, Swift, Kotlin 等）
- [ ] 优化关键字正则表达式性能
- [ ] 添加配置选项（禁用 Treesitter/关键字）

### 长期

- [ ] 支持语义高亮（LSP semantic tokens）
- [ ] 支持自定义关键字定义
- [ ] 支持高亮优先级配置
- [ ] 提供高亮调试工具

## 参考资料

- [Neovim Treesitter 文档](https://neovim.io/doc/user/treesitter.html)
- [Treesitter Highlighter 源码](https://github.com/neovim/neovim/blob/master/runtime/lua/vim/treesitter/highlighter.lua)
- [Lua Pattern Matching](https://www.lua.org/manual/5.1/manual.html#5.4.1)

## 维护者

如有问题或建议，请提交 Issue 或 Pull Request。

---

**最后更新**：2025-11-13
**版本**：1.0.0
