defmodule Slack.CaptchaTest do
  use ExUnit.Case, async: false

  alias Slack.Captcha

  setup do
    original = Application.get_env(:slack, :captcha)
    on_exit(fn -> Application.put_env(:slack, :captcha, original) end)
    :ok
  end

  describe "enabled?/0" do
    test "is false when no secret key is set" do
      Application.put_env(:slack, :captcha, site_key: nil, secret_key: nil)
      refute Captcha.enabled?()
    end

    test "is true when a secret key is configured" do
      Application.put_env(:slack, :captcha, site_key: "site", secret_key: "secret")
      assert Captcha.enabled?()
    end
  end

  describe "verify/2" do
    test "short-circuits to :ok when the captcha is disabled" do
      Application.put_env(:slack, :captcha, site_key: nil, secret_key: nil)
      assert Captcha.verify("any-token") == :ok
    end

    test "returns {:error, :missing_token} when no token is provided" do
      Application.put_env(:slack, :captcha, site_key: "site", secret_key: "secret")
      assert Captcha.verify(nil) == {:error, :missing_token}
      assert Captcha.verify("") == {:error, :missing_token}
    end
  end
end
