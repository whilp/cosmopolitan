local zip = require("cosmo.zip")
local unix = require("cosmo.unix")

-- Test module exists
assert(zip, "zip module should exist")
assert(type(zip.open) == "function", "zip.open should be a function")

-- Create a temporary directory for tests
local tmpdir = unix.mkdtemp("/tmp/test_zip_XXXXXX")
assert(tmpdir, "failed to create temp dir")

--------------------------------------------------------------------------------
-- Test zip.open (Reader) with system-created zip
--------------------------------------------------------------------------------

local file1_content = "Hello, World!"
local file2_content = "This is a longer text file with some content.\nIt has multiple lines.\nAnd some more text."

-- Write test files
local fd = unix.open(tmpdir .. "/file1.txt", unix.O_CREAT | unix.O_WRONLY, 0644)
assert(fd, "failed to create file1.txt")
unix.write(fd, file1_content)
unix.close(fd)

fd = unix.open(tmpdir .. "/file2.txt", unix.O_CREAT | unix.O_WRONLY, 0644)
assert(fd, "failed to create file2.txt")
unix.write(fd, file2_content)
unix.close(fd)

-- Create zip file using system zip command
local zippath = tmpdir .. "/test.zip"
local ok = os.execute("cd " .. tmpdir .. " && zip -q test.zip file1.txt file2.txt")
assert(ok == 0 or ok == true, "failed to create test zip file")

-- Test opening the zip file
local reader, err = zip.open(zippath)
assert(reader, "failed to open zip: " .. tostring(err))
assert(tostring(reader):match("zip.Reader"), "tostring should identify as zip.Reader")

