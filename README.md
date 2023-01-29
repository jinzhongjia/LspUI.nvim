# 🧰LspUI.nvim

A modern and useful UI plugin that wraps lsp operations.

> As neovim is the host system, its plugins should be kept as minimally intrusive as possible

## 🛎️Features Supported

-   Code Action(menu and lighthulb)
-   Rename
-   Hover Document
-   Diagnostic

## 🪡Recommand

For other features of lsp, such as `Defination`, `References`, `implementations`, you use this plugin [DNLHC/glance.nvim](https://github.com/DNLHC/glance.nvim), it is very good for above

## 🛠️Install

**Neovim(stable)**, but recommand you use **Neovim(nightly)**, now stable not support `title_pos`

### Lazy.nvim

```lua
{
    "jinzhongjia/LspUI.nvim",
    event="Verylazy",
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

```lua
-- Default config
require("LspUI").setup({
	lightbulb = {
		enable = false,
		command_enable = false,
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
        -- when you have not-one document, this will jump next document
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
})
```

## 🎁Command

- `LspUI hover`
- `LspUI rename`
- `LspUI code_action`
- `LspUI diagnostic next`
- `LspUI diagnostic prev`

## 🧭Design ideas

-   Highly controllable functions
-   Least invasive

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

## 📔Todo

-   Define(`Defination` and `Type Definitions`)
-   Finder(`References` and `implementations`)
