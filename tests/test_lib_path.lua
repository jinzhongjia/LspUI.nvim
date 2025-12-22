local h = require("tests.helpers")
local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()

local T = new_set({
    hooks = {
        pre_case = function()
            h.child_start(child)
        end,
        post_once = child.stop,
    },
})

T["normalize_path"] = new_set()

T["normalize_path"]["converts backslashes to forward slashes"] = function()
    local result = child.lua([[
        local path_lib = require("LspUI.lib.path")
        return path_lib.normalize_path("C:\\Users\\test\\file.lua", false)
    ]])
    h.eq("C:/Users/test/file.lua/", result)
end

T["normalize_path"]["adds trailing slash if missing"] = function()
    local result = child.lua([[
        local path_lib = require("LspUI.lib.path")
        return path_lib.normalize_path("/home/user/project", false)
    ]])
    h.eq("/home/user/project/", result)
end

T["normalize_path"]["keeps trailing slash if present"] = function()
    local result = child.lua([[
        local path_lib = require("LspUI.lib.path")
        return path_lib.normalize_path("/home/user/project/", false)
    ]])
    h.eq("/home/user/project/", result)
end

T["normalize_path"]["lowercases on windows"] = function()
    local result = child.lua([[
        local path_lib = require("LspUI.lib.path")
        return path_lib.normalize_path("C:\\Users\\Test\\FILE.lua", true)
    ]])
    h.eq("c:/users/test/file.lua/", result)
end

T["normalize_path"]["does not lowercase on non-windows"] = function()
    local result = child.lua([[
        local path_lib = require("LspUI.lib.path")
        return path_lib.normalize_path("/Home/User/FILE.lua", false)
    ]])
    h.eq("/Home/User/FILE.lua/", result)
end

T["normalize_display_path"] = new_set()

T["normalize_display_path"]["converts backslashes to forward slashes"] = function()
    local result = child.lua([[
        local path_lib = require("LspUI.lib.path")
        return path_lib.normalize_display_path("src\\components\\Button.tsx")
    ]])
    h.eq("src/components/Button.tsx", result)
end

T["normalize_display_path"]["keeps forward slashes unchanged"] = function()
    local result = child.lua([[
        local path_lib = require("LspUI.lib.path")
        return path_lib.normalize_display_path("src/components/Button.tsx")
    ]])
    h.eq("src/components/Button.tsx", result)
end

T["compare_uri"] = new_set()

T["compare_uri"]["returns true for identical URIs"] = function()
    local result = child.lua([[
        local path_lib = require("LspUI.lib.path")
        return path_lib.compare_uri(
            "file:///test/path.lua",
            "file:///test/path.lua",
            function(uri) return uri end,
            false
        )
    ]])
    h.eq(true, result)
end

T["compare_uri"]["returns false for different URIs"] = function()
    local result = child.lua([[
        local path_lib = require("LspUI.lib.path")
        return path_lib.compare_uri(
            "file:///test/path1.lua",
            "file:///test/path2.lua",
            function(uri) return uri end,
            false
        )
    ]])
    h.eq(false, result)
end

T["compare_uri"]["handles case insensitivity on windows"] = function()
    local result = child.lua([[
        local path_lib = require("LspUI.lib.path")
        return path_lib.compare_uri(
            "file:///C:/Test/Path.lua",
            "file:///c:/test/path.lua",
            function(uri) return uri:sub(8) end,
            true
        )
    ]])
    h.eq(true, result)
end

T["get_relative_path"] = new_set()

T["get_relative_path"]["returns relative path when within cwd"] = function()
    local result = child.lua([[
        local path_lib = require("LspUI.lib.path")
        return path_lib.get_relative_path("/home/user/project/src/file.lua", "/home/user/project", false)
    ]])
    h.eq("src/file.lua", result)
end

T["get_relative_path"]["returns nil when not within cwd"] = function()
    local result = child.lua([[
        local path_lib = require("LspUI.lib.path")
        return path_lib.get_relative_path("/other/path/file.lua", "/home/user/project", false) == nil
    ]])
    h.eq(true, result)
end

T["get_relative_path"]["handles windows paths"] = function()
    local result = child.lua([[
        local path_lib = require("LspUI.lib.path")
        return path_lib.get_relative_path("C:\\Users\\Test\\project\\src\\file.lua", "C:\\Users\\Test\\project", true)
    ]])
    h.eq("src/file.lua", result)
end

T["format_relative_display"] = new_set()

T["format_relative_display"]["formats current directory"] = function()
    local result = child.lua([[
        local path_lib = require("LspUI.lib.path")
        return path_lib.format_relative_display("file.lua")
    ]])
    h.eq(" (./)", result)
end

T["format_relative_display"]["formats subdirectory"] = function()
    local result = child.lua([[
        local path_lib = require("LspUI.lib.path")
        return path_lib.format_relative_display("src/components/Button.tsx")
    ]])
    h.eq(" (./src/components)", result)
end

T["format_absolute_display"] = new_set()

T["format_absolute_display"]["formats unix path"] = function()
    local result = child.lua([[
        local path_lib = require("LspUI.lib.path")
        return path_lib.format_absolute_display("/home/user/project/file.lua")
    ]])
    h.eq(" (/home/user/project)", result)
end

T["format_absolute_display"]["formats windows path"] = function()
    local result = child.lua([[
        local path_lib = require("LspUI.lib.path")
        return path_lib.format_absolute_display("C:\\Users\\Test\\file.lua")
    ]])
    h.eq(" (C:/Users/Test)", result)
end

return T
