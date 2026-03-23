local pkce = require("parrot.oauth.pkce")

describe("pkce", function()
  describe("base64url_encode", function()
    it("should encode data to base64url format", function()
      local data = "Hello, World!"
      local encoded = pkce.base64url_encode(data)

      -- Should not contain +, /, or =
      assert.is_nil(encoded:match("[+/=]"))

      -- Should be non-empty
      assert.is_true(#encoded > 0)
    end)

    it("should handle binary data", function()
      local data = "\0\1\2\3\4\5"
      local encoded = pkce.base64url_encode(data)

      -- Should be base64url (no +/=)
      assert.is_nil(encoded:match("[+/=]"))
    end)
  end)

  describe("generate_verifier", function()
    it("should generate a 128-character verifier", function()
      local verifier = pkce.generate_verifier()

      assert.is_not_nil(verifier)
      assert.equals(128, #verifier)
    end)

    it("should generate unique verifiers", function()
      local verifier1 = pkce.generate_verifier()
      local verifier2 = pkce.generate_verifier()

      assert.is_not_nil(verifier1)
      assert.is_not_nil(verifier2)
      assert.is_not.equals(verifier1, verifier2)
    end)

    it("should generate URL-safe characters", function()
      local verifier = pkce.generate_verifier()

      -- Should only contain base64url characters
      local pattern = "^[A-Za-z0-9_-]+$"
      assert.is_not_nil(verifier:match(pattern))
    end)
  end)

  describe("generate_challenge", function()
    it("should generate a valid challenge from a verifier", function()
      local verifier = "test_verifier_123456789012345678901234567890"
      local challenge = pkce.generate_challenge(verifier)

      assert.is_not_nil(challenge)
      assert.is_true(#challenge > 0)

      -- Should not contain +, /, or =
      assert.is_nil(challenge:match("[+/=]"))
    end)

    it("should generate the same challenge for the same verifier", function()
      local verifier = "consistent_verifier_12345678901234567890"
      local challenge1 = pkce.generate_challenge(verifier)
      local challenge2 = pkce.generate_challenge(verifier)

      assert.equals(challenge1, challenge2)
    end)

    it("should generate different challenges for different verifiers", function()
      local verifier1 = "verifier_one_123456789012345678901234567890"
      local verifier2 = "verifier_two_123456789012345678901234567890"

      local challenge1 = pkce.generate_challenge(verifier1)
      local challenge2 = pkce.generate_challenge(verifier2)

      assert.is_not.equals(challenge1, challenge2)
    end)

    it("should return nil for empty verifier", function()
      local challenge = pkce.generate_challenge("")

      assert.is_nil(challenge)
    end)

    it("should return nil for nil verifier", function()
      local challenge = pkce.generate_challenge(nil)

      assert.is_nil(challenge)
    end)
  end)

  describe("generate_pair", function()
    it("should generate both verifier and challenge", function()
      local pair = pkce.generate_pair()

      assert.is_not_nil(pair)
      assert.is_not_nil(pair.verifier)
      assert.is_not_nil(pair.challenge)
      assert.equals(128, #pair.verifier)
    end)

    it("should generate valid PKCE pairs", function()
      local pair = pkce.generate_pair()

      -- Verify challenge matches verifier
      local expected_challenge = pkce.generate_challenge(pair.verifier)
      assert.equals(expected_challenge, pair.challenge)
    end)

    it("should generate unique pairs", function()
      local pair1 = pkce.generate_pair()
      local pair2 = pkce.generate_pair()

      assert.is_not.equals(pair1.verifier, pair2.verifier)
      assert.is_not.equals(pair1.challenge, pair2.challenge)
    end)
  end)
end)
