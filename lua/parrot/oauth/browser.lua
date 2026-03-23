local logger = require("parrot.logger")

---@class BrowserFlow
---@field auth_url string
---@field state string|nil
local BrowserFlow = {}
BrowserFlow.__index = BrowserFlow

--- Creates a new BrowserFlow instance
--- @param auth_url string The OAuth authorization URL
--- @param state string|nil The state parameter used in the auth URL
--- @return BrowserFlow
function BrowserFlow:new(auth_url, state)
  local self = setmetatable({}, BrowserFlow)
  self.auth_url = auth_url
  self.state = state
  return self
end

--- Starts the OAuth flow asynchronously.
--- Shows the auth URL in a floating buffer, copies to clipboard,
--- and prompts the user to paste the code from the browser.
--- @param on_complete function callback(auth_code) called with the code or nil
function BrowserFlow:start_async(on_complete)
  -- Copy URL to + register (system clipboard)
  local ok_clip = pcall(vim.fn.setreg, "+", self.auth_url)
  local clipboard_msg = ok_clip and " (copied to clipboard)" or ""

  -- Show URL in a floating buffer
  local lines = {
    "OAuth Authorization" .. clipboard_msg,
    "",
    "1. Open this URL in your browser:",
    "",
    self.auth_url,
    "",
    "2. Authorize the application",
    "3. Copy the code shown on the page",
    "4. Paste it below and press Enter",
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
  local ui_info = vim.api.nvim_list_uis()[1]
  local row = math.floor((ui_info.height - height) / 2)
  local col = math.floor((ui_info.width - width) / 2)

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

  local state = self.state
  local completed = false

  local function close_win()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function finish(code)
    if completed then
      return
    end
    completed = true
    close_win()
    on_complete(code)
  end

  -- Press Enter to input the code
  vim.keymap.set("n", "<CR>", function()
    close_win()
    -- Use vim.fn.input directly (not vim.ui.input) to avoid issues
    -- with plugin overrides (dressing.nvim, noice.nvim, etc.)
    local ok, input = pcall(vim.fn.input, "Paste OAuth code: ")
    if not ok or not input or input == "" then
      logger.error("OAuth authorization cancelled (no code entered)")
      finish(nil)
      return
    end

    -- The code format may be "code#state" — extract just the code part
    local code = input:match("^([^#]+)")
    if not code or code == "" then
      logger.error("Invalid OAuth code format")
      finish(nil)
      return
    end

    code = code:gsub("^%s*(.-)%s*$", "%1")
    logger.info("Received OAuth authorization code (length=" .. #code .. ")")
    finish(code)
  end, { buffer = buf, nowait = true })

  -- Press q to cancel
  vim.keymap.set("n", "q", function()
    logger.info("OAuth authorization cancelled")
    finish(nil)
  end, { buffer = buf, nowait = true })
end

return BrowserFlow
