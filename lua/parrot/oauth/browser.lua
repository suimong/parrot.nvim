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

--- Starts the complete OAuth browser flow
--- Prints the URL for the user and waits for callback
--- @return string|nil Authorization code, or nil on failure
function BrowserFlow:start()
  logger.info("Starting OAuth callback server on port " .. self.port .. " (timeout: " .. self.timeout .. "s)")

  -- Print the URL for the user to open manually
  logger.info("Open this URL in your browser to authenticate:\n" .. self.auth_url)

  local auth_code = nil
  local server_completed = false

  -- Create Python callback server script
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
        local msg = table.concat(data, "\n")
        if msg:match("%S") then
          logger.debug("Server stderr: " .. msg)
        end
      end
    end,
    on_exit = function(_, _, _)
      server_completed = true
      os.remove(temp_script)
    end,
  })

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
