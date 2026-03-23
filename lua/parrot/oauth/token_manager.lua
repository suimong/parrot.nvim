local logger = require("parrot.logger")
local file_utils = require("parrot.file_utils")

---@class TokenManager
---@field provider_name string
---@field oauth_dir string
---@field token_file string
local TokenManager = {}
TokenManager.__index = TokenManager

--- Creates a new TokenManager instance
--- @param provider_name string The provider name (e.g., "anthropic")
--- @param oauth_dir string|nil Optional OAuth directory (defaults to stdpath data)
--- @return TokenManager
function TokenManager:new(provider_name, oauth_dir)
  local self = setmetatable({}, TokenManager)

  self.provider_name = provider_name
  self.oauth_dir = oauth_dir or (vim.fn.stdpath("data") .. "/parrot/oauth")
  self.token_file = self.oauth_dir .. "/" .. provider_name .. "-auth.json"

  -- Ensure OAuth directory exists with secure permissions
  vim.fn.mkdir(self.oauth_dir, "p")
  vim.fn.system("chmod 700 " .. vim.fn.shellescape(self.oauth_dir))

  return self
end

--- Validates token data structure
--- @param token_data table
--- @return boolean
local function validate_token_data(token_data)
  if type(token_data) ~= "table" then
    return false
  end

  -- Required fields
  if not token_data.access_token or type(token_data.access_token) ~= "string" then
    return false
  end

  if not token_data.expires_at or type(token_data.expires_at) ~= "number" then
    return false
  end

  -- Optional but should be strings if present
  if token_data.refresh_token and type(token_data.refresh_token) ~= "string" then
    return false
  end

  if token_data.token_type and type(token_data.token_type) ~= "string" then
    return false
  end

  return true
end

--- Saves token data to disk with secure permissions (0600)
--- @param token_data table { access_token, refresh_token, expires_at, token_type, scope }
--- @return boolean Success status
function TokenManager:save(token_data)
  if not validate_token_data(token_data) then
    logger.error("Invalid token data structure for " .. self.provider_name)
    return false
  end

  local json_str = vim.json.encode(token_data)
  local success = file_utils.write_file_secure(self.token_file, json_str)

  if success then
    logger.debug("Saved OAuth tokens for " .. self.provider_name)
  else
    logger.error("Failed to save OAuth tokens for " .. self.provider_name)
  end

  return success
end

--- Loads token data from disk
--- @return table|nil Token data or nil if file doesn't exist or is invalid
function TokenManager:load()
  -- Check if file exists
  if vim.fn.filereadable(self.token_file) == 0 then
    logger.debug("No OAuth token file found for " .. self.provider_name)
    return nil
  end

  local token_data = file_utils.file_to_table(self.token_file)

  if not token_data then
    logger.error("Failed to read OAuth token file for " .. self.provider_name)
    return nil
  end

  if not validate_token_data(token_data) then
    logger.error("Invalid token data in file for " .. self.provider_name)
    return nil
  end

  return token_data
end

--- Checks if the current token is valid (not expired)
--- Uses a 2-minute buffer before actual expiration
--- @return boolean
function TokenManager:is_valid()
  local token_data = self:load()
  if not token_data then
    return false
  end

  local now = os.time()
  local buffer_seconds = 120 -- 2 minutes

  -- Token is valid if current time < expiry time - buffer
  return now < (token_data.expires_at - buffer_seconds)
end

--- Checks if the token needs to be refreshed
--- Returns true if within 2 minutes of expiration
--- @return boolean
function TokenManager:needs_refresh()
  local token_data = self:load()
  if not token_data then
    return false
  end

  local now = os.time()
  local buffer_seconds = 120 -- 2 minutes

  -- Needs refresh if we're within the buffer period
  return now >= (token_data.expires_at - buffer_seconds) and now < token_data.expires_at
end

--- Clears/deletes the token file
--- @return boolean Success status
function TokenManager:clear()
  if vim.fn.filereadable(self.token_file) == 0 then
    logger.debug("No token file to clear for " .. self.provider_name)
    return true
  end

  local success = os.remove(self.token_file)
  if success then
    logger.info("Cleared OAuth tokens for " .. self.provider_name)
  else
    logger.error("Failed to clear OAuth tokens for " .. self.provider_name)
  end

  return success ~= nil
end

--- Gets the token file path
--- @return string
function TokenManager:get_token_file()
  return self.token_file
end

return TokenManager
