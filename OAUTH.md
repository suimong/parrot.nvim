# OAuth Authentication for parrot.nvim

This guide explains how to use OAuth authentication with parrot.nvim to access LLM providers like Claude using your Pro subscription.

## Overview

parrot.nvim now supports OAuth/OIDC authentication as an alternative to traditional API keys. This is particularly useful for:

- **Claude Pro subscriptions**: Access Claude through your Pro account without needing a separate API key
- **Enterprise authentication**: Use organization-managed OAuth flows
- **Enhanced security**: OAuth tokens are automatically refreshed and stored securely

## Supported Providers

Currently supported OAuth providers:

- **Anthropic Claude** (via Claude Pro)

## Quick Start

### 1. Configuration

Add OAuth configuration to your provider setup:

```lua
require('parrot').setup({
  providers = {
    anthropic = {
      endpoint = "https://api.anthropic.com/v1/messages",
      model = "claude-sonnet-4-5-20250929",
      -- OAuth configuration (replaces api_key)
      oauth = {
        enabled = true,
      },
    },
  },
})
```

### 2. Initial Authentication

When you first trigger an API call (e.g., `:PrtChatNew`), parrot.nvim will:

1. Open your browser to the Claude OAuth authorization page
2. Wait for you to authorize the application
3. Capture the authorization code
4. Exchange it for access and refresh tokens
5. Save the tokens securely to disk

**Example:**

```vim
:PrtChatNew
" Browser opens automatically to https://claude.ai/oauth/authorize
" After you authorize, the chat will open and work normally
```

### 3. Subsequent Usage

After initial authentication, tokens are cached and automatically refreshed:

- **Valid tokens**: Used immediately (no browser prompt)
- **Expiring tokens** (within 2 minutes): Automatically refreshed
- **Expired tokens**: New authentication flow triggered

## OAuth Commands

parrot.nvim provides several commands for managing OAuth authentication:

### `:PrtAuth <provider>`

Manually trigger OAuth authentication for a provider.

```vim
:PrtAuth anthropic
```

This is useful for:
- Pre-authenticating before your first API call
- Re-authenticating if you've revoked tokens
- Testing your OAuth configuration

### `:PrtAuthStatus [provider]`

Check OAuth authentication status.

```vim
" Check status for all OAuth-enabled providers
:PrtAuthStatus

" Check status for specific provider
:PrtAuthStatus anthropic
```

Output includes:
- Authentication status (Valid/Expired/Not authenticated)
- Token expiration time
- Whether refresh token is available

### `:PrtAuthRevoke <provider>`

Revoke and clear OAuth tokens for a provider.

```vim
:PrtAuthRevoke anthropic
```

This will:
- Delete stored tokens from disk
- Require re-authentication on next API call

## Configuration Options

### Basic Configuration

Minimal configuration to enable OAuth:

```lua
providers = {
  anthropic = {
    endpoint = "https://api.anthropic.com/v1/messages",
    model = "claude-sonnet-4-5-20250929",
    oauth = {
      enabled = true,
    },
  },
}
```

### Advanced Configuration

Override OAuth defaults (rarely needed):

```lua
providers = {
  anthropic = {
    endpoint = "https://api.anthropic.com/v1/messages",
    model = "claude-sonnet-4-5-20250929",
    oauth = {
      enabled = true,
      -- Override client_id (use default unless you have your own)
      client_id = "custom-client-id",
      -- Override scopes (use default unless you have specific requirements)
      scopes = "org:create_api_key user:profile user:inference",
      -- Override redirect URI (use default unless you have port conflicts)
      redirect_uri = "http://localhost:9876/callback",
    },
  },
}
```

### Hybrid Configuration (OAuth + API Key Fallback)

You can configure both OAuth and API key. OAuth will be tried first, falling back to API key on failure:

```lua
providers = {
  anthropic = {
    endpoint = "https://api.anthropic.com/v1/messages",
    model = "claude-sonnet-4-5-20250929",
    api_key = os.getenv("ANTHROPIC_API_KEY"), -- Fallback
    oauth = {
      enabled = true, -- Preferred method
    },
  },
}
```

