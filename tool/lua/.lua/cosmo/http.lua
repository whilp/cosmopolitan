---@meta cosmo.http

---HTTP parsing and formatting module for Lua.
---
---This module provides low-level HTTP primitives for building servers and clients.
---It wraps Cosmopolitan's battle-tested HTTP parser and provides simple formatting
---functions. All operations are stateless with no global state.
---
---@class cosmo.http
local http = {}

---Parsed HTTP request
---@class HttpRequest
---@field method string HTTP method (e.g., "GET", "POST", "PUT", "DELETE")
---@field uri string Request URI (e.g., "/path?query=value#fragment")
---@field version integer HTTP version (11 for HTTP/1.1, 10 for HTTP/1.0, 9 for HTTP/0.9)
---@field headers table<string, string> Request headers (normalized names)
---@field body? string Request body (may be nil for GET requests)
---@field header_size integer Size of headers in bytes (useful for streaming)

---Parsed HTTP response
---@class HttpResponse
---@field status integer HTTP status code (e.g., 200, 404, 500)
---@field message string Status message (e.g., "OK", "Not Found", "Internal Server Error")
---@field version integer HTTP version (11 for HTTP/1.1, 10 for HTTP/1.0)
---@field headers table<string, string> Response headers (normalized names)
---@field body? string Response body (may be nil for 204 No Content)
---@field header_size integer Size of headers in bytes (useful for streaming)

---HTTP response template for formatting
---@class HttpResponseTemplate
---@field status? integer HTTP status code (default: 200)
---@field headers? table<string, string> Response headers
---@field body? string Response body

---HTTP request template for formatting
---@class HttpRequestTemplate
---@field method? string HTTP method (default: "GET")
---@field uri string Request URI (required)
---@field headers? table<string, string> Request headers
---@field body? string Request body

---Parse an HTTP request from a raw string.
---
---The input buffer must contain at least the complete headers. Returns nil
---and an error message if parsing fails.
---
---Example:
---```lua
---local http = require('cosmo').http
---local raw = "GET /hello HTTP/1.1\r\nHost: localhost:8080\r\n\r\n"
---local req, err = http.parse(raw)
---if req then
---    print(req.method)  -- "GET"
---    print(req.uri)     -- "/hello"
---    print(req.headers.Host)  -- "localhost:8080"
---end
---```
---
---@param raw_request string Raw HTTP request string
---@return HttpRequest? request Parsed request, or nil on error
---@return string? error Error message if parsing failed
function http.parse(raw_request) end

---Parse an HTTP response from a raw string.
---
---The input buffer must contain at least the complete headers. Returns nil
---and an error message if parsing fails.
---
---Example:
---```lua
---local http = require('cosmo').http
---local raw = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n<h1>Hello</h1>"
---local resp, err = http.parse_response(raw)
---if resp then
---    print(resp.status)   -- 200
---    print(resp.message)  -- "OK"
---    print(resp.body)     -- "<h1>Hello</h1>"
---end
---```
---
---@param raw_response string Raw HTTP response string
---@return HttpResponse? response Parsed response, or nil on error
---@return string? error Error message if parsing failed
function http.parse_response(raw_response) end

---Format an HTTP response from a table.
---
---Creates a properly formatted HTTP/1.1 response string from a response
---template. All headers are automatically formatted with proper CRLF endings.
---
---Example:
---```lua
---local http = require('cosmo').http
---local response = http.format_response({
---    status = 200,
---    headers = {
---        ["Content-Type"] = "text/html; charset=utf-8",
---        ["Server"] = "my-server/1.0",
---    },
---    body = "<h1>Hello World</h1>"
---})
---print(response)
---```
---
---@param response_template HttpResponseTemplate Response configuration
---@return string formatted_response HTTP response string ready to send
function http.format_response(response_template) end

---Format an HTTP request from a table.
---
---Creates a properly formatted HTTP/1.1 request string from a request
---template. Useful for building HTTP clients.
---
---Example:
---```lua
---local http = require('cosmo').http
---local request = http.format_request({
---    method = "POST",
---    uri = "/api/data",
---    headers = {
---        ["Host"] = "example.com",
---        ["Content-Type"] = "application/json",
---    },
---    body = '{"key": "value"}'
---})
---```
---
---@param request_template HttpRequestTemplate Request configuration
---@return string formatted_request HTTP request string ready to send
function http.format_request(request_template) end

---Get the standard reason phrase for an HTTP status code.
---
---Returns the standard HTTP reason phrase for a given status code.
---For example, 200 returns "OK", 404 returns "Not Found", etc.
---
---Example:
---```lua
---local http = require('cosmo').http
---print(http.reason(200))  -- "OK"
---print(http.reason(404))  -- "Not Found"
---print(http.reason(500))  -- "Internal Server Error"
---```
---
---@param status_code integer HTTP status code (100-599)
---@return string reason Standard reason phrase
function http.reason(status_code) end

---Get the header name for a header constant.
---
---Returns the standard header name for a header constant from the
---kHttp* constants (e.g., http.CONTENT_TYPE -> "Content-Type").
---
---Example:
---```lua
---local http = require('cosmo').http
---print(http.header_name(http.CONTENT_TYPE))  -- "Content-Type"
---print(http.header_name(http.HOST))          -- "Host"
---```
---
---@param header_constant integer Header constant (from http.HOST, http.CONTENT_TYPE, etc.)
---@return string? header_name Header name, or nil if invalid constant
function http.header_name(header_constant) end

---HTTP method constants (as 64-bit integers)
---@type integer
http.GET = nil

---@type integer
http.POST = nil

---@type integer
http.PUT = nil

---@type integer
http.DELETE = nil

---@type integer
http.HEAD = nil

---@type integer
http.OPTIONS = nil

---@type integer
http.CONNECT = nil

---@type integer
http.TRACE = nil

---Common HTTP status code constants

---200 OK
---@type integer
http.OK = 200

---201 Created
---@type integer
http.CREATED = 201

---204 No Content
---@type integer
http.NO_CONTENT = 204

---301 Moved Permanently
---@type integer
http.MOVED_PERMANENTLY = 301

---302 Found
---@type integer
http.FOUND = 302

---304 Not Modified
---@type integer
http.NOT_MODIFIED = 304

---400 Bad Request
---@type integer
http.BAD_REQUEST = 400

---401 Unauthorized
---@type integer
http.UNAUTHORIZED = 401

---403 Forbidden
---@type integer
http.FORBIDDEN = 403

---404 Not Found
---@type integer
http.NOT_FOUND = 404

---405 Method Not Allowed
---@type integer
http.METHOD_NOT_ALLOWED = 405

---500 Internal Server Error
---@type integer
http.INTERNAL_SERVER_ERROR = 500

---502 Bad Gateway
---@type integer
http.BAD_GATEWAY = 502

---503 Service Unavailable
---@type integer
http.SERVICE_UNAVAILABLE = 503

---Header name constants (for efficient header access)

---Host header constant
---@type integer
http.HOST = nil

---Content-Type header constant
---@type integer
http.CONTENT_TYPE = nil

---Content-Length header constant
---@type integer
http.CONTENT_LENGTH = nil

---Connection header constant
---@type integer
http.CONNECTION = nil

---Accept header constant
---@type integer
http.ACCEPT = nil

---User-Agent header constant
---@type integer
http.USER_AGENT = nil

return http
