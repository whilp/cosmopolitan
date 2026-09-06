-- Per-file C line coverage floor for the Lua binding sources,
-- measured by tool/lua/line_coverage.lua from gcov data in
-- MODE=cov. Rewrite with LINE_COVERAGE_BASELINE=1; never lower a
-- covered count by hand, except lfetch.c below.
return {
  ["third_party/lua/cosmo/lunix.c"] = { covered = 1441, total = 2553 },
  ["tool/lua/lcosmo.c"] = { covered = 140, total = 167 },
  ["tool/net/largon2.c"] = { covered = 86, total = 90 },
  ["tool/net/lcov.c"] = { covered = 92, total = 95 },
  -- lfetch.c's covered count is a fixed base plus up to 16 lines split
  -- across four branches that fire on some serial runs and not others:
  -- TlsRecvImpl's socket-read-error path (a TLS read failing with a
  -- non-EAGAIN errno), FetchStreamRead's TLS body-read path (reached
  -- only when the streaming test's fetch of a real external HTTPS
  -- endpoint succeeds, so it tracks that run's network conditions),
  -- and two code paths -- one serving buffered header overshoot, one
  -- reading fresh from the socket -- for a chunked response whose
  -- final chunk and its zero-length terminator happen to arrive in
  -- the same read rather than two, which tracks how the test server's
  -- writes land relative to the client's reads. Each of the four is
  -- independent and all-or-nothing per run (every occurrence in a run
  -- takes the same side), so the covered count is the fixed base plus
  -- whichever of the four happened to fire, and the floor below is
  -- that base with none of them firing -- the true minimum, not a
  -- margin below an observed sample -- so no combination of these
  -- four can ever fail an unrelated PR; a real regression still has
  -- to drop coverage below the base itself.
  ["tool/net/lfetch.c"] = { covered = 579, total = 873 },
  ["tool/net/lfuncs.c"] = { covered = 612, total = 736 },
  ["tool/net/lgetopt.c"] = { covered = 130, total = 142 },
  ["tool/net/ljson.c"] = { covered = 113, total = 367 },
  ["tool/net/llua.c"] = { covered = 374, total = 413 },
  ["tool/net/lpath.c"] = { covered = 56, total = 73 },
  ["tool/net/lre.c"] = { covered = 117, total = 127 },
  ["tool/net/lsqlite3.c"] = { covered = 571, total = 1136 },
  ["tool/net/lzip.c"] = { covered = 983, total = 1268 },
}