-- Test listing entries
local entries = reader:list()
assert(entries, "list should return a table")
assert(#entries == 2, "should have 2 entries, got " .. #entries)

local has_file1, has_file2 = false, false
for _, name in ipairs(entries) do
  if name == "file1.txt" then has_file1 = true end
  if name == "file2.txt" then has_file2 = true end
end
assert(has_file1, "should have file1.txt")
assert(has_file2, "should have file2.txt")

-- Test stat
local stat = reader:stat("file1.txt")
assert(stat, "stat should return a table for existing file")
assert(stat.size == #file1_content, "size should match content length")
assert(stat.crc32, "should have crc32")
assert(stat.method ~= nil, "should have method")
assert(stat.mtime, "should have mtime")

-- Test stat for non-existent file
local stat2 = reader:stat("nonexistent.txt")
assert(stat2 == nil, "stat should return nil for non-existent file")

-- Test reading uncompressed content
local content1 = reader:read("file1.txt")
assert(content1 == file1_content, "read content should match original: got '" .. tostring(content1) .. "'")

-- Test reading compressed content (file2 might be compressed if large enough)
local content2 = reader:read("file2.txt")
assert(content2 == file2_content, "read content should match original for file2")

-- Test reading non-existent file
local content3, err3 = reader:read("nonexistent.txt")
assert(content3 == nil, "reading non-existent file should return nil")
assert(err3, "should have error message")

-- Test close
reader:close()
assert(tostring(reader):match("closed"), "tostring should indicate closed after close()")

-- Test operations on closed reader
local entries2, err2 = reader:list()
assert(entries2 == nil, "list on closed reader should return nil")
assert(err2, "should have error message for closed reader")

-- Test opening non-existent file
local reader2, err2 = zip.open("/nonexistent/path/to/file.zip")
assert(reader2 == nil, "opening non-existent file should return nil")
assert(err2, "should have error message")

-- Test opening non-zip file
local reader3, err3 = zip.open(tmpdir .. "/file1.txt")
assert(reader3 == nil, "opening non-zip file should return nil")
assert(err3, "should have error message for non-zip file")

--------------------------------------------------------------------------------
-- Test zip.open write mode (Writer)
--------------------------------------------------------------------------------

local zippath_writer = tmpdir .. "/test_writer.zip"
local writer_file1_content = "Hello, World!"
local writer_file2_content = "This is a longer text file with some content.\nIt has multiple lines.\nAnd some more text to ensure compression is worthwhile."

-- Test creating a new zip file
local writer, err = zip.open(zippath_writer, "w")
assert(writer, "failed to create zip: " .. tostring(err))
assert(tostring(writer):match("zip.Writer"), "tostring should identify as zip.Writer")
assert(tostring(writer):match("0 entries"), "new writer should have 0 entries")

-- Test adding files
ok, err = writer:add("file1.txt", writer_file1_content)
assert(ok, "failed to add file1.txt: " .. tostring(err))
assert(tostring(writer):match("1 entries"), "writer should have 1 entry after add")

ok, err = writer:add("subdir/file2.txt", writer_file2_content)
assert(ok, "failed to add subdir/file2.txt: " .. tostring(err))
assert(tostring(writer):match("2 entries"), "writer should have 2 entries after add")

-- Test adding with options
ok, err = writer:add("stored.txt", "stored content", {method = "store"})
assert(ok, "failed to add stored.txt: " .. tostring(err))

ok, err = writer:add("with_time.txt", "timed content", {mtime = 1700000000})
assert(ok, "failed to add with_time.txt: " .. tostring(err))

-- Test closing the writer
ok, err = writer:close()
assert(ok, "failed to close zip: " .. tostring(err))
assert(tostring(writer):match("closed"), "tostring should indicate closed")

-- Test operations on closed writer
local result, err = writer:add("test.txt", "content")
assert(result == nil, "add on closed writer should return nil")
assert(err, "should have error message for closed writer")

--------------------------------------------------------------------------------
-- Test reading back the zip we just wrote
--------------------------------------------------------------------------------

reader, err = zip.open(zippath_writer)
assert(reader, "failed to open zip we just wrote: " .. tostring(err))

-- Test listing entries
entries = reader:list()
assert(entries, "list should return a table")
assert(#entries == 4, "should have 4 entries, got " .. #entries)

has_file1, has_file2, has_stored, has_timed = false, false, false, false
for _, name in ipairs(entries) do
  if name == "file1.txt" then has_file1 = true end
  if name == "subdir/file2.txt" then has_file2 = true end
  if name == "stored.txt" then has_stored = true end
  if name == "with_time.txt" then has_timed = true end
end
assert(has_file1, "should have file1.txt")
assert(has_file2, "should have subdir/file2.txt")
assert(has_stored, "should have stored.txt")
assert(has_timed, "should have with_time.txt")

-- Test reading content
content1 = reader:read("file1.txt")
assert(content1 == writer_file1_content, "file1.txt content should match: got '" .. tostring(content1) .. "'")

content2 = reader:read("subdir/file2.txt")
assert(content2 == writer_file2_content, "subdir/file2.txt content should match")

local content_stored = reader:read("stored.txt")
assert(content_stored == "stored content", "stored.txt content should match")

-- Test stat
stat = reader:stat("file1.txt")
assert(stat, "stat should return a table")
assert(stat.size == #writer_file1_content, "size should match content length")
assert(stat.crc32, "should have crc32")

stat2 = reader:stat("stored.txt")
assert(stat2, "stat for stored.txt should work")
assert(stat2.method == 0, "stored file should have method 0 (store)")

reader:close()

--------------------------------------------------------------------------------
-- Test compression levels
--------------------------------------------------------------------------------

local zippath2 = tmpdir .. "/test_levels.zip"
writer, err = zip.open(zippath2, "w", {level = 9})
assert(writer, "failed to create zip with level 9: " .. tostring(err))

local big_content = string.rep("This is repetitive text. ", 1000)
ok, err = writer:add("big.txt", big_content)
assert(ok, "failed to add big.txt: " .. tostring(err))

ok, err = writer:close()
assert(ok, "failed to close: " .. tostring(err))

reader, err = zip.open(zippath2)
assert(reader, "failed to open level 9 zip: " .. tostring(err))

local stat_big = reader:stat("big.txt")
assert(stat_big, "stat should work for big.txt")
assert(stat_big.size == #big_content, "uncompressed size should match")
assert(stat_big.compressed_size < stat_big.size, "compressed size should be smaller for repetitive content")

local read_big = reader:read("big.txt")
assert(read_big == big_content, "content should match after compression/decompression")

reader:close()

--------------------------------------------------------------------------------
-- Test zip.open write mode with level 0 (store only)
--------------------------------------------------------------------------------

local zippath3 = tmpdir .. "/test_store.zip"
writer, err = zip.open(zippath3, "w", {level = 0})
assert(writer, "failed to create store-only zip: " .. tostring(err))

ok, err = writer:add("data.txt", big_content)
assert(ok, "failed to add data.txt: " .. tostring(err))

ok, err = writer:close()
assert(ok, "failed to close: " .. tostring(err))

reader, err = zip.open(zippath3)
assert(reader, "failed to open store-only zip: " .. tostring(err))

local stat_store = reader:stat("data.txt")
assert(stat_store.method == 0, "should use store method with level 0")
assert(stat_store.compressed_size == stat_store.size, "stored file should have same compressed and uncompressed size")

reader:close()

--------------------------------------------------------------------------------
-- Test edge cases
--------------------------------------------------------------------------------

-- Empty file
local zippath4 = tmpdir .. "/test_empty.zip"
writer, err = zip.open(zippath4, "w")
assert(writer, "failed to create zip: " .. tostring(err))

ok, err = writer:add("empty.txt", "")
assert(ok, "failed to add empty file: " .. tostring(err))

ok, err = writer:close()
assert(ok, "failed to close: " .. tostring(err))

reader, err = zip.open(zippath4)
assert(reader, "failed to open zip: " .. tostring(err))

local stat_empty = reader:stat("empty.txt")
assert(stat_empty.size == 0, "empty file should have size 0")

local content_empty = reader:read("empty.txt")
assert(content_empty == "", "empty file should read as empty string")

reader:close()

-- Binary content
local zippath5 = tmpdir .. "/test_binary.zip"
writer, err = zip.open(zippath5, "w")
assert(writer, "failed to create zip: " .. tostring(err))

local binary_content = ""
for i = 0, 255 do
  binary_content = binary_content .. string.char(i)
end

ok, err = writer:add("binary.bin", binary_content)
assert(ok, "failed to add binary file: " .. tostring(err))

ok, err = writer:close()
assert(ok, "failed to close: " .. tostring(err))

reader, err = zip.open(zippath5)
assert(reader, "failed to open zip: " .. tostring(err))

local read_binary = reader:read("binary.bin")
assert(read_binary == binary_content, "binary content should round-trip correctly")

reader:close()

--------------------------------------------------------------------------------
-- Test error cases
--------------------------------------------------------------------------------

-- Creating in non-existent directory
local bad_writer, bad_err = zip.open("/nonexistent/path/to/file.zip", "w")
assert(bad_writer == nil, "creating in non-existent dir should fail")
assert(bad_err, "should have error message")

-- Invalid compression level
ok, err = pcall(function()
  zip.open(tmpdir .. "/bad.zip", "w", {level = 10})
end)
assert(not ok, "level 10 should error")

--------------------------------------------------------------------------------
-- Test security validations
--------------------------------------------------------------------------------

local sec_zip = tmpdir .. "/security_test.zip"
writer, err = zip.open(sec_zip, "w")
assert(writer, "failed to create security test zip: " .. tostring(err))

-- Test path traversal rejection
result, err = writer:add("../escape.txt", "malicious")
assert(result == nil, "path traversal with .. should be rejected")
assert(err:match("unsafe path"), "error should mention unsafe path")

result, err = writer:add("/absolute/path.txt", "malicious")
assert(result == nil, "absolute path should be rejected")
assert(err:match("unsafe path"), "error should mention unsafe path")

result, err = writer:add("foo/../bar.txt", "malicious")
assert(result == nil, "embedded .. should be rejected")

result, err = writer:add("foo/bar/..", "malicious")
assert(result == nil, "trailing .. should be rejected")

-- Test empty name rejection
result, err = writer:add("", "content")
assert(result == nil, "empty name should be rejected")
assert(err:match("empty"), "error should mention empty")

-- Test null byte in name rejection
result, err = writer:add("foo\0bar.txt", "content")
assert(result == nil, "null byte in name should be rejected")
assert(err:match("null"), "error should mention null")

-- Test duplicate entry rejection
ok, err = writer:add("unique.txt", "first")
assert(ok, "first add should succeed")

result, err = writer:add("unique.txt", "second")
assert(result == nil, "duplicate entry should be rejected")
assert(err:match("duplicate"), "error should mention duplicate")

-- Test invalid mode rejection (symlink)
result, err = writer:add("symlink.txt", "content", {mode = 0120777})
assert(result == nil, "symlink mode should be rejected")
assert(err:match("regular file"), "error should mention regular file")

-- Test invalid mode rejection (directory)
result, err = writer:add("dir.txt", "content", {mode = 0040755})
assert(result == nil, "directory mode should be rejected")

-- Valid paths should still work
ok, err = writer:add("normal.txt", "content")
assert(ok, "normal path should work: " .. tostring(err))

ok, err = writer:add("subdir/file.txt", "content")
assert(ok, "subdir path should work: " .. tostring(err))

ok, err = writer:add("a/b/c/deep.txt", "content")
assert(ok, "deep path should work: " .. tostring(err))

-- Mode with just permissions (no file type) should default to regular file
ok, err = writer:add("perms.txt", "content", {mode = 0644})
assert(ok, "permission-only mode should work: " .. tostring(err))

writer:close()

--------------------------------------------------------------------------------
-- Test configurable max_file_size
--------------------------------------------------------------------------------

-- Test writer max_file_size enforcement
local limit_zip = tmpdir .. "/limit_test.zip"
writer, err = zip.open(limit_zip, "w", {max_file_size = 100})
assert(writer, "failed to create limited zip: " .. tostring(err))

ok, err = writer:add("small.txt", "hello")
assert(ok, "small content should work: " .. tostring(err))

result, err = writer:add("big.txt", string.rep("x", 200))
assert(result == nil, "content exceeding max_file_size should be rejected")
assert(err:match("max_file_size"), "error should mention max_file_size")

writer:close()

-- Test reader max_file_size enforcement
-- First create a zip with a larger file
local reader_limit_zip = tmpdir .. "/reader_limit_test.zip"
writer, err = zip.open(reader_limit_zip, "w")
assert(writer, "failed to create zip: " .. tostring(err))
ok, err = writer:add("big.txt", string.rep("y", 500))
assert(ok, "should add big file: " .. tostring(err))
writer:close()

-- Now try to read with a low limit
reader, err = zip.open(reader_limit_zip, {max_file_size = 100})
assert(reader, "failed to open zip with limit: " .. tostring(err))

result, err = reader:read("big.txt")
assert(result == nil, "reading file exceeding max_file_size should fail")
assert(err:match("too large"), "error should mention size")

reader:close()

-- Test invalid max_file_size values
ok, err = pcall(function()
  zip.open(tmpdir .. "/bad.zip", "w", {max_file_size = 0})
end)
assert(not ok, "max_file_size = 0 should error")

ok, err = pcall(function()
  zip.open(tmpdir .. "/bad.zip", "w", {max_file_size = -1})
end)
assert(not ok, "max_file_size = -1 should error")

ok, err = pcall(function()
  zip.open(limit_zip, {max_file_size = 0})
end)
assert(not ok, "max_file_size = 0 on open should error")

--------------------------------------------------------------------------------
-- Test append mode
--------------------------------------------------------------------------------

-- Create initial zip with write mode
local append_zip = tmpdir .. "/test_append.zip"
writer, err = zip.open(append_zip, "w")
assert(writer, "failed to create zip for append test: " .. tostring(err))

ok, err = writer:add("original.txt", "original content")
assert(ok, "failed to add original.txt: " .. tostring(err))

ok, err = writer:add("another.txt", "another file")
assert(ok, "failed to add another.txt: " .. tostring(err))

ok, err = writer:close()
assert(ok, "failed to close initial zip: " .. tostring(err))

-- Open in append mode and add new entries
local appender, err = zip.open(append_zip, "a")
assert(appender, "failed to open for append: " .. tostring(err))
assert(tostring(appender):match("zip.Appender"), "should be a zip.Appender")
assert(tostring(appender):match("0 pending"), "should have 0 pending entries")

ok, err = appender:add("appended.txt", "appended content")
assert(ok, "failed to add appended.txt: " .. tostring(err))
assert(tostring(appender):match("1 pending"), "should have 1 pending entry")

ok, err = appender:add("subdir/new.txt", "new file in subdir")
assert(ok, "failed to add subdir/new.txt: " .. tostring(err))

ok, err = appender:close()
assert(ok, "failed to close appender: " .. tostring(err))
assert(tostring(appender):match("closed"), "should be closed")

-- Verify all entries are present (original + appended)
reader, err = zip.open(append_zip)
assert(reader, "failed to open appended zip: " .. tostring(err))

entries = reader:list()
assert(#entries == 4, "should have 4 entries after append, got " .. #entries)

local entry_set = {}
for _, name in ipairs(entries) do
  entry_set[name] = true
end
assert(entry_set["original.txt"], "should have original.txt")
assert(entry_set["another.txt"], "should have another.txt")
assert(entry_set["appended.txt"], "should have appended.txt")
assert(entry_set["subdir/new.txt"], "should have subdir/new.txt")

-- Verify content is correct
local orig_content = reader:read("original.txt")
assert(orig_content == "original content", "original content should be preserved")

local appended_content = reader:read("appended.txt")
assert(appended_content == "appended content", "appended content should be correct")

reader:close()

--------------------------------------------------------------------------------
-- Test append mode security validations
--------------------------------------------------------------------------------

appender, err = zip.open(append_zip, "a")
assert(appender, "failed to open for security tests: " .. tostring(err))

-- Path traversal rejection
result, err = appender:add("../escape.txt", "malicious")
assert(result == nil, "path traversal should be rejected")
assert(err:match("unsafe path"), "error should mention unsafe path")

result, err = appender:add("/absolute/path.txt", "malicious")
assert(result == nil, "absolute path should be rejected")

result, err = appender:add("foo/../bar.txt", "malicious")
assert(result == nil, "embedded .. should be rejected")

-- Empty name rejection
result, err = appender:add("", "content")
assert(result == nil, "empty name should be rejected")
assert(err:match("empty"), "error should mention empty")

-- Null byte rejection
result, err = appender:add("foo\0bar.txt", "content")
assert(result == nil, "null byte should be rejected")
assert(err:match("null"), "error should mention null")

-- Duplicate entry rejection (against existing entries)
result, err = appender:add("original.txt", "duplicate")
assert(result == nil, "duplicate of existing entry should be rejected")
assert(err:match("duplicate"), "error should mention duplicate")

-- Duplicate entry rejection (against newly added entries)
ok, err = appender:add("unique_new.txt", "first")
assert(ok, "first add should succeed: " .. tostring(err))

result, err = appender:add("unique_new.txt", "second")
assert(result == nil, "duplicate of new entry should be rejected")
assert(err:match("duplicate"), "error should mention duplicate")

appender:close()

--------------------------------------------------------------------------------
-- Test append mode with max_file_size
--------------------------------------------------------------------------------

local limit_append_zip = tmpdir .. "/test_append_limit.zip"
writer, err = zip.open(limit_append_zip, "w")
assert(writer, "failed to create zip: " .. tostring(err))
writer:add("existing.txt", "existing")
writer:close()

appender, err = zip.open(limit_append_zip, "a", {max_file_size = 50})
assert(appender, "failed to open with limit: " .. tostring(err))

ok, err = appender:add("small.txt", "small content")
assert(ok, "small content should work: " .. tostring(err))

result, err = appender:add("big.txt", string.rep("x", 100))
assert(result == nil, "content exceeding limit should be rejected")
assert(err:match("max_file_size"), "error should mention max_file_size")

appender:close()

-- Test invalid max_file_size values for append mode
result, err = zip.open(limit_append_zip, "a", {max_file_size = 0})
assert(result == nil, "max_file_size = 0 should error")

result, err = zip.open(limit_append_zip, "a", {max_file_size = -1})
assert(result == nil, "max_file_size = -1 should error")

--------------------------------------------------------------------------------
-- Test append mode fd rejection
--------------------------------------------------------------------------------

local unix = require("cosmo.unix")
local fd_zip = tmpdir .. "/test_fd.zip"
writer = zip.open(fd_zip, "w")
writer:add("test.txt", "test")
writer:close()

local fd = unix.open(fd_zip, unix.O_RDONLY)
assert(fd, "failed to open fd")

result, err = zip.open(fd, "a")
assert(result == nil, "fd mode for append should be rejected")
assert(err:match("file descriptor"), "error should mention file descriptor")

unix.close(fd)

--------------------------------------------------------------------------------
-- Test append to non-existent file (should create new zip)
--------------------------------------------------------------------------------

local new_append_zip = tmpdir .. "/new_append.zip"
appender, err = zip.open(new_append_zip, "a")
assert(appender, "should be able to open non-existent file for append: " .. tostring(err))

ok, err = appender:add("first.txt", "first file")
assert(ok, "should add first entry: " .. tostring(err))

ok, err = appender:close()
assert(ok, "should close appender: " .. tostring(err))

reader = zip.open(new_append_zip)
assert(reader, "should be able to read new zip")
entries = reader:list()
assert(#entries == 1, "should have 1 entry")
assert(reader:read("first.txt") == "first file", "content should match")
reader:close()

--------------------------------------------------------------------------------
-- Test append with no entries (should be no-op)
--------------------------------------------------------------------------------

local noop_zip = tmpdir .. "/noop.zip"
writer = zip.open(noop_zip, "w")
writer:add("keep.txt", "keep this")
writer:close()

appender = zip.open(noop_zip, "a")
assert(appender, "should open for append")
-- Don't add anything
ok, err = appender:close()
assert(ok, "close with no entries should succeed: " .. tostring(err))

reader = zip.open(noop_zip)
entries = reader:list()
assert(#entries == 1, "should still have 1 entry")
assert(reader:read("keep.txt") == "keep this", "original content should be preserved")
reader:close()

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------

os.execute("rm -rf " .. tmpdir)

print("PASS")
