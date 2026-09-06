-- Per-file C line coverage floor for the Lua binding sources, measured
-- from MODE=cov's gcov data and ratcheted the way tool/lua/coverage.lua
-- ratchets function coverage from --ftrace traces. The two floors are
-- independent: this one reads .gcno/.gcda pairs gcc's -fprofile-arcs
-- writes under o/$(MODE)/ (COVERAGE_CFLAGS, build/config.mk) and is
-- only meaningful in MODE=cov; tool/lua/coverage.lua's ftrace-based
-- floor is measured in default mode and is unaffected by this file.
--
-- The 13 instrumented binding sources and the object each one's gcov
-- data lives at (relative to o/$(MODE)/) are hardcoded in FILES below,
-- not discovered: tool/net/lfuncs.c is the one file compiled into two
-- objects, and only tool/lua/lfuncs3.o -- the one TOOL_LUA_LUA_MODULES
-- actually links into this test target's lua.dbg -- carries coverage
-- from these tests; tool/net/lfuncs.o's (built for other MODE=cov
-- binaries) does not and is never read here.
--
-- For each (source, object) pair, this runs the host `gcov
-- --json-format` from a scratch directory so the `<object base
-- name>.gcov.json.gz` files it writes -- gcov names its output after
-- the OBJECT, not the source, and always writes to the current
-- directory regardless of `-o` -- land somewhere predictable and never
-- collide (no two objects here share a base name). Each is read back
-- with cosmo.Inflate({format = "gzip"}) then cosmo.DecodeJson, and
-- `files[1].lines[]` is reduced to one {covered, total} pair per file:
-- `total` is the number of distinct line_number entries, `covered` the
-- count of those whose max count across all entries on that line
-- (a line can hold more than one block, e.g. more than one function)
-- is greater than zero. This matches gcov's own "Lines executed:X% of
-- N" summary exactly -- cross-checked against tool/net/lpath.c and
-- tool/net/lsqlite3.c while writing this script.
--
-- A file whose object has no .gcno, or an empty one, is a build
-- regression: it fails by name rather than being silently measured as
-- 0/0. gcov itself tolerates a missing .gcda (the counters just read
-- as all-zero, "assuming not executed"), so that case surfaces as an
-- ordinary below-floor failure instead.
--
-- Usage, as tool/lua/BUILD.mk invokes it:
--
--   lua.dbg tool/lua/line_coverage.lua
--
-- MODE is read from the environment (make exports it to every recipe);
-- LINE_COVERAGE_BASELINE=1 rewrites tool/lua/line_coverage_floor.lua to
-- exactly what the run measured -- a distinct variable from function
-- coverage's COVERAGE_BASELINE=1, so the two floors never rewrite each
-- other by accident.

local unix = require("cosmo.unix")
local cosmo = require("cosmo")

local FLOOR_PATH = "tool/lua/line_coverage_floor.lua"

local FILES = {
  { source = "third_party/lua/cosmo/lunix.c", object = "third_party/lua/cosmo/lunix.o" },
  { source = "tool/lua/lcosmo.c", object = "tool/lua/lcosmo.o" },
  { source = "tool/net/largon2.c", object = "tool/net/largon2.o" },
  { source = "tool/net/lcov.c", object = "tool/net/lcov.o" },
  { source = "tool/net/lfetch.c", object = "tool/net/lfetch.o" },
  { source = "tool/net/lfuncs.c", object = "tool/lua/lfuncs3.o" },
  { source = "tool/net/lgetopt.c", object = "tool/net/lgetopt.o" },
  { source = "tool/net/ljson.c", object = "tool/net/ljson.o" },
  { source = "tool/net/llua.c", object = "tool/net/llua.o" },
  { source = "tool/net/lpath.c", object = "tool/net/lpath.o" },
  { source = "tool/net/lre.c", object = "tool/net/lre.o" },
  { source = "tool/net/lsqlite3.c", object = "tool/net/lsqlite3.o" },
  { source = "tool/net/lzip.c", object = "tool/net/lzip.o" },
}

local function dirname(path)
  return path:match("^(.*)/[^/]+$") or "."
