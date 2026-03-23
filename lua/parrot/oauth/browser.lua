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

--- Starts the OAuth browser flow asynchronously.
--- Shows the URL in a scratch buffer, copies to clipboard, starts callback
--- server in background, and returns immediately. Calls on_complete when
--- the user finishes authorization.
--- @param on_complete function callback(auth_code) called with the code or nil
function BrowserFlow:start_async(on_complete)
  -- Copy URL to + register (system clipboard)
  local ok_clip = pcall(vim.fn.setreg, "+", self.auth_url)
  local clipboard_msg = ok_clip and " (copied to clipboard)" or ""

  -- Show URL in a scratch floating buffer the user can yank from
  local lines = {
    "OAuth Authorization",
    "",
    "Open this URL in your browser:",
    "",
    self.auth_url,
    "",
    "Waiting for callback on port " .. self.port .. "..." .. clipboard_msg,
    "This window will close automatically after authorization.",
    "",
    "Press q to cancel.",
  }

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"

  -- Calculate floating window size
  local width = math.max(60, #self.auth_url + 4)
  local height = #lines
  local ui = vim.api.nvim_list_uis()[1]
  local row = math.floor((ui.height - height) / 2)
  local col = math.floor((ui.width - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " OAuth ",
    title_pos = "center",
  })

  -- Place cursor on the URL line for easy yanking
  vim.api.nvim_win_set_cursor(win, { 5, 0 })

  -- Create Python callback server script
  local python_script = string.format([[
import sys, socket
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

result = None

class CallbackHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_GET(self):
        global result
        parsed = urlparse(self.path)
        params = parse_qs(parsed.query)

        if 'code' in params:
            result = params['code'][0]
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
        elif 'error' in params:
            result = 'ERROR:' + params['error'][0]
            self.send_response(400)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            err = params['error'][0]
            self.wfile.write(f'<html><body><h1>Authorization Failed</h1><p>{err}</p></body></html>'.encode())
        else:
            self.send_response(404)
            self.end_headers()

server = HTTPServer(('127.0.0.1', %d), CallbackHandler)
server.timeout = %d
try:
    server.handle_request()
except socket.timeout:
    pass

if result:
    print(result, flush=True)
else:
    print('TIMEOUT', flush=True)
]], self.port, self.timeout)

  local temp_script = vim.fn.tempname() .. ".py"
  local file = io.open(temp_script, "w")
  if not file then
    logger.error("Failed to create temporary callback server script")
    on_complete(nil)
    return
  end
  file:write(python_script)
  file:close()

  local auth_code = nil

  -- Close floating window helper
  local function close_win()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  -- Start callback server in background
  local job_id = vim.fn.jobstart({ "python3", temp_script }, {
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
      os.remove(temp_script)
      vim.schedule(function()
        close_win()
        on_complete(auth_code)
      end)
    end,
  })

  -- Allow q to cancel
  vim.keymap.set("n", "q", function()
    vim.fn.jobstop(job_id)
    close_win()
    logger.info("OAuth authorization cancelled")
    on_complete(nil)
  end, { buffer = buf, nowait = true })
end

return BrowserFlow
