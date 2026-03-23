# OAuth Quick Start Guide

Get up and running with Claude Pro OAuth in parrot.nvim in under 2 minutes.

## Prerequisites

- ✅ Neovim >= 0.10
- ✅ Python 3 (for OAuth callback server)
- ✅ Claude Pro account (or other OAuth-enabled provider)
- ✅ parrot.nvim installed

## Step 1: Configuration (30 seconds)

Add this to your Neovim config:

```lua
require('parrot').setup({
  providers = {
    anthropic = {
      endpoint = "https://api.anthropic.com/v1/messages",
      model = "claude-sonnet-4-5-20250929",
      oauth = {
        enabled = true,  -- That's it!
      },
    },
  },
})
```

**Note:** No `api_key` needed when using OAuth!

## Step 2: Restart Neovim (10 seconds)

```bash
# Close and reopen Neovim
```

## Step 3: First Authentication (60 seconds)

Trigger any command that uses the LLM:

```vim
:PrtChatNew
```

**What happens:**
1. Browser opens to Claude OAuth page
2. You log in with your Claude Pro account
3. Click "Authorize"
4. Browser shows success message
5. Return to Neovim - you're authenticated!

## Step 4: Verify It Works (10 seconds)

Check authentication status:

```vim
:PrtAuthStatus anthropic
```

Expected output:
```
anthropic OAuth status: Valid
Expires in: 3600 seconds (2026-03-23 15:30:00)
Refresh token: Available
```

## Done! 🎉

Now you can use all parrot.nvim commands with your Claude Pro account:

- `:PrtChatNew` - Start a new chat
- `:PrtRewrite` - Rewrite selected text
- `:PrtAppend` - Append to selection
- `:PrtImplement` - Implement based on comments

Tokens are automatically refreshed - no more manual authentication needed!

---

## Useful Commands

### Check Status
```vim
:PrtAuthStatus          # All providers
:PrtAuthStatus anthropic  # Specific provider
```

### Re-authenticate
```vim
:PrtAuth anthropic
```

### Clear Tokens (force re-auth next time)
```vim
:PrtAuthRevoke anthropic
```

---

## Troubleshooting

### Browser doesn't open?

1. Check logs:
   ```vim
   :PrtLog
   ```

2. Look for the authorization URL and open it manually in your browser

### Port 9876 in use?

```bash
# Find what's using the port
lsof -i :9876

# Kill the process or wait for it to finish
```

### Python not found?

Install Python 3:
```bash
# Ubuntu/Debian
sudo apt install python3

# macOS
brew install python3
```

---

## Next Steps

- **Read the full guide:** [OAUTH.md](OAUTH.md)
- **See examples:** [examples/oauth_config.lua](examples/oauth_config.lua)
- **Check technical details:** [OAUTH_IMPLEMENTATION_SUMMARY.md](OAUTH_IMPLEMENTATION_SUMMARY.md)

---

## Compare: OAuth vs API Key

| | OAuth | API Key |
|---|---|---|
| **Setup time** | 60 seconds | Varies |
| **Claude Pro** | ✅ Works | ❌ Not available |
| **Auto-refresh** | ✅ Yes | N/A |
| **Browser needed** | Once (first time) | Never |
| **Best for** | Claude Pro users | Traditional API users |

---

**Need help?** Check the [FAQ in OAUTH.md](OAUTH.md#faq) or open an issue!
