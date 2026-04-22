local M = {}

--- Format source lines as a markdown blockquote.
--- Returns nil if source_lines is nil or empty.
---@param source_lines? string[]
---@return string?
local function source_quote(source_lines)
    if not source_lines or #source_lines == 0 then
        return nil
    end
    local quoted = {}
    for _, line in ipairs(source_lines) do
        quoted[#quoted + 1] = '> ' .. line
    end
    return table.concat(quoted, '\n')
end

--- Generate markdown export from annotations.
---@param annotations review.Annotation[]
---@return string
function M.generate(annotations)
    if #annotations == 0 then
        return ''
    end

    -- Separate overall, file-level, and line/range annotations
    ---@type review.Annotation?
    local overall = nil
    ---@type table<string, review.Annotation[]> -- file -> annotations
    local by_file = {}
    ---@type table<string, review.Annotation?> -- file -> file annotation
    local file_anns = {}
    ---@type string[] -- files in order of first annotation time
    local file_order = {}
    ---@type table<string, boolean>
    local file_seen = {}

    for _, ann in ipairs(annotations) do
        if ann.scope == 'overall' then
            overall = ann
        elseif ann.scope == 'file' then
            local file = ann.file or ''
            file_anns[file] = ann
            if not file_seen[file] then
                file_seen[file] = true
                file_order[#file_order + 1] = file
            end
        else
            local file = ann.file or ''
            if not by_file[file] then
                by_file[file] = {}
            end
            by_file[file][#by_file[file] + 1] = ann
            if not file_seen[file] then
                file_seen[file] = true
                file_order[#file_order + 1] = file
            end
        end
    end

    -- Sort line/range annotations within each file by line number
    for _, anns in pairs(by_file) do
        table.sort(anns, function(a, b)
            return (a.lnum or 0) < (b.lnum or 0)
        end)
    end

    local parts = {}

    parts[#parts + 1] = '# Code Review'

    -- Overall section first
    if overall then
        parts[#parts + 1] = ''
        parts[#parts + 1] = '## Overall'
        parts[#parts + 1] = ''
        parts[#parts + 1] = overall.text
    end

    -- File sections in order of first annotation time
    for _, file in ipairs(file_order) do
        parts[#parts + 1] = ''
        parts[#parts + 1] = '## ' .. file

        -- File-level annotation first
        local file_ann = file_anns[file]
        if file_ann then
            parts[#parts + 1] = ''
            parts[#parts + 1] = file_ann.text
        end

        -- Line/range annotations ordered by line number
        local anns = by_file[file]
        if anns then
            for _, ann in ipairs(anns) do
                parts[#parts + 1] = ''
                if ann.scope == 'range' and ann.start_lnum then
                    parts[#parts + 1] = '### L' .. ann.start_lnum .. '-L' .. ann.lnum
                else
                    parts[#parts + 1] = '### L' .. ann.lnum
                end
                local quote = source_quote(ann.source_lines)
                if quote then
                    parts[#parts + 1] = ''
                    parts[#parts + 1] = quote
                end
                parts[#parts + 1] = ''
                parts[#parts + 1] = ann.text
            end
        end
    end

    parts[#parts + 1] = ''

    return table.concat(parts, '\n')
end

return M
