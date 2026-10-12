defmodule TuistWeb.LiveHooks.PublicPageChallengeTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Phoenix.LiveView.Lifecycle
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

  test "allows the public root and rechecks scope on every patch" do
    socket = overview_socket(:public)
    assert {:cont, socket} = PublicPageChallenge.on_mount(:default, %{}, %{}, socket)
    assert {:cont, _socket} = Lifecycle.handle_params(%{}, "https://tuist.dev/account/project", socket)
    assert {:cont, _socket} = Lifecycle.handle_params(%{}, "https://tuist.dev/account/project?utm_source=slack", socket)

    for path <- [
          "/account/project/analytics",
          "/account/project?analytics-environment=ci",
          "/account/project?builds-date-range=custom",
          "/account/other"
        ] do
      assert {:halt, redirected} = Lifecycle.handle_params(%{}, "https://tuist.dev" <> path, socket)
      assert {:redirect, %{to: to}} = redirected.redirected
      assert to == PublicPageChallengePlug.challenge_path() <> "?return_to=" <> URI.encode_www_form(path)
    end
  end

  test "rejects filtered mounts before layout initialization" do
    params = %{"account_handle" => "account", "project_handle" => "project", "run_id" => Ecto.UUID.generate()}
    assert {:halt, _socket} = PublicPageChallenge.on_mount(:default, params, %{}, overview_socket(:public))
    socket = overview_socket(:public)
    socket = %{socket | assigns: Map.put(socket.assigns, :live_action, :analytics)}
    assert {:halt, _socket} = PublicPageChallenge.on_mount(:default, %{}, %{}, socket)
  end

  test "does not exempt private projects from the connected challenge" do
    assert {:cont, socket} = PublicPageChallenge.on_mount(:default, %{}, %{}, overview_socket(:private))
    assert {:halt, _socket} = Lifecycle.handle_params(%{}, "https://tuist.dev/account/project", socket)
  end

  test "does not exempt public projects behind private-account SSO" do
    socket = overview_socket(:public)
    project = %{socket.assigns.selected_project | account: %{name: "account", visibility: :private, organization_id: 1}}
    socket = %{socket | assigns: %{selected_project: project}}
    organization = %{sso_enforced: true, sso_provider: :okta}
    stub(Accounts, :get_organization_by_id, fn 1, [preload: []] -> {:ok, organization} end)

    assert {:cont, socket} = PublicPageChallenge.on_mount(:default, %{}, %{}, socket)
    assert {:halt, _socket} = Lifecycle.handle_params(%{}, "https://tuist.dev/account/project", socket)
  end

  test "an expired verification only permits the default public root" do
    session = %{PublicPageChallengePlug.session_key() => System.system_time(:second) - 24 * 60 * 60}
    assert {:cont, socket} = PublicPageChallenge.on_mount(:default, %{}, session, overview_socket(:public))
    assert {:cont, _socket} = Lifecycle.handle_params(%{}, "https://tuist.dev/account/project", socket)
    assert {:halt, _socket} = Lifecycle.handle_params(%{}, "https://tuist.dev/account/project/analytics", socket)
  end

  test "halts when the stored timestamp is stale" do
    stale = System.system_time(:second) - 24 * 60 * 60
    session = %{PublicPageChallengePlug.session_key() => stale}

    assert {:halt, _socket} = PublicPageChallenge.on_mount(:default, %{}, session, %Socket{})
  end

  defp overview_socket(visibility) do
    %Socket{
      view: TuistWeb.OverviewLive,
      router: TuistWeb.Router,
      assigns: %{
        selected_project: %{
          visibility: visibility,
          name: "project",
          account: %{name: "account", visibility: :public, organization_id: nil}
        }
      },
      private: %{lifecycle: Lifecycle.build([])}
    }
  end
end
