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
}

return M
