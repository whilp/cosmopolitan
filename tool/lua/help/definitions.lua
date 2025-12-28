---@meta
error("Tried to evaluate definition file.")

--[[
COSMO LUA

Cosmo Lua is a standalone Lua 5.4 interpreter with batteries included.
It provides the cosmo module with utilities for encoding, hashing,
compression, networking, and system programming.

MODULES

  cosmo         - Main module with encoding, hashing, and utilities
  cosmo.unix    - POSIX system calls
  cosmo.path    - Path manipulation utilities
  cosmo.re      - Regular expression support
  cosmo.sqlite3 - SQLite database bindings
  cosmo.argon2  - Password hashing

USAGE

  local cosmo = require("cosmo")
  local encoded = cosmo.EncodeBase64("hello")
  local hash = cosmo.Sha256("data")

]]

-- ENCODING FUNCTIONS

--- Encodes binary data as base32.
---@param data string binary data to encode
---@return string base32 encoded string
function cosmo.EncodeBase32(data) end

--- Decodes base32 string to binary data.
---@param encoded string base32 encoded string
---@return string decoded binary data
function cosmo.DecodeBase32(encoded) end

--- Encodes binary data as base64.
---@param data string binary data to encode
---@return string base64 encoded string
function cosmo.EncodeBase64(data) end

--- Decodes base64 string to binary data.
---@param encoded string base64 encoded string
---@return string decoded binary data
function cosmo.DecodeBase64(encoded) end

--- Encodes binary data as hexadecimal.
---@param data string binary data to encode
---@return string hex encoded string (lowercase)
function cosmo.EncodeHex(data) end

--- Decodes hexadecimal string to binary data.
---@param encoded string hex encoded string
---@return string decoded binary data
function cosmo.DecodeHex(encoded) end

--- Encodes a Lua value as JSON.
---@param value any Lua value to encode (table, string, number, boolean, nil)
---@param options? {maxdepth: integer?, sorted: boolean?, pretty: boolean?, indent: string?} encoding options
---@return string json JSON encoded string
---@overload fun(value: any, options?: table): nil, error: string
function cosmo.EncodeJson(value, options) end

--- Decodes a JSON string to a Lua value.
---@param json string JSON string to decode
---@return any value decoded Lua value
---@overload fun(json: string): nil, error: string
function cosmo.DecodeJson(json) end

--- Encodes a Lua value as Lua source code.
--- Useful for serialization and pretty-printing tables.
---@param value any Lua value to encode
---@param options? {maxdepth: integer?, sorted: boolean?, pretty: boolean?, indent: string?} encoding options
---@return string lua Lua source code representation
function cosmo.EncodeLua(value, options) end

--- Encodes a string for use in URLs.
---@param str string string to encode
---@return string encoded URL-encoded string
function cosmo.EncodeUrl(str) end

--- Converts UTF-8 to ISO-8859-1 (Latin-1).
---@param utf8 string UTF-8 encoded string
---@param flags integer encoding flags
---@return string latin1 ISO-8859-1 encoded string
function cosmo.EncodeLatin1(utf8, flags) end

--- Converts ISO-8859-1 (Latin-1) to UTF-8.
---@param latin1 string ISO-8859-1 encoded string
---@return string utf8 UTF-8 encoded string
function cosmo.DecodeLatin1(latin1) end

-- ESCAPE FUNCTIONS

--- Escapes a string for safe inclusion in HTML.
--- Converts <, >, &, ", and ' to their HTML entities.
---@param str string string to escape
---@return string escaped HTML-safe string
function cosmo.EscapeHtml(str) end

--- Escapes URL path component.
---@param str string string to escape
---@return string escaped escaped path
function cosmo.EscapePath(str) end

--- Escapes URL path segment (no slashes allowed).
---@param str string string to escape
---@return string escaped escaped segment
function cosmo.EscapeSegment(str) end

--- Escapes URL query parameter name or value.
---@param str string string to escape
---@return string escaped escaped parameter
function cosmo.EscapeParam(str) end

--- Escapes URL fragment.
---@param str string string to escape
---@return string escaped escaped fragment
function cosmo.EscapeFragment(str) end

