local h = require("null-ls.helpers")
local methods = require("null-ls.methods")

local DIAGNOSTICS = methods.internal.DIAGNOSTICS
local SEVERITIES = h.diagnostics.severities

local function get_document_root(bufnr)
    local has_parser, parser = pcall(vim.treesitter.get_parser, bufnr)
    if not has_parser then
        return
    end

    local tree = parser:parse()[1]
    if not tree or not tree:root() or tree:root():type() == "ERROR" then
        return
    end

    return tree:root()
end

local function parse_comments(root)
    local output = {}

    for node in root:iter_children() do
        if node:type() == "comment" then
            table.insert(output, parse_comments(node))
        elseif node:type() == "comment_content" then
            return node
        end
    end

    return output
end

local function get_comments(bufnr)
    local document_root = get_document_root(bufnr)
    if not document_root then
        return {}
    end

    return parse_comments(document_root)
end

local keywords = {
    TODO = {
        severity = SEVERITIES.information,
    },
    FIX = {
        severity = SEVERITIES.error,
        alt = { "FIXME", "BUG", "FIXIT", "ISSUE" },
    },
    HACK = {
        severity = SEVERITIES.warning,
    },
    WARN = {
        severity = SEVERITIES.warning,
        alt = { "WARNING", "XXX" },
    },
    PERF = {
        severity = SEVERITIES.information,
        alt = { "OPTIM", "PERFORMANCE", "OPTIMIZE" },
    },
    NOTE = {
        severity = SEVERITIES.hint,
        alt = { "INFO" },
    },
}

local keyword_by_name = {}

for kw, opts in pairs(keywords) do
    keyword_by_name[kw] = kw
    for _, alt in pairs(opts.alt or {}) do
        keyword_by_name[alt] = kw
    end
end

return h.make_builtin({
    name = "todo_comments",
    meta = {
        description = "Uses inbuilt Lua code and treesitter to detect lines with TODO comments and show a diagnostic warning on each line where it's present.",
    },
    method = DIAGNOSTICS,
    filetypes = {},
    generator = {
        fn = function(params)
            local result = {}
            for _, node in ipairs(get_comments(params.bufnr)) do
                local content = vim.treesitter.get_node_text(node, params.bufnr):match("^%s*(.*)")

                for kw, _ in pairs(keyword_by_name) do
                    if content:match("%f[%a]" .. kw .. "%f[%A]") then
                        local row, _, _ = node:start()

                        table.insert(result, {
                            message = content,
                            severity = keywords[keyword_by_name[kw]].severity,
                            row = row + 1,
                            source = "todo_comments",
                        })
                    end
                end
            end

            return result
        end,
    },
})
