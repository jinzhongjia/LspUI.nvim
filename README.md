# 🧰LspUI.nvim

A modern and useful UI plugin that wraps lsp operations.

> As neovim is the host system, its plugins should be kept as minimally intrusive as possible

## FAQ

**Why I make this plugin?**

In the past, I was a loyal user of `lspsaga`! But sometimes `lspsaga` has _breakchange_ which will affect my work, I just want a stable plugin, So I made this plugin with reference to the ui of lspsaga.

I only refer to its UI design, and the code logic is written by myself (part of the processing method refers to the official lsp library)!

If you criticize me because I refer `lspsaga`'s UI design, you win.

## 🛎️Features Supported

- Code Action(menu and lighthulb)
- Rename
- Hover Document
- Diagnostic
- Peek Definition

## 🪡Recommend

For other features of lsp, such as `Defination`, `References`, `implementations`, you use this plugin [DNLHC/glance.nvim](https://github.com/DNLHC/glance.nvim), it is very good for above

## 🛠️Install

**Neovim(stable)**, but recommend you use **Neovim(nightly)**, now stable not support `title_pos`

### Lazy.nvim

```lua
{
    "jinzhongjia/LspUI.nvim",
    event="VeryLazy",
    config=function()
        require("LspUI").setup()
    end
}
```

### Packer.nvim

```lua
use {
        "jinzhongjia/LspUI.nvim",
        -- event = 'VimEnter',
        config=function()
            require("LspUI").setup()
        end
    }
```

## 💾Config

If you want to use lua api to bind key, you can use the follow way.

```lua
local api = require("LspUI").api
-- more api info you can read api.lua in source code
```

```lua
-- Default config
require("LspUI").setup({
    lightbulb = {
        enable = false, -- close by default
        command_enable = false, -- close by default, this switch does not have to be turned on, this command has no effect
        icon = "💡",
    },
    code_action = {
        enable = true,
        command_enable = true,
        icon = "💡",
        keybind = {
            exec = "<CR>",
            prev = "k",
            next = "j",
            quit = "q",
        },
    },
    hover = {
        enable = true,
        command_enable = true,
        keybind = {
            prev = "p",
            next = "n",
            quit = "q",
        },
    },
    rename = {
        enable = true,
        command_enable = true,
        auto_select = true, -- whether select all automatically
        keybind = {
            change = "<CR>",
            quit = "<ESC>",
        },
    },
    diagnostic = {
        enable = true,
        command_enable = true,
        icons = {
            Error = " ",
            Warn = " ",
            Info = " ",
            Hint = " ",
        },
    },
    peek_definition = {
        enable = false, -- close by default
        command_enable = true,
        keybind = {
            edit = "op",
            vsplit = "ov",
            split = "os",
            quit = "q",
        },
    },
})
```

## 🎁Command

- `LspUI hover`
- `LspUI rename`
- `LspUI code_action`
- `LspUI diagnostic next`
- `LspUI diagnostic prev`
- `LspUI peek_definition`

## 🧭Design ideas

- Highly controllable functions
- Least invasive

## 📸Screenshot

**Code Action**:

![code_action_menu](https://github.com/jinzhongjia/LspUI.nvim/blob/main/.img/code_action.png)

![code_action_lightbulb](https://github.com/jinzhongjia/LspUI.nvim/blob/main/.img/lightbulb.png)

**Rename**:

![rename](https://github.com/jinzhongjia/LspUI.nvim/blob/main/.img/rename.png?raw=true)

**Hover Document**:

![hover_document](https://github.com/jinzhongjia/LspUI.nvim/blob/main/.img/hover_document.png)

**Diagnostic**:

![diagnostic](https://github.com/jinzhongjia/LspUI.nvim/blob/main/.img/diagnostic.png)

**Peek Definition**:

![peek_definition](https://github.com/jinzhongjia/LspUI.nvim/blob/main/.img/peek_definition.png)

## 📔Todo

- Define(`Defination` and `Type Definitions`)
- Finder(`References` and `implementations`)

## 🔮Thanks

- [lspsaga.nvim](https://github.com/glepnir/lspsaga.nvim) - inspiration
