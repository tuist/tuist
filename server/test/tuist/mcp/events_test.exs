defmodule Tuist.MCP.EventsTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.MCP.Events
  alias Tuist.MCP.Events.Callback
  alias Tuist.MCP.Events.Subscription
  alias Tuist.OAuth.Clients
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup :set_mimic_from_context

  setup do
    owner = Sandbox.start_owner!(Repo, shared: false)
    on_exit(fn -> Sandbox.stop_owner(owner) end)
    :ok
  end

  test "a browser-authorized user can subscribe, refresh, and unsubscribe" do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account: user.account)

    {:ok, client} =
      Clients.create_client(%{redirect_uris: ["https://example.com/callback"], name: "events-test-client"})

    claims = %{
      "type" => "account",
      "user_id" => user.id,
      "client_id" => client.id,
      "scopes" => ["project:tests:read"],
      "all_projects" => true
    }

    {:ok, token, _claims} =
      Tuist.Guardian.encode_and_sign(user.account, claims, token_type: "access_token", ttl: {1, :hour})

    subject = %AuthenticatedAccount{
      account: user.account,
      scopes: ["project:tests:read"],
      all_projects: true,
      issued_by: user
    }

    conn =
      :post
      |> Phoenix.ConnTest.build_conn("/mcp")
      |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
      |> Plug.Conn.assign(:current_subject, subject)

    params = %{
      "name" => "test_case.marked_flaky",
      "arguments" => %{"account_handle" => user.account.name, "project_handle" => project.name},
      "delivery" => %{
        "mode" => "webhook",
        "url" => "https://example.com/events",
        "secret" => "whsec_" <> Base.encode64(:crypto.strong_rand_bytes(32))
      }
    }

    expect(Callback, :verify, 2, fn "https://example.com/events", _secret, _id -> :ok end)

    assert {:ok, %{"id" => id}} = Events.subscribe(conn, params)
    assert %Subscription{oauth_client_id: client_id, account_token_id: nil} = Repo.get!(Subscription, id)
    assert client_id == client.id

    assert {:ok, %{"id" => ^id}} = Events.subscribe(conn, params)
    assert {:ok, %{}} = Events.unsubscribe(conn, params)
    assert Repo.get(Subscription, id) == nil
    assert {:ok, %{}} = Events.unsubscribe(conn, params)
  end
end
