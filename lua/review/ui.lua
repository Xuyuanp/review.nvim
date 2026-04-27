local M = {}

local ns = vim.api.nvim_create_namespace('review')

---@class review.HelpEntry
---@field lhs string
---@field mode string
---@field desc string

--- Float window title: either a plain string, or a list of [text, highlight] chunks
--- (as accepted by `nvim_open_win`'s `title` option).
---@alias review.FloatTitle string|{[1]: string, [2]: string}[]

---@class review.OpenFloatOpts
---@field title? review.FloatTitle
---@field text? string
---@field on_close fun(text: string)
---@field float_width integer
---@field float_height integer

---@class review.OpenPreviewOpts
---@field float_width integer
---@field float_height integer

local HL_BORDER = 'ReviewBorder'
local HL_TEXT = 'ReviewText'

-- Ensure highlight groups exist
local function ensure_highlights()
    if vim.fn.hlexists(HL_BORDER) == 0 then
        vim.api.nvim_set_hl(0, HL_BORDER, { link = 'Comment' })
    end
    if vim.fn.hlexists(HL_TEXT) == 0 then
        vim.api.nvim_set_hl(0, HL_TEXT, { link = 'String' })
    end
end

--- Build virtual lines for a box around annotation text.
---@param text string
---@return table[] virt_lines Each element is a list of [text, hl_group] chunks.
local function build_box_virt_lines(text)
    local lines = vim.split(text, '\n', { plain = true })

    -- Compute max width
    local max_width = 0
    for _, line in ipairs(lines) do
        local w = vim.fn.strdisplaywidth(line)
        if w > max_width then
            max_width = w
        end
    end

    -- Ensure minimum width
    if max_width < 1 then
        max_width = 1
    end

    local virt_lines = {}

    -- Top border: ╭──...──╮
    local top = '╭' .. string.rep('─', max_width + 2) .. '╮'
    virt_lines[#virt_lines + 1] = { { top, HL_BORDER } }

    -- Content lines: │ text │
    for _, line in ipairs(lines) do
        local pad_right = max_width - vim.fn.strdisplaywidth(line)
        virt_lines[#virt_lines + 1] = {
            { '│ ', HL_BORDER },
            { line .. string.rep(' ', pad_right), HL_TEXT },
            { ' │', HL_BORDER },
        }
    end

    -- Bottom border: ╰──...──╯
    local bottom = '╰' .. string.rep('─', max_width + 2) .. '╯'
    virt_lines[#virt_lines + 1] = { { bottom, HL_BORDER } }

    return virt_lines
end

--- Compute the primary extmark ID from an annotation ID.
---@param ann_id integer
---@return integer
local function primary_extmark_id(ann_id)
    return ann_id * 100
end

--- Create extmarks for a line annotation.
---@param ann review.Annotation
---@param config review.Config
local function create_line_extmarks(ann, config)
    if not ann.bufnr or not ann.lnum then
        return
    end
    if not vim.api.nvim_buf_is_valid(ann.bufnr) then
        return
    end

    local virt_lines = build_box_virt_lines(ann.text)
    local ext_id = primary_extmark_id(ann.id)

    vim.api.nvim_buf_set_extmark(ann.bufnr, ns, ann.lnum - 1, 0, {
        id = ext_id,
        sign_text = config.sign_text,
        sign_hl_group = HL_BORDER,
        virt_lines = virt_lines,
    })

    ann.extmark_id = ext_id
end

--- Create extmarks for a range annotation.
---@param ann review.Annotation
---@param config review.Config
local function create_range_extmarks(ann, config)
    if not ann.bufnr or not ann.lnum or not ann.start_lnum then
        return
    end
    if not vim.api.nvim_buf_is_valid(ann.bufnr) then
        return
    end

    local virt_lines = build_box_virt_lines(ann.text)
    local ext_id = primary_extmark_id(ann.id)

    -- Primary extmark on end line: sign + virt_lines
    vim.api.nvim_buf_set_extmark(ann.bufnr, ns, ann.lnum - 1, 0, {
        id = ext_id,
        sign_text = config.sign_text,
        sign_hl_group = HL_BORDER,
        virt_lines = virt_lines,
    })

    ann.extmark_id = ext_id

    -- Start line sign: ╭
    vim.api.nvim_buf_set_extmark(ann.bufnr, ns, ann.start_lnum - 1, 0, {
        id = ext_id + 1,
        sign_text = config.sign_range_start,
        sign_hl_group = HL_BORDER,
    })

    -- Intermediate line signs: │
    for i = ann.start_lnum + 1, ann.lnum - 1 do
        local offset = i - ann.start_lnum + 1
        vim.api.nvim_buf_set_extmark(ann.bufnr, ns, i - 1, 0, {
            id = ext_id + offset,
            sign_text = config.sign_range_mid,
            sign_hl_group = HL_BORDER,
        })
    end
end

--- Create extmarks for a file annotation.
---@param ann review.Annotation
local function create_file_extmarks(ann)
    if not ann.bufnr then
        return
    end
    if not vim.api.nvim_buf_is_valid(ann.bufnr) then
        return
    end

    local virt_lines = build_box_virt_lines(ann.text)
    local ext_id = primary_extmark_id(ann.id)

    vim.api.nvim_buf_set_extmark(ann.bufnr, ns, 0, 0, {
        id = ext_id,
        virt_lines = virt_lines,
        virt_lines_above = true,
    })

    ann.extmark_id = ext_id
end

--- Remove all extmarks for an annotation.
---@param ann review.Annotation
local function remove_extmarks(ann)
    if not ann.bufnr then
        return
    end
    if not vim.api.nvim_buf_is_valid(ann.bufnr) then
        return
    end

    local ext_id = primary_extmark_id(ann.id)

    -- Remove primary extmark
    pcall(vim.api.nvim_buf_del_extmark, ann.bufnr, ns, ext_id)

    -- For range annotations, remove sign extmarks
    if ann.scope == 'range' and ann.start_lnum and ann.lnum then
        for offset = 1, ann.lnum - ann.start_lnum do
            pcall(vim.api.nvim_buf_del_extmark, ann.bufnr, ns, ext_id + offset)
        end
    end
end

--- Handle state on_change events: create, update, or delete extmarks.
---@param config review.Config
---@return fun(event: review.ChangeEvent, annotation: review.Annotation)
function M.make_on_change(config)
    ensure_highlights()

    return function(event, ann)
        if event == 'add' then
            if ann.scope == 'line' then
                create_line_extmarks(ann, config)
            elseif ann.scope == 'range' then
                create_range_extmarks(ann, config)
            elseif ann.scope == 'file' then
                create_file_extmarks(ann)
            end
            -- overall: no extmarks
        elseif event == 'update' then
            if ann.scope == 'overall' then
                return
            end
            -- Recreate extmarks for simplicity (remove then add)
            remove_extmarks(ann)
            if ann.scope == 'line' then
                create_line_extmarks(ann, config)
            elseif ann.scope == 'range' then
                create_range_extmarks(ann, config)
            elseif ann.scope == 'file' then
                create_file_extmarks(ann)
            end
        elseif event == 'delete' then
            remove_extmarks(ann)
        end
    end
end

--- Open a floating window for annotation input.
---@param opts review.OpenFloatOpts
function M.open_float(opts)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = 'markdown'
    vim.bo[buf].bufhidden = 'wipe'

    -- Enable word wrap
    vim.api.nvim_create_autocmd('BufWinEnter', {
        buffer = buf,
        once = true,
        callback = function()
            local w = vim.fn.bufwinid(buf)
            if w ~= -1 then
                vim.wo[w].wrap = true
                vim.wo[w].linebreak = true
            end
        end,
    })

    -- Pre-populate if editing
    if opts.text and opts.text ~= '' then
        local lines = vim.split(opts.text, '\n', { plain = true })
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    end

    local width = opts.float_width
    local height = opts.float_height

    -- Center in editor
    local ui = vim.api.nvim_list_uis()[1]
    local row = math.floor((ui.height - height) / 2)
    local col = math.floor((ui.width - width) / 2)

    local win = vim.api.nvim_open_win(buf, true, {
        relative = 'editor',
        width = width,
        height = height,
        row = row,
        col = col,
        style = 'minimal',
        border = 'rounded',
        title = opts.title or ' Review Annotation ',
        title_pos = 'center',
    })

    -- Close keymap: q in normal mode
    vim.keymap.set('n', 'q', function()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end, { buffer = buf, nowait = true })

    -- Save on BufWinLeave
    vim.api.nvim_create_autocmd('BufWinLeave', {
        buffer = buf,
        once = true,
        callback = function()
            local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
            local text = vim.trim(table.concat(lines, '\n'))
            opts.on_close(text)
        end,
    })
end

--- Open a read-only preview float showing the markdown export.
---@param markdown string
---@param opts review.OpenPreviewOpts
function M.open_preview(markdown, opts)
    local buf = vim.api.nvim_create_buf(false, true)
    local lines = vim.split(markdown, '\n', { plain = true })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = 'markdown'
    vim.bo[buf].modifiable = false
    vim.bo[buf].bufhidden = 'wipe'

    local width = opts.float_width
    local height = opts.float_height

    local ui = vim.api.nvim_list_uis()[1]
    local row = math.floor((ui.height - height) / 2)
    local col = math.floor((ui.width - width) / 2)

    local win = vim.api.nvim_open_win(buf, true, {
        relative = 'editor',
        width = width,
        height = height,
        row = row,
        col = col,
        style = 'minimal',
        border = 'rounded',
        title = ' Review Preview ',
        title_pos = 'center',
    })

    vim.keymap.set('n', 'q', function()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end, { buffer = buf, nowait = true })
end

--- Build help lines from keymap entries.
--- Deduplicates entries that share both lhs and desc, appends a mode tag when
--- the binding is not plain normal-mode.
---@param entries review.HelpEntry[]
---@return string[] lines
local function build_help_lines(entries)
    -- Deduplicate entries that share both lhs AND desc (same key, same action).
    -- Entries with the same lhs but different desc (e.g. 'a' normal="annotate line",
    -- visual="annotate range") are kept as separate rows.
    ---@type {lhs: string, modes: string[], desc: string}[]
    local merged = {}
    ---@type table<string, integer> key = "lhs\0desc" -> index into merged
    local seen = {}
    for _, e in ipairs(entries) do
        local key = e.lhs .. '\0' .. e.desc
        if seen[key] then
            local m = merged[seen[key]]
            m.modes[#m.modes + 1] = e.mode
        else
            merged[#merged + 1] = { lhs = e.lhs, modes = { e.mode }, desc = e.desc }
            seen[key] = #merged
        end
    end

    -- Find max lhs width for alignment
    local max_lhs = 0
    for _, entry in ipairs(merged) do
        if #entry.lhs > max_lhs then
            max_lhs = #entry.lhs
        end
    end

    local lines = { 'Review Keymaps', '' }
    for _, entry in ipairs(merged) do
        -- Show mode tag unless the only mode is 'n' (the common default)
        local mode_tag = ''
        if not (entry.modes[1] == 'n' and #entry.modes == 1) then
            mode_tag = ' [' .. table.concat(entry.modes, ',') .. ']'
        end
        lines[#lines + 1] = '  ' .. entry.lhs .. string.rep(' ', max_lhs - #entry.lhs + 4) .. entry.desc .. mode_tag
    end

    return lines
end

--- Show keymaps help in a floating window.
---@param entries review.HelpEntry[]
function M.open_help(entries)
    if #entries == 0 then
        vim.notify('review: no keymaps active on this buffer', vim.log.levels.INFO)
        return
    end

    local lines = build_help_lines(entries)

    -- Compute max display width for the float
    local max_width = 0
    for _, line in ipairs(lines) do
        local w = vim.fn.strdisplaywidth(line)
        if w > max_width then
            max_width = w
        end
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.bo[buf].bufhidden = 'wipe'

    local width = max_width + 2
    local height = #lines
    local uis = vim.api.nvim_list_uis()[1]
    local row = math.floor((uis.height - height) / 2)
    local col = math.floor((uis.width - width) / 2)

    local win = vim.api.nvim_open_win(buf, true, {
        relative = 'editor',
        width = width,
        height = height,
        row = row,
        col = col,
        style = 'minimal',
        border = 'rounded',
        title = ' Help ',
        title_pos = 'center',
    })

    vim.keymap.set('n', 'q', function()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end, { buffer = buf, nowait = true })
end

--- Return the namespace ID (for testing).
---@return integer
function M.namespace()
    return ns
end

return M
