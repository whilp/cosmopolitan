-- Per-file C line coverage floor for the Lua binding sources,
-- measured by tool/lua/line_coverage.lua from gcov data in
-- MODE=cov. Rewrite with LINE_COVERAGE_BASELINE=1; never lower a
-- covered count by hand, except lfetch.c below.
return {
  ["third_party/lua/cosmo/lunix.c"] = { covered = 1441, total = 2553 },
  ["tool/lua/lcosmo.c"] = { covered = 140, total = 167 },
  ["tool/net/largon2.c"] = { covered = 86, total = 90 },
  ["tool/net/lcov.c"] = { covered = 92, total = 95 },
  -- lfetch.c's covered count varies by a few lines across otherwise
  -- identical serial runs (586-592 observed), most likely from
  -- timing-sensitive branches in the proxy/timeout tests exercising
  -- cosmo.Fetch/cosmo.FetchStream. Floored below the observed low end
  -- so run-to-run variance doesn't fail an unrelated PR; a real
  -- regression still has to drop coverage well past this margin.
  ["tool/net/lfetch.c"] = { covered = 585, total = 873 },
  ["tool/net/lfuncs.c"] = { covered = 612, total = 736 },
  ["tool/net/lgetopt.c"] = { covered = 130, total = 142 },
  ["tool/net/ljson.c"] = { covered = 113, total = 367 },
  ["tool/net/llua.c"] = { covered = 374, total = 413 },
  ["tool/net/lpath.c"] = { covered = 56, total = 73 },
  ["tool/net/lre.c"] = { covered = 117, total = 127 },
  ["tool/net/lsqlite3.c"] = { covered = 571, total = 1136 },
  ["tool/net/lzip.c"] = { covered = 983, total = 1268 },
}
