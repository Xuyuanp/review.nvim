stds.nvim = {
  read_globals = { "jit" }
}
std = "lua51+nvim"
cache = true
self = false
include_files = { "lua/", "tests/" }
read_globals = { "vim", "MiniTest" }
ignore = {
  "631",      -- max_line_length
  "212/_.*",  -- unused argument, for vars with "_" prefix
}
