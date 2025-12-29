---@meta
-- Cosmo Lua documentation overrides
-- These supplement/override the base definitions.lua from redbean

--- Sends an HTTP/HTTPS request to the specified URL.
---
--- Cosmo enhancements over base redbean Fetch:
---
--- - `proxy` (string): HTTP proxy URL, e.g. "http://proxy:8080"
---   Supports authentication: "http://user:pass@proxy:8080"
---   Falls back to http_proxy/HTTP_PROXY environment variables.
---
--- - `maxresponse` (default: 104857600): Maximum response body size in bytes.
---   Prevents memory exhaustion from large responses.
---
--- - `resettls` (default: true): Reset TLS state after fork.
---   Ensures child processes get fresh entropy.
---
--- Base options (see redbean docs):
--- - `method`, `body`, `headers`, `followredirect`, `maxredirects`, `keepalive`
---
---@param url string
---@param body? string|table
---@return integer status
---@return table headers
---@return string body
---@overload fun(url: string, body?: string|table): nil, error: string
function Fetch(url, body) end

--- Alias with cosmo prefix
---@param url string
---@param body? string|table
---@return integer status
---@return table headers
---@return string body
---@overload fun(url: string, body?: string|table): nil, error: string
function cosmo.Fetch(url, body) end
