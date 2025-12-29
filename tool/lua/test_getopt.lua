local getopt = require("cosmo.getopt")

-- Test module exists
assert(getopt, "getopt module should exist")
assert(type(getopt.parse) == "function", "getopt.parse should be a function")

-- Test short options only
local opts, args = getopt.parse({"-h", "-v", "-o", "out.txt", "file.txt"}, "hvo:", {})
assert(opts.h == true, "opts.h should be true")
assert(opts.v == true, "opts.v should be true")
assert(opts.o == "out.txt", "opts.o should be 'out.txt'")
assert(args[1] == "file.txt", "first remaining arg should be 'file.txt'")
assert(#args == 1, "should have exactly 1 remaining arg")

-- Test long options
opts, args = getopt.parse({"--help", "--output=foo.txt", "input.txt"}, "ho:", {
  {"help", "none", "h"},
  {"output", "required", "o"},
})
assert(opts.help == true, "opts.help should be true")
assert(opts.h == true, "opts.h should also be true (from --help)")
assert(opts.output == "foo.txt", "opts.output should be 'foo.txt'")
assert(opts.o == "foo.txt", "opts.o should also be 'foo.txt'")
assert(args[1] == "input.txt", "remaining arg should be 'input.txt'")

-- Test long option with separate argument
opts, args = getopt.parse({"--output", "bar.txt"}, "o:", {
  {"output", "required", "o"},
})
assert(opts.output == "bar.txt", "opts.output should be 'bar.txt'")
assert(opts.o == "bar.txt", "opts.o should be 'bar.txt'")

-- Test combined short options
opts, args = getopt.parse({"-hv", "file.txt"}, "hv", {})
assert(opts.h == true, "opts.h should be true")
assert(opts.v == true, "opts.v should be true")
assert(args[1] == "file.txt", "remaining arg should be 'file.txt'")

-- Test -- terminator
opts, args = getopt.parse({"-h", "--", "-v", "file.txt"}, "hv", {})
assert(opts.h == true, "opts.h should be true")
assert(opts.v == nil, "-v after -- should not be parsed as option")
assert(args[1] == "-v", "first remaining should be '-v'")
assert(args[2] == "file.txt", "second remaining should be 'file.txt'")

-- Test empty args
opts, args = getopt.parse({}, "hv", {})
assert(next(opts) == nil, "opts should be empty")
assert(#args == 0, "args should be empty")

-- Test no longopts argument
opts, args = getopt.parse({"-h"}, "h")
assert(opts.h == true, "opts.h should be true without longopts arg")

print("PASS")