end

local function basename(path)
  return path:match("^.*/([^/]+)$") or path
end

-- Runs argv, chdir'd to `cwd` first, waiting for it to exit. Returns
-- the child's merged stdout+stderr and a description of how it ended
-- ("exit status N" / "signal N"); the caller decides pass or fail --
-- gcov's own exit status is not that signal here (see the version-
-- mismatch note below), so this never raises on a nonzero exit.
local function run(argv, cwd)
  io.stdout:flush()
  io.stderr:flush()
  local pipe = assert(unix.pipe())
  local pid = assert(unix.fork())
  if pid == 0 then
    unix.close(pipe.reader)
    unix.dup(pipe.writer, 1)
    unix.dup(pipe.writer, 2)
    unix.close(pipe.writer)
    if cwd then
      local cok, cerr = unix.chdir(cwd)
      if not cok then
        io.stderr:write("chdir " .. cwd .. ": " .. tostring(cerr) .. "\n")
        unix.exit(127)
      end
    end
    local _, xerr = unix.execve(argv[1], argv)
    io.stderr:write("execve " .. argv[1] .. ": " .. tostring(xerr) .. "\n")
    unix.exit(127)
  end
  unix.close(pipe.writer)
  local output = {}
  while true do
    local chunk, _, errno = unix.read(pipe.reader, 65536)
    if chunk == nil then
      if errno ~= unix.EINTR then
        break
      end
    elseif chunk == "" then
      break
    else
      output[#output + 1] = chunk
    end
  end
  unix.close(pipe.reader)
  local result = assert(unix.wait(pid))
  local wstatus = result.wstatus
  local desc
  if unix.WIFEXITED(wstatus) then
    desc = "exit status " .. unix.WEXITSTATUS(wstatus)
  elseif unix.WIFSIGNALED(wstatus) then
    desc = "signal " .. unix.WTERMSIG(wstatus)
  else
    desc = "wait status " .. tostring(wstatus)
  end
  return table.concat(output), desc
end

local function sorted_keys(t)
  local keys = {}
  for k in pairs(t) do
    keys[#keys + 1] = k
  end
  table.sort(keys)
  return keys
end

local mode = os.getenv("MODE") or ""
local outroot = "o/" .. mode
local root = assert(unix.getcwd())
local covout = outroot .. "/tool/lua/covout"

local mkok, merr = unix.makedirs(covout)
if not mkok then
  io.stderr:write("line_coverage: makedirs " .. covout .. ": " .. tostring(merr) .. "\n")
  os.exit(1)
end

local gcov_path, cverr = unix.commandv("gcov")
if not gcov_path then
  io.stderr:write("line_coverage: commandv gcov: " .. tostring(cverr) .. "\n")
  os.exit(1)
end

-- 1. For each instrumented (source, object) pair: check its .gcno
-- exists and is non-empty, run gcov --json-format from `covout`, and
-- reduce the result to {covered, total}.
local measured = {}
local missing = {}
for _, entry in ipairs(FILES) do
  local obj_rel = outroot .. "/" .. entry.object
  local gcno_rel = obj_rel .. ".gcno"
  local st = unix.stat(gcno_rel)
  if st == nil or st:size() == 0 then
    missing[entry.source] = true
  else
    local objdir_abs = root .. "/" .. outroot .. "/" .. dirname(entry.object)
    local gcno_abs = root .. "/" .. gcno_rel
    local json_gz_path = covout .. "/" .. basename(entry.object) .. ".gcov.json.gz"
    os.remove(json_gz_path)
    -- gcov's own exit status is not the success signal: this host's
    -- gcov (13.3.0) reads .gcno notes cosmocc's gcc wrote in a newer
    -- format ('B41*' vs. the host's preferred 'B33*'), warns, and
    -- exits 3 -- while still writing a fully correct .gcov.json.gz.
    -- Whether that file now exists is the real signal.
    local output, desc = run({ gcov_path, "--json-format", "-o", objdir_abs, gcno_abs }, covout)
    local f, operr = io.open(json_gz_path, "rb")
    if not f then
      io.stderr:write("line_coverage: gcov " .. entry.source .. " (" .. desc ..
        ") produced no " .. json_gz_path .. ": " .. output .. "\n")
      os.exit(1)
    end
    local gz = f:read("a")
    f:close()
    local raw, inflerr = cosmo.Inflate(gz, { format = "gzip" })
    if not raw then
      io.stderr:write("line_coverage: inflate " .. json_gz_path .. ": " .. tostring(inflerr) .. "\n")
      os.exit(1)
    end
    local obj, jerr = cosmo.DecodeJson(raw)
    if not obj then
      io.stderr:write("line_coverage: decode " .. json_gz_path .. ": " .. tostring(jerr) .. "\n")
      os.exit(1)
    end
    local file_entry = obj.files and obj.files[1]
    local max_count = {}
    if file_entry then
      for _, line in ipairs(file_entry.lines or {}) do
        local n = line.line_number
        if max_count[n] == nil or line.count > max_count[n] then
          max_count[n] = line.count
        end
      end
    end
    local total, covered = 0, 0
    for _, count in pairs(max_count) do
      total = total + 1
      if count > 0 then
        covered = covered + 1
      end
    end
    measured[entry.source] = { covered = covered, total = total }
  end
end

-- 2. The floor: rewrite it, or gate on it.
local function write_floor(path)
  local lines = {
    "-- Per-file C line coverage floor for the Lua binding sources,",
    "-- measured by tool/lua/line_coverage.lua from gcov data in",
    "-- MODE=cov. Rewrite with LINE_COVERAGE_BASELINE=1; never lower a",
    "-- covered count by hand.",
    "return {",
  }
  for _, entry in ipairs(FILES) do
    local e = measured[entry.source]
    lines[#lines + 1] = string.format("  [%q] = { covered = %d, total = %d },",
      entry.source, e.covered, e.total)
  end
  lines[#lines + 1] = "}"
  local f = assert(io.open(path, "w"))
  f:write(table.concat(lines, "\n"), "\n")
  f:close()
end

if os.getenv("LINE_COVERAGE_BASELINE") == "1" then
  local missing_srcs = sorted_keys(missing)
  if #missing_srcs > 0 then
    io.stderr:write("line_coverage: cannot baseline, missing .gcno for: " ..
      table.concat(missing_srcs, " ") .. "\n")
    os.exit(1)
  end
  write_floor(FLOOR_PATH)
  print("line_coverage: floor rewritten to " .. FLOOR_PATH)
  os.exit(0)
end

local floor = dofile(FLOOR_PATH)
local instrumented = {}
for _, entry in ipairs(FILES) do
  instrumented[entry.source] = true
end

local failures = {}
print(string.format("%-36s %8s %8s %6s", "file", "total", "covered", "floor"))
for _, entry in ipairs(FILES) do
  local file = entry.source
  if missing[file] then
    print(string.format("%-36s %8s %8s %6s", file, "-", "-", "-"))
    failures[#failures + 1] = file .. ": no .gcno produced for its object " ..
      "(missing or empty) -- build regression"
  else
    local e, f = measured[file], floor[file]
    print(string.format("%-36s %8d %8d %6s", file, e.total, e.covered,
      f and tostring(f.covered) or "-"))
    if f == nil then
      failures[#failures + 1] = file .. ": measured " .. e.covered ..
        "/" .. e.total .. " lines but has no floor entry; run " ..
        "LINE_COVERAGE_BASELINE=1 to add it"
    elseif e.covered < f.covered then
      failures[#failures + 1] = string.format(
        "%s: covered %d, floor %d", file, e.covered, f.covered)
    end
  end
end
for _, file in ipairs(sorted_keys(floor)) do
  if not instrumented[file] then
    failures[#failures + 1] = file .. ": floored at " .. floor[file].covered ..
      " but is not one of the instrumented binding sources; run " ..
      "LINE_COVERAGE_BASELINE=1 if it was removed on purpose"
  end
end

if #failures > 0 then
  io.stderr:write("line_coverage: FAIL\n  " .. table.concat(failures, "\n  ") .. "\n")
  os.exit(1)
end
print("test_line_coverage: PASS")
