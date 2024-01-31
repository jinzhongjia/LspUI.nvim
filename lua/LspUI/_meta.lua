--- @class LspUI_rename_config
--- @field enable boolean? whether enable `rename` module
--- @field command_enable boolean? whether enable command for `rename`
--- @field auto_select boolean? whether select all string in float window
--- @field key_binding { exec: string?, quit: string? }? keybind for `rename`
--- @field transparency number? transparency for rename

--- @class LspUI_lightbulb_config
--- @field enable boolean? whether enable `lightbulb` module
--- @field is_cached boolean? whether enable cache
--- @field icon string? icon for lightbulb
--- @field debounce (integer|boolean)? whether enable debounce for lightbulb ? defalt is 250 milliseconds, this will reduce calculations when you move the cursor frequently, but it will cause the delay of lightbulb, false will diable it

--- @class LspUI_code_action_config
--- @field enable boolean? whether enable `code_action` module
--- @field command_enable boolean? whether enable command for `lightbulb`
--- @field gitsigns boolean? whether enable gitsigns support?
--- @field key_binding { exec: string?, prev: string?, next: string?, quit: string? }? keybind for `code_action`
--- @field transparency number? transparency for code action

--- @class LspUI_diagnostic_config
--- @field enable boolean? whether enable `diagnostic` module
--- @field command_enable boolean? whether enable command for `diagnostic`
--- @field transparency number? transparency for diagnostic

--- @class LspUI_hover_config
--- @field enable boolean? whether enable `hover` module
--- @field command_enable boolean? whether enable command for `hover`
--- @field key_binding { prev: string?, next: string?, quit: string? }? keybind for `hover`
--- @field transparency number? transparency for hover

--- @class LspUI_inlay_hint_config
--- @field enable boolean? whether enable `inlay_hint` module
--- @field command_enable boolean? whether enable command for `inlay_hint`
--- @field filter { whitelist: string[]?, blacklist:string[]? }? the filter of blacklist and whitelist, should be filetype list

-- this is just for some keybind like definition, type definition, declaration, reference, implementation
--- @alias LspUI_pos_keybind_config { secondary: { jump: string?, jump_tab: string?, jump_split: string?, jump_vsplit: string?, quit:string?, hide_main:string?, fold_all:string?, expand_all:string?, enter: string? }?, main: { back: string?, hide_secondary: string? }? , transparency: number? }
-- TODO: change this

-- TODO: replace above LspUI_pos_keybind_config with LspUI_pos_config
-- this will be a refector
--
-- this is just some config for definition, type definition, declaration, reference, implementation
--- @class LspUI_pos_config
--- @field secondary_keybind  { jump: string?, jump_tab: string?, jump_split: string?, jump_vsplit: string?, quit:string?, hide_main:string?, fold_all:string?, expand_all:string?, enter: string? }?
--- @field main_keybind { back: string?, hide_secondary: string? }?
--- @field transparency number

--- @class LspUI_definition_config
--- @field enable boolean? whether enable `definition` module
--- @field command_enable boolean? whether enable command for `definition`

--- @class LspUI_type_definition_config
--- @field enable boolean? whether enable `type_definition` module
--- @field command_enable boolean? whether enable command for `definition`

--- @class LspUI_declaration_config
--- @field enable boolean? whether enable `declaration` module
--- @field command_enable boolean? whether enable command for `definition`

--- @class LspUI_implementation_config
--- @field enable boolean? whether enable `implementation` module
--- @field command_enable boolean? whether enable command for `definition`

--- @class LspUI_reference_config
--- @field enable boolean? whether enable `reference` module
--- @field command_enable boolean? whether enable command for `definition`

--- @class LspUI_call_hierarchy_config
--- @field enable boolean? whether enable `call_hierarchy` module
--- @field command_enable boolean? whether enable command for `call_hierarchy`

--- @class LspUI_signature
--- @field enable boolean? whether enable `signature` module
--- @field command_enable boolean? whether enable command for `signature`
--- @field debounce (integer|boolean)?  whether enable debounce for signature ? defalt is 250 milliseconds, this will reduce calculations when you move the cursor frequently, but it will cause the delay of signature, false will diable it

--- @class LspUI_config config for LspUI
--- @field rename LspUI_rename_config? `rename` module
--- @field lightbulb LspUI_lightbulb_config? `lightbulb` module
--- @field code_action LspUI_code_action_config? `code_action` module
--- @field diagnostic LspUI_diagnostic_config? `diagnostic` module
--- @field hover LspUI_hover_config? `hover` module
--- @field inlay_hint LspUI_inlay_hint_config? `inlay_hint` module
--- @field definition LspUI_definition_config? `definition` module
--- @field type_definition LspUI_type_definition_config? `type_definition` module
--- @field declaration LspUI_declaration_config? `declaration` module
--- @field implementation LspUI_implementation_config? `implementation` module
--- @field reference LspUI_reference_config? `reference` module
--- @field pos_keybind LspUI_pos_keybind_config? keybind for `definition`, `type definition`, `declaration`, `reference`, implementation
--- @field pos_config LspUI_pos_config? keybind for `definition`, `type definition`, `declaration`, `reference`, implementation
--- @field call_hierarchy LspUI_call_hierarchy_config? `call_hierarchy` module
--- @field signature LspUI_signature? `signature` module
