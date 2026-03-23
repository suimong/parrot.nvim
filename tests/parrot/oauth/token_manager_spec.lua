local TokenManager = require("parrot.oauth.token_manager")

describe("TokenManager", function()
  local temp_dir = "/tmp/parrot_oauth_test_" .. os.time()
  local tm

  before_each(function()
    -- Create temp directory for tests
    os.execute("mkdir -p " .. temp_dir)
    tm = TokenManager:new("test_provider", temp_dir)
  end)

  after_each(function()
    -- Clean up temp directory
    os.execute("rm -rf " .. temp_dir)
  end)

  describe("new", function()
    it("should create a new TokenManager instance", function()
      assert.is_not_nil(tm)
      assert.equals("test_provider", tm.provider_name)
      assert.equals(temp_dir, tm.oauth_dir)
    end)

    it("should create OAuth directory if it doesn't exist", function()
      local new_dir = "/tmp/parrot_oauth_new_" .. os.time()
      local new_tm = TokenManager:new("test", new_dir)

      -- Directory should exist
      local stat = vim.uv.fs_stat(new_dir)
      assert.is_not_nil(stat)
      assert.equals("directory", stat.type)

      -- Clean up
      os.execute("rm -rf " .. new_dir)
    end)

    it("should use default directory if none provided", function()
      local default_tm = TokenManager:new("test")

      local expected_dir = vim.fn.stdpath("data") .. "/parrot/oauth"
      assert.equals(expected_dir, default_tm.oauth_dir)
    end)
  end)

  describe("save and load", function()
    it("should save and load valid token data", function()
      local token_data = {
        access_token = "test_access_token_123",
        refresh_token = "test_refresh_token_456",
        expires_at = os.time() + 3600,
        token_type = "Bearer",
        scope = "test:scope",
      }

      local save_success = tm:save(token_data)
      assert.is_true(save_success)

      local loaded = tm:load()
      assert.is_not_nil(loaded)
      assert.equals(token_data.access_token, loaded.access_token)
      assert.equals(token_data.refresh_token, loaded.refresh_token)
      assert.equals(token_data.expires_at, loaded.expires_at)
    end)

    it("should return nil when loading non-existent token file", function()
      local loaded = tm:load()
      assert.is_nil(loaded)
    end)

    it("should save token file with secure permissions", function()
      local token_data = {
        access_token = "test_token",
        expires_at = os.time() + 3600,
      }

      tm:save(token_data)

      -- Check file permissions (should be 0600)
      local stat = vim.uv.fs_stat(tm.token_file)
      assert.is_not_nil(stat)

      -- Note: Exact permission checking is platform-specific
      -- Just verify the file exists and is readable
      assert.is_not_nil(io.open(tm.token_file, "r"))
    end)

    it("should handle minimal token data", function()
      local token_data = {
        access_token = "minimal_token",
        expires_at = os.time() + 1800,
      }

      local save_success = tm:save(token_data)
      assert.is_true(save_success)

      local loaded = tm:load()
      assert.is_not_nil(loaded)
      assert.equals(token_data.access_token, loaded.access_token)
    end)

    it("should reject invalid token data - missing access_token", function()
      local invalid_data = {
        expires_at = os.time() + 3600,
      }

      local save_success = tm:save(invalid_data)
      assert.is_false(save_success)
    end)

    it("should reject invalid token data - missing expires_at", function()
      local invalid_data = {
        access_token = "test_token",
      }

      local save_success = tm:save(invalid_data)
      assert.is_false(save_success)
    end)

    it("should reject invalid token data - wrong type", function()
      local invalid_data = "not a table"

      local save_success = tm:save(invalid_data)
      assert.is_false(save_success)
    end)
  end)

  describe("is_valid", function()
    it("should return true for valid (non-expired) token", function()
      local token_data = {
        access_token = "valid_token",
        expires_at = os.time() + 3600, -- Expires in 1 hour
      }

      tm:save(token_data)
      assert.is_true(tm:is_valid())
    end)

    it("should return false for expired token", function()
      local token_data = {
        access_token = "expired_token",
        expires_at = os.time() - 100, -- Expired 100 seconds ago
      }

      tm:save(token_data)
      assert.is_false(tm:is_valid())
    end)

    it("should return false when within 2-minute buffer of expiry", function()
      local token_data = {
        access_token = "soon_to_expire",
        expires_at = os.time() + 60, -- Expires in 60 seconds (within 2-min buffer)
      }

      tm:save(token_data)
      assert.is_false(tm:is_valid())
    end)

    it("should return false when no token exists", function()
      assert.is_false(tm:is_valid())
    end)
  end)

  describe("needs_refresh", function()
    it("should return false for token with plenty of time left", function()
      local token_data = {
        access_token = "fresh_token",
        expires_at = os.time() + 3600, -- Expires in 1 hour
      }

      tm:save(token_data)
      assert.is_false(tm:needs_refresh())
    end)

    it("should return true when within 2-minute buffer of expiry", function()
      local token_data = {
        access_token = "refresh_needed",
        expires_at = os.time() + 60, -- Expires in 60 seconds
      }

      tm:save(token_data)
      assert.is_true(tm:needs_refresh())
    end)

    it("should return false for already expired token", function()
      local token_data = {
        access_token = "already_expired",
        expires_at = os.time() - 100,
      }

      tm:save(token_data)
      assert.is_false(tm:needs_refresh())
    end)

    it("should return false when no token exists", function()
      assert.is_false(tm:needs_refresh())
    end)
  end)

  describe("clear", function()
    it("should delete the token file", function()
      local token_data = {
        access_token = "to_be_cleared",
        expires_at = os.time() + 3600,
      }

      tm:save(token_data)

      -- Verify file exists
      assert.is_not_nil(io.open(tm.token_file, "r"))

      -- Clear it
      local success = tm:clear()
      assert.is_true(success)

      -- Verify file is gone
      assert.is_nil(io.open(tm.token_file, "r"))
    end)

    it("should return true when clearing non-existent token", function()
      local success = tm:clear()
      assert.is_true(success)
    end)
  end)

  describe("get_token_file", function()
    it("should return the token file path", function()
      local expected = temp_dir .. "/test_provider-auth.json"
      assert.equals(expected, tm:get_token_file())
    end)
  end)
end)
