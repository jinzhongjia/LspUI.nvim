# LspUI.nvim

A modern Neovim plugin that enhances LSP functionality with beautiful and intuitive user interfaces.

## Features

LspUI.nvim provides 13 enhanced LSP modules with custom UI implementations:

- Code Action - Enhanced code action menu with plugin registration support
- Rename - Smart symbol renaming with preview
- Hover - Rich hover information with markdown support
- Diagnostics - Beautiful diagnostic displays with navigation
- Definition - Go to definition with enhanced UI
- Type Definition - Navigate to type definitions
- Declaration - Jump to symbol declarations
- Reference - Find all references with organized display
- Implementation - Locate implementations with filtering
- Inlay Hint - Toggle inlay hints with visual feedback
- Signature Help - Enhanced function signature assistance
- Call Hierarchy - Interactive call hierarchy navigation
- Lightbulb - Visual indicators for available code actions
- Jump History - Review recent LSP jumps in a searchable list with context

## Installation

Requirements:
- Neovim 0.11+
- A configured LSP server
- Recommended: A markdown plugin for enhanced hover features (render-markdown.nvim or markview.nvim)

Using lazy.nvim:

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

Using packer.nvim:

```lua
use {
  "jinzhongjia/LspUI.nvim",
  branch = "main",
  config = function()
    require("LspUI").setup({
      -- config options go here
    })
  end
}
```

## Configuration

Basic setup:

```lua
local LspUI = require("LspUI")
LspUI.setup()
```

Custom configuration:

```lua
require("LspUI").setup({
  -- Rename configuration
  rename = {
    enable = true,
    command_enable = true,
    auto_select = true,
    fixed_width = false,
    width = 30,
    key_binding = {
      exec = "<CR>",
      quit = "<ESC>",
    },
    border = "rounded",
    transparency = 0,
  },
  
  -- Code Action configuration
  code_action = {
    enable = true,
    command_enable = true,
    gitsigns = true,
    key_binding = {
      exec = "<cr>",
      prev = "k",
      next = "j",
      quit = "q",
    },
    border = "rounded",
    transparency = 0,
  },
  
  -- Hover configuration
  hover = {
    enable = true,
    command_enable = true,
    key_binding = {
      prev = "p",
      next = "n",
      quit = "q",
    },
    border = "rounded",
    transparency = 0,
  },
  
  -- Diagnostic configuration
  diagnostic = {
    enable = true,
    command_enable = true,
    border = "rounded",
    transparency = 0,
    severity = nil,
    show_source = true,
    show_code = true,
    show_related_info = true,
    max_width = 0.6,
  },
  
  -- Lightbulb configuration
  lightbulb = {
    enable = true,
    is_cached = true,
    icon = "💡",
    debounce = 250,
  },
  
  -- Inlay Hint configuration
  inlay_hint = {
    enable = true,
    command_enable = true,
    filter = {
      whitelist = {},
      blacklist = {},
    },
  },
  
  -- Signature configuration
  signature = {
    enable = false,
    icon = "✨",
    color = {
      fg = "#FF8C00",
      bg = nil,
    },
    debounce = 300,
  },
  
  -- Definition, Reference, Implementation, Type Definition, Declaration
  definition = {
    enable = true,
    command_enable = true,
  },
  
  reference = {
    enable = true,
    command_enable = true,
  },
  
  implementation = {
    enable = true,
    command_enable = true,
  },
  
  type_definition = {
    enable = true,
    command_enable = true,
  },
  
  declaration = {
    enable = true,
    command_enable = true,
  },
  
  -- Call Hierarchy configuration
  call_hierarchy = {
    enable = true,
    command_enable = true,
  },
  
  -- Position keybinds for definition, reference, etc.
  pos_keybind = {
    main = {
      back = "<leader>l",
      hide_secondary = "<leader>h",
    },
    secondary = {
      jump = "o",
      jump_split = "sh",
      jump_vsplit = "sv",
      jump_tab = "t",
      toggle_fold = "<CR>",
      next_entry = "J",
      prev_entry = "K",
      quit = "q",
      hide_main = "<leader>h",
      fold_all = "w",
      expand_all = "e",
      enter = "<leader>l",
    },
    transparency = 0,
    main_border = "none",
    secondary_border = "single",
  },
})
```

Jump History and Virtual Scroll configuration:

```lua
require("LspUI").setup({
  jump_history = {
    enable = true,
    command_enable = true,
    max_size = 50,
    win_max_height = 20,
    smart_jumplist = {
      min_distance = 5,
      cross_file_only = false,
    },
  },
  virtual_scroll = {
    threshold = 500,
    chunk_size = 200,
    load_more_threshold = 50,
  },
})
```

For more detailed configuration options, see the Configuration Wiki at https://github.com/jinzhongjia/LspUI.nvim/wiki/Config

## Commands

Basic LSP Operations:
- LspUI hover - Open an LSP hover window above cursor
- LspUI rename - Rename the symbol below the cursor
- LspUI code_action - Open a code action selection prompt

Navigation Commands:
- LspUI definition - Go to definition
- LspUI type_definition - Go to type definition
- LspUI declaration - Go to declaration
- LspUI reference - Show all references
- LspUI implementation - Show all implementations

Diagnostic Commands:
- LspUI diagnostic next - Go to the next diagnostic
- LspUI diagnostic prev - Go to the previous diagnostic

Call Hierarchy Commands:
- LspUI call_hierarchy incoming_calls - Show incoming calls
- LspUI call_hierarchy outgoing_calls - Show outgoing calls

Utility Commands:
- LspUI inlay_hint - Toggle inlay hints on/off
- LspUI signature - Show signature help
- LspUI history - Open the interactive jump history viewer

Keybinding example:

```lua
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

## Screenshots

See https://github.com/jinzhongjia/LspUI.nvim/wiki/Screen-Shot for visual examples of all features.

## Reference

This plugin was inspired by and references:

- [lspsaga.nvim](https://github.com/glepnir/lspsaga.nvim) - Original inspiration for enhanced LSP UI
- [glance.nvim](https://github.com/DNLHC/glance.nvim) - Reference for navigation interfaces