--- Escapes URL host component.
---@param str string string to escape
---@return string escaped escaped host
function cosmo.EscapeHost(str) end

--- Escapes URL username.
---@param str string string to escape
---@return string escaped escaped username
function cosmo.EscapeUser(str) end

--- Escapes URL password.
---@param str string string to escape
---@return string escaped escaped password
function cosmo.EscapePass(str) end

--- Escapes a JavaScript/JSON string literal.
--- The caller must add surrounding quotes.
---@param str string string to escape
---@return string escaped escaped string
function cosmo.EscapeLiteral(str) end

--- Escapes an IP address for use in URLs.
---@param ip integer IP address as 32-bit integer
---@return string escaped escaped IP string
function cosmo.EscapeIp(ip) end

-- HASH FUNCTIONS

--- Computes MD5 hash.
---@param data string data to hash
---@return string hash 16-byte MD5 hash
function cosmo.Md5(data) end

--- Computes SHA-1 hash.
---@param data string data to hash
---@return string hash 20-byte SHA-1 hash
function cosmo.Sha1(data) end

--- Computes SHA-224 hash.
---@param data string data to hash
---@return string hash 28-byte SHA-224 hash
function cosmo.Sha224(data) end

--- Computes SHA-256 hash.
---@param data string data to hash
---@return string hash 32-byte SHA-256 hash
function cosmo.Sha256(data) end

--- Computes SHA-384 hash.
---@param data string data to hash
---@return string hash 48-byte SHA-384 hash
function cosmo.Sha384(data) end

--- Computes SHA-512 hash.
---@param data string data to hash
---@return string hash 64-byte SHA-512 hash
function cosmo.Sha512(data) end

--- Computes CRC32 checksum.
---@param data string data to checksum
---@return integer crc32 CRC32 checksum
function cosmo.Crc32(data) end

--- Computes CRC32C (Castagnoli) checksum.
--- This is the hardware-accelerated variant used by iSCSI, SCTP, etc.
---@param data string data to checksum
---@return integer crc32c CRC32C checksum
function cosmo.Crc32c(data) end

--- Computes HighwayHash64.
--- A fast, keyed hash function suitable for hash tables.
---@param data string data to hash
---@param key? string optional 32-byte key
---@return integer hash 64-bit hash value
function cosmo.HighwayHash64(data, key) end

--- Computes a cryptographic hash using the specified algorithm.
---@param algorithm string hash algorithm name (e.g., "sha256", "sha512")
---@param data string data to hash
---@return string hash computed hash
function cosmo.GetCryptoHash(algorithm, data) end

--- Measures the entropy of data in bits per byte.
---@param data string data to measure
---@return number entropy entropy in bits per byte (0-8)
function cosmo.MeasureEntropy(data) end

-- COMPRESSION FUNCTIONS

--- Compresses data using zlib.
---@param data string data to compress
---@param level? integer compression level 0-9 (default 6)
---@return string compressed compressed data
function cosmo.Compress(data, level) end

--- Decompresses zlib-compressed data.
---@param data string compressed data
---@return string decompressed decompressed data
function cosmo.Uncompress(data) end

--- Compresses data using raw DEFLATE (no zlib header).
---@param data string data to compress
---@param level? integer compression level 0-9 (default 6)
---@return string deflated compressed data
function cosmo.Deflate(data, level) end

--- Decompresses raw DEFLATE data.
---@param data string deflated data
---@return string inflated decompressed data
function cosmo.Inflate(data) end

-- NETWORKING FUNCTIONS

