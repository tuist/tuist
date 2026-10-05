defmodule Tuist.MCP.EventsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import Ecto.Query

  alias Tuist.Accounts.AgentRegistration
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Bazel
  alias Tuist.MCP.Events
  alias Tuist.MCP.Events.Callback
  alias Tuist.MCP.Events.Subscription
  alias Tuist.MCP.Events.Workers.DeliveryWorker
  alias Tuist.MCP.Events.Workers.FanoutWorker
  alias Tuist.MCP.Events.Workers.PruneExpiredSubscriptionsWorker
  alias Tuist.OAuth.Clients
  alias Tuist.OAuth2.SSRFGuard
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.GradleFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  setup :set_mimic_from_context

  defp claimed_token_fixture(user) do
    token = AccountsFixtures.account_token_fixture(account: user.account, scopes: ["mcp"])

    Repo.insert!(%AgentRegistration{
      registration_type: :agent_provider,
      status: :claimed,
      requested_credential_type: :api_key,
      claim_token_hash: :crypto.strong_rand_bytes(32),
      claim_token_expires_at: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second),
      claimed_at: DateTime.truncate(DateTime.utc_now(), :second),
      claimed_by_user_id: user.id,
      account_token_id: token.id
    })

    token
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

  test "an agent can subscribe to each failure event with the required scope" do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account: user.account)
    token = claimed_token_fixture(user)

    subject = %AuthenticatedAccount{
      account: user.account,
      scopes: token.scopes,
      all_projects: true,
      token_id: token.id
    }

    conn =
      :post
      |> Phoenix.ConnTest.build_conn("/mcp")
      |> Plug.Conn.assign(:current_subject, subject)
      |> Plug.Conn.assign(:current_user, user)

    expect(Callback, :verify, 3, fn "https://example.com/events", _secret, _id -> :ok end)

    for name <- ["build.failed", "test_run.failed", "ci_job.failed"] do
      arguments =
        if name == "ci_job.failed" do
          %{"account_handle" => user.account.name}
        else
          %{"account_handle" => user.account.name, "project_handle" => project.name}
        end

      assert {:ok, %{"id" => id}} =
               Events.subscribe(conn, %{
                 "name" => name,
                 "arguments" => arguments,
                 "delivery" => %{
                   "mode" => "webhook",
                   "url" => "https://example.com/events",
                   "secret" => "whsec_" <> Base.encode64(:crypto.strong_rand_bytes(32))
                 }
               })

      assert %Subscription{event_name: ^name, account_id: account_id} = Repo.get!(Subscription, id)
      assert account_id == user.account.id
    end
  end

  test "a built-in OAuth client keeps delivery after its access token expires" do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account: user.account)
    static_client_id = Ecto.UUID.generate()
    stub(Tuist.Environment, :oauth_client_id, fn -> static_client_id end)
    client = Clients.public!()

    claims = %{
      "type" => "account",
      "user_id" => user.id,
      "client_id" => client.id,
      "scopes" => ["project:builds:read"],
      "all_projects" => true
    }

    {:ok, bearer, _claims} =
      Tuist.Guardian.encode_and_sign(user.account, claims, token_type: "access_token", ttl: {1, :hour})

    subject = %AuthenticatedAccount{
      account: user.account,
      scopes: ["project:builds:read"],
      all_projects: true,
      issued_by: user
    }

    conn =
      :post
      |> Phoenix.ConnTest.build_conn("/mcp")
      |> Plug.Conn.put_req_header("authorization", "Bearer #{bearer}")
      |> Plug.Conn.assign(:current_subject, subject)

    Repo.insert!(%Boruta.Ecto.Token{
      type: "access_token",
      value: Ecto.UUID.generate(),
      refresh_token: Ecto.UUID.generate(),
      client_id: client.id,
      sub: to_string(user.id),
      scope: "project:builds:read",
      expires_at: System.system_time(:second) - 60
    })

    expect(Callback, :verify, fn _url, _secret, _id -> :ok end)

    assert {:ok, %{"id" => id}} =
             Events.subscribe(conn, %{
               "name" => "build.failed",
               "arguments" => %{"account_handle" => user.account.name, "project_handle" => project.name},
               "delivery" => %{
                 "mode" => "webhook",
                 "url" => "https://example.com/events",
                 "secret" => "whsec_" <> Base.encode64(:crypto.strong_rand_bytes(32))
               }
             })

    assert %Subscription{oauth_client_id: client_id} = Repo.get!(Subscription, id)
    assert client_id == client.id

    assert :ok = Events.publish_failed_build(project.id, "xcode", Ecto.UUID.generate())
    fanout_job = Repo.one!(from job in Oban.Job, where: job.worker == ^inspect(FanoutWorker))
    assert :ok = FanoutWorker.perform(fanout_job)

    stub(SSRFGuard, :pin, fn _url -> {:ok, "https://203.0.113.10/events", "example.com"} end)
    stub(SSRFGuard, :connect_options, fn _host -> [] end)
    expect(Req, :post, fn _url, _options -> {:ok, %Req.Response{status: 200}} end)

    delivery_job = Repo.one!(from job in Oban.Job, where: job.worker == ^inspect(DeliveryWorker))
    assert :ok = DeliveryWorker.perform(delivery_job)
  end

  test "a published flaky test event reaches the signed callback" do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account: user.account)

    token = claimed_token_fixture(user)

    subscription =
      %Subscription{}
      |> Subscription.changeset(%{
        id: "sub_" <> Ecto.UUID.generate(),
        user_id: user.id,
        account_token_id: token.id,
        account_id: user.account.id,
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

  test "failed builds, test runs, and runner jobs reach signed callbacks" do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account: user.account)

    token = claimed_token_fixture(user)

    secret = "whsec_" <> Base.encode64(:crypto.strong_rand_bytes(32))

    for name <- ["build.failed", "test_run.failed", "ci_job.failed"] do
      %Subscription{}
      |> Subscription.changeset(%{
        id: "sub_#{name}",
        user_id: user.id,
        account_token_id: token.id,
        account_id: user.account.id,
        project_id: if(name == "ci_job.failed", do: nil, else: project.id),
        event_name: name,
        callback_url: "https://example.com/events",
        signing_secret: secret,
        refresh_before: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)
      })
      |> Repo.insert!()
    end

    build_id = Ecto.UUID.generate()
    test_run_id = Ecto.UUID.generate()

    assert :ok = Events.publish_failed_build(project.id, "xcode", build_id)
    assert :ok = Events.publish_failed_test_run(project.id, test_run_id)
    assert :ok = Events.publish_failed_ci_job(user.account.id, 42, 123)

    fanout_jobs = Repo.all(from job in Oban.Job, where: job.worker == ^inspect(FanoutWorker))
    assert length(fanout_jobs) == 3
    Enum.each(fanout_jobs, fn job -> assert :ok = FanoutWorker.perform(job) end)

    delivery_jobs = Repo.all(from job in Oban.Job, where: job.worker == ^inspect(DeliveryWorker))
    assert length(delivery_jobs) == 3

    stub(SSRFGuard, :pin, fn "https://example.com/events" ->
      {:ok, "https://203.0.113.10/events", "example.com"}
    end)

    stub(SSRFGuard, :connect_options, fn "example.com" -> [] end)

    expect(Req, :post, 3, fn "https://203.0.113.10/events", options ->
      headers = Map.new(options[:headers])
      body = options[:body]

      assert headers["webhook-signature"] ==
               Callback.sign(headers["webhook-id"], headers["webhook-timestamp"], body, secret)

      send(self(), {:delivered, JSON.decode!(body)})
      {:ok, %Req.Response{status: 200}}
    end)

    Enum.each(delivery_jobs, fn job -> assert :ok = DeliveryWorker.perform(job) end)

    delivered =
      for _ <- 1..3,
          do:
            (
              assert_receive {:delivered, body}
              body
            )

    assert Enum.sort(Enum.map(delivered, & &1["name"])) == ["build.failed", "ci_job.failed", "test_run.failed"]

    assert Enum.any?(delivered, fn body ->
             body["name"] == "build.failed" and body["data"]["build_id"] == build_id and
               body["data"]["build_system"] == "xcode"
           end)

    assert Enum.any?(delivered, fn body ->
             body["name"] == "test_run.failed" and body["data"]["test_run_id"] == test_run_id
           end)

    assert Enum.any?(delivered, fn body ->
             body["name"] == "ci_job.failed" and body["data"]["workflow_job_id"] == 123 and
               body["data"]["workflow_run_id"] == 42
           end)
  end

  test "failed build and test ingestion queues events for the owning project" do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account: user.account)

    for name <- ["build.failed", "test_run.failed"] do
      %Subscription{}
      |> Subscription.changeset(%{
        id: "sub_ingestion_#{name}",
        user_id: user.id,
        account_token_id: claimed_token_fixture(user).id,
        account_id: user.account.id,
        project_id: project.id,
        event_name: name,
        callback_url: "https://example.com/events",
        signing_secret: "whsec_" <> Base.encode64(:crypto.strong_rand_bytes(32)),
        refresh_before: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)
      })
      |> Repo.insert!()
    end

    {:ok, xcode_build} =
      RunsFixtures.build_fixture(project_id: project.id, status: "failure")

    gradle_build_id =
      GradleFixtures.build_fixture(project_id: project.id, account_id: user.account.id, status: "failure")

    bazel_invocation_id = Ecto.UUID.generate()

    Bazel.create_invocations([
      %{
        invocation_id: bazel_invocation_id,
        command: "build",
        status: "failure",
        exit_code: 1,
        started_at: ~N[2026-10-05 10:00:00],
        finished_at: ~N[2026-10-05 10:00:01],
        duration_ms: 1000,
        project_id: project.id,
        account_handle: user.account.name,
        project_handle: project.name,
        cache_endpoint: "cache.tuist.dev"
      }
    ])

    {:ok, test_run} =
      RunsFixtures.test_fixture(project_id: project.id, account_id: user.account.id, status: "failure")

    args = Repo.all(from(job in Oban.Job, where: job.worker == ^inspect(FanoutWorker), select: job.args))

    assert Enum.any?(args, &(&1["event_name"] == "build.failed" and &1["build_id"] == xcode_build.id))
    assert Enum.any?(args, &(&1["event_name"] == "build.failed" and &1["build_id"] == gradle_build_id))
    assert Enum.any?(args, &(&1["event_name"] == "build.failed" and &1["build_id"] == bazel_invocation_id))
    assert Enum.any?(args, &(&1["event_name"] == "test_run.failed" and &1["test_run_id"] == test_run.id))
    assert Enum.all?(args, &(&1["project_id"] == project.id))
  end

  test "failures without a subscription do not queue fan-out" do
    project_id = ProjectsFixtures.project_fixture().id
    build_id = Ecto.UUID.generate()

    assert :ok = Events.publish_failed_build(project_id, "xcode", build_id)

    refute Repo.exists?(from job in Oban.Job, where: job.worker == ^inspect(FanoutWorker))
  end

  test "a revoked agent claim stops delivery" do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account: user.account)
    token = claimed_token_fixture(user)

    subscription =
      %Subscription{}
      |> Subscription.changeset(%{
        id: "sub_revoked_#{Ecto.UUID.generate()}",
        user_id: user.id,
        account_token_id: token.id,
        account_id: user.account.id,
        project_id: project.id,
        event_name: "build.failed",
        callback_url: "https://example.com/events",
        signing_secret: "whsec_" <> Base.encode64(:crypto.strong_rand_bytes(32)),
        refresh_before: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)
      })
      |> Repo.insert!()

    assert :ok = Events.publish_failed_build(project.id, "xcode", Ecto.UUID.generate())
    fanout_job = Repo.one!(from job in Oban.Job, where: job.worker == ^inspect(FanoutWorker))
    assert :ok = FanoutWorker.perform(fanout_job)

    Repo.update_all(from(registration in AgentRegistration, where: registration.account_token_id == ^token.id),
      set: [status: :revoked]
    )

    delivery_job = Repo.one!(from job in Oban.Job, where: job.worker == ^inspect(DeliveryWorker))
    assert :ok = DeliveryWorker.perform(delivery_job)
    assert Repo.get(Subscription, subscription.id) == nil
  end

  test "expired subscriptions are removed after a day" do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account: user.account)
    token = claimed_token_fixture(user)

    for {id, offset} <- [{"expired", -2 * 24 * 3600}, {"active", 3600}] do
      %Subscription{}
      |> Subscription.changeset(%{
        id: "sub_#{id}_#{Ecto.UUID.generate()}",
        user_id: user.id,
        account_token_id: token.id,
        account_id: user.account.id,
        project_id: project.id,
        event_name: "build.failed",
        callback_url: "https://example.com/events",
        signing_secret: "whsec_" <> Base.encode64(:crypto.strong_rand_bytes(32)),
        refresh_before: DateTime.utc_now() |> DateTime.add(offset, :second) |> DateTime.truncate(:second)
      })
      |> Repo.insert!()
    end

    assert :ok = PruneExpiredSubscriptionsWorker.perform(%Oban.Job{})
    assert Repo.aggregate(Subscription, :count, :id) == 1
    assert Repo.one!(from s in Subscription, select: s.id) =~ "sub_active_"
  end
end
