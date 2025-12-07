# AGENTS.md

## Project Overview

LspUI.nvim is a modern Neovim plugin written in Lua that enhances LSP functionality with beautiful and intuitive user interfaces. It provides 13 enhanced LSP modules including code actions, rename, hover, diagnostics, navigation (definition/reference/implementation), call hierarchy, lightbulb indicators, and jump history.

**Key characteristics:**
- Pure Lua codebase targeting Neovim 0.11+
- Modular architecture with independent feature modules
- Custom UI layer for floating windows and displays

## File Structure

```
lua/LspUI/
├── **/init.lua           - Module entry points for each LSP feature
├── layer/                - Core UI and utility layers
│   ├── controller.lua    - Main UI controller logic
│   ├── view.lua          - View rendering
│   ├── main_view.lua     - Main window management
│   ├── sub_view.lua      - Secondary window management
│   └── notify.lua        - Notification system
├── config.lua            - Configuration system with defaults
├── command.lua           - Command registration
├── modules.lua           - Module registry
└── api.lua               - Public API
doc/                      - Vim help documentation
```

## Code Style

### Lua Conventions
- Use 4 spaces for indentation (configured in `.stylua.toml`)
- Follow the existing module pattern: each feature has its own directory with `init.lua`
- Type annotations: Use LuaLS type annotations (`---@type`, `---@param`, `---@return`)
- Naming: snake_case for functions and variables
- Local by default: Always use `local` unless exporting

### Module Structure Pattern
```lua
local M = {}

M.init = function()
    -- Module initialization (commands, autocommands, etc.)
end

-- Additional module functions

return M
```

### Configuration Pattern
- All features have an `enable` flag and `command_enable` flag
- Use `vim.tbl_deep_extend("force", defaults, user_config)` to merge configs
- Validate user input and provide helpful error messages via `require("LspUI.layer.notify")`

## Cross-Platform Compatibility

This plugin must support all three major platforms:
- **Linux** - Primary development platform
- **macOS** - Full feature parity with Linux
- **Windows** - Full feature parity with Linux and macOS

### Platform Considerations
- Use `vim.fn.has()` to check platform-specific features when necessary
- Use `vim.uv` (libuv) APIs for cross-platform file operations and async tasks
- Avoid platform-specific shell commands or paths
- Test path separators work correctly across platforms (`/` vs `\`)
- Use Neovim's built-in APIs (`vim.fn`, `vim.api`, `vim.lsp`) which are cross-platform by design
