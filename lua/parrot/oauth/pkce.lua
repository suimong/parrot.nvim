local logger = require("parrot.logger")

---@class PKCE
local M = {}

--- Base64url encodes data (URL-safe variant without padding)
--- @param data string
--- @return string
M.base64url_encode = function(data)
  -- Standard base64 encode
  local b64 = vim.base64.encode(data)

  -- Convert to base64url: replace +/= with -_
  b64 = b64:gsub("+", "-"):gsub("/", "_"):gsub("=", "")

  return b64
end

--- Generates a cryptographically secure random verifier string
--- Uses OpenSSL for security, falls back to Lua random with warning
--- @return string A 128-character base64url-encoded verifier
M.generate_verifier = function()
  -- Try OpenSSL first for cryptographic security
  local handle = io.popen("openssl rand -base64 96 2>/dev/null")
  if handle then
    local random_bytes = handle:read("*a")
    handle:close()

    if random_bytes and #random_bytes > 0 then
      -- Clean and encode to base64url, take first 128 chars
      local verifier = M.base64url_encode(random_bytes):sub(1, 128)
      return verifier
    end
  end

  -- Fallback to Lua random (less secure)
  logger.warning("OpenSSL not available, using fallback random generator (less secure)")

  local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
  local verifier = {}
  for i = 1, 128 do
    local idx = math.random(1, #chars)
    verifier[i] = chars:sub(idx, idx)
  end

  return table.concat(verifier)
end

--- Generates a PKCE code challenge from a verifier using SHA256
--- @param verifier string The code verifier
--- @return string|nil The base64url-encoded SHA256 challenge, or nil on error
M.generate_challenge = function(verifier)
  if not verifier or verifier == "" then
    logger.error("Cannot generate challenge: verifier is empty")
    return nil
  end

  -- Use OpenSSL to generate SHA256 hash
  local cmd = string.format('printf "%%s" "%s" | openssl dgst -sha256 -binary 2>/dev/null', verifier)
  local handle = io.popen(cmd)

  if not handle then
    logger.error("Failed to execute OpenSSL command for PKCE challenge")
    return nil
  end

  local hash_binary = handle:read("*a")
  handle:close()

  if not hash_binary or #hash_binary == 0 then
    logger.error("OpenSSL failed to generate SHA256 hash")
    return nil
  end

  -- Encode to base64url
  local challenge = M.base64url_encode(hash_binary)
  return challenge
end

--- Generates both PKCE verifier and challenge
--- @return table|nil { verifier: string, challenge: string } or nil on error
M.generate_pair = function()
  local verifier = M.generate_verifier()
  if not verifier then
    return nil
  end

  local challenge = M.generate_challenge(verifier)
  if not challenge then
    return nil
  end

  return {
    verifier = verifier,
    challenge = challenge,
  }
end

return M
