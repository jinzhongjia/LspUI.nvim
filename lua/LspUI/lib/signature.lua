local M = {}

--- @class LspUI_SignatureParameter
--- @field label string
--- @field doc (string|table)?

--- @class LspUI_SignatureInfo
--- @field label string
--- @field active_parameter integer?
--- @field parameters LspUI_SignatureParameter[]?
--- @field doc string?

--- @param help table?
--- @return LspUI_SignatureInfo?
function M.build_signature_info(help)
    if not help or not help.signatures or #help.signatures == 0 then
        return nil
    end

    local active_signature = (help.activeSignature or 0) + 1
    if active_signature > #help.signatures then
        active_signature = 1
    end

    local current_signature = help.signatures[active_signature]
    local active_parameter = (help.activeParameter or 0) + 1

    local res = {
        label = current_signature.label,
        doc = type(current_signature.documentation) == "table"
                and current_signature.documentation.value
            or (current_signature.documentation or nil),
    }

    if
        not current_signature.parameters
        or #current_signature.parameters == 0
    then
        return res
    end

    if current_signature.activeParameter then
        active_parameter = current_signature.activeParameter + 1
    end

    if
        active_parameter > #current_signature.parameters
        or active_parameter < 1
    then
        active_parameter = 1
    end

    res.parameters = {}
    res.active_parameter = active_parameter

    for _, parameter in ipairs(current_signature.parameters) do
        local label
        if type(parameter.label) == "string" then
            label = parameter.label
        else
            label = string.sub(
                current_signature.label,
                parameter.label[1] + 1,
                parameter.label[2]
            )
        end

        table.insert(res.parameters, {
            label = label,
            doc = parameter.documentation,
        })
    end

    return res
end

--- @param info LspUI_SignatureInfo?
--- @return string?
function M.get_active_parameter_label(info)
    if not info or not info.parameters or not info.active_parameter then
        return nil
    end
    local param = info.parameters[info.active_parameter]
    return param and param.label or nil
end

return M
