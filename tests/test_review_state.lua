local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local State = require('review.state')

local T = new_set()

-- Helper: create a state with an optional change log
local function make_state_with_log()
    local log = {}
    local s = State.new({
        on_change = function(event, ann)
            log[#log + 1] = { event = event, id = ann.id }
        end,
    })
    return s, log
end

-- Test 1: add() line annotation, verify in state
T['add_line'] = function()
    local s = State.new()
    local ann = s:add({ scope = 'line', file = 'foo.lua', lnum = 42, text = 'fix this', bufnr = 1 })
    eq(ann.scope, 'line')
    eq(ann.file, 'foo.lua')
    eq(ann.lnum, 42)
    eq(ann.text, 'fix this')
    eq(type(ann.id), 'number')
    eq(type(ann.created_at), 'number')
end

-- Test 2: add() range annotation, verify start_lnum and lnum
T['add_range'] = function()
    local s = State.new()
    local ann = s:add({ scope = 'range', file = 'foo.lua', lnum = 11, start_lnum = 7, text = 'range note', bufnr = 1 })
    eq(ann.scope, 'range')
    eq(ann.start_lnum, 7)
    eq(ann.lnum, 11)
    eq(ann.text, 'range note')
end

-- Test 3: add() file annotation, verify lnum is nil
T['add_file'] = function()
    local s = State.new()
    local ann = s:add({ scope = 'file', file = 'foo.lua', text = 'file comment', bufnr = 1 })
    eq(ann.scope, 'file')
    eq(ann.lnum, nil)
    eq(ann.file, 'foo.lua')
end

-- Test 4: add() overall annotation, verify file/lnum are nil
T['add_overall'] = function()
    local s = State.new()
    local ann = s:add({ scope = 'overall', text = 'overall note' })
    eq(ann.scope, 'overall')
    eq(ann.file, nil)
    eq(ann.lnum, nil)
end

-- Test 5: delete() by ID, verify removal
T['delete'] = function()
    local s = State.new()
    local ann = s:add({ scope = 'line', file = 'a.lua', lnum = 1, text = 'x', bufnr = 1 })
    local deleted = s:delete(ann.id)
    eq(deleted.id, ann.id)
    eq(s:get(ann.id), nil)
end

-- Test 6: update() text, verify change
T['update'] = function()
    local s = State.new()
    local ann = s:add({ scope = 'line', file = 'a.lua', lnum = 1, text = 'old', bufnr = 1 })
    local updated = s:update(ann.id, 'new')
    eq(updated.text, 'new')
    eq(s:get(ann.id).text, 'new')
end

-- Test 7: get() by ID returns correct annotation
T['get'] = function()
    local s = State.new()
    local ann = s:add({ scope = 'line', file = 'a.lua', lnum = 1, text = 'hello', bufnr = 1 })
    local got = s:get(ann.id)
    eq(got.id, ann.id)
    eq(got.text, 'hello')
end

-- Test 8: find() returns line annotation on exact line
T['find_line'] = function()
    local s = State.new()
    s:add({ scope = 'line', file = 'a.lua', lnum = 10, text = 'found', bufnr = 1 })
    local found = s:find(1, 10)
    eq(found.text, 'found')
end

-- Test 9: find() returns range annotation covering a mid-range line
T['find_range_mid'] = function()
    local s = State.new()
    s:add({ scope = 'range', file = 'a.lua', lnum = 15, start_lnum = 10, text = 'range', bufnr = 1 })
    local found = s:find(1, 12)
    eq(found.text, 'range')
    -- Also find on start and end
    eq(s:find(1, 10).text, 'range')
    eq(s:find(1, 15).text, 'range')
end

-- Test 10: find() returns nil for non-annotated line
T['find_nil'] = function()
    local s = State.new()
    s:add({ scope = 'line', file = 'a.lua', lnum = 10, text = 'x', bufnr = 1 })
    eq(s:find(1, 11), nil)
    eq(s:find(2, 10), nil) -- different buffer
end

-- Test 11: find_file() returns file-scoped annotation
T['find_file'] = function()
    local s = State.new()
    s:add({ scope = 'file', file = 'a.lua', text = 'file note', bufnr = 1 })
    local found = s:find_file('a.lua')
    eq(found.text, 'file note')
    eq(s:find_file('b.lua'), nil)
end

-- Test 12: find_overall() returns overall annotation
T['find_overall'] = function()
    local s = State.new()
    s:add({ scope = 'overall', text = 'overall' })
    eq(s:find_overall().text, 'overall')
end

-- Test 13: all() ordered by created_at
T['all_ordered'] = function()
    local s = State.new()
    local a1 = s:add({ scope = 'line', file = 'a.lua', lnum = 1, text = 'first', bufnr = 1 })
    local a2 = s:add({ scope = 'line', file = 'a.lua', lnum = 2, text = 'second', bufnr = 1 })
    local a3 = s:add({ scope = 'line', file = 'a.lua', lnum = 3, text = 'third', bufnr = 1 })
    local all = s:all()
    eq(#all, 3)
    eq(all[1].id, a1.id)
    eq(all[2].id, a2.id)
    eq(all[3].id, a3.id)
end

-- Test 14: by_buffer() ordered by lnum, excludes file-scoped
T['by_buffer'] = function()
    local s = State.new()
    s:add({ scope = 'line', file = 'a.lua', lnum = 20, text = 'b', bufnr = 1 })
    s:add({ scope = 'line', file = 'a.lua', lnum = 5, text = 'a', bufnr = 1 })
    s:add({ scope = 'file', file = 'a.lua', text = 'file', bufnr = 1 })
    s:add({ scope = 'line', file = 'b.lua', lnum = 1, text = 'other', bufnr = 2 })
    local result = s:by_buffer(1)
    eq(#result, 2)
    eq(result[1].lnum, 5)
    eq(result[2].lnum, 20)
end

-- Test 15: next() returns first annotation after given lnum
T['next'] = function()
    local s = State.new()
    s:add({ scope = 'line', file = 'a.lua', lnum = 5, text = 'a', bufnr = 1 })
    s:add({ scope = 'line', file = 'a.lua', lnum = 15, text = 'b', bufnr = 1 })
    s:add({ scope = 'line', file = 'a.lua', lnum = 25, text = 'c', bufnr = 1 })
    local ann = s:next(1, 5)
    eq(ann.lnum, 15)
end

-- Test 16: next() returns nil at last annotation (no wrap)
T['next_no_wrap'] = function()
    local s = State.new()
    s:add({ scope = 'line', file = 'a.lua', lnum = 5, text = 'a', bufnr = 1 })
    s:add({ scope = 'line', file = 'a.lua', lnum = 15, text = 'b', bufnr = 1 })
    eq(s:next(1, 15), nil)
    eq(s:next(1, 20), nil)
end

-- Test 17: next() skips file-scoped annotations
T['next_skip_file'] = function()
    local s = State.new()
    s:add({ scope = 'line', file = 'a.lua', lnum = 5, text = 'a', bufnr = 1 })
    s:add({ scope = 'file', file = 'a.lua', text = 'file', bufnr = 1 })
    s:add({ scope = 'line', file = 'a.lua', lnum = 15, text = 'b', bufnr = 1 })
    local ann = s:next(1, 5)
    eq(ann.lnum, 15)
end

-- Test 18: prev() returns last annotation before given lnum
T['prev'] = function()
    local s = State.new()
    s:add({ scope = 'line', file = 'a.lua', lnum = 5, text = 'a', bufnr = 1 })
    s:add({ scope = 'line', file = 'a.lua', lnum = 15, text = 'b', bufnr = 1 })
    s:add({ scope = 'line', file = 'a.lua', lnum = 25, text = 'c', bufnr = 1 })
    local ann = s:prev(1, 25)
    eq(ann.lnum, 15)
end

-- Test 19: prev() returns nil at first annotation (no wrap)
T['prev_no_wrap'] = function()
    local s = State.new()
    s:add({ scope = 'line', file = 'a.lua', lnum = 5, text = 'a', bufnr = 1 })
    s:add({ scope = 'line', file = 'a.lua', lnum = 15, text = 'b', bufnr = 1 })
    eq(s:prev(1, 5), nil)
    eq(s:prev(1, 3), nil)
end

-- Test 20: prev() skips file-scoped annotations
T['prev_skip_file'] = function()
    local s = State.new()
    s:add({ scope = 'line', file = 'a.lua', lnum = 5, text = 'a', bufnr = 1 })
    s:add({ scope = 'file', file = 'a.lua', text = 'file', bufnr = 1 })
    s:add({ scope = 'line', file = 'a.lua', lnum = 15, text = 'b', bufnr = 1 })
    local ann = s:prev(1, 15)
    eq(ann.lnum, 5)
end

-- Test 21: ID auto-increments across additions
T['id_autoincrement'] = function()
    local s = State.new()
    local a1 = s:add({ scope = 'line', file = 'a.lua', lnum = 1, text = 'x', bufnr = 1 })
    local a2 = s:add({ scope = 'line', file = 'a.lua', lnum = 2, text = 'y', bufnr = 1 })
    local a3 = s:add({ scope = 'line', file = 'a.lua', lnum = 3, text = 'z', bufnr = 1 })
    eq(a2.id, a1.id + 1)
    eq(a3.id, a2.id + 1)
end

-- Test 22: on_change fires "add" on add
T['on_change_add'] = function()
    local s, log = make_state_with_log()
    local ann = s:add({ scope = 'line', file = 'a.lua', lnum = 1, text = 'x', bufnr = 1 })
    eq(#log, 1)
    eq(log[1].event, 'add')
    eq(log[1].id, ann.id)
end

-- Test 23: on_change fires "update" on update
T['on_change_update'] = function()
    local s, log = make_state_with_log()
    local ann = s:add({ scope = 'line', file = 'a.lua', lnum = 1, text = 'x', bufnr = 1 })
    s:update(ann.id, 'y')
    eq(#log, 2)
    eq(log[2].event, 'update')
    eq(log[2].id, ann.id)
end

-- Test 24: on_change fires "delete" on delete
T['on_change_delete'] = function()
    local s, log = make_state_with_log()
    local ann = s:add({ scope = 'line', file = 'a.lua', lnum = 1, text = 'x', bufnr = 1 })
    s:delete(ann.id)
    eq(#log, 2)
    eq(log[2].event, 'delete')
    eq(log[2].id, ann.id)
end

-- Test 25: delete() returns the deleted annotation
T['delete_returns'] = function()
    local s = State.new()
    local ann = s:add({ scope = 'line', file = 'a.lua', lnum = 1, text = 'x', bufnr = 1 })
    local deleted = s:delete(ann.id)
    eq(deleted.id, ann.id)
    eq(deleted.text, 'x')
end

-- Test 26: update() on nonexistent ID returns nil
T['update_nonexistent'] = function()
    local s = State.new()
    eq(s:update(999, 'nope'), nil)
end

-- Test 27: add() rejects line inside existing range
T['reject_line_in_range'] = function()
    local s = State.new()
    s:add({ scope = 'range', file = 'a.lua', lnum = 15, start_lnum = 10, text = 'range', bufnr = 1 })
    local ann, err = s:add({ scope = 'line', file = 'a.lua', lnum = 12, text = 'bad', bufnr = 1 })
    eq(ann, nil)
    eq(type(err), 'string')
    -- Boundary: start line
    local ann2, err2 = s:add({ scope = 'line', file = 'a.lua', lnum = 10, text = 'bad', bufnr = 1 })
    eq(ann2, nil)
    eq(type(err2), 'string')
    -- Boundary: end line
    local ann3, err3 = s:add({ scope = 'line', file = 'a.lua', lnum = 15, text = 'bad', bufnr = 1 })
    eq(ann3, nil)
    eq(type(err3), 'string')
end

-- Test 28: add() rejects range overlapping existing range
T['reject_overlapping_range'] = function()
    local s = State.new()
    s:add({ scope = 'range', file = 'a.lua', lnum = 15, start_lnum = 10, text = 'first', bufnr = 1 })
    -- Partial overlap from below
    local a1, e1 = s:add({ scope = 'range', file = 'a.lua', lnum = 12, start_lnum = 5, text = 'bad', bufnr = 1 })
    eq(a1, nil)
    eq(type(e1), 'string')
    -- Partial overlap from above
    local a2, e2 = s:add({ scope = 'range', file = 'a.lua', lnum = 20, start_lnum = 14, text = 'bad', bufnr = 1 })
    eq(a2, nil)
    eq(type(e2), 'string')
    -- Fully contained
    local a3, e3 = s:add({ scope = 'range', file = 'a.lua', lnum = 13, start_lnum = 11, text = 'bad', bufnr = 1 })
    eq(a3, nil)
    eq(type(e3), 'string')
    -- Non-overlapping should work
    local a4, e4 = s:add({ scope = 'range', file = 'a.lua', lnum = 20, start_lnum = 16, text = 'ok', bufnr = 1 })
    eq(type(a4.id), 'number')
    eq(e4, nil)
end

-- Test 29: add() rejects duplicate file annotation for same file
T['reject_dup_file'] = function()
    local s = State.new()
    s:add({ scope = 'file', file = 'a.lua', text = 'first', bufnr = 1 })
    local ann, err = s:add({ scope = 'file', file = 'a.lua', text = 'second', bufnr = 1 })
    eq(ann, nil)
    eq(type(err), 'string')
    -- Different file should work
    local ann2, err2 = s:add({ scope = 'file', file = 'b.lua', text = 'ok', bufnr = 2 })
    eq(type(ann2.id), 'number')
    eq(err2, nil)
end

-- Test 30: add() rejects duplicate overall annotation
T['reject_dup_overall'] = function()
    local s = State.new()
    s:add({ scope = 'overall', text = 'first' })
    local ann, err = s:add({ scope = 'overall', text = 'second' })
    eq(ann, nil)
    eq(type(err), 'string')
end

-- Test 31: reset() clears all annotations
T['reset'] = function()
    local s = State.new()
    s:add({ scope = 'line', file = 'a.lua', lnum = 1, text = 'a', bufnr = 1 })
    s:add({ scope = 'line', file = 'a.lua', lnum = 2, text = 'b', bufnr = 1 })
    s:add({ scope = 'overall', text = 'c' })
    s:reset()
    eq(#s:all(), 0)
end

-- Test 32: reset() fires on_change("delete") for each
T['reset_on_change'] = function()
    local s, log = make_state_with_log()
    s:add({ scope = 'line', file = 'a.lua', lnum = 1, text = 'a', bufnr = 1 })
    s:add({ scope = 'line', file = 'a.lua', lnum = 2, text = 'b', bufnr = 1 })
    s:add({ scope = 'overall', text = 'c' })
    -- 3 add events so far
    eq(#log, 3)
    s:reset()
    -- 3 more delete events
    eq(#log, 6)
    eq(log[4].event, 'delete')
    eq(log[5].event, 'delete')
    eq(log[6].event, 'delete')
end

return T
