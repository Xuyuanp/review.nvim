if vim.g.loaded_review then
    return
end
vim.g.loaded_review = true

vim.api.nvim_create_user_command('Review', function(opts)
    require('review').setup({
        output = opts.args ~= '' and opts.args or nil,
        keymaps = true,
    })
end, {
    nargs = '?',
    complete = 'file',
    desc = 'Start a review session. Optionally specify an output file path for auto-export on exit.',
})
