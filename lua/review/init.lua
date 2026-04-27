local State = require('review.state')
local ui = require('review.ui')
local export = require('review.export')
local picker = require('review.picker')

local M = {}

---@class review.Config
---@field output? string
---@field sign_text? string
---@field sign_range_start? string
---@field sign_range_mid? string
---@field float_width? integer
---@field float_height? integer
---@field keymaps? boolean Enable review keymaps (designed for `nvim -R`). Default: false.

---@type review.Config
local default_config = {
    output = nil,
    sign_text = '󰅺',
    sign_range_start = '╭',
    sign_range_mid = '│',
    float_width = 60,
    float_height = 10,
    keymaps = false,
}

---@type review.Config
local config = vim.deepcopy(default_config)

---@type review.State
local state = State.new({
    on_change = ui.make_on_change(config),
})

--- Get the file path relative to cwd for a buffer.
---@param bufnr integer
---@return string
local function buf_file(bufnr)
    local abs = vim.api.nvim_buf_get_name(bufnr)
    if abs == '' then
        return ''
    end
    return vim.fn.fnamemodify(abs, ':.') or abs
end

--- Optional setup. Merges user config and registers VimLeavePre if output is set.
---@param opts? review.Config
function M.setup(opts)
    if opts then
        config = vim.tbl_deep_extend('force', config, opts)
    end

    -- Recreate state with updated config
    state = State.new({
        on_change = ui.make_on_change(config),
    })

    -- Set up keymaps if enabled
    if config.keymaps then
        M._setup_keymaps()
    end

    -- Register VimLeavePre autocmd for auto-export
    if config.output then
        vim.api.nvim_create_autocmd('VimLeavePre', {
            callback = function()
                local md = M.export()
                if md == '' then
                    return
                end
                local f = io.open(config.output, 'w')
                if f then
                    f:write(md)
                    f:close()
                end
            end,
        })
    end
end

--- Get the state (for testing).
---@return review.State
function M._state()
    return state
end

--- Create, edit, or delete an annotation.
---@param scope? "file"|"overall"
function M.annotate(scope)
    if scope == 'overall' then
        M._annotate_overall()
    elseif scope == 'file' then
        M._annotate_file()
    else
        M._annotate_line_or_range()
    end
end

--- Handle overall annotation.
function M._annotate_overall()
    local existing = state:find_overall()

    ui.open_float({
        text = existing and existing.text or nil,
        float_width = config.float_width,
        float_height = config.float_height,
        on_close = function(text)
            if existing then
                if text == '' then
                    state:delete(existing.id)
                else
                    state:update(existing.id, text)
                end
            else
                if text ~= '' then
                    state:add({
                        scope = 'overall',
                        text = text,
                    })
                end
            end
        end,
    })
end

--- Handle file annotation.
function M._annotate_file()
    local bufnr = vim.api.nvim_get_current_buf()
    local file = buf_file(bufnr)
    local existing = state:find_file(file)

    ui.open_float({
        text = existing and existing.text or nil,
        float_width = config.float_width,
        float_height = config.float_height,
        on_close = function(text)
            if existing then
                if text == '' then
                    state:delete(existing.id)
                else
                    state:update(existing.id, text)
                end
            else
                if text ~= '' then
                    state:add({
                        scope = 'file',
                        file = file,
                        text = text,
                        bufnr = bufnr,
                    })
                end
            end
        end,
    })
end

--- Read source lines from a buffer.
---@param bufnr integer
---@param start_lnum integer 1-indexed, inclusive
---@param end_lnum integer 1-indexed, inclusive
---@return string[]?
local function read_source_lines(bufnr, start_lnum, end_lnum)
    local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, start_lnum - 1, end_lnum, false)
    if ok then
        return lines
    end
    return nil
end

--- Handle line or range annotation (normal or visual mode).
function M._annotate_line_or_range()
    local mode = vim.fn.mode()
    local bufnr = vim.api.nvim_get_current_buf()
    local file = buf_file(bufnr)

    if mode == 'v' or mode == 'V' or mode == '\22' then
        -- Visual mode: range annotation
        -- Exit visual mode to get marks
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
        local start_lnum = vim.fn.line("'<")
        local end_lnum = vim.fn.line("'>")

        if start_lnum > end_lnum then
            start_lnum, end_lnum = end_lnum, start_lnum
        end

        -- Check for overlap
        for _, ann in ipairs(state:all()) do
            if ann.scope == 'range' and ann.bufnr == bufnr then
                if ann.start_lnum and ann.lnum then
                    if start_lnum <= ann.lnum and ann.start_lnum <= end_lnum then
                        vim.notify('review: range overlaps existing annotation (L' .. ann.start_lnum .. '-L' .. ann.lnum .. ')', vim.log.levels.WARN)
                        return
                    end
                end
            end
        end

        -- Also check if any line in the range has a line annotation
        for lnum = start_lnum, end_lnum do
            local existing = state:find(bufnr, lnum)
            if existing and existing.scope == 'line' then
                vim.notify('review: range contains existing line annotation at L' .. lnum, vim.log.levels.WARN)
                return
            end
        end

        ui.open_float({
            float_width = config.float_width,
            float_height = config.float_height,
            on_close = function(text)
                if text ~= '' then
                    state:add({
                        scope = 'range',
                        file = file,
                        lnum = end_lnum,
                        start_lnum = start_lnum,
                        text = text,
                        source_lines = read_source_lines(bufnr, start_lnum, end_lnum),
                        bufnr = bufnr,
                    })
                end
            end,
        })
    else
        -- Normal mode: line annotation or edit existing
        local lnum = vim.fn.line('.')

        -- Check if cursor is on/inside an existing annotation
        local existing = state:find(bufnr, lnum)
        if existing then
            -- Edit existing
            ui.open_float({
                text = existing.text,
                float_width = config.float_width,
                float_height = config.float_height,
                on_close = function(text)
                    if text == '' then
                        state:delete(existing.id)
                    else
                        state:update(existing.id, text)
                    end
                end,
            })
        else
            -- New line annotation
            ui.open_float({
                float_width = config.float_width,
                float_height = config.float_height,
                on_close = function(text)
                    if text ~= '' then
                        state:add({
                            scope = 'line',
                            file = file,
                            lnum = lnum,
                            text = text,
                            source_lines = read_source_lines(bufnr, lnum, lnum),
                            bufnr = bufnr,
                        })
                    end
                end,
            })
        end
    end
