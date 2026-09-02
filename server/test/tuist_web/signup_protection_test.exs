defmodule TuistWeb.SignupProtectionTest do
  use ExUnit.Case, async: true
  use Mimic

  alias TuistWeb.RateLimit.Registration
  alias TuistWeb.SignupProtection
  alias TuistWeb.Turnstile

  test "checks the session rate limit before sending a token for verification" do
    stub(Turnstile, :required?, fn -> true end)
    expect(Registration, :hit, fn "session-token" -> {:deny, 0} end)
    reject(&Turnstile.verify/2)

    assert {:error, :rate_limited} = SignupProtection.verify("session-token", %{}, "email_signup")
  end

  test "binds a successful verification to the registration action" do
    stub(Turnstile, :required?, fn -> true end)
    expect(Registration, :hit, fn "session-token" -> {:allow, 2} end)

    expect(Turnstile, :verify, fn "token", [expected_action: "oauth_signup"] ->
      :ok
    end)

    assert :ok = SignupProtection.verify("session-token", %{"cf-turnstile-response" => "token"}, "oauth_signup")
  end

  test "does not add friction when the hosted protection switch is off" do
    stub(Turnstile, :required?, fn -> false end)
    reject(&Registration.hit/1)
    reject(&Turnstile.verify/2)

    assert :ok = SignupProtection.verify("session-token", %{}, "email_signup")
  end
end
