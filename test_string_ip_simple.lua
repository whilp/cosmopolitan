#!/usr/bin/env lua
-- Simple test for string IP bind functionality

print("Testing string IP in unix.bind()...")

-- Test 1: Basic string IP binding
print("\n1. Creating socket and binding to '127.0.0.1'...")
local server = assert(unix.socket())
local ok, err = unix.bind(server, '127.0.0.1', 0)
if ok then
    print("  ✓ Successfully bound to string IP '127.0.0.1'")
    local ip, port = assert(unix.getsockname(server))
    print("  ✓ Got IP:", string.format("0x%08X", ip), "Port:", port)
    assert(ip == 0x7F000001, "IP should be 0x7F000001")
else
    print("  ✗ FAILED:", err)
    os.exit(1)
end
unix.close(server)

-- Test 2: Integer IP (backward compatibility)
print("\n2. Testing backward compatibility with integer IP...")
server = assert(unix.socket())
ok, err = unix.bind(server, 0x7F000001, 0)
if ok then
    print("  ✓ Integer IP still works")
else
    print("  ✗ FAILED:", err)
    os.exit(1)
end
unix.close(server)

-- Test 3: ParseIp still works
print("\n3. Testing ParseIp() backward compatibility...")
server = assert(unix.socket())
ok, err = unix.bind(server, ParseIp('192.168.1.1'), 0)
if ok then
    print("  ✓ ParseIp() still works")
    local ip, port = assert(unix.getsockname(server))
    print("  ✓ Got IP:", string.format("0x%08X", ip))
    assert(ip == 0xC0A80101, "IP should be 0xC0A80101")
else
    print("  ✗ FAILED:", err)
    os.exit(1)
end
unix.close(server)

print("\n✓ All tests passed!")