--- Performs an HTTP/HTTPS request.
---
--- If only URL is provided, performs a GET request.
--- If body is a string, performs a POST request.
--- If body is a table, uses the specified options.
---
--- Options table fields:
---   method        (string)  HTTP method (default "GET")
---   body          (string)  Request body
---   headers       (table)   Custom headers {name=value, ...}
---   followredirect (boolean) Follow redirects (default true)
---   maxredirects  (integer) Maximum redirects (default 5)
---   maxresponse   (integer) Maximum response size in bytes (default 100MB)
---   keepalive     (boolean|table) Enable connection reuse
---   proxy         (string)  HTTP proxy URL (e.g., "http://proxy:8080")
---   resettls      (boolean) Reset TLS state after fork (default true)
---
--- Proxy authentication is supported via URL credentials:
---   proxy = "http://user:password@proxy:8080"
---
--- Environment variables http_proxy/HTTP_PROXY are used if no proxy option.
---
---@param url string URL to fetch
---@param body? string|table request body or options table
---@return integer status HTTP status code
---@return table headers response headers
---@return string body response body
---@overload fun(url: string, body?: string|table): nil, error: string
function cosmo.Fetch(url, body) end

--- Parses a URL into its components.
---@param url string URL to parse
---@return table url parsed URL with fields: scheme, host, port, path, params, fragment, user, pass
function cosmo.ParseUrl(url) end

--- Parses a host:port string.
---@param hostport string host:port string
---@return string host hostname
---@return integer port port number
function cosmo.ParseHost(hostport) end

--- Parses an IP address string to a 32-bit integer.
---@param ip string IP address string (e.g., "192.168.1.1")
---@return integer ip 32-bit IP address
function cosmo.ParseIp(ip) end

--- Formats a 32-bit IP address as a string.
---@param ip integer 32-bit IP address
---@return string ip IP address string (e.g., "1.2.3.4")
function cosmo.FormatIp(ip) end

--- Resolves a hostname to an IP address.
---@param hostname string hostname to resolve
---@return integer ip 32-bit IP address
function cosmo.ResolveIp(hostname) end

--- Categorizes an IP address.
--- Returns a string like "PRIVATE", "PUBLIC", "LOOPBACK", etc.
---@param ip integer 32-bit IP address
---@return string category IP category
function cosmo.CategorizeIp(ip) end

--- Checks if an IP address is public.
---@param ip integer 32-bit IP address
---@return boolean public true if public
function cosmo.IsPublicIp(ip) end

--- Checks if an IP address is private (RFC 1918).
---@param ip integer 32-bit IP address
---@return boolean private true if private
function cosmo.IsPrivateIp(ip) end

--- Checks if an IP address is loopback (127.0.0.0/8).
---@param ip integer 32-bit IP address
---@return boolean loopback true if loopback
function cosmo.IsLoopbackIp(ip) end

--- Checks if a host string is acceptable.
---@param host string hostname to check
---@return boolean valid true if acceptable
function cosmo.IsAcceptableHost(host) end

--- Checks if a path string is acceptable.
---@param path string path to check
---@return boolean valid true if acceptable
function cosmo.IsAcceptablePath(path) end

--- Checks if a port string is acceptable.
---@param port string port to check
---@return boolean valid true if acceptable
function cosmo.IsAcceptablePort(port) end

--- Checks if a path is reasonable (not malicious).
---@param path string path to check
---@return boolean valid true if reasonable
function cosmo.IsReasonablePath(path) end

--- Parses URL query parameters.
---@param query string query string (without leading ?)
---@return table params key-value table of parameters
function cosmo.ParseParams(query) end

--- Parses HTTP date/time string.
---@param datetime string HTTP datetime string (RFC 1123)
---@return integer timestamp UNIX timestamp
function cosmo.ParseHttpDateTime(datetime) end

--- Formats a UNIX timestamp as HTTP date/time string.
---@param timestamp integer UNIX timestamp
---@return string datetime RFC 1123 datetime string
function cosmo.FormatHttpDateTime(timestamp) end

--- Gets the HTTP reason phrase for a status code.
---@param status integer HTTP status code
---@return string reason reason phrase (e.g., "OK", "Not Found")
function cosmo.GetHttpReason(status) end

--- Checks if an HTTP token is valid.
---@param token string token to check
---@return boolean valid true if valid
function cosmo.IsValidHttpToken(token) end

--- Checks if an HTTP header is repeatable.
---@param header string header name
---@return boolean repeatable true if header can appear multiple times
function cosmo.IsHeaderRepeatable(header) end

-- CRYPTOGRAPHY FUNCTIONS

