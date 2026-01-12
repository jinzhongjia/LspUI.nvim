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
- Our code need to support multiple platform environments(linux mac windows) without any issues

## Testing

### Testing Philosophy

All tests in this project are **internal integration tests** that do not require external dependencies:
- No real LSP server required
- No external plugins required (gitsigns, render-markdown, etc.)
- No real terminal UI interaction required
- No network access required

### What We Test

| Category | What We Test |
|----------|--------------|
| **Module Initialization** | init/deinit behavior, idempotency |
| **Configuration** | Default values, config merging, option validation |
| **Command System** | Registration, unregistration, completion, error handling |
| **Disabled State** | Graceful handling when features are disabled |
| **No-Client Warnings** | Proper notifications when no LSP client available |
| **Pure Utilities** | lib/path, lib/util, lib/diagnostic, lib/signature |
| **UI Components** | ClassView API (buffer/window creation, keymaps) |

### What We Do NOT Test

These require external conditions and are excluded from automated tests:
- Actual LSP request/response cycles (requires real LSP server)
- Real code action execution
- Actual rename operations across files
- Live hover content from LSP
- Syntax highlighting rendering (requires Treesitter)
- External plugin integrations (gitsigns, markdown renderers)
- Debounce timing with real delays

### Running Tests

```bash
# Install dependencies
mise run deps

# Run all tests
mise run test

# Run specific test file
mise run test:file file=tests/test_config.lua
```

### Test Framework

- **Framework**: mini.test (from mini.nvim)
- **Pattern**: `tests/test_*.lua`
- **Child Neovim**: Tests run in isolated child Neovim instances via `MiniTest.new_child_neovim()`

### Writing New Tests

Follow the existing pattern:
```lua
local h = require("tests.helpers")
local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()

local T = new_set({
    hooks = {
        pre_case = function() h.child_start(child) end,
        post_once = child.stop,
    },
})

T["module name"]["test description"] = function()
    local result = child.lua([[ ... ]])
    h.eq(expected, result)
end

return T
```

## LLM NOTES

- Ensure all UI elements are responsive and adapt to different terminal sizes
- Use Neovim's native floating window APIs for all popups and dialogs
- Provide clear error messages and fallbacks for unsupported LSP features
- Optimize performance for large codebases and files
- Follow Neovim's best practices for async operations to avoid blocking the UI
- Maintain a consistent user experience across all LSP features
- If need to access file system, use `vim.loop` (libuv) for cross-platform compatibility
- LLM can modify this file to add more notes as needed

