-- note: This file is used to expose api externally
local modules = require("LspUI.modules")

local M = {}

-- A brief description:
-- you can just require this file through
-- ```lua
-- local api = require("LspUI").api
-- api.peek_definition()
-- api.code_action()
-- api.hover()
-- api.rename()
-- api.diagnostic("next")
-- api.diagnostic("prev")
-- ````
--

M.api = {
    code_action = modules.code_action.run,
    rename = modules.code_action.run,
    diagnostic = modules.diagnostic.run,
    hover = modules.hover.run,
    definition = modules.definition.run,
    type_definition = modules.type_definition.run,
    declaration = modules.declaration.run,
    reference = modules.reference.run,
    implementation = modules.implementation.run,
    inlay_hint = modules.inlay_hint.run,
}

return M
