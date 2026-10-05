defmodule Tuist.MCP.EventsTest do
  use ExUnit.Case, async: true
  use Mimic

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.MCP.Events
  alias Tuist.MCP.Events.Callback
  alias Tuist.MCP.Events.Subscription
  alias Tuist.MCP.Events.Workers.DeliveryWorker
  alias Tuist.MCP.Events.Workers.FanoutWorker
  alias Tuist.OAuth.Clients
  alias Tuist.OAuth2.SSRFGuard
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

  test "a published flaky test event reaches the signed callback" do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account: user.account)

    token =
      AccountsFixtures.account_token_fixture(account: user.account, scopes: ["project:tests:read"])

    subscription =
      %Subscription{}
      |> Subscription.changeset(%{
        id: "sub_" <> Ecto.UUID.generate(),
        user_id: user.id,
        account_token_id: token.id,
        project_id: project.id,
        event_name: "test_case.marked_flaky",
        callback_url: "https://example.com/events",
        signing_secret: "whsec_" <> Base.encode64(:crypto.strong_rand_bytes(32)),
        refresh_before: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)
      })
      |> Repo.insert!()

    test_case_id = Ecto.UUID.generate()
    source_id = Ecto.UUID.generate()

    assert :ok = Events.publish_marked_flaky(project.id, test_case_id, source_id)

    fanout_job = Repo.one!(from job in Oban.Job, where: job.worker == ^inspect(FanoutWorker))
    assert :ok = FanoutWorker.perform(fanout_job)

    delivery_job = Repo.one!(from job in Oban.Job, where: job.worker == ^inspect(DeliveryWorker))

    expect(SSRFGuard, :pin, fn "https://example.com/events" ->
      {:ok, "https://203.0.113.10/events", "example.com"}
    end)

    expect(SSRFGuard, :connect_options, fn "example.com" -> [] end)

    expect(Req, :post, fn "https://203.0.113.10/events", options ->
      headers = Map.new(options[:headers])
      body = options[:body]

      assert headers["x-mcp-subscription-id"] == subscription.id
      assert headers["webhook-id"] == delivery_job.args["event_id"]

      assert headers["webhook-signature"] ==
               Callback.sign(headers["webhook-id"], headers["webhook-timestamp"], body, subscription.signing_secret)

      assert %{"name" => "test_case.marked_flaky", "data" => %{"test_case_id" => ^test_case_id}} =
               JSON.decode!(body)

      {:ok, %Req.Response{status: 200}}
    end)

    assert :ok = DeliveryWorker.perform(delivery_job)
  end
end
