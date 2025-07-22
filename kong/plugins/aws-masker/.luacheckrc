-- Luacheck configuration for AWS Masker Plugin
std = "lua51"

-- Global variables allowed
globals = {
  "kong",
  "ngx", 
  "_KONG",
  "describe",
  "it",
  "before_each",
  "after_each",
  "setup",
  "teardown",
  "assert",
  "spy",
  "stub",
  "mock",
  "finally"
}

-- Ignore specific warnings
ignore = {
  "212", -- unused argument
  "213", -- unused loop variable
  "311", -- value assigned to a local variable is unused
  "431", -- shadowing upvalue
}

-- Files to exclude
exclude_files = {
  "spec/**/*.lua", -- Test files have different rules
}

-- Maximum line length
max_line_length = 120

-- Maximum cyclomatic complexity
max_cyclomatic_complexity = 10