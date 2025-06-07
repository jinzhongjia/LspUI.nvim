# LspUI.nvim

A modern, customizable Neovim plugin that enhances LSP functionality with beautiful and intuitive user interfaces.

## ✨ Features

- **13 Enhanced LSP Modules**: Custom implementations of essential LSP operations with improved UI/UX
- **Beautiful Out-of-the-box UI**: Thoughtfully designed interfaces for better code navigation and editing
- **Optimized Performance**: Reimplemented LSP functions for potentially better performance than builtin Neovim functions
- **Highly Customizable**: Extensive configuration options for each module
- **Smart UI Components**: 
  - Floating windows with borders and highlights
  - Interactive lightbulb indicators for code actions
  - Breadcrumb navigation for call hierarchy
  - Customizable keybindings for all interfaces

### Supported LSP Features:
- **Code Action** - Enhanced code action menu with plugin registration support
- **Rename** - Smart symbol renaming with preview
- **Hover** - Rich hover information with markdown support
- **Diagnostics** - Beautiful diagnostic displays with navigation
- **Definition** - Go to definition with enhanced UI
- **Type Definition** - Navigate to type definitions
- **Declaration** - Jump to symbol declarations  
- **Reference** - Find all references with organized display
- **Implementation** - Locate implementations with filtering
- **Inlay Hint** - Toggle inlay hints with visual feedback
- **Signature Help** - Enhanced function signature assistance
- **Call Hierarchy** - Interactive call hierarchy navigation
- **Lightbulb** - Visual indicators for available code actions

## 📦 Installation

### Requirements