## Token Storage

### Location

OAuth tokens are stored in:

```
~/.local/share/nvim/parrot/oauth/<provider>-auth.json
```

For example:
- Anthropic: `~/.local/share/nvim/parrot/oauth/anthropic-auth.json`

### Security

Token files are stored with secure permissions:
- **File permissions**: `0600` (owner read/write only)
- **Directory permissions**: `0700` (owner access only)

### Token Structure

Token files contain:

```json
{
  "access_token": "eyJ...",
  "refresh_token": "eyJ...",
  "expires_at": 1234567890,
  "token_type": "Bearer",
  "scope": "org:create_api_key user:profile user:inference"
}
```

## How OAuth Works

### Authorization Code Flow with PKCE

parrot.nvim uses the OAuth 2.0 Authorization Code Flow with PKCE (Proof Key for Code Exchange) for security:

1. **PKCE Generation**: Generate a random `code_verifier` and SHA256 `code_challenge`
2. **Authorization Request**: Open browser to provider's authorize endpoint with challenge
3. **User Authorization**: User logs in and authorizes the application
4. **Callback**: Provider redirects to `http://localhost:9876/callback?code=...`
5. **Token Exchange**: Exchange authorization code + verifier for tokens
6. **Token Storage**: Save tokens with secure permissions
7. **Token Refresh**: Automatically refresh tokens before expiration

### Security Features

- **PKCE**: Prevents authorization code interception attacks
- **Secure Storage**: Tokens stored with restrictive file permissions
- **Auto-Refresh**: Tokens refreshed 2 minutes before expiration
- **Local Callback**: Callback server binds to `127.0.0.1` only

## Troubleshooting

### Browser doesn't open

**Problem**: Browser doesn't open during authentication

**Solutions**:
1. Check if `xdg-open` (Linux), `open` (macOS), or `start` (Windows) is available:
   ```bash
   which xdg-open  # Linux
   which open      # macOS
   ```
2. Manually open the authorization URL from the logs:
   ```vim
   :PrtLog
   " Look for "Authorization URL: https://claude.ai/oauth/authorize?..."
   ```

### Port already in use

**Problem**: Port 9876 is already in use by another application

**Solutions**:
1. Find and stop the process using the port:
   ```bash
   lsof -i :9876
   ```
2. Override the redirect URI in your config (not recommended, as the OAuth client ID is configured for port 9876)

### Token refresh fails

**Problem**: Token refresh fails and triggers re-authentication frequently

**Solutions**:
1. Check token file permissions:
   ```bash
   ls -la ~/.local/share/nvim/parrot/oauth/
   ```
2. Check logs for refresh errors:
   ```vim
   :PrtLog
   ```
3. Revoke and re-authenticate:
   ```vim
   :PrtAuthRevoke anthropic
   :PrtAuth anthropic
   ```

### Python not found

**Problem**: Callback server fails because Python 3 is not installed

**Solution**:
Install Python 3:
```bash
# Ubuntu/Debian
sudo apt install python3

# macOS (with Homebrew)
brew install python3

# Windows
# Download from https://www.python.org/downloads/
```

### OAuth not enabled error

**Problem**: "OAuth is not enabled for provider" error

**Solution**:
Ensure `oauth.enabled = true` in your config:
```lua
providers = {
  anthropic = {
    oauth = {
      enabled = true,  -- Must be explicitly true
    },
  },
}
```

## API Reference

### Lua API

You can also use OAuth programmatically:

```lua
local OAuth = require("parrot.oauth")

-- Create OAuth client
local oauth = OAuth:new("anthropic", {
  enabled = true,
})

-- Get access token (auto-refreshes if needed)
local token = oauth:get_access_token()

-- Check authentication status
local token_data = oauth.token_manager:load()
if token_data then
  local is_valid = oauth.token_manager:is_valid()
  local needs_refresh = oauth.token_manager:needs_refresh()
end

-- Manually trigger authentication
local token = oauth:authenticate()

-- Revoke tokens
oauth:revoke()
```

### Module API

#### `OAuth:new(provider_name, config)`

Creates a new OAuth client instance.