end

--- Jump to next annotation in current buffer.
function M.next()
    local bufnr = vim.api.nvim_get_current_buf()
    local lnum = vim.fn.line('.')
    local ann = state:next(bufnr, lnum)
    if ann and ann.lnum then
        vim.api.nvim_win_set_cursor(0, { ann.lnum, 0 })
    end
end

--- Jump to previous annotation in current buffer.
function M.prev()
    local bufnr = vim.api.nvim_get_current_buf()
    local lnum = vim.fn.line('.')
    local ann = state:prev(bufnr, lnum)
    if ann and ann.lnum then
        vim.api.nvim_win_set_cursor(0, { ann.lnum, 0 })
    end
end

--- List all annotations via vim.ui.select.
function M.pick()
    local annotations = state:all()
    picker.pick(annotations, function(ann)
        if ann.scope == 'overall' then
            -- Open float for editing
            M._annotate_overall()
        else
            -- Jump to location
            if ann.bufnr and vim.api.nvim_buf_is_valid(ann.bufnr) then
                vim.api.nvim_set_current_buf(ann.bufnr)
            elseif ann.file then
                vim.cmd('edit ' .. vim.fn.fnameescape(ann.file))
            end

            if ann.lnum then
                vim.api.nvim_win_set_cursor(0, { ann.lnum, 0 })
            end
        end
    end)
end

--- Generate markdown export string.
---@return string
function M.export()
    return export.generate(state:all())
end

--- Show export in a read-only floating window.
function M.preview()
    local md = M.export()
    if md == '' then
        vim.notify('review: no annotations to preview', vim.log.levels.INFO)
        return
    end
    ui.open_preview(md, {
        float_width = config.float_width,
        float_height = config.float_height,
    })
end

--- Set buffer-local review keymaps on a single buffer.
---@param bufnr integer
local function set_buf_keymaps(bufnr)
    local bopts = function(desc)
        return { buffer = bufnr, desc = desc }
    end
    vim.keymap.set('n', 'a', function() M.annotate() end, bopts('Review: annotate line'))
    vim.keymap.set('x', 'a', function() M.annotate() end, bopts('Review: annotate range'))
    vim.keymap.set('n', 'A', function() M.annotate('file') end, bopts('Review: annotate file'))
    vim.keymap.set('n', 'o', function() M.annotate('overall') end, bopts('Review: annotate overall'))
    vim.keymap.set('n', 'P', function() M.preview() end, bopts('Review: preview annotations'))
    vim.keymap.set('n', 'X', function() M.reset() end, bopts('Review: discard all annotations'))
    vim.keymap.set('n', ']]', function() M.next() end, bopts('Review: next annotation'))
    vim.keymap.set('n', '[[', function() M.prev() end, bopts('Review: previous annotation'))
    vim.keymap.set('n', 'gp', function() M.pick() end, bopts('Review: pick annotation'))
    vim.keymap.set('n', 'H', function() M.help() end, bopts('Review: show keymaps help'))
end

--- Set up review keymaps for normal file buffers only.
--- Intended for readonly sessions (`nvim -R`).
function M._setup_keymaps()
    -- Apply to all existing normal buffers
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buftype == '' and vim.bo[bufnr].readonly then
            set_buf_keymaps(bufnr)
        end
    end

    -- Apply to future normal buffers
    vim.api.nvim_create_autocmd('BufEnter', {
        group = vim.api.nvim_create_augroup('ReviewKeymaps', { clear = true }),
        callback = function(ev)
            if vim.bo[ev.buf].buftype == '' and vim.bo[ev.buf].readonly then
                set_buf_keymaps(ev.buf)
            end
        end,
    })
end

--- Show keymaps help in a floating window.
function M.help()
    local lines = {
        'Review Keymaps',
        '',
        '  a     annotate line (normal) / range (visual)',
        '  A     annotate file',
        '  o     annotate overall',
        '  P     preview annotations',
        '  X     discard all annotations',
        '  ]]    next annotation',
        '  [[    previous annotation',
        '  gp    pick annotation',
        '  H     show this help',
    }

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.bo[buf].bufhidden = 'wipe'

    local width = 44
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

    vim.keymap.set('n', 'H', function()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end, { buffer = buf, nowait = true })
end

--- Discard all annotations and clear all UI.
function M.reset()
    state:reset()
end

return M
