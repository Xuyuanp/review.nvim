local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local export = require('review.export')

local T = new_set()

--- Helper: create a fake annotation
---@param overrides table
---@return review.Annotation
local function make_ann(overrides)
    ---@type review.Annotation
    local ann = {
        id = overrides.id or 1,
        scope = overrides.scope or 'line',
        file = overrides.file,
        lnum = overrides.lnum,
        start_lnum = overrides.start_lnum,
        text = overrides.text or '',
        source_lines = overrides.source_lines,
        created_at = overrides.created_at or os.time(),
    }
    return ann
end

-- Test 33: Empty annotations produce empty string
T['empty'] = function()
    eq(export.generate({}), '')
end

-- Test 34: Overall-only export
T['overall_only'] = function()
    local result = export.generate({
        make_ann({ scope = 'overall', text = 'General feedback' }),
    })
    local expected = table.concat({
        '# Code Review',
        '',
        '## Overall',
        '',
        'General feedback',
        '',
    }, '\n')
    eq(result, expected)
end

-- Test 35: Single file with line annotations
T['single_file_lines'] = function()
    local result = export.generate({
        make_ann({ id = 1, scope = 'line', file = 'src/main.rs', lnum = 10, text = 'Fix this', created_at = 100 }),
        make_ann({ id = 2, scope = 'line', file = 'src/main.rs', lnum = 20, text = 'And this', created_at = 101 }),
    })
    local expected = table.concat({
        '# Code Review',
        '',
        '## src/main.rs',
        '',
        '### L10',
        '',
        'Fix this',
        '',
        '### L20',
        '',
        'And this',
        '',
    }, '\n')
    eq(result, expected)
end

-- Test 36: Range annotations produce L{start}-L{end} format
T['range_format'] = function()
    local result = export.generate({
        make_ann({
            id = 1,
            scope = 'range',
            file = 'src/lib.rs',
            lnum = 95,
            start_lnum = 87,
            text = 'Duplicated logic',
            created_at = 100,
        }),
    })
    local expected = table.concat({
        '# Code Review',
        '',
        '## src/lib.rs',
        '',
        '### L87-L95',
        '',
        'Duplicated logic',
        '',
    }, '\n')
    eq(result, expected)
end

-- Test 37: Line annotations produce L{num} format
T['line_format'] = function()
    local result = export.generate({
        make_ann({ id = 1, scope = 'line', file = 'a.lua', lnum = 42, text = 'Check whitespace', created_at = 100 }),
    })
    eq(result:match('### L42'), '### L42')
end

-- Test 38: File-level annotation appears before line annotations
T['file_before_lines'] = function()
    local result = export.generate({
        make_ann({ id = 1, scope = 'file', file = 'src/auth.rs', text = 'Needs refactor', created_at = 100 }),
        make_ann({
            id = 2,
            scope = 'line',
            file = 'src/auth.rs',
            lnum = 5,
            text = 'Fix this line',
            created_at = 101,
        }),
    })
    local expected = table.concat({
        '# Code Review',
        '',
        '## src/auth.rs',
        '',
        'Needs refactor',
        '',
        '### L5',
        '',
        'Fix this line',
        '',
    }, '\n')
    eq(result, expected)
end

-- Test 39: Multiple files ordered by first annotation time
T['multi_file_order'] = function()
    local result = export.generate({
        make_ann({ id = 1, scope = 'line', file = 'first.lua', lnum = 1, text = 'A', created_at = 100 }),
        make_ann({ id = 2, scope = 'line', file = 'second.lua', lnum = 1, text = 'B', created_at = 200 }),
    })
    -- first.lua should appear before second.lua
    local pos_first = result:find('## first.lua')
    local pos_second = result:find('## second.lua')
    eq(pos_first < pos_second, true)
end

-- Test 40: Within-file annotations ordered by line number
T['within_file_line_order'] = function()
    -- Add in reverse order, but output should be sorted by lnum
    local result = export.generate({
        make_ann({ id = 1, scope = 'line', file = 'a.lua', lnum = 50, text = 'Later', created_at = 100 }),
        make_ann({ id = 2, scope = 'line', file = 'a.lua', lnum = 10, text = 'Earlier', created_at = 101 }),
    })
    local pos_10 = result:find('### L10')
    local pos_50 = result:find('### L50')
    eq(pos_10 < pos_50, true)
end

-- Test 41: File paths are relative to cwd (input already relative, pass-through)
T['relative_paths'] = function()
    local result = export.generate({
        make_ann({
            id = 1,
            scope = 'line',
            file = 'src/db/pool.rs',
            lnum = 12,
            text = 'Hardcoded?',
            created_at = 100,
        }),
    })
    eq(result:match('## src/db/pool.rs'), '## src/db/pool.rs')
end

-- Test: Line annotation with source_lines includes blockquote
T['line_with_source'] = function()
    local result = export.generate({
        make_ann({
            id = 1,
            scope = 'line',
            file = 'src/main.rs',
            lnum = 23,
            text = 'Needs error handling',
            source_lines = { '    let x = foo();' },
            created_at = 100,
        }),
    })
    local expected = table.concat({
        '# Code Review',
        '',
        '## src/main.rs',
        '',
        '### L23',
        '',
        '>     let x = foo();',
        '',
        'Needs error handling',
        '',
    }, '\n')
    eq(result, expected)
end

-- Test: Range annotation with source_lines includes all lines as blockquote
T['range_with_source'] = function()
    local result = export.generate({
        make_ann({
            id = 1,
            scope = 'range',
            file = 'src/lib.rs',
            lnum = 32,
            start_lnum = 30,
            text = 'Extract this into a function',
            source_lines = { '    let a = 1;', '    let b = 2;', '    let c = a + b;' },
            created_at = 100,
        }),
    })
    local expected = table.concat({
        '# Code Review',
        '',
        '## src/lib.rs',
        '',
        '### L30-L32',
        '',
        '>     let a = 1;',
        '>     let b = 2;',
        '>     let c = a + b;',
        '',
        'Extract this into a function',
        '',
    }, '\n')
    eq(result, expected)
end

-- Test: nil source_lines omits blockquote (backward compat)
T['nil_source_lines'] = function()
    local result = export.generate({
        make_ann({
            id = 1,
            scope = 'line',
            file = 'a.lua',
            lnum = 5,
            text = 'Comment',
            created_at = 100,
        }),
    })
    local expected = table.concat({
        '# Code Review',
        '',
        '## a.lua',
        '',
        '### L5',
        '',
        'Comment',
        '',
    }, '\n')
    eq(result, expected)
end

-- Test: empty source_lines omits blockquote
T['empty_source_lines'] = function()
    local result = export.generate({
        make_ann({
            id = 1,
            scope = 'line',
            file = 'a.lua',
            lnum = 5,
            text = 'Comment',
            source_lines = {},
            created_at = 100,
        }),
    })
    local expected = table.concat({
        '# Code Review',
        '',
        '## a.lua',
        '',
        '### L5',
        '',
        'Comment',
        '',
    }, '\n')
    eq(result, expected)
end

-- Test: source line containing > character is not double-escaped
T['source_with_gt_char'] = function()
    local result = export.generate({
        make_ann({
            id = 1,
            scope = 'line',
            file = 'a.lua',
            lnum = 1,
            text = 'Check this',
            source_lines = { 'if x > 0 then' },
            created_at = 100,
        }),
    })
    eq(result:match('> if x > 0 then'), '> if x > 0 then')
end

return T
