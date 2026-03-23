local logger = require("parrot.logger")

---@class BrowserFlow
---@field auth_url string
---@field callback_url string
---@field port number
---@field timeout number
local BrowserFlow = {}
BrowserFlow.__index = BrowserFlow

--- Creates a new BrowserFlow instance
--- @param auth_url string The OAuth authorization URL to open
--- @param callback_url string The callback URL (e.g., "http://localhost:9876/callback")
--- @param port number|nil Optional port (default: 9876)
--- @return BrowserFlow
function BrowserFlow:new(auth_url, callback_url, port)
  local self = setmetatable({}, BrowserFlow)

  self.auth_url = auth_url
  self.callback_url = callback_url
  self.port = port or 9876
  self.timeout = 300 -- 5 minutes

  return self
end

--- Opens a URL in the system's default browser
--- @param url string The URL to open
--- @return boolean Success status
function BrowserFlow:open_browser(url)
  local cmd

  -- Detect platform and use appropriate command
  if vim.fn.has("mac") == 1 then
    cmd = "open"
  elseif vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
    cmd = "start"
  else
    -- Linux and other Unix-like systems
    cmd = "xdg-open"
  end

  -- Execute the command
  local result = vim.fn.system(cmd .. " " .. vim.fn.shellescape(url))
  local exit_code = vim.v.shell_error

  if exit_code ~= 0 then
    logger.error("Failed to open browser: " .. result)
    return false
  end

  logger.info("Opened browser for OAuth authorization")
  return true
end

--- Starts a simple HTTP server to listen for the OAuth callback
--- Uses a Python one-liner for maximum compatibility
--- @return string|nil Authorization code, or nil on timeout/error
function BrowserFlow:start_callback_server()
  logger.info("Starting OAuth callback server on port " .. self.port)

  -- Create a temporary Python script for the callback server
  local python_script = string.format([[
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

class CallbackHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # Suppress logs

    def do_GET(self):
        parsed = urlparse(self.path)
        params = parse_qs(parsed.query)

        if 'code' in params:
            code = params['code'][0]
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            self.wfile.write(b'''
                <html><body>
                <h1>Authorization Successful!</h1>
                <p>You can close this window and return to Neovim.</p>
                <script>window.close();</script>
                </body></html>
            ''')
            print(code, flush=True)
            sys.exit(0)
        elif 'error' in params:
            error = params['error'][0]
            self.send_response(400)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            self.wfile.write(f'<html><body><h1>Authorization Failed</h1><p>{error}</p></body></html>'.encode())
            print('ERROR:' + error, flush=True)
            sys.exit(1)
        else:
            self.send_response(404)
            self.end_headers()

server = HTTPServer(('127.0.0.1', %d), CallbackHandler)
server.timeout = %d
try:
    server.handle_request()
except Exception as e:
    print('TIMEOUT', flush=True)
    sys.exit(2)
]], self.port, self.timeout)

  -- Write Python script to temp file
  local temp_script = vim.fn.tempname() .. ".py"
  local file = io.open(temp_script, "w")
  if not file then
    logger.error("Failed to create temporary callback server script")
    return nil
  end
  file:write(python_script)
  file:close()

  -- Run the server and capture output
  logger.debug("Starting callback server with timeout: " .. self.timeout .. "s")
  local handle = io.popen("python3 " .. vim.fn.shellescape(temp_script) .. " 2>&1")
  if not handle then
    logger.error("Failed to start callback server")
    os.remove(temp_script)
    return nil
  end

  local output = handle:read("*a")
  handle:close()
  os.remove(temp_script)

  -- Parse the output
  output = output:gsub("^%s*(.-)%s*$", "%1") -- Trim whitespace

  if output == "TIMEOUT" then
    logger.error("OAuth callback timed out after " .. self.timeout .. " seconds")
    return nil
  elseif output:match("^ERROR:") then
    local error_msg = output:gsub("^ERROR:", "")
    logger.error("OAuth authorization failed: " .. error_msg)
    return nil
  elseif output and output ~= "" then
    logger.info("Received OAuth authorization code")
    return output
  else
    logger.error("Failed to receive OAuth callback")
    return nil
  end
end

--- Starts the complete OAuth browser flow
--- Opens browser and waits for callback
--- @return string|nil Authorization code, or nil on failure
function BrowserFlow:start()
  -- Start the callback server in a separate thread/coroutine
  -- Since Lua doesn't have native threading, we'll use a synchronous approach

  logger.info("Starting OAuth browser flow...")

  -- Fork: Start server first, then open browser
  -- We'll use vim.fn.jobstart for async execution
  local auth_code = nil
  local server_completed = false

  -- Use vim.loop (libuv) for async operations
  local stdin = vim.loop.new_pipe(false)
  local stdout = vim.loop.new_pipe(false)
  local stderr = vim.loop.new_pipe(false)

  -- Create Python script
  local python_script = string.format([[
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

class CallbackHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_GET(self):
        parsed = urlparse(self.path)
        params = parse_qs(parsed.query)

        if 'code' in params:
            code = params['code'][0]
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            self.wfile.write(b'''
                <html><body>
                <h1>Authorization Successful!</h1>
                <p>You can close this window and return to Neovim.</p>
                <script>window.close();</script>
                </body></html>
            ''')
            print(code, flush=True)
            sys.exit(0)
        elif 'error' in params:
            error = params['error'][0]
            self.send_response(400)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            self.wfile.write(f'<html><body><h1>Authorization Failed</h1><p>{error}</p></body></html>'.encode())
            print('ERROR:' + error, flush=True)
            sys.exit(1)

server = HTTPServer(('127.0.0.1', %d), CallbackHandler)
server.timeout = %d
try:
    server.handle_request()
except:
    print('TIMEOUT', flush=True)
    sys.exit(2)
]], self.port, self.timeout)

  local temp_script = vim.fn.tempname() .. ".py"
  local file = io.open(temp_script, "w")
  if not file then
    logger.error("Failed to create temporary callback server script")
    return nil
  end
  file:write(python_script)
  file:close()

  -- Start callback server in background
  vim.fn.jobstart({ "python3", temp_script }, {
    on_stdout = function(_, data, _)
      if data and #data > 0 then
        local output = table.concat(data, "\n"):gsub("^%s*(.-)%s*$", "%1")
        if output == "TIMEOUT" then
          logger.error("OAuth callback timed out")
        elseif output:match("^ERROR:") then
          logger.error("OAuth authorization failed: " .. output:gsub("^ERROR:", ""))
        elseif output ~= "" then
          auth_code = output
        end
        server_completed = true
      end
    end,
    on_stderr = function(_, data, _)
      if data and #data > 0 then
        logger.debug("Server stderr: " .. table.concat(data, "\n"))
      end
    end,
    on_exit = function(_, exit_code, _)
      server_completed = true
      os.remove(temp_script)
    end,
  })

  -- Wait a moment for server to start
  vim.wait(500)

  -- Open browser
  local browser_ok = self:open_browser(self.auth_url)
  if not browser_ok then
    logger.error("Failed to open browser for OAuth")
    return nil
  end

  -- Wait for server to complete (with timeout)
  local wait_time = 0
  local wait_interval = 100 -- Check every 100ms
  while not server_completed and wait_time < (self.timeout * 1000) do
    vim.wait(wait_interval)
    wait_time = wait_time + wait_interval
  end

  if not server_completed then
    logger.error("OAuth callback server timed out")
    return nil
  end

  return auth_code
end

return BrowserFlow
