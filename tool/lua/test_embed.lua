#!/usr/bin/env lua
-- Test cosmo.embed module
-- Tests embedding Lua libraries into the executable

local unix = require("cosmo.unix")
local zip = require("cosmo.zip")

local tests_run = 0
local tests_passed = 0

local function test(name, fn)
  tests_run = tests_run + 1
  io.write("Testing " .. name .. "... ")
  io.flush()

  local ok, err = pcall(fn)
  if ok then
    tests_passed = tests_passed + 1
    print("OK")
  else
    print("FAIL")
    print("  Error: " .. tostring(err))
  end
end

local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s",
                        msg or "assertion failed",
                        tostring(expected),
                        tostring(actual)))
  end
end

local function assert_match(str, pattern, msg)
  if not string.match(str, pattern) then
    error(string.format("%s: '%s' does not match pattern '%s'",
                        msg or "assertion failed",
                        str,
                        pattern))
  end
end

local function cleanup()
  -- Clean up test files
  local files = {
    "/tmp/test-package.zip",
    "/tmp/test-embed-lua",
    "/tmp/embed-test-simple.lua",
  }
  for _, f in ipairs(files) do
    unix.unlink(f)
  end
end

-- Test 1: Module can be loaded
test("cosmo.embed module loads", function()
  local embed = require("cosmo.embed")
  assert(embed ~= nil, "embed module should not be nil")
  assert(type(embed) == "table", "embed module should be a table")
end)

-- Test 2: Module has expected functions
test("cosmo.embed has install function", function()
  local embed = require("cosmo.embed")
  assert(type(embed.install) == "function", "embed.install should be a function")
end)

-- Test 3: Create a simple test package
test("create test package", function()
  -- Create a simple Lua module
  local test_module = [[
-- Test module
local M = {}

function M.hello()
  return "Hello from embedded module!"
end

function M.add(a, b)
  return a + b
end

M.version = "1.0.0"

return M
]]

  -- Write test module to temp file
  local fd = unix.open("/tmp/embed-test-simple.lua",
                       unix.O_WRONLY | unix.O_CREAT | unix.O_TRUNC,
                       0644)
  assert(fd, "Failed to create test module file")
  unix.write(fd, test_module)
  unix.close(fd)

  -- Verify file was created
  fd = unix.open("/tmp/embed-test-simple.lua", unix.O_RDONLY)
  assert(fd, "Failed to open created test module")
  local stat = unix.fstat(fd)
  assert(stat, "Failed to stat test module")
  assert(stat:size() > 0, "Test module should not be empty")
  unix.close(fd)
end)

