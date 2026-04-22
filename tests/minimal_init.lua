-- Minimal init for running tests with mini.test
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')

-- Add plugin to runtimepath
vim.opt.rtp:prepend(root)

-- Clone mini.nvim if not present (used for mini.test)
local mini_path = root .. '/.tests/mini.nvim'
if not vim.uv.fs_stat(mini_path) then
    vim.fn.system({ 'git', 'clone', '--filter=blob:none', 'https://github.com/echasnovski/mini.nvim', mini_path })
end
vim.opt.rtp:prepend(mini_path)

-- Set up mini.test
require('mini.test').setup()
