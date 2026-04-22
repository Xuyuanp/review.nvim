---@alias review.ChangeEvent "add"|"update"|"delete"

---@class review.Annotation
---@field id integer
---@field scope "line"|"range"|"file"|"overall"
---@field file? string
---@field lnum? integer
---@field start_lnum? integer
---@field text string
---@field source_lines? string[] Source code lines captured at creation time.
---@field extmark_id? integer
---@field bufnr? integer
---@field created_at integer

---@class review.AnnotationInput
---@field scope "line"|"range"|"file"|"overall"
---@field file? string
---@field lnum? integer
---@field start_lnum? integer
---@field text string
---@field source_lines? string[]
---@field bufnr? integer

---@class review.StateOpts
---@field on_change? fun(event: review.ChangeEvent, annotation: review.Annotation)

---@class review.State
---@field private _annotations table<integer, review.Annotation>
---@field private _next_id integer
---@field private _on_change? fun(event: review.ChangeEvent, annotation: review.Annotation)
local State = {}
State.__index = State

--- Create a new State instance.
---@param opts? review.StateOpts
---@return review.State
function State.new(opts)
    opts = opts or {}
    local self = setmetatable({
        _annotations = {},
        _next_id = 1,
        _on_change = opts.on_change,
    }, State)
    return self
end

--- Validate and add an annotation.
---@param input review.AnnotationInput
---@return review.Annotation? annotation
---@return string? error
function State:add(input)
    -- Validate based on scope
    if input.scope == 'overall' then
        -- Only one overall annotation allowed
        for _, ann in pairs(self._annotations) do
            if ann.scope == 'overall' then
                return nil, 'An overall annotation already exists'
            end
        end
    elseif input.scope == 'file' then
        -- Only one file annotation per file
        for _, ann in pairs(self._annotations) do
            if ann.scope == 'file' and ann.file == input.file then
                return nil, 'A file annotation already exists for ' .. (input.file or '')
            end
        end
    elseif input.scope == 'range' then
        -- Range limited to 10 lines
        if input.start_lnum and input.lnum then
            if input.lnum - input.start_lnum + 1 > 10 then
                return nil, 'Range annotations are limited to 10 lines maximum'
            end
        end
        -- No overlapping ranges in same buffer
        local err = self:_check_overlap(input)
        if err then
            return nil, err
        end
    elseif input.scope == 'line' then
        -- No line annotation inside an existing range
        local err = self:_check_line_in_range(input)
        if err then
            return nil, err
        end
    end

    local id = self._next_id
    self._next_id = id + 1

    ---@type review.Annotation
    local ann = {
        id = id,
        scope = input.scope,
        file = input.file,
        lnum = input.lnum,
        start_lnum = input.start_lnum,
        text = input.text,
        source_lines = input.source_lines,
        bufnr = input.bufnr,
        created_at = os.time(),
    }

    self._annotations[id] = ann

    if self._on_change then
        self._on_change('add', ann)
    end

    return ann, nil
end

--- Check if a line annotation would fall inside an existing range.
---@param input review.AnnotationInput
---@return string? error
function State:_check_line_in_range(input)
    for _, ann in pairs(self._annotations) do
        if ann.scope == 'range' and ann.bufnr == input.bufnr then
            if ann.start_lnum and ann.lnum and input.lnum then
                if input.lnum >= ann.start_lnum and input.lnum <= ann.lnum then
                    return 'Cannot create line annotation inside existing range (L' .. ann.start_lnum .. '-L' .. ann.lnum .. ')'
                end
            end
        end
    end
    return nil
end

--- Check if a range overlaps any existing range in the same buffer.
---@param input review.AnnotationInput
---@return string? error
function State:_check_overlap(input)
    if not input.start_lnum or not input.lnum then
        return nil
    end
    for _, ann in pairs(self._annotations) do
        if ann.scope == 'range' and ann.bufnr == input.bufnr then
            if ann.start_lnum and ann.lnum then
                -- Two ranges [a, b] and [c, d] overlap iff a <= d and c <= b
                if input.start_lnum <= ann.lnum and ann.start_lnum <= input.lnum then
                    return 'Range overlaps existing annotation (L' .. ann.start_lnum .. '-L' .. ann.lnum .. ')'
                end
            end
        end
    end
    return nil
