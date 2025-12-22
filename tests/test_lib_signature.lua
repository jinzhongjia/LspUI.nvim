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

T["build_signature_info"] = new_set()

T["build_signature_info"]["returns nil for nil input"] = function()
    local result = child.lua([[
        local sig = require("LspUI.lib.signature")
        return sig.build_signature_info(nil) == nil
    ]])
    h.eq(true, result)
end

T["build_signature_info"]["returns nil for empty signatures"] = function()
    local result = child.lua([[
        local sig = require("LspUI.lib.signature")
        return sig.build_signature_info({ signatures = {} }) == nil
    ]])
    h.eq(true, result)
end

T["build_signature_info"]["returns nil when signatures field is missing"] = function()
    local result = child.lua([[
        local sig = require("LspUI.lib.signature")
        return sig.build_signature_info({}) == nil
    ]])
    h.eq(true, result)
end

T["build_signature_info"]["extracts basic signature info"] = function()
    local result = child.lua([[
        local sig = require("LspUI.lib.signature")
        local help = {
            signatures = {
                { label = "func(a, b)" }
            }
        }
        return sig.build_signature_info(help)
    ]])
    h.eq("func(a, b)", result.label)
    h.eq(nil, result.parameters)
end

T["build_signature_info"]["extracts string documentation"] = function()
    local result = child.lua([[
        local sig = require("LspUI.lib.signature")
        local help = {
            signatures = {
                { label = "func()", documentation = "This is a function" }
            }
        }
        return sig.build_signature_info(help)
    ]])
    h.eq("This is a function", result.doc)
end

T["build_signature_info"]["extracts MarkupContent documentation"] = function()
    local result = child.lua([[
        local sig = require("LspUI.lib.signature")
        local help = {
            signatures = {
                {
                    label = "func()",
                    documentation = { kind = "markdown", value = "Markdown doc" }
                }
            }
        }
        return sig.build_signature_info(help)
    ]])
    h.eq("Markdown doc", result.doc)
end

T["build_signature_info"]["handles activeSignature"] = function()
    local result = child.lua([[
        local sig = require("LspUI.lib.signature")
        local help = {
            activeSignature = 1,
            signatures = {
                { label = "func1()" },
                { label = "func2()" }
            }
        }
        return sig.build_signature_info(help)
    ]])
    h.eq("func2()", result.label)
end

T["build_signature_info"]["clamps invalid activeSignature"] = function()
    local result = child.lua([[
        local sig = require("LspUI.lib.signature")
        local help = {
            activeSignature = 10,
            signatures = {
                { label = "func1()" },
                { label = "func2()" }
            }
        }
        return sig.build_signature_info(help)
    ]])
    h.eq("func1()", result.label)
end

T["build_signature_info"]["extracts parameters with string labels"] = function()
    local result = child.lua([[
        local sig = require("LspUI.lib.signature")
        local help = {
            signatures = {
                {
                    label = "func(a, b)",
                    parameters = {
                        { label = "a" },
                        { label = "b" }
                    }
                }
            }
        }
        return sig.build_signature_info(help)
    ]])
    h.eq(2, #result.parameters)
    h.eq("a", result.parameters[1].label)
    h.eq("b", result.parameters[2].label)
    h.eq(1, result.active_parameter)
end

T["build_signature_info"]["extracts parameters with range labels"] = function()
    local result = child.lua([[
        local sig = require("LspUI.lib.signature")
        local help = {
            signatures = {
                {
                    label = "func(arg1, arg2)",
                    parameters = {
                        { label = {5, 9} },
                        { label = {11, 15} }
                    }
                }
            }
        }
        return sig.build_signature_info(help)
    ]])
    h.eq("arg1", result.parameters[1].label)
    h.eq("arg2", result.parameters[2].label)
end

T["build_signature_info"]["handles activeParameter from help"] = function()
    local result = child.lua([[
        local sig = require("LspUI.lib.signature")
        local help = {
            activeParameter = 1,
            signatures = {
                {
                    label = "func(a, b)",
                    parameters = {
                        { label = "a" },
                        { label = "b" }
                    }
                }
            }
        }
        return sig.build_signature_info(help)
    ]])
    h.eq(2, result.active_parameter)
end

T["build_signature_info"]["prefers signature-level activeParameter"] = function()
    local result = child.lua([[
        local sig = require("LspUI.lib.signature")
        local help = {
            activeParameter = 0,
            signatures = {
                {
                    label = "func(a, b, c)",
                    activeParameter = 2,
                    parameters = {
                        { label = "a" },
                        { label = "b" },
                        { label = "c" }
                    }
                }
            }
        }
        return sig.build_signature_info(help)
    ]])
    h.eq(3, result.active_parameter)
end

T["build_signature_info"]["clamps invalid activeParameter"] = function()
    local result = child.lua([[
        local sig = require("LspUI.lib.signature")
        local help = {
            activeParameter = 10,
            signatures = {
                {
                    label = "func(a, b)",
                    parameters = {
                        { label = "a" },
                        { label = "b" }
                    }
                }
            }
        }
        return sig.build_signature_info(help)
    ]])
    h.eq(1, result.active_parameter)
end

T["get_active_parameter_label"] = new_set()

T["get_active_parameter_label"]["returns nil for nil info"] = function()
    local result = child.lua([[
        local sig = require("LspUI.lib.signature")
        return sig.get_active_parameter_label(nil) == nil
    ]])
    h.eq(true, result)
end

T["get_active_parameter_label"]["returns nil when no parameters"] = function()
    local result = child.lua([[
        local sig = require("LspUI.lib.signature")
        return sig.get_active_parameter_label({ label = "func()" }) == nil
    ]])
    h.eq(true, result)
end

T["get_active_parameter_label"]["returns nil when no active_parameter"] = function()
    local result = child.lua([[
        local sig = require("LspUI.lib.signature")
        return sig.get_active_parameter_label({
            label = "func(a)",
            parameters = {{ label = "a" }}
        }) == nil
    ]])
    h.eq(true, result)
end

T["get_active_parameter_label"]["returns active parameter label"] = function()
    local result = child.lua([[
        local sig = require("LspUI.lib.signature")
        return sig.get_active_parameter_label({
            label = "func(a, b)",
            active_parameter = 2,
            parameters = {
                { label = "a" },
                { label = "b" }
            }
        })
    ]])
    h.eq("b", result)
end

return T