--- Performs X25519 elliptic curve Diffie-Hellman.
---@param secret string 32-byte private key
---@param point? string 32-byte public key (default: base point)
---@return string result 32-byte shared secret or public key
function cosmo.Curve25519(secret, point) end

--- Generates cryptographically secure random bytes.
---@param count integer number of bytes to generate
---@return string bytes random bytes
function cosmo.GetRandomBytes(count) end

--- Generates a random 64-bit integer.
---@return integer rand random 64-bit integer
function cosmo.Rand64() end

--- Generates a random 64-bit integer using the Lemur64 PRNG.
---@return integer rand random 64-bit integer
function cosmo.Lemur64() end

--- Generates a UUID v4 (random).
---@return string uuid UUID string (36 characters)
function cosmo.UuidV4() end

--- Generates a UUID v7 (timestamp-based, sortable).
---@return string uuid UUID string (36 characters)
function cosmo.UuidV7() end

-- FILE I/O FUNCTIONS

--- Reads entire file contents.
---@param path string file path
---@return string contents file contents
---@overload fun(path: string): nil, error: string
function cosmo.Slurp(path) end

--- Writes data to a file.
---@param path string file path
---@param data string data to write
---@param mode? integer file mode (default 0644)
---@return boolean success true on success
---@overload fun(path: string, data: string, mode?: integer): nil, error: string
function cosmo.Barf(path, data, mode) end

-- SYSTEM FUNCTIONS

--- Returns current time in seconds with microsecond precision.
---@return number time current time
function cosmo.GetTime() end

--- Sleeps for the specified duration.
---@param seconds number time to sleep in seconds
function cosmo.Sleep(seconds) end

--- Returns the number of CPU cores.
---@return integer count number of CPUs
function cosmo.GetCpuCount() end

--- Returns the current CPU core number.
---@return integer core current CPU core
function cosmo.GetCpuCore() end

--- Returns the current NUMA node.
---@return integer node current NUMA node
function cosmo.GetCpuNode() end

--- Returns the host operating system name.
---@return string os OS name (e.g., "LINUX", "WINDOWS", "MACOS")
function cosmo.GetHostOs() end

--- Returns the host instruction set architecture.
---@return string isa ISA name (e.g., "X86_64", "AARCH64")
function cosmo.GetHostIsa() end

-- BIT MANIPULATION FUNCTIONS

--- Finds the first set bit (bit scan forward).
---@param n integer number to scan
---@return integer pos position of first set bit (1-indexed), or 0 if none
function cosmo.Bsf(n) end

--- Finds the last set bit (bit scan reverse).
---@param n integer number to scan
---@return integer pos position of last set bit (1-indexed), or 0 if none
function cosmo.Bsr(n) end

--- Counts the number of set bits (population count).
---@param n integer number to count
---@return integer count number of set bits
function cosmo.Popcnt(n) end

-- STRING UTILITY FUNCTIONS

--- Gets the monospace display width of a string.
---@param str string string to measure
---@return integer width display width in columns
function cosmo.GetMonospaceWidth(str) end

--- Checks if a string contains control codes.
---@param str string string to check
---@return boolean hascontrols true if contains control codes
function cosmo.HasControlCodes(str) end

--- Makes control codes visible in a string.
---@param str string string to process
---@return string visible string with visible control codes
function cosmo.VisualizeControlCodes(str) end

--- Indents each line of a string.
---@param str string string to indent
---@param prefix string prefix to add to each line
---@return string indented indented string
function cosmo.IndentLines(str, prefix) end

--- Decodes overlong UTF-8 sequences.
---@param str string string to decode
---@return string decoded decoded string
function cosmo.Underlong(str) end

--- Decimates a string (removes every other character).
---@param str string string to decimate
---@return string decimated decimated string
function cosmo.Decimate(str) end

-- FORMATTING FUNCTIONS

--- Formats a number in hexadecimal.
---@param n integer number to format
---@return string hex hexadecimal string
function cosmo.hex(n) end

--- Formats a number in octal.
---@param n integer number to format
---@return string oct octal string
function cosmo.oct(n) end

