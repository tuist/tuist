defmodule Tuist.MCP.EventsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import Ecto.Query

  alias Boruta.Ecto.Token
  alias Tuist.Accounts.AgentAuthCredential
  alias Tuist.Accounts.AgentRegistration
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Bazel
  alias Tuist.MCP.Events
  alias Tuist.MCP.Events.Callback
  alias Tuist.MCP.Events.Publisher
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
  alias TuistWeb.AuthenticationPlug

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

    Repo.insert!(%Token{
      type: "access_token",
      value: token,
      refresh_token: Ecto.UUID.generate(),
      client_id: client.id,
      sub: to_string(user.id),
      scope: "project:tests:read"
    })

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
      "ttlMs" => 1,
      "arguments" => %{"account_handle" => user.account.name, "project_handle" => project.name},
      "delivery" => %{
        "mode" => "webhook",
        "url" => "https://example.com/events",
        "secret" => "whsec_" <> Base.encode64(:crypto.strong_rand_bytes(32))
      }
    }

    expect(Callback, :verify, 2, fn "https://example.com/events", _secret, _id -> :ok end)

    assert {:ok, %{"id" => id, "refreshBefore" => refresh_before}} = Events.subscribe(conn, params)
    assert {:ok, refresh_before, _offset} = DateTime.from_iso8601(refresh_before)
    assert DateTime.diff(refresh_before, DateTime.utc_now()) > 3500
    assert %Subscription{oauth_client_id: client_id, account_token_id: nil} = Repo.get!(Subscription, id)
    assert client_id == client.id

    assert {:ok, %{"id" => ^id}} = Events.subscribe(conn, params)
    assert {:ok, %{}} = Events.unsubscribe(conn, params)
    assert Repo.get(Subscription, id) == nil
    assert {:ok, %{}} = Events.unsubscribe(conn, params)
  end

  test "a claimed auth.md agent can subscribe and keeps delivery across token rotation" do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account: user.account)

    registration =
      Repo.insert!(%AgentRegistration{
        registration_type: :anonymous,
        status: :claimed,
        requested_credential_type: :access_token,
        claim_token_hash: :crypto.strong_rand_bytes(32),
        claim_token_expires_at: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second),
        claimed_at: DateTime.truncate(DateTime.utc_now(), :second),
        claimed_by_user_id: user.id
      })

    issue_token = fn ->
      {:ok, bearer, claims} =
        Tuist.Guardian.encode_and_sign(
          user.account,
          %{
            "type" => "account",
            "user_id" => user.id,
            "agent_registration_id" => registration.id,
            "scopes" => ["mcp"],
            "all_projects" => true
          },
          token_type: "access_token",
          ttl: {1, :hour}
        )

      credential =
        %{agent_registration_id: registration.id, jti: claims["jti"], expires_at: DateTime.add(DateTime.utc_now(), 3600)}
        |> AgentAuthCredential.create_changeset()
        |> Repo.insert!()

      {bearer, credential}
    end

    authenticate = fn bearer ->
      :post
      |> Phoenix.ConnTest.build_conn("/mcp")
      |> Plug.Conn.put_req_header("authorization", "Bearer #{bearer}")
      |> AuthenticationPlug.call(AuthenticationPlug.init(:load_authenticated_subject))
    end

    {bearer, first_credential} = issue_token.()
    conn = authenticate.(bearer)
    assert conn.assigns.current_user.id == user.id

    params = %{
      "name" => "test_run.failed",
      "arguments" => %{"account_handle" => user.account.name, "project_handle" => project.name},
      "delivery" => %{
        "mode" => "webhook",
        "url" => "https://example.com/events",
        "secret" => "whsec_" <> Base.encode64(:crypto.strong_rand_bytes(32))
      }
    }

    expect(Callback, :verify, 2, fn _url, _secret, _id -> :ok end)
    assert {:ok, %{"id" => id}} = Events.subscribe(conn, params)
    assert %Subscription{agent_registration_id: registration_id} = Repo.get!(Subscription, id)
    assert registration_id == registration.id

    {rotated_bearer, rotated_credential} = issue_token.()

    first_credential
    |> AgentAuthCredential.revoke_changeset(DateTime.truncate(DateTime.utc_now(), :second))
    |> Repo.update!()

    rotated_conn = authenticate.(rotated_bearer)
    assert {:ok, %{"id" => ^id}} = Events.subscribe(rotated_conn, params)

    assert :ok =
             Publisher.publish(
               "test_run.failed",
               %{"project_id" => project.id, "test_run_id" => Ecto.UUID.generate()},
               id
             )

    fanout = Repo.one!(from job in Oban.Job, where: job.worker == ^inspect(FanoutWorker))
    assert :ok = FanoutWorker.perform(fanout)
    delivery = Repo.one!(from job in Oban.Job, where: job.worker == ^inspect(DeliveryWorker))

    expect(Callback, :post, fn _url, _secret, _id, _event_id, _body -> {:ok, %Req.Response{status: 200}} end)
    assert :ok = DeliveryWorker.perform(delivery)

    rotated_credential
    |> AgentAuthCredential.revoke_changeset(DateTime.truncate(DateTime.utc_now(), :second))
    |> Repo.update!()

    assert :ok = DeliveryWorker.perform(delivery)
    assert Repo.get(Subscription, id) == nil
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

      subscription = Subscription |> Repo.get!(id) |> Repo.preload([:user, :account, :project, :account_token])
      assert %Subscription{event_name: ^name, account_id: account_id} = subscription
      assert account_id == user.account.id
      assert subscription.user.id == user.id
      assert subscription.account.id == user.account.id
      assert subscription.account_token.id == token.id
      assert is_nil(subscription.project) == (name == "ci_job.failed")
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

    original_grant =
      Repo.insert!(%Token{
        type: "access_token",
        value: bearer,
        refresh_token: Ecto.UUID.generate(),
        client_id: client.id,
        sub: to_string(user.id),
        scope: "project:builds:read",
        expires_at: System.system_time(:second) - 60
      })

    expect(Callback, :verify, 2, fn _url, _secret, _id -> :ok end)

    params = %{
      "name" => "build.failed",
      "arguments" => %{"account_handle" => user.account.name, "project_handle" => project.name},
      "delivery" => %{
        "mode" => "webhook",
        "url" => "https://example.com/events",
        "secret" => "whsec_" <> Base.encode64(:crypto.strong_rand_bytes(32))
      }
    }

    assert {:ok, %{"id" => id}} = Events.subscribe(conn, params)

    assert %Subscription{oauth_client_id: client_id, oauth_grant_id: grant_id} = Repo.get!(Subscription, id)
    assert client_id == client.id
    assert grant_id == original_grant.id

    assert :ok =
             Publisher.publish(
               "build.failed",
               %{"project_id" => project.id, "build_system" => "xcode", "build_id" => Ecto.UUID.generate()},
               "xcode:sample"
             )

    fanout_job = Repo.one!(from job in Oban.Job, where: job.worker == ^inspect(FanoutWorker))
    assert :ok = FanoutWorker.perform(fanout_job)

    stub(SSRFGuard, :pin, fn _url -> {:ok, "https://203.0.113.10/events", "example.com"} end)
    stub(SSRFGuard, :connect_options, fn _host -> [] end)
    expect(Req, :post, 2, fn _url, _options -> {:ok, %Req.Response{status: 200}} end)

    delivery_job = Repo.one!(from job in Oban.Job, where: job.worker == ^inspect(DeliveryWorker))
    assert :ok = DeliveryWorker.perform(delivery_job)

    {:ok, rotated_bearer, _claims} =
      Tuist.Guardian.encode_and_sign(user.account, claims, token_type: "access_token", ttl: {1, :hour})

    rotated_grant =
      Repo.insert!(%Token{
        type: "access_token",
        value: rotated_bearer,
        previous_token: bearer,
        refresh_token: Ecto.UUID.generate(),
        client_id: client.id,
        sub: to_string(user.id),
        scope: "project:builds:read"
      })

    original_grant
    |> Ecto.Changeset.change(refresh_token_revoked_at: DateTime.utc_now())
    |> Repo.update!()

    rotated_conn = Plug.Conn.put_req_header(conn, "authorization", "Bearer #{rotated_bearer}")
    assert {:ok, %{"id" => ^id}} = Events.subscribe(rotated_conn, params)
    assert Repo.aggregate(Subscription, :count, :id) == 1

    assert :ok = DeliveryWorker.perform(delivery_job)

    Repo.insert!(%Token{
      type: "access_token",
      value: Ecto.UUID.generate(),
      refresh_token: Ecto.UUID.generate(),
      client_id: client.id,
      sub: to_string(user.id),
      scope: "project:builds:read"
    })

    rotated_grant
    |> Ecto.Changeset.change(refresh_token_revoked_at: DateTime.utc_now())
    |> Repo.update!()

    assert :ok = DeliveryWorker.perform(delivery_job)
    assert Repo.get(Subscription, id) == nil
    assert {:ok, %{}} = Events.unsubscribe(rotated_conn, params)
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

    assert :ok =
             Publisher.publish(
               "test_case.marked_flaky",
               %{"project_id" => project.id, "test_case_id" => test_case_id},
               source_id
             )

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

    expect(Callback, :post, fn _url, _secret, _id, _event_id, _body -> {:error, :timeout} end)
    assert {:error, :timeout} = DeliveryWorker.perform(delivery_job)
    assert Repo.get!(Subscription, subscription.id).consecutive_timeouts == 1

    expect(Callback, :post, fn _url, _secret, _id, _event_id, _body -> {:ok, %Req.Response{status: 200}} end)
    assert :ok = DeliveryWorker.perform(delivery_job)
    assert Repo.get!(Subscription, subscription.id).consecutive_timeouts == 0

    expect(Callback, :post, 4, fn _url, _secret, _id, _event_id, _body -> {:error, :timeout} end)
    assert {:error, :timeout} = DeliveryWorker.perform(delivery_job)
    assert {:error, :timeout} = DeliveryWorker.perform(delivery_job)
    assert {:error, :timeout} = DeliveryWorker.perform(delivery_job)
    assert Repo.get!(Subscription, subscription.id).consecutive_timeouts == 3

    Repo.update_all(from(s in Subscription, where: s.id == ^subscription.id),
      set: [first_timeout_at: DateTime.add(DateTime.utc_now(), -301, :second)]
    )

    assert :ok = DeliveryWorker.perform(delivery_job)
    assert Repo.get(Subscription, subscription.id) == nil
    assert :ok = DeliveryWorker.perform(delivery_job)
  end

  test "fan-out queues every subscriber across pagination boundaries" do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account: user.account)
    token = claimed_token_fixture(user)
    secret = "whsec_" <> Base.encode64(:crypto.strong_rand_bytes(32))

    for number <- 1..101 do
      %Subscription{}
      |> Subscription.changeset(%{
        id: "sub_page_#{number}",
        user_id: user.id,
        account_token_id: token.id,
        account_id: user.account.id,
        project_id: project.id,
        event_name: "build.failed",
        callback_url: "https://example.com/events/#{number}",
        signing_secret: secret,
        refresh_before: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)
      })
      |> Repo.insert!()
    end

    build_id = Ecto.UUID.generate()

    assert :ok =
             Publisher.publish(
               "build.failed",
               %{"project_id" => project.id, "build_system" => "xcode", "build_id" => build_id},
               "xcode:#{build_id}"
             )

    fanout = Repo.one!(from job in Oban.Job, where: job.worker == ^inspect(FanoutWorker))
    assert :ok = FanoutWorker.perform(fanout)
    assert :ok = FanoutWorker.perform(fanout)
    assert Repo.aggregate(from(job in Oban.Job, where: job.worker == ^inspect(DeliveryWorker)), :count, :id) == 101

    assert :ok =
             Publisher.publish(
               "build.failed",
               %{"project_id" => project.id, "build_system" => "xcode", "build_id" => build_id},
               "xcode:#{build_id}"
             )

    assert Repo.aggregate(from(job in Oban.Job, where: job.worker == ^inspect(FanoutWorker)), :count, :id) == 1
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

    assert :ok =
             Publisher.publish(
               "build.failed",
               %{
                 "project_id" => project.id,
                 "build_system" => "xcode",
                 "build_id" => build_id,
                 "is_ci" => true,
                 "git_branch" => "main"
               },
               "xcode:#{build_id}"
             )

    assert :ok =
             Publisher.publish(
               "test_run.failed",
               %{"project_id" => project.id, "test_run_id" => test_run_id, "is_ci" => false, "git_branch" => "topic"},
               test_run_id
             )

    assert :ok =
             Publisher.publish(
               "ci_job.failed",
               %{"account_id" => user.account.id, "workflow_run_id" => 42, "workflow_job_id" => 123},
               123
             )

    fanout_jobs = Repo.all(from job in Oban.Job, where: job.worker == ^inspect(FanoutWorker))
    assert length(fanout_jobs) == 3
    Enum.each(fanout_jobs, fn job -> assert :ok = FanoutWorker.perform(job) end)

    delivery_jobs = Repo.all(from job in Oban.Job, where: job.worker == ^inspect(DeliveryWorker))
    assert length(delivery_jobs) == 3

    stub(SSRFGuard, :pin, fn "https://example.com/events" ->
      {:ok, "https://203.0.113.10/events", "example.com"}
    end)

    stub(SSRFGuard, :connect_options, fn "example.com" -> [] end)

    test_process = self()

    expect(Req, :post, 3, fn "https://203.0.113.10/events", options ->
      headers = Map.new(options[:headers])
      body = options[:body]

      assert headers["webhook-signature"] ==
               Callback.sign(headers["webhook-id"], headers["webhook-timestamp"], body, secret)

      send(test_process, {:delivered, JSON.decode!(body)})
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
               body["data"]["build_system"] == "xcode" and body["data"]["is_ci"] == true and
               body["data"]["git_branch"] == "main"
           end)

    assert Enum.any?(delivered, fn body ->
             body["name"] == "test_run.failed" and body["data"]["test_run_id"] == test_run_id and
               body["data"]["is_ci"] == false and body["data"]["git_branch"] == "topic"
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
      RunsFixtures.build_fixture(project_id: project.id, status: "failure", is_ci: true, git_branch: "main")

    gradle_build_id =
      GradleFixtures.build_fixture(
        project_id: project.id,
        account_id: user.account.id,
        status: "failure",
        is_ci: false,
        git_branch: "local-fix"
      )

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
        is_ci: true,
        git_branch: "release",
        cache_endpoint: "cache.tuist.dev"
      }
    ])

    {:ok, test_run} =
      RunsFixtures.test_fixture(
        project_id: project.id,
        account_id: user.account.id,
        status: "failure",
        is_ci: false,
        git_branch: "local-test"
      )

    args = Repo.all(from(job in Oban.Job, where: job.worker == ^inspect(FanoutWorker), select: job.args))

    assert Enum.any?(args, &(&1["event_name"] == "build.failed" and &1["build_id"] == xcode_build.id))
    assert Enum.any?(args, &(&1["build_id"] == xcode_build.id and &1["is_ci"] == true and &1["git_branch"] == "main"))
    assert Enum.any?(args, &(&1["event_name"] == "build.failed" and &1["build_id"] == gradle_build_id))

    assert Enum.any?(
             args,
             &(&1["build_id"] == gradle_build_id and &1["is_ci"] == false and &1["git_branch"] == "local-fix")
           )

    assert Enum.any?(args, &(&1["event_name"] == "build.failed" and &1["build_id"] == bazel_invocation_id))

    assert Enum.any?(
             args,
             &(&1["build_id"] == bazel_invocation_id and &1["is_ci"] == true and &1["git_branch"] == "release")
           )

    assert Enum.any?(args, &(&1["event_name"] == "test_run.failed" and &1["test_run_id"] == test_run.id))

    assert Enum.any?(
             args,
             &(&1["test_run_id"] == test_run.id and &1["is_ci"] == false and &1["git_branch"] == "local-test")
           )

    assert Enum.all?(args, &(&1["project_id"] == project.id))
  end

  test "failures without a subscription do not queue fan-out" do
    project_id = ProjectsFixtures.project_fixture().id
    build_id = Ecto.UUID.generate()

    assert :ok =
             Publisher.publish(
               "build.failed",
               %{"project_id" => project_id, "build_system" => "xcode", "build_id" => build_id},
               "xcode:#{build_id}"
             )

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

    assert :ok =
             Publisher.publish(
               "build.failed",
               %{"project_id" => project.id, "build_system" => "xcode", "build_id" => Ecto.UUID.generate()},
               "xcode:sample"
             )

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
