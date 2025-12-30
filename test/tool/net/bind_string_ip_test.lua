-- Copyright 2025 Justine Alexandra Roberts Tunney
--
-- Permission to use, copy, modify, and/or distribute this software for
-- any purpose with or without fee is hereby granted, provided that the
-- above copyright notice and this permission notice appear in all copies.
--
-- THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL
-- WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED
-- WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE
-- AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL
-- DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR
-- PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
-- TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
-- PERFORMANCE OF THIS SOFTWARE.

-- Test unix.bind() and unix.connect() with string IP addresses

tmpdir = "%s/o/tmp/bind_string_ip_test.%d" % {os.getenv('TMPDIR'), unix.getpid()}
unixpath = tmpdir .. "/socket"

function TestStringIpBind()
    -- Test 1: Bind with string IP (new feature)
    local server = assert(unix.socket())
    assert(unix.bind(server, '127.0.0.1', 0))  -- bind to loopback with ephemeral port
    assert(unix.listen(server))

    -- Get the port that was assigned
    local ip, port = assert(unix.getsockname(server))
    assert(ip == 0x7F000001)  -- 127.0.0.1 in host byte order
    assert(port > 0)  -- should have assigned an ephemeral port

    -- Test 2: Connect with string IP (new feature)
    local client = assert(unix.socket())
    assert(unix.connect(client, '127.0.0.1', port))

    -- Accept the connection
    local accepted = assert(unix.accept(server))

    -- Clean up
    assert(unix.close(accepted))
    assert(unix.close(client))
    assert(unix.close(server))

    print("✓ String IP bind and connect work")
end

function TestIntegerIpBackwardCompat()
    -- Test 3: Ensure integer IPs still work (backward compatibility)
    local server = assert(unix.socket())
    assert(unix.bind(server, 0x7F000001, 0))  -- 127.0.0.1 as integer
    assert(unix.listen(server))

    local ip, port = assert(unix.getsockname(server))
    assert(ip == 0x7F000001)

    local client = assert(unix.socket())
    assert(unix.connect(client, 0x7F000001, port))  -- connect with integer IP

    local accepted = assert(unix.accept(server))

    assert(unix.close(accepted))
    assert(unix.close(client))
    assert(unix.close(server))

    print("✓ Integer IP backward compatibility works")
end

function TestParseIpStillWorks()
    -- Test 4: Ensure ParseIp() still works
    local server = assert(unix.socket())
    assert(unix.bind(server, ParseIp('127.0.0.1'), 0))
    assert(unix.listen(server))

    local ip, port = assert(unix.getsockname(server))
    assert(ip == 0x7F000001)

    assert(unix.close(server))

    print("✓ ParseIp() backward compatibility works")
end

function TestUnixSocketPath()
    -- Test 5: Ensure Unix socket paths still work
    local server = assert(unix.socket(unix.AF_UNIX, unix.SOCK_STREAM))
    assert(unix.bind(server, unixpath))
    assert(unix.listen(server))

    local client = assert(unix.socket(unix.AF_UNIX, unix.SOCK_STREAM))
    assert(unix.connect(client, unixpath))

    local accepted = assert(unix.accept(server))

    assert(unix.close(accepted))
    assert(unix.close(client))
    assert(unix.close(server))
    assert(unix.unlink(unixpath))

    print("✓ Unix socket paths still work")
end

function TestVariousIpFormats()
    -- Test 6: Test various IP string formats
    local test_ips = {
        {'0.0.0.0', 0x00000000},
        {'127.0.0.1', 0x7F000001},
        {'192.168.1.1', 0xC0A80101},
        {'255.255.255.255', 0xFFFFFFFF},
        {'10.20.30.40', 0x0A141E28},
    }

    for _, test in ipairs(test_ips) do
        local ip_str, expected = test[1], test[2]
        local server = assert(unix.socket())
        assert(unix.bind(server, ip_str, 0))

        local ip, port = assert(unix.getsockname(server))
        assert(ip == expected, "IP mismatch for %s: got 0x%08X, expected 0x%08X" % {ip_str, ip, expected})

        assert(unix.close(server))
    end

    print("✓ Various IP string formats work correctly")
end

function TestDefaultPort()
    -- Test 7: Test that default port (0) works with string IPs
    local server = assert(unix.socket())
    assert(unix.bind(server, '127.0.0.1'))  -- no port specified, should default to 0

    local ip, port = assert(unix.getsockname(server))
    assert(ip == 0x7F000001)
    assert(port > 0)  -- kernel should assign ephemeral port

    assert(unix.close(server))

    print("✓ Default port (0) works with string IPs")
end

function main()
    assert(unix.makedirs(tmpdir))

    local ok, err = pcall(function()
        TestStringIpBind()
        TestIntegerIpBackwardCompat()
        TestParseIpStillWorks()
        TestUnixSocketPath()
        TestVariousIpFormats()
        TestDefaultPort()
    end)

    assert(unix.rmrf(tmpdir))

    if not ok then
        print("ERROR: " .. tostring(err))
        os.exit(1)
    end

    print("\nAll tests passed! ✓")
end

main()
