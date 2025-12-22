local H = {}

H.eq = MiniTest.expect.equality
H.not_eq = MiniTest.expect.no_equality
H.expect_error = MiniTest.expect.error
H.expect_no_error = MiniTest.expect.no_error

H.expect_match = MiniTest.new_expectation("string matching", function(pattern, str)
    return str:find(pattern, 1, true) ~= nil
end, function(pattern, str)
    return string.format("Pattern: %s\nObserved string: %s", vim.inspect(pattern), str)
end)

H.expect_truthy = MiniTest.new_expectation("truthy", function(x)
    return x
end, function(x)
    return string.format("Expected truthy value, got: %s", vim.inspect(x))
end)

H.expect_falsy = MiniTest.new_expectation("falsy", function(x)
    return not x
end, function(x)
    return string.format("Expected falsy value, got: %s", vim.inspect(x))
end)

H.expect_type = MiniTest.new_expectation("type check", function(expected_type, value)
    return type(value) == expected_type
end, function(expected_type, value)
    return string.format("Expected type '%s', got '%s' for value: %s", expected_type, type(value), vim.inspect(value))
end)

H.child_start = function(child)
    child.restart({ "-u", "tests/minimal_init.lua" })
end

return H
