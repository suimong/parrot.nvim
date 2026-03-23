local logger = require("parrot.logger")
local TokenManager = require("parrot.oauth.token_manager")
local PKCE = require("parrot.oauth.pkce")
local BrowserFlow = require("parrot.oauth.browser")

---@class OAuth
---@field provider_name string
---@field config table
---@field provider_module table
---@field token_manager TokenManager
local OAuth = {}
OAuth.__index = OAuth

--- Creates a new OAuth instance
--- @param provider_name string The provider name (e.g., "anthropic")
--- @param config table|nil Optional OAuth configuration overrides
--- @return OAuth
function OAuth:new(provider_name, config)
  local self = setmetatable({}, OAuth)

  self.provider_name = provider_name
  self.config = config or {}

  -- Load provider-specific OAuth module
  -- For now, we only support Claude/Anthropic
  local provider_module_name = "parrot.oauth.providers.claude"
  local ok, provider_module = pcall(require, provider_module_name)

  if not ok then
    logger.error("Failed to load OAuth provider module: " .. provider_module_name)
    error("Unsupported OAuth provider: " .. provider_name)
  end

  self.provider_module = provider_module

  -- Merge user config with provider defaults
  if config then
    for k, v in pairs(config) do
      if k ~= "enabled" then
        self.provider_module.config[k] = v
      end
    end
  end

  -- Initialize token manager
  self.token_manager = TokenManager:new(provider_name)

  return self
end

--- Gets a valid access token if one is cached (and still valid).
--- Refreshes automatically if needed. Does NOT trigger browser auth.
--- @return string|nil Access token, or nil if not authenticated
function OAuth:get_access_token()
  -- Try to load existing token
  local token_data = self.token_manager:load()

  -- No token exists
  if not token_data then
    logger.error(
      "No OAuth token for " .. self.provider_name .. ". Run :PrtAuth " .. self.provider_name .. " to authenticate."
    )
    return nil
  end

  -- Token is valid - return it
  if self.token_manager:is_valid() then
    logger.debug("Using cached OAuth token for " .. self.provider_name)
    return token_data.access_token
  end

  -- Token needs refresh
  if self.token_manager:needs_refresh() and token_data.refresh_token then
    logger.info("Refreshing OAuth token for " .. self.provider_name)
    local new_token_data = self.provider_module.refresh_token(token_data.refresh_token)

    if new_token_data and new_token_data.access_token then
      self.token_manager:save(new_token_data)
      return new_token_data.access_token
    else
      logger.error("Token refresh failed. Run :PrtAuth " .. self.provider_name .. " to re-authenticate.")
      self.token_manager:clear()
      return nil
    end
  end

  -- Token is expired
  logger.error(
    "OAuth token expired for " .. self.provider_name .. ". Run :PrtAuth " .. self.provider_name .. " to re-authenticate."
  )
  self.token_manager:clear()
  return nil
end

--- Starts the OAuth authentication flow asynchronously.
--- Shows URL in a floating buffer, starts callback server in background,
--- and returns immediately. Calls on_complete(token) when done.
--- @param on_complete function|nil callback(token_or_nil)
function OAuth:authenticate_async(on_complete)
  on_complete = on_complete or function() end

  logger.info("Starting OAuth authentication for " .. self.provider_name)

  -- Generate PKCE pair
  local pkce_pair = PKCE.generate_pair()
  if not pkce_pair then
    logger.error("Failed to generate PKCE pair")
    on_complete(nil)
    return
  end

  -- Generate random state for CSRF protection
  local state = PKCE.base64url_encode(tostring(math.random(1e15)) .. tostring(os.time()))

  -- Build authorization URL
  local auth_url = self.provider_module.build_auth_url(pkce_pair.challenge, state)
  if not auth_url or auth_url == "" then
    logger.error("Failed to build authorization URL")
    on_complete(nil)
    return
  end

  -- Start async browser flow
  local redirect_uri = self.provider_module.config.redirect_uri
  local port = tonumber(redirect_uri:match(":(%d+)")) or 9876

  local browser_flow = BrowserFlow:new(auth_url, redirect_uri, port)
  local provider_module = self.provider_module
  local token_manager = self.token_manager
  local provider_name = self.provider_name

  browser_flow:start_async(function(auth_code)
    if not auth_code then
      logger.error("Failed to obtain authorization code")
      on_complete(nil)
      return
    end

    logger.info("Received authorization code, exchanging for tokens...")

    -- Exchange code for tokens (async)
    provider_module.exchange_code(auth_code, pkce_pair.verifier, function(token_data)
      if not token_data or not token_data.access_token then
        logger.error("Failed to exchange authorization code for tokens")
        on_complete(nil)
        return
      end

      -- Save tokens
      local save_ok = token_manager:save(token_data)
      if not save_ok then
        logger.error("Failed to save OAuth tokens")
        on_complete(nil)
        return
      end

      logger.info("OAuth authentication successful for " .. provider_name)
      on_complete(token_data.access_token)
    end)
  end)
end

--- Revokes and clears OAuth tokens
--- @return boolean Success status
function OAuth:revoke()
  logger.info("Revoking OAuth tokens for " .. self.provider_name)
  return self.token_manager:clear()
end

--- Checks if OAuth is configured and enabled
--- @param provider_config table The provider configuration
--- @return boolean True if OAuth is enabled
function OAuth.is_enabled(provider_config)
  return provider_config.oauth and provider_config.oauth.enabled == true
end

return OAuth
