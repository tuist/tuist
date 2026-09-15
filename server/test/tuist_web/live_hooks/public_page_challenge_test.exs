defmodule TuistWeb.LiveHooks.PublicPageChallengeTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Phoenix.LiveView.Socket
  alias Tuist.Accounts
  alias Tuist.FeatureFlags
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.LiveHooks.PublicPageChallenge
  alias TuistWeb.Plugs.PublicPageChallengePlug

  setup do
    stub(FeatureFlags, :public_page_challenge_enabled?, fn -> true end)
    :ok
  end

  test "continues when the feature flag is off" do
    stub(FeatureFlags, :public_page_challenge_enabled?, fn -> false end)
    assert {:cont, socket} = PublicPageChallenge.on_mount(:default, %{}, %{}, %Socket{})
    assert socket == %Socket{}
  end

  test "continues when the visitor is signed in" do
    user = AccountsFixtures.user_fixture()
    token = Accounts.generate_user_session_token(user)
    stub(Accounts, :get_user_by_session_token, fn ^token -> user end)

    assert {:cont, _socket} =
             PublicPageChallenge.on_mount(:default, %{}, %{"user_token" => token}, %Socket{})
  end

  test "continues when the session has a fresh verification timestamp" do
    session = %{PublicPageChallengePlug.session_key() => System.system_time(:second)}
    assert {:cont, _socket} = PublicPageChallenge.on_mount(:default, %{}, session, %Socket{})
  end

  test "halts and redirects when the session is anonymous and unverified" do
    assert {:halt, socket} = PublicPageChallenge.on_mount(:default, %{}, %{}, %Socket{})
    assert socket.redirected == {:redirect, %{to: PublicPageChallengePlug.challenge_path(), status: 302}}
  end

  test "halts when a forged session token does not resolve to a user" do
    stub(Accounts, :get_user_by_session_token, fn _ -> nil end)

    assert {:halt, _socket} =
             PublicPageChallenge.on_mount(:default, %{}, %{"user_token" => "forged"}, %Socket{})
  end

  test "halts when the stored timestamp is stale" do
    stale = System.system_time(:second) - 24 * 60 * 60
    session = %{PublicPageChallengePlug.session_key() => stale}

    assert {:halt, _socket} = PublicPageChallenge.on_mount(:default, %{}, session, %Socket{})
  end
end
