local M = {}

--- Format an annotation for display in vim.ui.select.
---@param ann review.Annotation
---@return string
function M.format_item(ann)
    local first_line = vim.split(ann.text, '\n', { plain = true })[1] or ''

    if ann.scope == 'overall' then
        return '(overall) -- ' .. first_line
    elseif ann.scope == 'file' then
        return (ann.file or '') .. ' (file) -- ' .. first_line
    elseif ann.scope == 'range' then
        return (ann.file or '') .. ':' .. ann.start_lnum .. '-' .. ann.lnum .. ' -- ' .. first_line
    else
        return (ann.file or '') .. ':' .. ann.lnum .. ' -- ' .. first_line
    end
end

--- Open picker with all annotations. Calls on_select with the chosen annotation.
---@param annotations review.Annotation[]
---@param on_select fun(ann: review.Annotation)
function M.pick(annotations, on_select)
    if #annotations == 0 then
        vim.notify('No annotations', vim.log.levels.INFO)
        return
    end

    vim.ui.select(annotations, {
        prompt = 'Review Annotations',
        format_item = M.format_item,
    }, function(choice)
        if choice then
            on_select(choice)
        end
    end)
end

return M