--- Formats a number in binary.
---@param n integer number to format
---@return string bin binary string
function cosmo.bin(n) end

--------------------------------------------------------------------------------
-- COSMO.PATH MODULE
--------------------------------------------------------------------------------

cosmo.path = {}

--- Returns the last component of a path.
---@param path string file path
---@return string basename file name without directory
function cosmo.path.basename(path) end

--- Returns the directory portion of a path.
---@param path string file path
---@return string dirname directory path
function cosmo.path.dirname(path) end

--- Joins path components.
---@param ... string path components
---@return string path joined path
function cosmo.path.join(...) end

--- Checks if a path exists.
---@param path string file path
---@return boolean exists true if exists
function cosmo.path.exists(path) end

--- Checks if a path is a regular file.
---@param path string file path
---@return boolean isfile true if regular file
function cosmo.path.isfile(path) end

--- Checks if a path is a directory.
---@param path string file path
---@return boolean isdir true if directory
function cosmo.path.isdir(path) end

--- Checks if a path is a symbolic link.
---@param path string file path
---@return boolean islink true if symbolic link
function cosmo.path.islink(path) end

--------------------------------------------------------------------------------
-- COSMO.RE MODULE
--------------------------------------------------------------------------------

cosmo.re = {}

--- Compiles a regular expression pattern.
---@param pattern string regex pattern
---@param flags? integer regex flags
---@return userdata regex compiled regex object
function cosmo.re.compile(pattern, flags) end

--- Searches for a pattern in a string.
---@param regex userdata compiled regex
---@param str string string to search
---@param pos? integer starting position (default 1)
---@return integer? start match start position
---@return integer? stop match end position
---@return string? ... captured groups
function cosmo.re.search(regex, str, pos) end

--------------------------------------------------------------------------------
-- COSMO.UNIX MODULE
--------------------------------------------------------------------------------

cosmo.unix = {}

--- Environment variables table.
---@type table<string,string>
cosmo.unix.environ = {}

-- Process functions

--- Creates a child process.
---@return integer pid child PID (in parent), 0 (in child)
---@overload fun(): nil, unix.Errno
function cosmo.unix.fork() end

--- Replaces current process with a new program.
---@param path string program path
---@param args table argument list
---@param env? table environment variables
---@return nil, unix.Errno never returns on success
function cosmo.unix.execve(path, args, env) end

--- Terminates the current process.
---@param code? integer exit code (default 0)
function cosmo.unix.exit(code) end

--- Sends a signal to a process.
---@param pid integer process ID
---@param sig integer signal number
---@return integer result 0 on success
---@overload fun(pid: integer, sig: integer): nil, unix.Errno
function cosmo.unix.kill(pid, sig) end

--- Waits for a child process to change state.
---@param pid? integer process ID (-1 for any child)
---@param options? integer wait options
---@return integer pid child PID
---@return integer status exit status
---@overload fun(pid?: integer, options?: integer): nil, unix.Errno
function cosmo.unix.wait(pid, options) end

--- Finds an executable in PATH.
---@param name string program name
---@return string path absolute path to executable
---@overload fun(name: string): nil
function cosmo.unix.commandv(name) end

--- Gets the process ID.
---@return integer pid current process ID
function cosmo.unix.getpid() end

--- Gets the parent process ID.
---@return integer ppid parent process ID
function cosmo.unix.getppid() end

--- Gets the user ID.
---@return integer uid current user ID
function cosmo.unix.getuid() end

--- Gets the effective user ID.
---@return integer euid effective user ID
function cosmo.unix.geteuid() end

--- Gets the group ID.
---@return integer gid current group ID
function cosmo.unix.getgid() end

--- Gets the effective group ID.
---@return integer egid effective group ID
function cosmo.unix.getegid() end

--- Sets the user ID.
---@param uid integer user ID to set
---@return integer result 0 on success
---@overload fun(uid: integer): nil, unix.Errno
function cosmo.unix.setuid(uid) end

--- Sets the effective user ID.
---@param euid integer effective user ID
---@return integer result 0 on success
---@overload fun(euid: integer): nil, unix.Errno
function cosmo.unix.seteuid(euid) end

