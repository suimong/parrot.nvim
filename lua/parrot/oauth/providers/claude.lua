local logger = require("parrot.logger")

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

--- Helper to stringify an error value that may be a string or table
--- @param val any
--- @return string
local function error_to_string(val)
  if type(val) == "string" then
    return val
  end
  return vim.inspect(val)
end

--- Helper to parse a token response from curl stdout lines
--- @param stdout_lines table
--- @return table|nil token_data, string|nil error_msg
local function parse_token_response(stdout_lines)
  local response = table.concat(stdout_lines, "")
  if not response or response == "" then
    return nil, "empty response"
  end

  local ok, token_data = pcall(vim.json.decode, response)
  if not ok then
    return nil, "failed to parse JSON: " .. response
  end

  if token_data.error then
    local desc = token_data.error_description
    local err = token_data.error
    return nil, "OAuth error: " .. error_to_string(desc or err)
  end

  -- Calculate expires_at from expires_in
  if token_data.expires_in then
    token_data.expires_at = os.time() + token_data.expires_in
  end

  return token_data, nil
end

--- Exchanges an authorization code for access and refresh tokens (async)
--- @param code string The authorization code from the callback
--- @param verifier string The PKCE code verifier
--- @param callback function callback(token_data_or_nil)
M.exchange_code = function(code, verifier, callback)
  if not code or code == "" then
    logger.error("Cannot exchange code: code is empty")
    callback(nil)
    return
  end

  if not verifier or verifier == "" then
    logger.error("Cannot exchange code: verifier is empty")
    callback(nil)
    return
  end

  local request_body = vim.json.encode({
    grant_type = M.config.grant_type,
    client_id = M.config.client_id,
    code = code,
    redirect_uri = M.config.redirect_uri,
    code_verifier = verifier,
  })

  local stdout_lines = {}

  vim.fn.jobstart({
    "curl", "-s",
    "-X", "POST",
    "-H", "Content-Type: application/json",
    "-d", request_body,
    M.config.token_endpoint,
  }, {
    on_stdout = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stdout_lines, line)
          end
        end
      end
    end,
    on_exit = function(_, exit_code, _)
      vim.schedule(function()
        if exit_code ~= 0 then
          logger.error("Token exchange curl failed with exit code: " .. exit_code)
          callback(nil)
          return
        end

        local token_data, err = parse_token_response(stdout_lines)
        if err then
          logger.error("Token exchange failed: " .. err)
          callback(nil)
          return
        end

        callback(token_data)
      end)
    end,
  })
end

--- Refreshes an access token using a refresh token (async)
--- @param refresh_tok string The refresh token
--- @param callback function callback(token_data_or_nil)
M.refresh_token = function(refresh_tok, callback)
  if not refresh_tok or refresh_tok == "" then
    logger.error("Cannot refresh token: refresh_token is empty")
    callback(nil)
    return
  end

  local request_body = vim.json.encode({
    grant_type = "refresh_token",
    client_id = M.config.client_id,
    refresh_token = refresh_tok,
  })

  local stdout_lines = {}

  vim.fn.jobstart({
    "curl", "-s",
    "-X", "POST",
    "-H", "Content-Type: application/json",
    "-d", request_body,
    M.config.token_endpoint,
  }, {
    on_stdout = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stdout_lines, line)
          end
        end
      end
    end,
    on_exit = function(_, exit_code, _)
      vim.schedule(function()
        if exit_code ~= 0 then
          logger.error("Token refresh curl failed with exit code: " .. exit_code)
          callback(nil)
          return
        end

        local token_data, err = parse_token_response(stdout_lines)
        if err then
          logger.error("Token refresh failed: " .. err)
          callback(nil)
          return
        end

        -- Preserve the original refresh token if not returned
        if not token_data.refresh_token then
          token_data.refresh_token = refresh_tok
        end

        callback(token_data)
      end)
    end,
  })
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

  -- URL-encode a value (percent encoding)
  local function url_encode(str)
    return str:gsub("([^%w%-%.%_%~])", function(c)
      return string.format("%%%02X", string.byte(c))
    end)
  end

  local query_parts = {}
  for k, v in pairs(params) do
    table.insert(query_parts, url_encode(k) .. "=" .. url_encode(v))
  end

  return M.config.auth_endpoint .. "?" .. table.concat(query_parts, "&")
end

return M
