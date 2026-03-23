local logger = require("parrot.logger")
local Job = require("plenary.job")

---@class ClaudeOAuth
local M = {}

-- Claude OAuth configuration
M.config = {
  auth_endpoint = "https://claude.ai/oauth/authorize",
  token_endpoint = "https://console.anthropic.com/v1/oauth/token",
  client_id = "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
  redirect_uri = "http://localhost:9876/callback",
  scopes = "org:create_api_key user:profile user:inference",
  response_type = "code",
  grant_type = "authorization_code",
}

--- Exchanges an authorization code for access and refresh tokens
--- @param code string The authorization code from the callback
--- @param verifier string The PKCE code verifier
--- @param callback function|nil Optional callback function(success, token_data)
--- @return table|nil Token data on success, nil on failure
M.exchange_code = function(code, verifier, callback)
  if not code or code == "" then
    logger.error("Cannot exchange code: code is empty")
    return nil
  end

  if not verifier or verifier == "" then
    logger.error("Cannot exchange code: verifier is empty")
    return nil
  end

  local request_body = {
    grant_type = M.config.grant_type,
    client_id = M.config.client_id,
    code = code,
    redirect_uri = M.config.redirect_uri,
    code_verifier = verifier,
  }

  local result = nil
  local job = Job:new({
    command = "curl",
    args = {
      "-X", "POST",
      "-H", "Content-Type: application/json",
      "-d", vim.json.encode(request_body),
      M.config.token_endpoint,
    },
    on_exit = function(j, return_val)
      if return_val ~= 0 then
        logger.error("Token exchange failed with exit code: " .. return_val)
        if callback then
          callback(false, nil)
        end
        return
      end

      local response = table.concat(j:result(), "\n")
      if not response or response == "" then
        logger.error("Token exchange returned empty response")
        if callback then
          callback(false, nil)
        end
        return
      end

      local success, token_data = pcall(vim.json.decode, response)
      if not success then
        logger.error("Failed to parse token response: " .. response)
        if callback then
          callback(false, nil)
        end
        return
      end

      if token_data.error then
        logger.error("OAuth token exchange error: " .. (token_data.error_description or token_data.error))
        if callback then
          callback(false, nil)
        end
        return
      end

      -- Calculate expires_at from expires_in
      if token_data.expires_in then
        token_data.expires_at = os.time() + token_data.expires_in
      end

      result = token_data
      if callback then
        callback(true, token_data)
      end
    end,
  })

  job:start()
  job:wait()

  return result
end

--- Refreshes an access token using a refresh token
--- @param refresh_token string The refresh token
--- @param callback function|nil Optional callback function(success, token_data)
--- @return table|nil New token data on success, nil on failure
M.refresh_token = function(refresh_token, callback)
  if not refresh_token or refresh_token == "" then
    logger.error("Cannot refresh token: refresh_token is empty")
    return nil
  end

  local request_body = {
    grant_type = "refresh_token",
    client_id = M.config.client_id,
    refresh_token = refresh_token,
  }

  local result = nil
  local job = Job:new({
    command = "curl",
    args = {
      "-X", "POST",
      "-H", "Content-Type: application/json",
      "-d", vim.json.encode(request_body),
      M.config.token_endpoint,
    },
    on_exit = function(j, return_val)
      if return_val ~= 0 then
        logger.error("Token refresh failed with exit code: " .. return_val)
        if callback then
          callback(false, nil)
        end
        return
      end

      local response = table.concat(j:result(), "\n")
      if not response or response == "" then
        logger.error("Token refresh returned empty response")
        if callback then
          callback(false, nil)
        end
        return
      end

      local success, token_data = pcall(vim.json.decode, response)
      if not success then
        logger.error("Failed to parse refresh response: " .. response)
        if callback then
          callback(false, nil)
        end
        return
      end

      if token_data.error then
        logger.error("OAuth token refresh error: " .. (token_data.error_description or token_data.error))
        if callback then
          callback(false, nil)
        end
        return
      end

      -- Calculate expires_at from expires_in
      if token_data.expires_in then
        token_data.expires_at = os.time() + token_data.expires_in
      end

      -- Preserve the refresh token if not returned in response
      if not token_data.refresh_token then
        token_data.refresh_token = refresh_token
      end

      result = token_data
      if callback then
        callback(true, token_data)
      end
    end,
  })

  job:start()
  job:wait()

  return result
end

--- Builds the authorization URL with PKCE parameters
--- @param challenge string The PKCE code challenge
--- @param state string|nil Optional state parameter for CSRF protection
--- @return string The authorization URL
M.build_auth_url = function(challenge, state)
  if not challenge or challenge == "" then
    logger.error("Cannot build auth URL: challenge is empty")
    return ""
  end

  local params = {
    response_type = M.config.response_type,
    client_id = M.config.client_id,
    redirect_uri = M.config.redirect_uri,
    scope = M.config.scopes,
    code_challenge = challenge,
    code_challenge_method = "S256",
  }

  if state then
    params.state = state
  end

  local query_parts = {}
  for k, v in pairs(params) do
    table.insert(query_parts, k .. "=" .. vim.fn.shellescape(v):gsub("'", ""))
  end

  return M.config.auth_endpoint .. "?" .. table.concat(query_parts, "&")
end

return M