--- Sets the group ID.
---@param gid integer group ID to set
---@return integer result 0 on success
---@overload fun(gid: integer): nil, unix.Errno
function cosmo.unix.setgid(gid) end

--- Sets the effective group ID.
---@param egid integer effective group ID
---@return integer result 0 on success
---@overload fun(egid: integer): nil, unix.Errno
function cosmo.unix.setegid(egid) end

-- File system functions

--- Opens a file.
---@param path string file path
---@param flags integer open flags (O_RDONLY, O_WRONLY, O_RDWR, etc.)
---@param mode? integer file mode for creation
---@return integer fd file descriptor
---@overload fun(path: string, flags: integer, mode?: integer): nil, unix.Errno
function cosmo.unix.open(path, flags, mode) end

--- Closes a file descriptor.
---@param fd integer file descriptor
---@return integer result 0 on success
---@overload fun(fd: integer): nil, unix.Errno
function cosmo.unix.close(fd) end

--- Reads from a file descriptor.
---@param fd integer file descriptor
---@param count? integer maximum bytes to read
---@return string data data read
---@overload fun(fd: integer, count?: integer): nil, unix.Errno
function cosmo.unix.read(fd, count) end

--- Writes to a file descriptor.
---@param fd integer file descriptor
---@param data string data to write
---@return integer written bytes written
---@overload fun(fd: integer, data: string): nil, unix.Errno
function cosmo.unix.write(fd, data) end

--- Seeks in a file.
---@param fd integer file descriptor
---@param offset integer seek offset
---@param whence? integer seek mode (SEEK_SET, SEEK_CUR, SEEK_END)
---@return integer pos new file position
---@overload fun(fd: integer, offset: integer, whence?: integer): nil, unix.Errno
function cosmo.unix.lseek(fd, offset, whence) end

--- Gets file status.
---@param path string file path
---@return table stat file status table
---@overload fun(path: string): nil, unix.Errno
function cosmo.unix.stat(path) end

