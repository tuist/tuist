defmodule TuistWeb.TurnstileTest do
  use ExUnit.Case, async: true

  alias TuistWeb.Turnstile

  test "accepts a successful verification for the expected action" do
    request = fn endpoint, options ->
      assert endpoint == "https://challenges.cloudflare.com/turnstile/v0/siteverify"
      assert options[:form] == %{secret: "secret", response: "token"}

      {:ok,
       %Req.Response{
         status: 200,
         body: %{"success" => true, "action" => "email_signup", "hostname" => "tuist.dev"}
       }}
    end

    assert :ok =
             Turnstile.verify("token",
               required?: true,
               secret_key: "secret",
               expected_action: "email_signup",
               expected_hostname: "tuist.dev",
               request: request
             )
  end

  test "rejects a token issued for a different action" do
    request = fn _endpoint, _options ->
      {:ok, %Req.Response{status: 200, body: %{"success" => true, "action" => "oauth_signup"}}}
    end

    assert {:error, :rejected} =
             Turnstile.verify("token",
               required?: true,
               secret_key: "secret",
               expected_action: "email_signup",
               expected_hostname: "tuist.dev",
               request: request
             )
  end

  test "rejects a token issued for a different hostname" do
    request = fn _endpoint, _options ->
      {:ok,
       %Req.Response{
         status: 200,
         body: %{"success" => true, "action" => "email_signup", "hostname" => "canary.tuist.dev"}
       }}
    end

    assert {:error, :rejected} =
             Turnstile.verify("token",
               required?: true,
               secret_key: "secret",
               expected_action: "email_signup",
               expected_hostname: "tuist.dev",
               request: request
             )
  end

  test "does not call the verifier without a token" do
    assert {:error, :missing_token} =
             Turnstile.verify(nil,
               required?: true,
               secret_key: "secret",
               request: fn _endpoint, _options -> flunk("must not verify a missing token") end
             )
  end

  test "fails closed when the verification service is unavailable" do
    assert {:error, :unavailable} =
             Turnstile.verify("token",
               required?: true,
               secret_key: "secret",
               request: fn _endpoint, _options -> {:error, :timeout} end
             )
  end
end
