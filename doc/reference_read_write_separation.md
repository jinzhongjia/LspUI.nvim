# Reference 读写分离功能

## 功能介绍

LspUI.nvim 现在支持将 LSP reference 的结果按照读取和写入操作分开显示，让你能够更清晰地看到变量或函数在哪里被修改，在哪里被引用。

## 使用方式

### 配置

在你的 Neovim 配置中添加：

```lua
require('LspUI').setup({
    reference = {
        enable = true,
        command_enable = true,
        separate_read_write = true,  -- 启用读写分离显示（默认为 true）
    }
})
```

### 禁用读写分离

如果你想恢复原来的混合显示模式，设置 `separate_read_write = false`：

```lua
require('LspUI').setup({
    reference = {
        enable = true,
        command_enable = true,
        separate_read_write = false,  -- 禁用读写分离，恢复混合显示
    }
})
```

## 显示效果

### 启用读写分离时

```
▼ filename.lua (./)
   ▪ Writes: (2)
     local foo = 123
     foo = 456
   ▪ Reads: (3)
     print(foo)
     return foo
     if foo > 0 then

▼ another_file.lua (./src)
   ▪ Writes: (1)
     module.foo = "updated"
   ▪ Reads: (2)
     local value = module.foo
     process(module.foo)
```

### 禁用读写分离时（传统模式）

```
▼ filename.lua (./)
   local foo = 123
   foo = 456
   print(foo)
   return foo
   if foo > 0 then

▼ another_file.lua (./src)
   module.foo = "updated"
   local value = module.foo
   process(module.foo)
```

## 写操作识别模式

系统会将以下模式识别为写操作：

1. **变量赋值**
   - `foo = value`
   - `local foo = value`
   - `foo, bar = values`

2. **函数定义**
   - `function foo()`
   - `local function foo()`
   - `Class:foo()`
   - `Class.foo = function()`

3. **表字段赋值**
   - `table.foo = value`
   - `table["foo"] = value`
   - `table['foo'] = value`

4. **自增/自减操作**（支持其他语言）
   - `foo++`
   - `++foo`
   - `foo--`
   - `--foo`

5. **复合赋值操作**
   - `foo += value`
   - `foo -= value`
   - `foo *= value`
   - `foo /= value`

其他所有情况都会被识别为读操作。

## 快捷键

在 reference 结果窗口中，所有原有的快捷键保持不变：

- `o` - 跳转到引用位置
- `<CR>` - 折叠/展开文件
- `J/K` - 在引用间导航
- `q` - 关闭窗口
- `w` - 折叠所有文件
- `e` - 展开所有文件

## 注意事项

1. 读写检测基于语法模式匹配，可能不是 100% 准确，特别是在复杂的代码结构中
2. 读写分离功能仅对 reference 功能有效，不影响 definition、implementation 等其他功能
3. 分组显示会在每个分组标题后显示该分组的引用数量，方便快速了解读写分布