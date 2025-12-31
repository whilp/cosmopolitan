#!/usr/bin/env lua
-- Test script for new ISO 8601 Lua bindings

print("Testing new ISO 8601 and time conversion functions\n")

-- Test 1: Iso8601 - Fast ISO 8601 formatting
print("1. cosmo.Iso8601(timestamp, localtime)")
local ts = 1704067200  -- 2024-01-01 00:00:00 UTC
print("   UTC:   " .. cosmo.Iso8601(ts, false))
print("   Local: " .. cosmo.Iso8601(ts, true))
print()

-- Test 2: Iso8601us - ISO 8601 with microsecond precision
print("2. cosmo.Iso8601us(timestamp, nanoseconds, localtime)")
print("   UTC:   " .. cosmo.Iso8601us(ts, 123456000, false))
print("   Local: " .. cosmo.Iso8601us(ts, 123456000, true))
print()

-- Test 3: Parse an ISO 8601 date with Strptime
print("3. cosmo.Strptime(datestring, format)")
local date_str = "2024-12-29T15:30:45"
local parsed = cosmo.Strptime(date_str, "%Y-%m-%dT%H:%M:%S")
if parsed then
  print("   Parsed: " .. date_str)
  print("   Year:  " .. parsed.year)
  print("   Month: " .. parsed.month)
  print("   Day:   " .. parsed.day)
  print("   Hour:  " .. parsed.hour)
  print("   Min:   " .. parsed.min)
  print("   Sec:   " .. parsed.sec)
else
  print("   Parse failed!")
end
print()

-- Test 4: Timegm - Convert parsed date to Unix timestamp (UTC)
print("4. cosmo.Timegm(date_table)")
local timestamp = cosmo.Timegm(parsed)
if timestamp then
  print("   Unix timestamp (UTC): " .. timestamp)
  print("   Formatted back:       " .. cosmo.Iso8601(timestamp, false))
else
  print("   Conversion failed!")
end
print()

-- Test 5: Mktime - Convert parsed date to Unix timestamp (local time)
print("5. cosmo.Mktime(date_table)")
local timestamp_local = cosmo.Mktime(parsed)
if timestamp_local then
  print("   Unix timestamp (local): " .. timestamp_local)
  print("   Formatted back:         " .. cosmo.Iso8601(timestamp_local, true))
else
  print("   Conversion failed!")
end
print()

-- Test 6: Round-trip test
print("6. Round-trip test: Parse -> Convert -> Format")
local original = "2025-06-15T10:30:00"
local parsed2 = cosmo.Strptime(original, "%Y-%m-%dT%H:%M:%S")
local ts2 = cosmo.Timegm(parsed2)
local formatted = cosmo.Iso8601(ts2, false)
print("   Original:  " .. original)
print("   Formatted: " .. formatted)
print("   Match:     " .. (original == formatted and "YES" or "NO"))
print()

-- Test 7: Performance comparison
print("7. Performance comparison: Strftime vs Iso8601")
local iterations = 100000
local t = os.time()

local start = cosmo.GetTime()
for i = 1, iterations do
  local _ = cosmo.Strftime("%Y-%m-%dT%H:%M:%S", t, false)
end
local strftime_time = cosmo.GetTime() - start

start = cosmo.GetTime()
for i = 1, iterations do
  local _ = cosmo.Iso8601(t, false)
end
local iso8601_time = cosmo.GetTime() - start

print(string.format("   Strftime: %.3f seconds", strftime_time))
print(string.format("   Iso8601:  %.3f seconds", iso8601_time))
print(string.format("   Speedup:  %.1fx faster", strftime_time / iso8601_time))
