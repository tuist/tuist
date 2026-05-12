defmodule Tuist.Webhooks.SignatureTest do
  use ExUnit.Case, async: true

  alias Tuist.Webhooks.Signature

  describe "sign/3" do
    test "is deterministic for the same payload, secret, and timestamp" do
      header = Signature.sign(~s({"hello":"world"}), "whsec_test", 1_700_000_000)
      assert header == Signature.sign(~s({"hello":"world"}), "whsec_test", 1_700_000_000)
    end

    test "encodes the timestamp and scheme in the expected format" do
      assert "t=1700000000,v1=" <> sig = Signature.sign("body", "whsec_test", 1_700_000_000)
      assert String.length(sig) == 64
    end
  end

  describe "verify/4" do
    test "accepts a freshly signed payload" do
      now = System.system_time(:second)
      header = Signature.sign("body", "whsec_test", now)
      assert :ok = Signature.verify("body", header, "whsec_test", now: now)
    end

    test "rejects a tampered payload" do
      now = System.system_time(:second)
      header = Signature.sign("body", "whsec_test", now)
      assert {:error, :signature_mismatch} = Signature.verify("tampered", header, "whsec_test", now: now)
    end

    test "rejects a payload signed with the wrong secret" do
      now = System.system_time(:second)
      header = Signature.sign("body", "whsec_test", now)
      assert {:error, :signature_mismatch} = Signature.verify("body", header, "whsec_other", now: now)
    end

    test "rejects a timestamp older than the tolerance" do
      now = System.system_time(:second)
      old_ts = now - 1_000
      header = Signature.sign("body", "whsec_test", old_ts)

      assert {:error, :timestamp_outside_tolerance} =
               Signature.verify("body", header, "whsec_test", now: now, tolerance_seconds: 300)
    end

    test "rejects a malformed header" do
      assert {:error, :invalid_header} = Signature.verify("body", "not-a-real-header", "whsec_test")
      assert {:error, :invalid_header} = Signature.verify("body", "t=abc,v1=def", "whsec_test")
    end
  end

  describe "generate_secret/0" do
    test "returns a whsec-prefixed string and is non-deterministic" do
      secret = Signature.generate_secret()
      assert String.starts_with?(secret, "whsec_")
      # 32 random bytes → base64url without padding = 43 chars; plus "whsec_" prefix.
      assert byte_size(secret) >= 49
      assert secret != Signature.generate_secret()
    end
  end
end
