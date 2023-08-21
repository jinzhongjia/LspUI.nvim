# LspUI.nvim

A plugin which wraps Neovim LSP operations with a nicer UI.


## ✨ Features

- Custom implementations of common LSP functions
- Great out of the box UI
- Due to reimplementation of builtins, potentially better performance than builtin neovim functions.
- Commands:
  - Code Action (nvim plugin can register code_action)
  - Rename
  - Hover
  - Show Diagnostics
  - Definiton
  - Type Definition
  - Declaration
  - Reference
  - Implementation

## 📦 Installation

- Requires neovim `nightly`
- Migrating from v1? See [Migration](#migration)

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
    "jinzhongjia/LspUI.nvim",
	branch = "v2",
    config = function()
        require("LspUI").setup({
			-- config options go here
		})
    end
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
        "jinzhongjia/LspUI.nvim",
		branch = 'v2',
        config = function()
            require("LspUI").setup({
				-- config options go here
			})
        end
    }
```

## ⚙️ Configuration

## Setup

```lua
require("LspUI").setup({
	code_action = {
		-- e.g disable gitsigns for code_action
		gitsigns = false
		-- ...
	},
	lightbulb = {},
	rename = {},
	diagnostic = {},
	hover = {},
	-- note: the stability of the following functions has not been tested
	definition = {},
	type_definition = {},
	declaration = {},
	implementation = {},
	reference = {},
	pos_keybind = {}, -- keybind for above
	-- See below for all options
})
```

---

To use bind a key with the lua api, use `require("LspUI").api`, for example:

```lua
local lsp_ui = require("LspUI").api

vim.keymap.set("n", "K", lsp_ui.api.hover, { desc = "LSP Hover" })
vim.keymap.set("n", "<leader>ca", lsp_ui.api.code_action, { desc = "LSP Code Action" })
-- ...etc.
-- see more in api.lua

```

---
You can also change the settings of any LspUI module at any time after initialization. For example:

```lua
local lsp_ui_config = require("LspUI.config")

-- Override just the properties you need
lsp_ui_config.code_action_setup({
	gitsigns = false
})

-- There are corresponding functions for each module:
lsp_ui_config.diagnostic_setup(...)
lsp_ui_config.hover_setup(...)
lsp_ui_config.lightbulb_setup(...)
lsp_ui_config.rename_setup(...)
```

---

### Default Config Options

```lua
--- @type LspUI_rename_config
local default_rename_config = {
	enable = true,
	command_enable = true,
	auto_select = true,
	key_binding = {
		exec = "<CR>",
		quit = "<ESC>",
	},
}

--- @type LspUI_lightbulb_config
local default_lightbulb_config = {
	enable = true,
	-- whether cache code action, if do, code action will use lightbulb's cache
	-- Sadly, currently this option is invalid, I haven't implemented caching yet
	is_cached = true,
	icon = "💡",
	-- defalt is 250 milliseconds, this will reduce calculations when you move the cursor frequently, but it will cause the delay of lightbulb, false will disable it
	debounce = 250, 
}

--- @type LspUI_code_action_config
local default_code_action_config = {
	enable = true,
	command_enable = true,
	gitsigns = true, -- this will support gitsigns code actions, if you install gitsigns
	key_binding = {
		exec = "<cr>",
		prev = "k",
		next = "j",
		quit = "q",
	},
}

--- @type LspUI_diagnostic_config
local default_diagnostic_config = {
	enable = true,
	command_enable = true,
}

--- @type LspUI_hover_config
local default_hover_config = {
	enable = true,
	command_enable = true,
	key_binding = {
		prev = "p",
		next = "n",
		quit = "q",
	},
}

--- @type LspUI_definition_config
local default_definition_config = {
    enable = true,
    command_enable = true,
}

--- @type LspUI_type_definition_config
local default_type_definition_config = {
    enable = true,
    command_enable = true,
}

--- @type LspUI_declaration_config
local default_declaration_config = {
    enable = true,
    command_enable = true,
}

--- @type LspUI_implementation_config
local default_implementation_config = {
    enable = true,
    command_enable = true,
}

--- @type LspUI_reference_config
local default_reference_config = {
    enable = true,
    command_enable = true,
}

--- @type LspUI_pos_keybind_config
local default_pos_keybind_config = {
    main = {
        back = "q",
        hide_secondary = "<leader>h",
    },
    secondary = {
        jump = "o",
        quit = "q",
        hide_main = "<leader>h",
        enter = "<leader>l",
    },
}

-- default config
--- @type LspUI_config
local default_config = {
    rename = default_rename_config,
    lightbulb = default_lightbulb_config,
    code_action = default_code_action_config,
    diagnostic = default_diagnostic_config,
    hover = default_hover_config,
    definition = default_definition_config,
    type_definition = default_type_definition_config,
    declaration = default_declaration_config,
    implementation = default_implementation_config,
    reference = default_reference_config,
    pos_keybind = default_pos_keybind_config,
}

```
## 🚀 Usage

## Commands

-   `LspUI hover`: Open an LSP hover window above cursor
-   `LspUI rename`: Rename the symbol below the cursor
-   `LspUI code_action`: Open a code action selection prompt
-   `LspUI diagnostic next`: Go to the next diagnostic
-   `LspUI diagnostic prev`: Go to the previous diagnostic
-   `LspUI definition`: Open the definition
-   `LspUI type_definition`: Open the type definition
-   `LspUI declaration`: Open the declaration
-   `LspUI reference`: Open the reference
-   `LspUI implementation`: Open the implementation

## Register `code action`

now, you can register your handle on `LspUI.nvim`, just like this:

```lua
local LspUI_register = require("LspUI.code_action.register")

-- register code action
LspUI_register.register(
    "demo",
    --- @param uri lsp.URI
    --- @param range lsp.Range
    function(uri, range)
        --- @type {title:string,action:function}[]
        local res

        -- do something

        return res
    end
)

-- unregister code action
LspUI_register.unregister("demo")
```

## Migration

There's no need to change the your configuration as it's backwards compatible - however, some previous config items are deleted in v2. 

## Current Goals / Roadmap

You can see the current goals [here](https://github.com/jinzhongjia/LspUI.nvim/issues/12).

### Design Goals

> As neovim is the host system, its plugins should be kept as minimally intrusive as possible
>
> And plugins should be highly controllable

-   Highly controllable functions
-   Minimally invasive


## Reference

- [glepnir/lspsaga.nvim](https://github.com/glepnir/lspsaga.nvim)
- [DNLHC/glance.nvim](https://github.com/DNLHC/glance.nvim)