- **Parameters:**
  - `provider_name` (string): Provider name (e.g., "anthropic")
  - `config` (table|nil): Optional OAuth configuration overrides

- **Returns:** OAuth instance

#### `OAuth:get_access_token()`

Gets a valid access token, automatically refreshing or re-authenticating if needed.

- **Returns:** (string|nil) Access token or nil on failure

#### `OAuth:authenticate()`

Performs the full OAuth authentication flow (browser + token exchange).

- **Returns:** (string|nil) Access token or nil on failure

#### `OAuth:revoke()`

Revokes and clears stored OAuth tokens.

- **Returns:** (boolean) Success status

## Example Configurations

### Claude Pro Only

```lua
require('parrot').setup({
  providers = {
    anthropic = {
      endpoint = "https://api.anthropic.com/v1/messages",
      model = {
        "claude-sonnet-4-5-20250929",
        "claude-opus-4-6-20250929",
        "claude-haiku-4-5-20251001",
      },
      oauth = {
        enabled = true,
      },
    },
  },
})
```

### Multiple Providers (OAuth + API Key)

```lua
require('parrot').setup({
  providers = {
    -- Claude with OAuth
    anthropic = {
      endpoint = "https://api.anthropic.com/v1/messages",
      model = "claude-sonnet-4-5-20250929",
      oauth = {
        enabled = true,
      },
    },
    -- OpenAI with API key
    openai = {
      endpoint = "https://api.openai.com/v1/chat/completions",
      api_key = os.getenv("OPENAI_API_KEY"),
      model = "gpt-4o",
    },
  },
})
```

## Comparison: OAuth vs API Key

| Feature | OAuth | API Key |
|---------|-------|---------|
| **Setup** | Browser authorization | Environment variable |
| **Security** | Tokens auto-refresh, can be revoked | Static, must be manually rotated |
| **Claude Pro** | ✅ Supported | ❌ Not available |
| **Enterprise** | ✅ Supports SSO | ❌ Individual keys only |
| **Offline** | ❌ Requires initial auth | ✅ Works offline |
| **Portability** | ❌ Machine-specific | ✅ Portable across machines |

## Best Practices

1. **Use OAuth for Claude Pro**: If you have a Claude Pro subscription, OAuth is the only way to use it with parrot.nvim

2. **Secure your token files**: Don't commit or share your OAuth token files (they're automatically in `~/.local/share/nvim/`)

3. **Monitor expiration**: Use `:PrtAuthStatus` to check when tokens will expire

4. **Handle authentication failures gracefully**: Configure an API key fallback for critical workflows

5. **Revoke tokens when changing machines**: Use `:PrtAuthRevoke` before switching to a new machine

6. **Check logs for issues**: Use `:PrtLog` to debug OAuth problems

## FAQ

### Q: Can I use OAuth with multiple Neovim instances?

**A:** Yes, but be aware that token refresh may happen in multiple instances simultaneously. The last instance to refresh will overwrite the token file. This is generally fine as the new token is still valid.

### Q: Do I need a Claude API key if I use OAuth?

**A:** No, OAuth replaces the API key requirement. You can use your Claude Pro subscription without any API key.

### Q: Can I backup my OAuth tokens?

**A:** While you can backup the token files, they're tied to your account and will expire. It's better to just re-authenticate when needed.

### Q: What happens if my refresh token expires?

**A:** parrot.nvim will automatically trigger a new authentication flow (browser prompt) to get new tokens.

### Q: Can I use OAuth in headless/SSH environments?

**A:** OAuth requires a browser, so it's not ideal for headless environments. Consider using API key authentication for servers.

### Q: How do I switch between OAuth and API key?

**A:** Just update your config:

```lua
-- Disable OAuth, use API key
oauth = {
  enabled = false,
},
api_key = os.getenv("ANTHROPIC_API_KEY"),
```

Then restart Neovim or `:source` your config.

## Contributing

If you encounter issues with OAuth or want to add support for additional providers, please open an issue or PR on the GitHub repository.

---

**Related Documentation:**
- [Main README](README.md)
- [Provider Configuration](docs/providers.md)
- [API Reference](docs/api.md)