--- Gets file status (doesn't follow symlinks).
---@param path string file path
---@return table stat file status table
---@overload fun(path: string): nil, unix.Errno
function cosmo.unix.lstat(path) end

--- Gets file status by descriptor.
---@param fd integer file descriptor
---@return table stat file status table
---@overload fun(fd: integer): nil, unix.Errno
function cosmo.unix.fstat(fd) end

--- Checks file accessibility.
---@param path string file path
---@param mode integer access mode (R_OK, W_OK, X_OK, F_OK)
---@return boolean accessible true if accessible
function cosmo.unix.access(path, mode) end

--- Changes file mode.
---@param path string file path
---@param mode integer file mode
---@return integer result 0 on success
---@overload fun(path: string, mode: integer): nil, unix.Errno
function cosmo.unix.chmod(path, mode) end

--- Changes file owner.
---@param path string file path
---@param uid integer user ID
---@param gid integer group ID
---@return integer result 0 on success
---@overload fun(path: string, uid: integer, gid: integer): nil, unix.Errno
function cosmo.unix.chown(path, uid, gid) end

--- Deletes a file.
---@param path string file path
---@return integer result 0 on success
---@overload fun(path: string): nil, unix.Errno
function cosmo.unix.unlink(path) end

--- Renames a file.
---@param oldpath string current path
---@param newpath string new path
---@return integer result 0 on success
---@overload fun(oldpath: string, newpath: string): nil, unix.Errno
function cosmo.unix.rename(oldpath, newpath) end

--- Creates a hard link.
---@param target string existing path
---@param linkpath string new link path
---@return integer result 0 on success
---@overload fun(target: string, linkpath: string): nil, unix.Errno
function cosmo.unix.link(target, linkpath) end

--- Creates a symbolic link.
---@param target string target path
---@param linkpath string symlink path
---@return integer result 0 on success
---@overload fun(target: string, linkpath: string): nil, unix.Errno
function cosmo.unix.symlink(target, linkpath) end

--- Reads a symbolic link.
---@param path string symlink path
---@return string target link target
---@overload fun(path: string): nil, unix.Errno
function cosmo.unix.readlink(path) end

--- Resolves a path to its absolute canonical form.
---@param path string file path
---@return string realpath absolute path
---@overload fun(path: string): nil, unix.Errno
function cosmo.unix.realpath(path) end

--- Creates a directory.
---@param path string directory path
---@param mode? integer directory mode (default 0755)
---@return integer result 0 on success
---@overload fun(path: string, mode?: integer): nil, unix.Errno
function cosmo.unix.mkdir(path, mode) end

--- Removes a directory.
---@param path string directory path
---@return integer result 0 on success
---@overload fun(path: string): nil, unix.Errno
function cosmo.unix.rmdir(path) end

--- Opens a directory for reading.
---@param path string directory path
---@return userdata dir directory iterator
---@overload fun(path: string): nil, unix.Errno
function cosmo.unix.opendir(path) end

--- Gets current working directory.
---@return string cwd current directory
function cosmo.unix.getcwd() end

--- Changes current working directory.
---@param path string new directory
---@return integer result 0 on success
---@overload fun(path: string): nil, unix.Errno
function cosmo.unix.chdir(path) end

--- Changes root directory.
---@param path string new root directory
---@return integer result 0 on success
---@overload fun(path: string): nil, unix.Errno
function cosmo.unix.chroot(path) end

-- Socket functions

--- Creates a socket.
---@param domain integer address family (AF_INET, AF_UNIX, etc.)
---@param type integer socket type (SOCK_STREAM, SOCK_DGRAM, etc.)
---@param protocol? integer protocol (default 0)
---@return integer fd socket file descriptor
---@overload fun(domain: integer, type: integer, protocol?: integer): nil, unix.Errno
function cosmo.unix.socket(domain, type, protocol) end

--- Binds a socket to an address.
---@param fd integer socket file descriptor
---@param addr string address (IP:port or unix path)
---@return integer result 0 on success
---@overload fun(fd: integer, addr: string): nil, unix.Errno
function cosmo.unix.bind(fd, addr) end

--- Listens for connections.
---@param fd integer socket file descriptor
---@param backlog? integer connection queue size (default 128)
---@return integer result 0 on success
---@overload fun(fd: integer, backlog?: integer): nil, unix.Errno
function cosmo.unix.listen(fd, backlog) end

--- Accepts a connection.
---@param fd integer listening socket
---@return integer clientfd client socket
---@return string addr client address
---@overload fun(fd: integer): nil, unix.Errno
function cosmo.unix.accept(fd) end

--- Connects to an address.
---@param fd integer socket file descriptor
---@param addr string address to connect to
---@return integer result 0 on success
---@overload fun(fd: integer, addr: string): nil, unix.Errno
function cosmo.unix.connect(fd, addr) end

--- Sends data on a socket.
---@param fd integer socket file descriptor
---@param data string data to send
---@param flags? integer send flags
---@return integer sent bytes sent
---@overload fun(fd: integer, data: string, flags?: integer): nil, unix.Errno
function cosmo.unix.send(fd, data, flags) end

--- Receives data from a socket.
---@param fd integer socket file descriptor
---@param count? integer maximum bytes to receive
---@param flags? integer receive flags
---@return string data data received
---@overload fun(fd: integer, count?: integer, flags?: integer): nil, unix.Errno
function cosmo.unix.recv(fd, count, flags) end

--- Polls file descriptors for events.
---@param fds table array of {fd=n, events=n} tables
---@param timeout? integer timeout in milliseconds (-1 for infinite)
---@return integer count number of ready descriptors
---@overload fun(fds: table, timeout?: integer): nil, unix.Errno
function cosmo.unix.poll(fds, timeout) end

--- Duplicates a file descriptor.
---@param fd integer file descriptor to duplicate
---@return integer newfd new file descriptor
---@overload fun(fd: integer): nil, unix.Errno
function cosmo.unix.dup(fd) end

--- Creates a pipe.
---@return integer readfd read end of pipe
---@return integer writefd write end of pipe
---@overload fun(): nil, unix.Errno
function cosmo.unix.pipe() end

-- Signal functions

--- Raises a signal.
---@param sig integer signal number
---@return integer result 0 on success
function cosmo.unix.raise(sig) end

--- Sets a signal handler.
---@param sig integer signal number
---@param handler function|string handler function or "SIG_IGN"/"SIG_DFL"
---@return function? previous previous handler
---@overload fun(sig: integer, handler: function|string): nil, unix.Errno
function cosmo.unix.sigaction(sig, handler) end

-- Resource limits

--- Gets resource limit.
---@param resource integer resource type (RLIMIT_*)
---@return integer soft soft limit
---@return integer hard hard limit
---@overload fun(resource: integer): nil, unix.Errno
function cosmo.unix.getrlimit(resource) end

--- Sets resource limit.
---@param resource integer resource type (RLIMIT_*)
---@param soft integer soft limit
---@param hard? integer hard limit (default: same as soft)
---@return integer result 0 on success
---@overload fun(resource: integer, soft: integer, hard?: integer): nil, unix.Errno
function cosmo.unix.setrlimit(resource, soft, hard) end

-- Constants (commonly used)

---@type integer Read permission flag for access()
cosmo.unix.R_OK = 4
---@type integer Write permission flag for access()
cosmo.unix.W_OK = 2
---@type integer Execute permission flag for access()
cosmo.unix.X_OK = 1
---@type integer Existence flag for access()
cosmo.unix.F_OK = 0

---@type integer Open for reading only
cosmo.unix.O_RDONLY = 0
---@type integer Open for writing only
cosmo.unix.O_WRONLY = 1
---@type integer Open for reading and writing
cosmo.unix.O_RDWR = 2
---@type integer Create file if it doesn't exist
cosmo.unix.O_CREAT = 64
---@type integer Fail if file exists with O_CREAT
cosmo.unix.O_EXCL = 128
---@type integer Truncate file to zero length
cosmo.unix.O_TRUNC = 512
---@type integer Append to file
cosmo.unix.O_APPEND = 1024

---@type integer Seek from beginning of file
cosmo.unix.SEEK_SET = 0
---@type integer Seek from current position
cosmo.unix.SEEK_CUR = 1
---@type integer Seek from end of file
cosmo.unix.SEEK_END = 2

---@type integer IPv4 address family
cosmo.unix.AF_INET = 2
---@type integer IPv6 address family
cosmo.unix.AF_INET6 = 10
---@type integer Unix domain sockets
cosmo.unix.AF_UNIX = 1

---@type integer Stream socket (TCP)
cosmo.unix.SOCK_STREAM = 1
---@type integer Datagram socket (UDP)
cosmo.unix.SOCK_DGRAM = 2

---@type integer SIGINT - Interrupt
cosmo.unix.SIGINT = 2
---@type integer SIGTERM - Terminate
cosmo.unix.SIGTERM = 15
---@type integer SIGKILL - Kill (cannot be caught)
cosmo.unix.SIGKILL = 9
---@type integer SIGCHLD - Child status changed
cosmo.unix.SIGCHLD = 17

--------------------------------------------------------------------------------
-- COSMO.SQLITE3 MODULE
--------------------------------------------------------------------------------

cosmo.sqlite3 = {}

--- Opens a SQLite database.
---@param path string database file path (":memory:" for in-memory)
---@param flags? integer open flags
---@return userdata db database handle
---@overload fun(path: string, flags?: integer): nil, string, integer
function cosmo.sqlite3.open(path, flags) end

--- SQLite version string.
---@type string
cosmo.sqlite3.version = ""

--------------------------------------------------------------------------------
-- COSMO.ARGON2 MODULE
--------------------------------------------------------------------------------

cosmo.argon2 = {}

--- Hashes a password using Argon2.
---@param password string password to hash
---@param options? table hashing options
---@return string hash encoded hash string
function cosmo.argon2.hash_encoded(password, options) end

--- Verifies a password against an Argon2 hash.
---@param encoded string encoded hash
---@param password string password to verify
---@return boolean valid true if password matches
function cosmo.argon2.verify(encoded, password) end
