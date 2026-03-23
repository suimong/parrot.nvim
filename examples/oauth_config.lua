-- Example parrot.nvim configuration with OAuth authentication
-- This demonstrates how to set up Claude with OAuth (Claude Pro)

require('parrot').setup({
  -- Provider configuration
  providers = {
    -- Anthropic Claude with OAuth (recommended for Claude Pro users)
    anthropic = {
      endpoint = "https://api.anthropic.com/v1/messages",
      -- Models to use
      model = {
        "claude-sonnet-4-5-20250929",   -- Fast and capable
        "claude-opus-4-6-20250929",     -- Most capable
        "claude-haiku-4-5-20251001",    -- Fast and efficient
      },
      -- OAuth configuration - enables authentication via Claude Pro
      oauth = {
        enabled = true,  -- Set to true to use OAuth instead of API key
        -- Optional overrides (usually not needed):
        -- client_id = "9d1c250a-e61b-44d9-88ed-5944d1962f5e",  -- Default Claude OAuth client
        -- scopes = "org:create_api_key user:profile user:inference",
        -- redirect_uri = "http://localhost:9876/callback",
      },
    },

    -- Alternative: Anthropic with API key fallback
    -- anthropic = {
    --   endpoint = "https://api.anthropic.com/v1/messages",
    --   api_key = os.getenv("ANTHROPIC_API_KEY"),  -- Fallback if OAuth fails
    --   model = "claude-sonnet-4-5-20250929",
    --   oauth = {
    --     enabled = true,  -- Try OAuth first
    --   },
    -- },

    -- OpenAI with traditional API key (OAuth not yet supported)
    -- openai = {
    --   endpoint = "https://api.openai.com/v1/chat/completions",
    --   api_key = os.getenv("OPENAI_API_KEY"),
    --   model = "gpt-4o",
    -- },
  },

  -- Optional: Customize OAuth-related settings
  -- (These are general parrot.nvim settings, not OAuth-specific)

  -- Command prefix for all commands
  cmd_prefix = "Prt",

  -- Enable spinner during API calls
  enable_spinner = true,
  spinner_type = "dots",

  -- Chat configuration
  chat_dir = vim.fn.stdpath("data") .. "/parrot/chats",
  chat_user_prefix = "🗨:",
  llm_prefix = "🦜:",

  -- Keyboard shortcuts
  chat_shortcut_respond = { modes = { "n", "i", "v", "x" }, shortcut = "<C-g><C-g>" },
  chat_shortcut_delete = { modes = { "n", "i", "v", "x" }, shortcut = "<C-g>d" },
  chat_shortcut_stop = { modes = { "n", "i", "v", "x" }, shortcut = "<C-g>s" },
  chat_shortcut_new = { modes = { "n", "i", "v", "x" }, shortcut = "<C-g>c" },
})

-- OAuth Usage Examples:
--
-- 1. Start a chat (will trigger OAuth on first use):
--    :PrtChatNew
--    Browser will open automatically for authorization
--
-- 2. Manually authenticate before first use:
--    :PrtAuth anthropic
--
-- 3. Check authentication status:
--    :PrtAuthStatus anthropic
--
-- 4. Revoke tokens (force re-authentication):
--    :PrtAuthRevoke anthropic
--
-- 5. Check all OAuth-enabled providers:
--    :PrtAuthStatus

-- Workflow:
--
-- First time setup:
-- 1. Add the configuration above to your init.lua
-- 2. Restart Neovim
-- 3. Run :PrtChatNew (or any command that uses the LLM)
-- 4. Browser opens to Claude OAuth page
-- 5. Authorize the application
-- 6. Return to Neovim - tokens are now saved
--
-- Subsequent usage:
-- - Tokens are cached and auto-refreshed
-- - No browser prompts unless tokens expire or are revoked
-- - Check status with :PrtAuthStatus anthropic

-- Token Location:
-- ~/.local/share/nvim/parrot/oauth/anthropic-auth.json
-- (Automatically created with secure 0600 permissions)

-- Troubleshooting:
--
-- If OAuth fails:
-- 1. Check logs: :PrtLog
-- 2. Verify Python 3 is installed: python3 --version
-- 3. Check if port 9876 is available: lsof -i :9876
-- 4. Manually revoke and retry: :PrtAuthRevoke anthropic && :PrtAuth anthropic
--
-- If browser doesn't open:
-- 1. Check :PrtLog for the authorization URL
-- 2. Manually open the URL in your browser
-- 3. Complete authorization - tokens will be saved when you see success page