- Neovim `0.11+`
- A configured LSP server
- **Recommended**: A markdown plugin for enhanced hover features:
  - [render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim)
  - [markview.nvim](https://github.com/OXY2DEV/markview.nvim)

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

### Basic Setup

```lua
local LspUI = require("LspUI")
LspUI.setup()
```

### Custom Configuration

```lua
require("LspUI").setup({
  -- General settings
  prompt = {
    border = true,
    borderchars = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" },
  },
  
  -- Code Action configuration
  code_action = {
    enable = true,
    command_enable = true,
    gitsigns = false,
    extend_gitsigns = false,
    ui = {
      title = "Code Action",
      border = "rounded",
      winblend = 0,
    },
    keys = {
      quit = "q",
      exec = "<CR>",
    },
  },
  
  -- Hover configuration  
  hover = {
    enable = true,
    command_enable = true,
    ui = {
      title = "Hover",
      border = "rounded",
      winblend = 0,
    },
    keys = {
      quit = "q",
    },
  },
  
  -- Rename configuration
  rename = {
    enable = true,
    command_enable = true,
    auto_save = false,
    ui = {
      title = "Rename",
      border = "rounded",
      winblend = 0,
    },
    keys = {
      quit = "<C-c>",
      exec = "<CR>",
    },
  },
  
  -- Diagnostic configuration
  diagnostic = {
    enable = true,
    command_enable = true,
    ui = {
      title = "Diagnostic",
      border = "rounded",
      winblend = 0,
    },
    keys = {
      quit = "q",
      exec = "<CR>",
    },
  },
  
  -- Definition configuration
  definition = {
    enable = true,
    command_enable = true,
    ui = {
      title = "Definition",
      border = "rounded",
      winblend = 0,
    },
    keys = {
      quit = "q",
      exec = "<CR>",
      vsplit = "v",
      split = "s",
      tabe = "t",
    },
  },
  
  -- Reference configuration
  reference = {
    enable = true,
    command_enable = true,
    ui = {
      title = "Reference",
      border = "rounded",
      winblend = 0,
    },
    keys = {
      quit = "q",
      exec = "<CR>",
      vsplit = "v",
      split = "s",
      tabe = "t",
    },
  },
  
  -- Implementation configuration
  implementation = {
    enable = true,
    command_enable = true,
    ui = {
      title = "Implementation",
      border = "rounded",
      winblend = 0,
    },
    keys = {
      quit = "q",
      exec = "<CR>",
      vsplit = "v",
      split = "s",
      tabe = "t",
    },
  },
  
  -- Type Definition configuration
  type_definition = {
    enable = true,
    command_enable = true,
    ui = {
      title = "Type Definition",
      border = "rounded",
      winblend = 0,
    },
    keys = {
      quit = "q",
      exec = "<CR>",
      vsplit = "v",
      split = "s",
      tabe = "t",
    },
  },
  
  -- Declaration configuration
  declaration = {
    enable = true,
    command_enable = true,
    ui = {
      title = "Declaration",
      border = "rounded",
      winblend = 0,
    },
    keys = {
      quit = "q",
      exec = "<CR>",
      vsplit = "v",
      split = "s",
      tabe = "t",
    },
  },
  
  -- Call Hierarchy configuration
  call_hierarchy = {
    enable = true,
    command_enable = true,
    ui = {
      title = "Call Hierarchy",
      border = "rounded",
      winblend = 0,
    },
    keys = {
      quit = "q",
      exec = "<CR>",
      expand = "o",
      jump = "e",
      vsplit = "v",
      split = "s",
      tabe = "t",
    },
  },
  
  -- Lightbulb configuration
  lightbulb = {
    enable = true,
    command_enable = true,
    icon = "💡",
    action_kind = {
      QuickFix = "🔧",
      Refactor = "♻️",
      RefactorExtract = "📤",
      RefactorInline = "📥",
      RefactorRewrite = "✏️",
      Source = "📄",
      SourceOrganizeImports = "📦",
    },
  },
  
  -- Inlay Hint configuration
  inlay_hint = {
    enable = true,
    command_enable = true,
  },
  
  -- Signature Help configuration
  signature = {
    enable = true,
    command_enable = true,
    ui = {
      title = "Signature Help",
      border = "rounded",
      winblend = 0,
    },
    keys = {
      quit = "q",
    },
  },
})
```

For more detailed configuration options, see the [Configuration Wiki](https://github.com/jinzhongjia/LspUI.nvim/wiki/Config).

## 🚀 Commands

### Basic LSP Operations
- `LspUI hover` - Open an LSP hover window above cursor
- `LspUI rename` - Rename the symbol below the cursor  
- `LspUI code_action` - Open a code action selection prompt

### Navigation Commands
- `LspUI definition` - Go to definition
- `LspUI type_definition` - Go to type definition  
- `LspUI declaration` - Go to declaration
- `LspUI reference` - Show all references
- `LspUI implementation` - Show all implementations

### Diagnostic Commands
- `LspUI diagnostic next` - Go to the next diagnostic
- `LspUI diagnostic prev` - Go to the previous diagnostic

### Call Hierarchy Commands
- `LspUI call_hierarchy incoming_calls` - Show incoming calls
- `LspUI call_hierarchy outgoing_calls` - Show outgoing calls

### Utility Commands
- `LspUI inlay_hint` - Toggle inlay hints on/off
- `LspUI signature` - Show signature help

### Advanced Features
- **Lightbulb**: Automatically shows visual indicators when code actions are available
- **Plugin Integration**: Supports code action registration from other Neovim plugins

## 📖 Documentation

For comprehensive documentation including keybindings, API reference, and advanced configuration:

```vim
:help LspUI
```

Or visit the [Wiki](https://github.com/jinzhongjia/LspUI.nvim/wiki) for additional resources.

## 💡 Quick Start Example

```lua
-- Basic keybinding setup
vim.keymap.set("n", "K", "<cmd>LspUI hover<CR>")
vim.keymap.set("n", "gr", "<cmd>LspUI reference<CR>")  
vim.keymap.set("n", "gd", "<cmd>LspUI definition<CR>")
vim.keymap.set("n", "gt", "<cmd>LspUI type_definition<CR>")
vim.keymap.set("n", "gi", "<cmd>LspUI implementation<CR>")
vim.keymap.set("n", "<leader>rn", "<cmd>LspUI rename<CR>")
vim.keymap.set("n", "<leader>ca", "<cmd>LspUI code_action<CR>")
vim.keymap.set("n", "<leader>ci", "<cmd>LspUI call_hierarchy incoming_calls<CR>")
vim.keymap.set("n", "<leader>co", "<cmd>LspUI call_hierarchy outgoing_calls<CR>")
```

## 📸 [Screenshots](https://github.com/jinzhongjia/LspUI.nvim/wiki/Screen-Shot)

See the [Screenshots Wiki](https://github.com/jinzhongjia/LspUI.nvim/wiki/Screen-Shot) for visual examples of all features.

## 🗺️ Current Goals / Roadmap

You can see the current development goals and upcoming features [here](https://github.com/jinzhongjia/LspUI.nvim/issues/12).

## 🤝 Contributing

Contributions are welcome! Please feel free to submit pull requests or open issues for bugs, feature requests, or suggestions.

## 📚 Reference

This plugin was inspired by and references:

- [lspsaga.nvim](https://github.com/glepnir/lspsaga.nvim) - Original inspiration for enhanced LSP UI
- [glance.nvim](https://github.com/DNLHC/glance.nvim) - Reference for navigation interfaces
