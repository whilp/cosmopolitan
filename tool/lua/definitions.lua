---@meta cosmo
error("Tried to evaluate definition file.")

--[[
────────────────────────────────────────────────────────────────────────────────
COSMO LUA

  Cosmopolitan Lua is a portable Lua distribution that runs on Linux,
  macOS, Windows, FreeBSD, OpenBSD, and NetBSD. It includes the cosmo
  module which provides encoding, hashing, compression, and networking.

────────────────────────────────────────────────────────────────────────────────
]]

---@class cosmo
---The cosmo module provides encoding, hashing, compression, networking,
---and other utilities for Lua programs.
cosmo = {}

--- Check if the calling script is being run directly (not require'd).
---
--- This function provides a Python-like `if __name__ == "__main__"` idiom
--- for Lua scripts. It returns true when the script is executed directly
--- from the command line, and false when the script is loaded via require().
---
--- Example usage:
---
---     local M = {}
---
---     function M.greet(name)
---       return "Hello, " .. name .. "!"
---     end
---
---     function M.main(args)
---       if not args[1] then
---         io.stderr:write("usage: greet.lua <name>\n")
---         os.exit(1)
---       end
---       print(M.greet(args[1]))
---     end
---
---     if cosmo.is_main() then
---       M.main(arg)
---     end
---
---     return M
---
--- This pattern allows a module to be both:
--- 1. Imported by other scripts: `local greet = require("greet")`
--- 2. Run directly: `lua greet.lua World`
---
---@return boolean is_main true if script is run directly, false if require'd
---@nodiscard
function cosmo.is_main() end
