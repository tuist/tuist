defmodule AtlasWeb.ConnectionsLiveTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Atlas.Audit.Activity
  alias Atlas.Connections.Config
  alias Atlas.Connections.Connection
  alias Atlas.Repo

  setup do
    stub(Config, :credentials, fn _ -> %{client_id: "test-client", client_secret: "test-secret"} end)
    :ok
  end

  test "requires browser sign-in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/settings/connections")
  end

  test "preserves account layout and disconnects only the caller without rendering credentials", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    {_other, other} = log_in_user(build_conn())
    own = insert_connection!(user, "github")
    foreign = insert_connection!(other, "slack")
    {:ok, view, _html} = live(conn, ~p"/settings/connections")
    assert has_element?(view, "#account-layout")
    assert has_element?(view, "#account-general-link[href='/settings']")
    assert has_element?(view, "#account-ai-providers-link[href='/settings/llm-providers']")
    assert has_element?(view, "#account-connections-link [data-selected]")
    assert has_element?(view, "#connection-account-github", "octocat")
    assert has_element?(view, "#connection-connect-google[href='/connections/google/authorize']")
    refute has_element?(view, "#connection-disconnect-slack")
    refute render(view) =~ "private-access"
    refute render(view) =~ "private-refresh"

    view |> element("#connection-disconnect-github") |> render_click()
    refute has_element?(view, "#connection-account-github")
    refute has_element?(view, "#connection-disconnect-github")
    assert Repo.get(Connection, own.id) == nil
    assert Repo.get!(Connection, foreign.id)
    assert Repo.get_by!(Activity, action: "connection.disconnected", target_id: own.id).interface == "dashboard"
  end

  test "unconfigured connections remain visible without unusable consent links", %{conn: conn} do
    stub(Config, :credentials, fn _ -> %{} end)
    {conn, _user} = log_in_user(conn)
    {:ok, view, _html} = live(conn, ~p"/settings/connections")

    for provider <- ~w(github slack google) do
      assert has_element?(view, "#connection-#{provider}")
      refute has_element?(view, "#connection-connect-#{provider}")
    end
  end

  defp insert_connection!(user, provider) do
    %Connection{user_id: user.id, provider: provider}
    |> Connection.changeset(%{
      provider_user_id: "42",
      account_name: "octocat",
      access_token: "private-access",
      refresh_token: "private-refresh"
    })
    |> Repo.insert!()
  end
end