end

--- Update the text of an existing annotation.
---@param id integer
---@param text string
---@return review.Annotation?
function State:update(id, text)
    local ann = self._annotations[id]
    if not ann then
        return nil
    end

    ann.text = text

    if self._on_change then
        self._on_change('update', ann)
    end

    return ann
end

--- Delete an annotation by ID.
---@param id integer
---@return review.Annotation?
function State:delete(id)
    local ann = self._annotations[id]
    if not ann then
        return nil
    end

    self._annotations[id] = nil

    if self._on_change then
        self._on_change('delete', ann)
    end

    return ann
end

--- Get an annotation by ID.
---@param id integer
---@return review.Annotation?
function State:get(id)
    return self._annotations[id]
end

--- Find a line or range annotation covering a position in a buffer.
---@param bufnr integer
---@param lnum integer
---@return review.Annotation?
function State:find(bufnr, lnum)
    for _, ann in pairs(self._annotations) do
        if ann.bufnr == bufnr then
            if ann.scope == 'line' and ann.lnum == lnum then
                return ann
            elseif ann.scope == 'range' then
                if ann.start_lnum and ann.lnum then
                    if lnum >= ann.start_lnum and lnum <= ann.lnum then
                        return ann
                    end
                end
            end
        end
    end
    return nil
end

--- Find a file-scoped annotation for a file.
---@param file string
---@return review.Annotation?
function State:find_file(file)
    for _, ann in pairs(self._annotations) do
        if ann.scope == 'file' and ann.file == file then
            return ann
        end
    end
    return nil
end

--- Find the overall annotation.
---@return review.Annotation?
function State:find_overall()
    for _, ann in pairs(self._annotations) do
        if ann.scope == 'overall' then
            return ann
        end
    end
    return nil
end

--- Get all annotations, ordered by created_at.
---@return review.Annotation[]
function State:all()
    local result = {}
    for _, ann in pairs(self._annotations) do
        result[#result + 1] = ann
    end
    table.sort(result, function(a, b)
        return a.created_at < b.created_at
    end)
    return result
end

--- Get annotations in a buffer, ordered by lnum. Excludes file-scoped.
---@param bufnr integer
---@return review.Annotation[]
function State:by_buffer(bufnr)
    local result = {}
    for _, ann in pairs(self._annotations) do
        if ann.bufnr == bufnr and ann.scope ~= 'file' and ann.scope ~= 'overall' then
            result[#result + 1] = ann
        end
    end
    table.sort(result, function(a, b)
        return (a.lnum or 0) < (b.lnum or 0)
    end)
    return result
end

--- Get the first annotation after lnum in a buffer. Skips file-scoped.
---@param bufnr integer
---@param lnum integer
---@return review.Annotation?
function State:next(bufnr, lnum)
    local annotations = self:by_buffer(bufnr)
    for _, ann in ipairs(annotations) do
        if ann.lnum and ann.lnum > lnum then
            return ann
        end
    end
    return nil
end

--- Get the last annotation before lnum in a buffer. Skips file-scoped.
---@param bufnr integer
---@param lnum integer
---@return review.Annotation?
function State:prev(bufnr, lnum)
    local annotations = self:by_buffer(bufnr)
    local result = nil
    for _, ann in ipairs(annotations) do
        if ann.lnum and ann.lnum < lnum then
            result = ann
        end
    end
    return result
end

--- Delete all annotations, firing on_change("delete") for each.
function State:reset()
    -- Collect all IDs first to avoid mutation during iteration
    local ids = {}
    for id, _ in pairs(self._annotations) do
        ids[#ids + 1] = id
    end
    for _, id in ipairs(ids) do
        self:delete(id)
    end
end

return State
