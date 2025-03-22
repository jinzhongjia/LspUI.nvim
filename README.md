# LspUI.nvim

A plugin which wraps Neovim LSP operations with a nicer UI.

## ✨ Features

- Custom implementations of common LSP functions
- Great out of the box UI
- Due to reimplementation of builtins, potentially better performance than builtin neovim functions.
- Supported features:
  - Code Action (nvim plugin can register code_action)
  - Rename
  - Hover
  - Show Diagnostics
  - Definiton
  - Type Definition
  - Declaration
  - Reference
  - Implementation
  - Inlay Hint
  - Signature Help

## 📦 Installation

- Requires neovim `0.10`

Recommend to install one markdown plugin for hover feature, like [render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim), [markview.nvim](https://github.com/OXY2DEV/markview.nvim)

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "jinzhongjia/LspUI.nvim",
  branch = "main",
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
	branch = 'main',
	config = function()
    require("LspUI").setup({
	  -- config options go here
	  })
  end
}
```

## ⚙️ Configuration

```lua
local LspUI = require("LspUI")
LspUI.setup()
```

more about [here](https://github.com/jinzhongjia/LspUI.nvim/wiki/Config)

## 🚀Commands

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
-   `LspUI inlay_hint`: Quickly open or close inlay hint

## [Screen Shot](https://github.com/jinzhongjia/LspUI.nvim/wiki/Screen-Shot)

## Current Goals / Roadmap

You can see the current goals [here](https://github.com/jinzhongjia/LspUI.nvim/issues/12).

## Reference

- [glepnir/lspsaga.nvim](https://github.com/glepnir/lspsaga.nvim)
- [DNLHC/glance.nvim](https://github.com/DNLHC/glance.nvim)
