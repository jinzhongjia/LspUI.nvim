# LspUI.nvim

A plugin which wrap s lsp opeartions

## Design ideas

> As neovim is the host system, its plugins should be kept as minimally intrusive as possible
>
> And plugins should be highly controllable

-   Highly controllable functions
-   Least invasive

## Feature

Re-implemented some functions of neovim, theoretically, the running speed should be slightly higher than the built-in functions of neovim, and at the same time, it has a good UI

-   `code action`
-   `rename`
-   `hover`
-   `diagnostic`

## Install

neovim version is `nightly`

Migrating from the old version, there is no need to change the original configuration (after refactoring, only some configuration items are deleted)

### Lazy.nvim

```lua
{
    "jinzhongjia/LspUI.nvim",
	branch = "v2",
    config=function()
        require("LspUI").setup()
    end
}
```

### Packer.nvim

```lua
use {
        "jinzhongjia/LspUI.nvim",
		branch = 'v2',
        config=function()
            require("LspUI").setup()
        end
    }
```

## Config

You just require `LspUI.nvim` like `require("LspUI").setup({})`.

For parameters, there are complete type annotations recognized by `lua_ls`

---

If you want to use lua api to bind key, you can use the follow way.

```lua
local api = require("LspUI").api
-- more api info you can read api.lua in source code
```

---

If you want to change the settings of the module in real time after neovim has loaded all the plugins, you can use:

`local LspUI_config = require("LspUI.config")`

```lua
-- LspUI_config has these function to use
{
    code_action_setup: function,
    diagnostic_setup: function,
    hover_setup: function,
    lightbulb_setup: function,
    rename_setup: function,
}
```

---

Default config:

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

-- default config
--- @type LspUI_config
local default_config = {
	rename = default_rename_config,
	lightbulb = default_lightbulb_config,
	code_action = default_code_action_config,
	diagnostic = default_diagnostic_config,
	hover = default_hover_config,
}
```

## Command

-   `LspUI hover`
-   `LspUI rename`
-   `LspUI code_action`
-   `LspUI diagnostic next`
-   `LspUI diagnostic prev`

## Current Goals

You can see [here](https://github.com/jinzhongjia/LspUI.nvim/issues/12)


## Reference

- [glepnir/lspsaga.nvim](https://github.com/glepnir/lspsaga.nvim)