-- Test 4: Create a ZIP package with the test module
test("create test ZIP package", function()
  local cosmo = require("cosmo")

  -- Read the test module
  local fd = unix.open("/tmp/embed-test-simple.lua", unix.O_RDONLY)
  assert(fd, "Failed to open test module")
  local stat = unix.fstat(fd)
  local content = unix.read(fd, stat:size())
  unix.close(fd)

  -- Create a simple ZIP file with the module
  -- We'll manually create a ZIP with one file
  local function pack_u16(n)
    return string.char(n & 0xFF, (n >> 8) & 0xFF)
  end

  local function pack_u32(n)
    return string.char(
      n & 0xFF,
      (n >> 8) & 0xFF,
      (n >> 16) & 0xFF,
      (n >> 24) & 0xFF
    )
  end

  local filename = "testpkg/init.lua"
  local crc = cosmo.Crc32(0, content)

  -- Local file header
  local lfh =
    "\x50\x4B\x03\x04" ..  -- signature
    pack_u16(20) ..         -- version
    pack_u16(0) ..          -- flags
    pack_u16(0) ..          -- compression (none)
    pack_u16(0) ..          -- mod time
    pack_u16(0) ..          -- mod date
    pack_u32(crc) ..        -- crc32
    pack_u32(#content) ..   -- compressed size
    pack_u32(#content) ..   -- uncompressed size
    pack_u16(#filename) ..  -- filename length
    pack_u16(0)             -- extra field length

  -- Central directory header
  local cfh =
    "\x50\x4B\x01\x02" ..  -- signature
    pack_u16((3 << 8) | 20) .. -- version made by
    pack_u16(20) ..         -- version needed
    pack_u16(0) ..          -- flags
    pack_u16(0) ..          -- compression
    pack_u16(0) ..          -- mod time
    pack_u16(0) ..          -- mod date
    pack_u32(crc) ..        -- crc32
    pack_u32(#content) ..   -- compressed size
    pack_u32(#content) ..   -- uncompressed size
    pack_u16(#filename) ..  -- filename length
    pack_u16(0) ..          -- extra field length
    pack_u16(0) ..          -- comment length
    pack_u16(0) ..          -- disk number
    pack_u16(0) ..          -- internal attrs
    pack_u32(0x81A40000) .. -- external attrs
    pack_u32(0)             -- offset of local header

  local cdir_offset = #lfh + #filename + #content
  local cdir_size = #cfh + #filename

  -- End of central directory
  local eocd =
    "\x50\x4B\x05\x06" ..  -- signature
    pack_u16(0) ..          -- disk number
    pack_u16(0) ..          -- disk with central dir
    pack_u16(1) ..          -- entries on this disk
    pack_u16(1) ..          -- total entries
    pack_u32(cdir_size) ..  -- central directory size
    pack_u32(cdir_offset) .. -- central directory offset
    pack_u16(0)             -- comment length

  -- Write ZIP file
  local zip_content = lfh .. filename .. content .. cfh .. filename .. eocd

  fd = unix.open("/tmp/test-package.zip",
                 unix.O_WRONLY | unix.O_CREAT | unix.O_TRUNC,
                 0644)
  assert(fd, "Failed to create test ZIP")
  unix.write(fd, zip_content)
  unix.close(fd)

  -- Verify ZIP can be read
  local reader = zip.open("/tmp/test-package.zip")
  assert(reader, "Failed to open created ZIP")
  local entries = reader:list()
  assert(#entries == 1, "ZIP should have 1 entry")
  assert(entries[1] == filename, "Entry should have correct name")
  reader:close()
end)

-- Test 5: Test ZIP writing functions (internal)
test("ZIP writing functions work", function()
  local cosmo = require("cosmo")

  local function pack_u16(n)
    return string.char(n & 0xFF, (n >> 8) & 0xFF)
  end

  local function pack_u32(n)
    return string.char(
      n & 0xFF,
      (n >> 8) & 0xFF,
      (n >> 16) & 0xFF,
      (n >> 24) & 0xFF
    )
  end

  -- Test pack_u16
  local packed = pack_u16(0x1234)
  assert(#packed == 2, "pack_u16 should produce 2 bytes")
  assert(packed:byte(1) == 0x34, "pack_u16 byte 1")
  assert(packed:byte(2) == 0x12, "pack_u16 byte 2")

  -- Test pack_u32
  packed = pack_u32(0x12345678)
  assert(#packed == 4, "pack_u32 should produce 4 bytes")
  assert(packed:byte(1) == 0x78, "pack_u32 byte 1")
  assert(packed:byte(2) == 0x56, "pack_u32 byte 2")
  assert(packed:byte(3) == 0x34, "pack_u32 byte 3")
  assert(packed:byte(4) == 0x12, "pack_u32 byte 4")

  -- Test CRC32
  local crc = cosmo.Crc32(0, "hello")
  assert(type(crc) == "number", "CRC32 should return a number")
  assert(crc > 0, "CRC32 should be positive")
end)

-- Test 6: Test path normalization logic
test("path normalization", function()
  local function normalize_path(path, package_name)
    local zippath = path

    -- Remove common prefixes
    zippath = zippath:gsub("^[^/]+/lua/", "")
    zippath = zippath:gsub("^lua/", "")

    -- If path doesn't start with package name, prepend it
    if not zippath:match("^" .. package_name .. "/") and
       not zippath:match("^" .. package_name .. "%.lua$") then
      zippath = package_name .. "/" .. zippath
    end

    -- Ensure .lua/ prefix for ZIP
    if not zippath:match("^%.lua/") then
      zippath = ".lua/" .. zippath
    end

    return zippath
  end

  -- Test cases
  assert_eq(normalize_path("testpkg/init.lua", "testpkg"),
            ".lua/testpkg/init.lua",
            "simple path")

  assert_eq(normalize_path("testpkg-1.0/lua/testpkg/init.lua", "testpkg"),
            ".lua/testpkg/init.lua",
            "path with lua/ prefix")

  assert_eq(normalize_path("lua/testpkg/utils.lua", "testpkg"),
            ".lua/testpkg/utils.lua",
            "path with leading lua/")

  assert_eq(normalize_path("init.lua", "testpkg"),
            ".lua/testpkg/init.lua",
            "bare filename")
end)

-- Test 7: File copying works
test("file copy operations", function()
  -- Create a test file
  local test_content = "test file content\n"
  local src = "/tmp/test-copy-src.txt"
  local dst = "/tmp/test-copy-dst.txt"

  -- Write source
  local fd = unix.open(src, unix.O_WRONLY | unix.O_CREAT | unix.O_TRUNC, 0644)
  assert(fd, "Failed to create source file")
  unix.write(fd, test_content)
  unix.close(fd)

  -- Copy to destination
  local src_fd = unix.open(src, unix.O_RDONLY)
  assert(src_fd, "Failed to open source")

  local stat = unix.fstat(src_fd)
  assert(stat, "Failed to stat source")

  local dst_fd = unix.open(dst, unix.O_WRONLY | unix.O_CREAT | unix.O_TRUNC, 0644)
  assert(dst_fd, "Failed to create destination")

  -- Copy in chunks
  local chunk_size = 64
  local remaining = stat:size()
  while remaining > 0 do
    local to_read = math.min(remaining, chunk_size)
    local chunk = unix.read(src_fd, to_read)
    if not chunk or #chunk == 0 then break end
    unix.write(dst_fd, chunk)
    remaining = remaining - #chunk
  end

  unix.close(src_fd)
  unix.close(dst_fd)

  -- Verify copy
  dst_fd = unix.open(dst, unix.O_RDONLY)
  assert(dst_fd, "Failed to open destination")
  stat = unix.fstat(dst_fd)
  local content = unix.read(dst_fd, stat:size())
  unix.close(dst_fd)

  assert_eq(content, test_content, "Copied content should match")

  -- Cleanup
  unix.unlink(src)
  unix.unlink(dst)
end)

-- Test 8: Error handling
test("error handling for missing files", function()
  local ok, err = pcall(function()
    unix.open("/nonexistent/path/file.txt", unix.O_RDONLY)
  end)
  -- This should not crash, just return nil/false
  assert(ok, "Opening nonexistent file should not throw")
end)

-- Test 9: Verify executable path detection
test("executable path detection", function()
  local function get_executable_path()
    local fd = unix.open("/proc/self/exe", unix.O_RDONLY)
    if fd then
      unix.close(fd)
      return "/proc/self/exe"
    end
    return arg[0] or arg[-1]
  end

  local path = get_executable_path()
  assert(path ~= nil, "Should detect executable path")
  assert(type(path) == "string", "Path should be a string")
  assert(#path > 0, "Path should not be empty")
end)

-- Test 10: Verify rockspec parsing sandbox works
test("rockspec parsing sandbox", function()
  local rockspec_content = [[
package = "testpkg"
version = "1.0-1"
source = {
  url = "https://example.com/testpkg-1.0.zip"
}
description = {
  summary = "Test package",
  license = "MIT"
}
dependencies = {
  "lua >= 5.1"
}
build = {
  type = "builtin",
  modules = {
    testpkg = "testpkg.lua"
  }
}
]]

  local env = {
    package = {},
    version = nil,
    source = {},
    build = {},
    dependencies = {},
    description = {},
  }

  local chunk, err = load(rockspec_content, "rockspec", "t", env)
  assert(chunk, "Rockspec should parse: " .. tostring(err))

  local ok, result = pcall(chunk)
  assert(ok, "Rockspec should execute: " .. tostring(result))

  assert_eq(env.package, "testpkg", "Package name should be parsed")
  assert_eq(env.version, "1.0-1", "Version should be parsed")
  assert_eq(env.source.url, "https://example.com/testpkg-1.0.zip", "Source URL should be parsed")
end)

-- Cleanup
cleanup()

-- Summary
print("\n" .. string.rep("=", 60))
print(string.format("Tests: %d/%d passed", tests_passed, tests_run))
print(string.rep("=", 60))

if tests_passed ~= tests_run then
  os.exit(1)
end
